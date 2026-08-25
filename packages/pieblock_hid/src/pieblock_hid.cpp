#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <hidsdi.h>
#include <setupapi.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#ifndef GUID_DEVINTERFACE_HID
DEFINE_GUID(GUID_DEVINTERFACE_HID, 0x4d1e55b2, 0xf16f, 0x11cf, 0x88, 0xcb,
            0x00, 0x11, 0x11, 0x00, 0x00, 0x30);
#endif

namespace {
constexpr WORD kVid = 0x34BF;
constexpr WORD kPid = 0x1001;
std::mutex g_mutex;
HANDLE g_handle = INVALID_HANDLE_VALUE;
DWORD g_input_size = 65;
DWORD g_output_size = 65;

using HidPGetCapsFn = NTSTATUS(WINAPI*)(PHIDP_PREPARSED_DATA, PHIDP_CAPS);

std::vector<std::wstring> Enumerate() {
  GUID guid;
  HidD_GetHidGuid(&guid);
  HDEVINFO devices = SetupDiGetClassDevsW(
      &guid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  std::vector<std::wstring> result;
  if (devices == INVALID_HANDLE_VALUE) return result;
  SP_DEVICE_INTERFACE_DATA interface_data{};
  interface_data.cbSize = sizeof(interface_data);
  for (DWORD index = 0; SetupDiEnumDeviceInterfaces(
           devices, nullptr, &guid, index, &interface_data);
       ++index) {
    DWORD required = 0;
    SetupDiGetDeviceInterfaceDetailW(devices, &interface_data, nullptr, 0,
                                     &required, nullptr);
    if (required == 0) continue;
    std::vector<BYTE> storage(required);
    auto* detail = reinterpret_cast<PSP_DEVICE_INTERFACE_DETAIL_DATA_W>(
        storage.data());
    detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    if (!SetupDiGetDeviceInterfaceDetailW(devices, &interface_data, detail,
                                          required, nullptr, nullptr))
      continue;
    HANDLE probe = CreateFileW(detail->DevicePath, 0,
                               FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                               OPEN_EXISTING, 0, nullptr);
    if (probe == INVALID_HANDLE_VALUE) continue;
    HIDD_ATTRIBUTES attributes{};
    attributes.Size = sizeof(attributes);
    if (HidD_GetAttributes(probe, &attributes) && attributes.VendorID == kVid &&
        attributes.ProductID == kPid) {
      result.emplace_back(detail->DevicePath);
    }
    CloseHandle(probe);
  }
  SetupDiDestroyDeviceInfoList(devices);
  return result;
}

void CloseUnlocked() {
  if (g_handle != INVALID_HANDLE_VALUE) {
    CancelIoEx(g_handle, nullptr);
    CloseHandle(g_handle);
    g_handle = INVALID_HANDLE_VALUE;
  }
}
}  // namespace

extern "C" __declspec(dllexport) int32_t pb_hid_count() {
  return static_cast<int32_t>(Enumerate().size());
}

extern "C" __declspec(dllexport) int32_t pb_hid_open() {
  std::lock_guard<std::mutex> lock(g_mutex);
  CloseUnlocked();
  const auto devices = Enumerate();
  if (devices.size() != 1) return 0;
  g_handle = CreateFileW(devices.front().c_str(), GENERIC_READ | GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                         OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
  if (g_handle == INVALID_HANDLE_VALUE) return 0;
  PHIDP_PREPARSED_DATA preparsed = nullptr;
  if (HidD_GetPreparsedData(g_handle, &preparsed) && preparsed != nullptr) {
    HMODULE hid_module = LoadLibraryW(L"hid.dll");
    auto get_caps = hid_module == nullptr
                        ? nullptr
                        : reinterpret_cast<HidPGetCapsFn>(
                              GetProcAddress(hid_module, "HidP_GetCaps"));
    HIDP_CAPS caps{};
    if (get_caps != nullptr && get_caps(preparsed, &caps) == HIDP_STATUS_SUCCESS) {
      if (caps.InputReportByteLength > 0 && caps.InputReportByteLength <= 256)
        g_input_size = caps.InputReportByteLength;
      if (caps.OutputReportByteLength > 0 && caps.OutputReportByteLength <= 256)
        g_output_size = caps.OutputReportByteLength;
    }
    HidD_FreePreparsedData(preparsed);
    if (hid_module != nullptr) FreeLibrary(hid_module);
  }
  return 1;
}

extern "C" __declspec(dllexport) int32_t pb_hid_write(const uint8_t* data,
                                                        int32_t length) {
  HANDLE handle;
  DWORD output_size;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    handle = g_handle;
    output_size = g_output_size;
  }
  if (handle == INVALID_HANDLE_VALUE || data == nullptr || length <= 0 ||
      static_cast<DWORD>(length) > output_size)
    return 0;
  std::vector<uint8_t> buffer(output_size, 0);
  std::memcpy(buffer.data(), data, length);
  OVERLAPPED overlapped{};
  overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (overlapped.hEvent == nullptr) return 0;
  DWORD written = 0;
  BOOL ok = WriteFile(handle, buffer.data(), output_size, &written, &overlapped);
  if (!ok && GetLastError() == ERROR_IO_PENDING) {
    if (WaitForSingleObject(overlapped.hEvent, 2000) == WAIT_OBJECT_0)
      ok = GetOverlappedResult(handle, &overlapped, &written, FALSE);
    else
      CancelIoEx(handle, &overlapped);
  }
  CloseHandle(overlapped.hEvent);
  return ok && written == output_size ? 1 : 0;
}

extern "C" __declspec(dllexport) int32_t pb_hid_read(uint8_t* destination,
                                                       int32_t capacity,
                                                       int32_t timeout_ms) {
  HANDLE handle;
  DWORD input_size;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    handle = g_handle;
    input_size = g_input_size;
  }
  if (handle == INVALID_HANDLE_VALUE || destination == nullptr || capacity <= 0)
    return 0;
  std::vector<uint8_t> buffer(input_size, 0);
  OVERLAPPED overlapped{};
  overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (overlapped.hEvent == nullptr) return 0;
  DWORD read = 0;
  BOOL ok = ReadFile(handle, buffer.data(), input_size, &read, &overlapped);
  if (!ok && GetLastError() == ERROR_IO_PENDING) {
    if (WaitForSingleObject(overlapped.hEvent, std::max(timeout_ms, 0)) ==
        WAIT_OBJECT_0)
      ok = GetOverlappedResult(handle, &overlapped, &read, FALSE);
    else
      CancelIoEx(handle, &overlapped);
  }
  CloseHandle(overlapped.hEvent);
  if (!ok || read == 0) return 0;
  DWORD offset = buffer[0] == 0 ? 1 : 0;
  const DWORD available = read > offset ? read - offset : 0;
  const DWORD copied = std::min<DWORD>(available, capacity);
  std::memcpy(destination, buffer.data() + offset, copied);
  return static_cast<int32_t>(copied);
}

extern "C" __declspec(dllexport) void pb_hid_cancel() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_handle != INVALID_HANDLE_VALUE) CancelIoEx(g_handle, nullptr);
}

extern "C" __declspec(dllexport) void pb_hid_close() {
  std::lock_guard<std::mutex> lock(g_mutex);
  CloseUnlocked();
}
