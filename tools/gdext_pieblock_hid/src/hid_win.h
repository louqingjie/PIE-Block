#pragma once

#include <godot_cpp/classes/object.hpp>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <string>

namespace godot {

// STC32G USB-HID 裸读写单例（Windows）。
//
// 对应 Android 侧 PieBlockUsb 插件的职责：枚举/打开/读写 HID 中断端点，
// 不实现任何烧录协议——协议层在 scripts/hid_flasher.gd（GDScript 移植）。
//
// 方法签名与 scripts/usb_port_windows.gd 的鸭子接口一一对应：
//   find_stc_device() -> bool           枚举 VID 0x34BF / PID 0x1001 的设备
//   open() -> bool                      打开第一个匹配设备（claim 接口）
//   write_report(bytes) -> bool         写一个 64 字节报告（含报告 ID 前缀）
//   read_report(timeout_ms) -> PackedByteArray  读一个报告；超时/失败返回空数组
//   close()                             关闭并释放句柄
//
// 线程安全说明：调用方（HidFlasher）在 Godot worker 线程里串行调用，
// 单例内不做跨线程同步；烧录流程保证同一时刻只有一个调用者在用。
class PieBlockHidWindows : public Object {
	GDCLASS(PieBlockHidWindows, Object)

	static PieBlockHidWindows *singleton;

	HANDLE _handle;
	std::wstring _device_path;
	DWORD _report_in_size;
	DWORD _report_out_size;
	String _last_error;

	bool _enumerate_first(std::wstring &r_path);
	void _close_internal();
	void _set_last_error(const String &p_err);
	String _winapi_error_text(const char *p_what);

protected:
	static void _bind_methods();

public:
	PieBlockHidWindows();
	~PieBlockHidWindows();

	static PieBlockHidWindows *get_singleton();

	bool find_stc_device();
	bool open();
	bool write_report(const PackedByteArray &p_data);
	PackedByteArray read_report(int64_t p_timeout_ms);
	void close();
	String get_last_error() const;
};

} // namespace godot
