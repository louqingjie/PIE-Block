// PIE-Block USB-HID 烧录传输层的公共 C ABI。
// 两套平台实现保持同一签名与语义：
//   - Windows: pieblock_hid.cpp（Win32 HIDCLASS + overlapped I/O）
//   - Linux:   pieblock_hid_hidraw.cpp（hidraw + poll/eventfd 取消）
// 协议与时序全部在 Dart 侧（lib/src/flasher.dart、protocol.dart）。
#ifndef PIEBLOCK_HID_H_
#define PIEBLOCK_HID_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 返回当前在线且 VID/PID 匹配的主控板数量。
int32_t pb_hid_count(void);

// 打开唯一一块匹配设备；0 或多块都拒绝。成功返回 1，失败返回 0。
// 隐式先关闭旧会话（幂等）。
int32_t pb_hid_open(void);

// 写一份报告：data[0] 为 report ID 槽（本设备恒为 0x00），其余为报告本体。
// 成功（设备层完整发出）返回 1，失败返回 0。
int32_t pb_hid_write(const uint8_t* data, int32_t length);

// 阻塞读一份报告，最多等待 timeout_ms；返回拷贝到 destination 的字节数，
// 超时/失败返回 0。取消会立即打断阻塞中的读并返回 0。
int32_t pb_hid_read(uint8_t* destination, int32_t capacity, int32_t timeout_ms);

// 打断当前阻塞中的 read/write；句柄保持打开。无挂起 I/O 时为空操作。
void pb_hid_cancel(void);

// 关闭会话；幂等，未打开时安全。
void pb_hid_close(void);

#ifdef __cplusplus
}
#endif

#endif  // PIEBLOCK_HID_H_
