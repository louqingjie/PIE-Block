#include "hid_win.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <hidsdi.h>
#include <setupapi.h>

#include <vector>

#ifndef GUID_DEVINTERFACE_HID
DEFINE_GUID(GUID_DEVINTERFACE_HID, 0x4d1e55b2, 0xf16f, 0x11cf, 0x88, 0xcb, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30);
#endif

namespace godot {

// STC32G ROM bootloader USB-HID（"USB-ISP"）。
constexpr WORD STC_VID = 0x34BF;
constexpr WORD STC_PID = 0x1001;

// HidP_GetCaps 在用户态由 hid.dll 转发（hidapi 同款取法：LoadLibrary + GetProcAddress）。
typedef NTSTATUS(WINAPI *HidPGetCapsFunc)(PHIDP_PREPARSED_DATA, PHIDP_CAPS);

static HidPGetCapsFunc _load_hidp_get_caps() {
	static HidPGetCapsFunc cached = nullptr;
	if (cached != nullptr) {
		return cached;
	}
	HMODULE hid_mod = LoadLibraryW(L"hid.dll");
	if (hid_mod != nullptr) {
		cached = reinterpret_cast<HidPGetCapsFunc>(GetProcAddress(hid_mod, "HidP_GetCaps"));
	}
	return cached;
}

PieBlockHidWindows *PieBlockHidWindows::singleton = nullptr;

PieBlockHidWindows::PieBlockHidWindows() {
	_handle = INVALID_HANDLE_VALUE;
	_report_in_size = 64;
	_report_out_size = 64;
	singleton = this;
}

PieBlockHidWindows::~PieBlockHidWindows() {
	_close_internal();
	singleton = nullptr;
}

PieBlockHidWindows *PieBlockHidWindows::get_singleton() {
	return singleton;
}

void PieBlockHidWindows::_bind_methods() {
	ClassDB::bind_method(D_METHOD("find_stc_device"), &PieBlockHidWindows::find_stc_device);
	ClassDB::bind_method(D_METHOD("open"), &PieBlockHidWindows::open);
	ClassDB::bind_method(D_METHOD("write_report", "data"), &PieBlockHidWindows::write_report);
	ClassDB::bind_method(D_METHOD("read_report", "timeout_ms"), &PieBlockHidWindows::read_report);
	ClassDB::bind_method(D_METHOD("close"), &PieBlockHidWindows::close);
	ClassDB::bind_method(D_METHOD("get_last_error"), &PieBlockHidWindows::get_last_error);
}

void PieBlockHidWindows::_set_last_error(const String &p_err) {
	_last_error = p_err;
}

String PieBlockHidWindows::get_last_error() const {
	return _last_error;
}

String PieBlockHidWindows::_winapi_error_text(const char *p_what) {
	DWORD code = GetLastError();
	char buf[256];
	FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
			nullptr, code, 0, buf, sizeof(buf), nullptr);
	// 去掉 FormatMessage 附加的换行/句号。
	String msg = String::utf8(buf).strip_edges();
	if (msg.is_empty()) {
		msg = String::num_int64(code);
	}
	return String(p_what) + " (0x" + String::num_int64(code, 16) + "): " + msg;
}

// ------------------------------------------------------------------ 枚举

bool PieBlockHidWindows::_enumerate_first(std::wstring &r_path) {
	GUID guid;
	HidD_GetHidGuid(&guid);

	HDEVINFO devs = SetupDiGetClassDevsW(&guid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
	if (devs == INVALID_HANDLE_VALUE) {
		_set_last_error(_winapi_error_text("SetupDiGetClassDevsW"));
		return false;
	}

	bool found = false;
	SP_DEVICE_INTERFACE_DATA did;
	did.cbSize = sizeof(did);
	for (DWORD idx = 0; SetupDiEnumDeviceInterfaces(devs, nullptr, &guid, idx, &did); idx++) {
		DWORD need = 0;
		SetupDiGetDeviceInterfaceDetailW(devs, &did, nullptr, 0, &need, nullptr);
		if (need == 0) {
			continue;
		}
		std::vector<BYTE> buf(need);
		PSP_DEVICE_INTERFACE_DETAIL_DATA_W detail = reinterpret_cast<PSP_DEVICE_INTERFACE_DETAIL_DATA_W>(buf.data());
		detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
		if (!SetupDiGetDeviceInterfaceDetailW(devs, &did, detail, need, nullptr, nullptr)) {
			continue;
		}

		// 以只读方式打开一次拿 VID/PID（HidD_GetAttributes 不需要读写权限）。
		HANDLE probe = CreateFileW(detail->DevicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE,
				nullptr, OPEN_EXISTING, 0, nullptr);
		if (probe == INVALID_HANDLE_VALUE) {
			continue;
		}
		HIDD_ATTRIBUTES attr;
		attr.Size = sizeof(attr);
		if (HidD_GetAttributes(probe, &attr) && attr.VendorID == STC_VID && attr.ProductID == STC_PID) {
			r_path = detail->DevicePath;
			found = true;
		}
		CloseHandle(probe);
		if (found) {
			break;
		}
	}
	SetupDiDestroyDeviceInfoList(devs);
	if (!found) {
		_set_last_error("未找到 STC USB-HID 设备 (VID=34BF PID=1001)");
	}
	return found;
}

// ------------------------------------------------------------------ 鸭子接口

bool PieBlockHidWindows::find_stc_device() {
	std::wstring path;
	return _enumerate_first(path);
}

bool PieBlockHidWindows::open() {
	_close_internal();
	std::wstring path;
	if (!_enumerate_first(path)) {
		return false;
	}
	_handle = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE,
			FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
	if (_handle == INVALID_HANDLE_VALUE) {
		_set_last_error(_winapi_error_text("CreateFileW"));
		return false;
	}
	_device_path = path;

	// 报告长度以设备 HID 描述符为准（STC USB-ISP 实测 65 字节：0x00 报告号 + 64 数据）。
	// Windows 的 WriteFile 要求长度 == OutputReportByteLength，读同理，必须取真值。
	PHIDP_PREPARSED_DATA pp_data = nullptr;
	HidPGetCapsFunc hidp_get_caps = _load_hidp_get_caps();
	if (HidD_GetPreparsedData(_handle, &pp_data) && pp_data != nullptr) {
		if (hidp_get_caps != nullptr) {
			HIDP_CAPS caps;
			memset(&caps, 0, sizeof(caps));
			if (hidp_get_caps(pp_data, &caps) == HIDP_STATUS_SUCCESS) {
				if (caps.OutputReportByteLength > 0 && caps.OutputReportByteLength <= 256) {
					_report_out_size = caps.OutputReportByteLength;
				}
				if (caps.InputReportByteLength > 0 && caps.InputReportByteLength <= 256) {
					_report_in_size = caps.InputReportByteLength;
				}
			}
		}
		HidD_FreePreparsedData(pp_data);
	}
	_set_last_error("");
	return true;
}

void PieBlockHidWindows::_close_internal() {
	if (_handle != INVALID_HANDLE_VALUE) {
		CloseHandle(_handle);
		_handle = INVALID_HANDLE_VALUE;
	}
	_device_path.clear();
}

bool PieBlockHidWindows::write_report(const PackedByteArray &p_data) {
	if (_handle == INVALID_HANDLE_VALUE || p_data.size() <= 0) {
		_set_last_error(_handle == INVALID_HANDLE_VALUE ? "设备未打开" : "空数据");
		return false;
	}

	// 与 hidapi 对齐：Windows 要求 WriteFile 长度 == OutputReportByteLength。
	// 短报告补零到该长度；等长/超长原样发送（协议层不会发超长）。
	// 长度超过 OutputReportByteLength 时 WriteFile 会直接报 0x57（参数错误），
	// 协议层不应发出超长报告，这里显式拒绝并给出可读错误。
	if (static_cast<DWORD>(p_data.size()) > _report_out_size) {
		_set_last_error("报告超长 (" + String::num_int64(p_data.size()) + " > " + String::num_int64(_report_out_size) + ")");
		return false;
	}

	const BYTE *buf = p_data.ptr();
	DWORD len = static_cast<DWORD>(p_data.size());
	std::vector<BYTE> padded;
	if (len < _report_out_size) {
		padded.assign(_report_out_size, 0);
		memcpy(padded.data(), p_data.ptr(), len);
		buf = padded.data();
		len = _report_out_size;
	}

	// 句柄以 FILE_FLAG_OVERLAPPED 打开，WriteFile 必须提供 OVERLAPPED
	// （传 nullptr 对 HID 设备会直接失败，GetLastError()=0x57 参数错误）。
	// 与 read_report 相同模式：挂起则等待事件，2 秒视为超时。
	OVERLAPPED ov;
	memset(&ov, 0, sizeof(ov));
	ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	if (ov.hEvent == nullptr) {
		_set_last_error(_winapi_error_text("CreateEventW"));
		return false;
	}

	DWORD written = 0;
	bool ok = false;
	if (WriteFile(_handle, buf, len, &written, &ov)) {
		ok = true;
	} else if (GetLastError() == ERROR_IO_PENDING) {
		DWORD wait = WaitForSingleObject(ov.hEvent, 2000);
		if (wait == WAIT_TIMEOUT) {
			CancelIoEx(_handle, &ov);
			WaitForSingleObject(ov.hEvent, 1000);
			CloseHandle(ov.hEvent);
			_set_last_error("WriteFile 超时");
			return false;
		}
		if (GetOverlappedResult(_handle, &ov, &written, FALSE)) {
			ok = true;
		}
	}
	CloseHandle(ov.hEvent);

	if (!ok) {
		_set_last_error(_winapi_error_text("WriteFile"));
		return false;
	}
	if (written != len) {
		_set_last_error("WriteFile 写入长度不符 (" + String::num_int64(written) + "/" + String::num_int64(len) + ")");
		return false;
	}
	return true;
}

PackedByteArray PieBlockHidWindows::read_report(int64_t p_timeout_ms) {
	PackedByteArray empty;
	if (_handle == INVALID_HANDLE_VALUE) {
		_set_last_error("设备未打开");
		return empty;
	}

	std::vector<BYTE> buf(_report_in_size, 0);
	OVERLAPPED ov;
	memset(&ov, 0, sizeof(ov));
	ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	if (ov.hEvent == nullptr) {
		_set_last_error(_winapi_error_text("CreateEventW"));
		return empty;
	}

	DWORD got = 0;
	bool ok = false;
	if (ReadFile(_handle, buf.data(), static_cast<DWORD>(buf.size()), &got, &ov)) {
		ok = true;
	} else if (GetLastError() == ERROR_IO_PENDING) {
		DWORD wait = WaitForSingleObject(ov.hEvent, static_cast<DWORD>(p_timeout_ms));
		if (wait == WAIT_TIMEOUT) {
			// 取消挂起的读，避免下次读被旧数据污染。
			CancelIoEx(_handle, &ov);
			WaitForSingleObject(ov.hEvent, 1000);
			CloseHandle(ov.hEvent);
			return empty;
		}
		if (GetOverlappedResult(_handle, &ov, &got, FALSE)) {
			ok = true;
		}
	}
	CloseHandle(ov.hEvent);

	if (!ok || got == 0) {
		return empty;
	}
	// 与 hidapi 对齐：Windows 会给报告加 0x00 报告号前缀（即使设备未用编号报告），
	// hidapi 读到后剥掉再返回；协议层期望响应从 0x46 帧头开始。
	int offset = 0;
	if (got > 0 && buf[0] == 0x00) {
		offset = 1;
		got--;
	}
	if (got == 0) {
		return empty;
	}
	PackedByteArray result;
	result.resize(got);
	memcpy(result.ptrw(), buf.data() + offset, got);
	return result;
}

void PieBlockHidWindows::close() {
	_close_internal();
}

} // namespace godot
