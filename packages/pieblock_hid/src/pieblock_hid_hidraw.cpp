// Linux hidraw 后端，与 pieblock_hid.cpp（Win32）保持同一 C ABI 与语义。
// 设备：STC32G ROM ISP（"USB-ISP"），VID 0x34BF / PID 0x1001，
// 单 HID 接口、64 字节报告、无 report ID（stc32g/toolchain/stcflash/HID_PROTOCOL.md）。
//
// 取消机制：hidraw 没有类似 CancelIoEx 的 API，用 eventfd 与 hidraw fd
// 一起 poll——pb_hid_cancel 写 eventfd 即时唤醒阻塞中的 poll，语义与
// Windows 等价（打断当前 I/O、句柄保持打开、无挂起 I/O 时为空操作，
// 由读开始时的预排空保证）。
#include "pieblock_hid.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <linux/hidraw.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {
constexpr uint16_t kVid = 0x34BF;
constexpr uint16_t kPid = 0x1001;
// 设备报告本体 64 字节；传输缓冲沿用 Windows 侧的 65 字节
//（byte0 为 report ID 槽，Dart 侧 protocol.dart 恒填 0x00）。
constexpr int kReportWireSize = 64;
constexpr int kTransferSize = 65;

std::mutex g_mutex;
int g_fd = -1;
// eventfd 生命周期与进程一致：跨 open/close 复用，避免与在途读竞争关闭。
int g_cancel_fd = -1;
std::atomic<int> g_active_reads{0};

bool MatchesVidPid(int fd) {
  struct hidraw_devinfo info {};
  if (ioctl(fd, HIDIOCGRAWINFO, &info) != 0) return false;
  return info.vendor == static_cast<short>(kVid) &&
         info.product == static_cast<short>(kPid);
}

std::vector<std::string> Enumerate() {
  std::vector<std::string> result;
  DIR* dir = opendir("/dev");
  if (dir == nullptr) return result;
  while (auto* entry = readdir(dir)) {
    const std::string name = entry->d_name;
    if (name.rfind("hidraw", 0) != 0) continue;
    const std::string path = "/dev/" + name;
    const int probe = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (probe < 0) continue;  // 无权限（未装 udev 规则）或设备刚消失
    const bool matched = MatchesVidPid(probe);
    close(probe);
    if (matched) result.push_back(path);
  }
  closedir(dir);
  return result;
}

void CloseUnlocked() {
  if (g_fd >= 0) {
    close(g_fd);
    g_fd = -1;
  }
}

void DrainCancelUnlocked() {
  if (g_cancel_fd < 0) return;
  uint64_t value = 0;
  while (read(g_cancel_fd, &value, sizeof(value)) > 0) {
  }
}
}  // namespace

extern "C" int32_t pb_hid_count(void) {
  return static_cast<int32_t>(Enumerate().size());
}

extern "C" int32_t pb_hid_open(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  CloseUnlocked();
  const auto devices = Enumerate();
  if (devices.size() != 1) return 0;
  const int fd = open(devices.front().c_str(), O_RDWR | O_CLOEXEC);
  if (fd < 0) return 0;
  if (g_cancel_fd < 0) {
    g_cancel_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (g_cancel_fd < 0) {
      close(fd);
      return 0;
    }
  } else {
    DrainCancelUnlocked();  // 清掉上一会话遗留的取消信号
  }
  g_fd = fd;
  return 1;
}

extern "C" int32_t pb_hid_write(const uint8_t* data, int32_t length) {
  int fd;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    fd = g_fd;
  }
  if (fd < 0 || data == nullptr || length <= 0 || length > kTransferSize) {
    return 0;
  }
  // data[0] 是 report ID 槽（恒 0x00）：hidraw 对无 report ID 设备直接发
  // 64 字节本体，与 Windows 写 65 字节（内核剥离 ID 槽）在总线上等价。
  uint8_t buffer[kReportWireSize] = {};
  const int body = length - 1;
  if (body > kReportWireSize) return 0;
  if (body > 0) std::memcpy(buffer, data + 1, static_cast<size_t>(body));
  // 内核对中断 OUT 有缓冲，write 常规立即返回；Windows 侧的 2000ms 超时
  // 对应的失败模式（设备不收）在这里表现为 write 报错返回 0。
  const ssize_t written = ::write(fd, buffer, kReportWireSize);
  return written == kReportWireSize ? 1 : 0;
}

extern "C" int32_t pb_hid_read(uint8_t* destination, int32_t capacity,
                               int32_t timeout_ms) {
  int fd;
  int cancel_fd;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    fd = g_fd;
    cancel_fd = g_cancel_fd;
  }
  if (fd < 0 || destination == nullptr || capacity <= 0) return 0;
  g_active_reads.fetch_add(1);
  int32_t result = 0;
  {
    // 预排空：对齐 Windows"无挂起 I/O 时 cancel 为空操作"的语义。
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      DrainCancelUnlocked();
    }
    int remaining = timeout_ms > 0 ? timeout_ms : 0;
    uint8_t buffer[kTransferSize] = {};
    for (;;) {
      struct pollfd fds[2] = {
          {fd, POLLIN, 0},
          {cancel_fd, POLLIN, 0},
      };
      const int ready = ::poll(fds, 2, remaining);
      if (ready < 0) {
        if (errno == EINTR) continue;
        break;
      }
      if (ready == 0) break;  // 超时，不留挂起读（与 Windows 一致）
      if (fds[1].revents & POLLIN) {
        std::lock_guard<std::mutex> lock(g_mutex);
        DrainCancelUnlocked();
        break;  // 被取消：返回 0，句柄保持打开
      }
      if ((fds[0].revents & POLLIN) == 0) break;
      const ssize_t n = ::read(fd, buffer, sizeof(buffer));
      if (n < 0) {
        if (errno == EINTR) continue;
        break;
      }
      if (n == 0) break;
      const auto available = static_cast<int32_t>(n);
      const int32_t copied = available < capacity ? available : capacity;
      std::memcpy(destination, buffer, static_cast<size_t>(copied));
      result = copied;
      break;
    }
  }
  g_active_reads.fetch_sub(1);
  return result;
}

extern "C" void pb_hid_cancel(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_active_reads.load() <= 0 || g_cancel_fd < 0) return;
  const uint64_t one = 1;
  // EAGAIN 表示已有人写过信号，同样足以唤醒 poll。
  ssize_t ignored = write(g_cancel_fd, &one, sizeof(one));
  (void)ignored;
}

extern "C" void pb_hid_close(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  CloseUnlocked();
}
