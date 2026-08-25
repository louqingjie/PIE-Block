extends SceneTree

## Windows USB-HID 端口适配（UsbPortWindows）验证脚本。
## 运行方式：godot --headless --path . --script scripts/test_usb_port_windows.gd
##
## 不依赖真机：无设备时验证所有接口优雅失败（false / 空数组），
## 同时验证 toolchain.ensure_hid_plugin_loaded() 能把 dll 部署到 user:// 并加载。
## 真机联调见 dev_test_ports.gd（烧录全流程）。

const Toolchain = preload("res://scripts/toolchain.gd")
const UsbPortWindows = preload("res://scripts/usb_port_windows.gd")

var _fail: int = 0


func _initialize() -> void:
	print("=== Windows USB-HID 端口适配验证 ===")
	_test_copy_from_pck()
	_test_plugin_deploy()
	_test_port_duck_interface()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


## 1. 单文件导出模拟：资源只存在于 PCK 时，仍能流式部署到实体目录。
func _test_copy_from_pck() -> void:
	var tc = Toolchain.new()
	var test_dir: String = ProjectSettings.globalize_path("user://hid_pck_copy_test")
	_check("创建 PCK 复制测试目录", DirAccess.make_dir_recursive_absolute(test_dir) == OK)
	var pck_path: String = test_dir.path_join("fixture.pck")
	var dst_path: String = test_dir.path_join("deployed.dll")
	var virtual_path: String = "res://__hid_pck_copy_test__/payload.dll"
	var physical_virtual_path: String = ProjectSettings.globalize_path(virtual_path)
	var source_path: String = ProjectSettings.globalize_path(
		"res://addons/pieblock_usb/win/pieblock_hid.dll")

	var packer := PCKPacker.new()
	var packed: bool = packer.pck_start(pck_path) == OK
	packed = packed and packer.add_file(virtual_path, source_path) == OK
	packed = packed and packer.flush() == OK
	_check("生成仅含虚拟资源的临时 PCK", packed)
	if not packed:
		return
	_check("PCK 资源没有同名实体文件", not FileAccess.file_exists(physical_virtual_path))
	_check("挂载临时 PCK", ProjectSettings.load_resource_pack(pck_path))
	_check("可读取 PCK 内的 DLL", FileAccess.file_exists(virtual_path))
	var copied: bool = tc._copy_file(virtual_path, dst_path)
	_check("从 PCK 部署 DLL 成功", copied)
	if copied:
		_check("PCK 部署文件校验一致",
			FileAccess.get_sha256(virtual_path) == FileAccess.get_sha256(dst_path))


## 2. 插件部署：ensure_hid_plugin_loaded 应在 Windows 上把 dll 备到 user:// 并加载。
func _test_plugin_deploy() -> void:
	var log_lines: PackedStringArray = PackedStringArray()
	var tc = Toolchain.new(func(line: String) -> void: log_lines.append(line))
	var loaded: bool = tc.ensure_hid_plugin_loaded()
	if OS.get_name() == "Windows":
		_check("Windows 上 HID 插件加载成功", loaded and Engine.has_singleton("PieBlockHidWindows"))
		if loaded:
			var dll_path: String = ProjectSettings.globalize_path("user://pieblock_hid/pieblock_hid.dll")
			_check("dll 已部署到 user://pieblock_hid/", FileAccess.file_exists(dll_path))
			var gd_path: String = ProjectSettings.globalize_path("user://pieblock_hid/pieblock_hid.gdextension")
			_check(".gdextension 已生成", FileAccess.file_exists(gd_path))
	else:
		_check("非 Windows 平台不加载插件", not loaded)


## 3. 鸭子接口：无设备时全部安全失败；有设备时 find_device 返回 bool。
func _test_port_duck_interface() -> void:
	var port = UsbPortWindows.new()
	_check("is_available 与 singleton 一致",
		port.is_available() == Engine.has_singleton("PieBlockHidWindows"))
	_check("has_usb_host 恒 true（桌面无 OTG 概念）", port.has_usb_host())
	_check("ensure_permission 恒 true（免驱动）", port.ensure_permission())

	var found: bool = port.find_device()
	_check("find_device 返回 bool", found is bool)

	if port.is_available():
		# 插件已加载：未 open 时读写必须安全失败（与烧录流程的失败分支对齐）。
		_check("未 open 时 write 返回 false", not port.write(PackedByteArray([0])))
		var resp: PackedByteArray = port.read(200)
		_check("未 open 时 read 返回空数组", resp.size() == 0)
