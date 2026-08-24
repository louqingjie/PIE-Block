class_name SdccToolchain
extends RefCounted

## 内置 SDCC MCS-251 工具链。
## res:// 中的编译器和固件模板在导出后位于只读 PCK，首次使用时部署到 user://。

const MANIFEST_SRC := "res://stc32g_sdcc/build_manifest.json"
const FIRMWARE_SRC := "res://stc32g_sdcc"
const FIRMWARE_DST := "user://sdcc/stc32g_sdcc"
const TOOLCHAIN_SRC := "res://vendor/sdcc-toolchain"
const TOOLCHAIN_DST := "user://sdcc/toolchain"
const VERSION_FILE := "user://sdcc/.runtime_version"
const BUNDLE_MANIFEST := "bundle_manifest.json"
const SDCC_ENV_VAR := "PIEBLOCK_SDCC"

const APP_BASE := 0xFE0000
const VECTOR_BASE := 0xFF0000
const VECTOR_LIMIT := 0xFF1000
const XRAM_BASE := 0x010000
const XRAM_LIMIT := 0x012000
const IRAM_LIMIT := 0x1000

var _log: Callable


func _init(log_sink: Callable = Callable()) -> void:
	_log = log_sink


func _emit(text: String) -> void:
	if _log.is_valid():
		_log.call(text)


static func to_abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_SRC):
		return {}
	return _read_json_dictionary(MANIFEST_SRC)


func project_for_kind(kind: String) -> String:
	var manifest := load_manifest()
	var mappings: Dictionary = manifest.get("kind_projects", {})
	return str(mappings.get(kind, ""))


func ensure_deployed() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "reason": "内置 SDCC 当前仅支持 Windows x64"}
	var manifest := load_manifest()
	if manifest.is_empty():
		return {"ok": false, "reason": "SDCC 构建清单缺失或损坏"}
	var expected_version := str(manifest.get("version", ""))
	var bundle_source := _resolve_bundle_source()
	if bundle_source.is_empty():
		return {"ok": false, "reason": "内置 SDCC 工具链未准备；发布前请运行 tools/prepare_sdcc_toolchain.ps1"}
	var bundle_version := _bundle_version(bundle_source)
	if bundle_version.is_empty():
		return {"ok": false, "reason": "SDCC 工具链缺少 bundle_manifest.json"}
	expected_version += ":" + bundle_version
	var current_version := ""
	if FileAccess.file_exists(VERSION_FILE):
		current_version = FileAccess.get_file_as_string(VERSION_FILE).strip_edges()
	if current_version == expected_version and _deployment_complete():
		return {"ok": true, "sdcc": _sdcc_path()}
	# 进程号隔离临时目录，避免两个应用实例首次编译时互相写坏部署内容。
	var deployment_suffix := str(OS.get_process_id())
	var pending := "user://sdcc.pending." + deployment_suffix
	var backup := "user://sdcc.backup." + deployment_suffix
	_emit("正在部署内置 SDCC C251 工具链…")
	_remove_tree(pending)
	_remove_tree(backup)
	if DirAccess.make_dir_recursive_absolute(to_abs(pending)) != OK:
		return {"ok": false, "reason": "无法创建 SDCC 临时目录"}
	if not _copy_tree(FIRMWARE_SRC, pending.path_join("stc32g_sdcc")):
		_remove_tree(pending)
		return {"ok": false, "reason": "无法部署 SDCC 固件模板"}
	if not _copy_tree(bundle_source, pending.path_join("toolchain")):
		_remove_tree(pending)
		return {"ok": false, "reason": "无法部署 SDCC 编译器"}
	if DirAccess.dir_exists_absolute(to_abs("user://sdcc")) \
			and DirAccess.rename_absolute(to_abs("user://sdcc"), to_abs(backup)) != OK:
		_remove_tree(pending)
		return {"ok": false, "reason": "无法切换旧 SDCC 工具链"}
	if DirAccess.rename_absolute(to_abs(pending), to_abs("user://sdcc")) != OK:
		if DirAccess.dir_exists_absolute(to_abs(backup)):
			DirAccess.rename_absolute(to_abs(backup), to_abs("user://sdcc"))
		return {"ok": false, "reason": "无法启用新 SDCC 工具链"}
	_remove_tree(backup)
	var version_file := FileAccess.open(VERSION_FILE, FileAccess.WRITE)
	if version_file == null:
		return {"ok": false, "reason": "无法写入 SDCC 部署版本"}
	version_file.store_string(expected_version)
	version_file.close()
	if not _deployment_complete():
		return {"ok": false, "reason": "SDCC 工具链部署后完整性检查失败"}
	return {"ok": true, "sdcc": _sdcc_path()}


func build(kind: String, code: String, canonical_hex: String) -> Dictionary:
	# 无论部署、编译或校验在哪一步失败，都不能让烧录流程误用上次的产物。
	_remove_file(canonical_hex)
	var ready := ensure_deployed()
	if not bool(ready.get("ok", false)):
		return {"ok": false, "exit": -1, "log": str(ready.get("reason", "SDCC 未就绪"))}
	var manifest := load_manifest()
	var project := project_for_kind(kind)
	if project.is_empty():
		return {"ok": false, "exit": -1, "log": "SDCC 不支持项目类型：%s" % kind}
	var projects: Dictionary = manifest.get("projects", {})
	if not projects.has(project):
		return {"ok": false, "exit": -1, "log": "SDCC 构建清单缺少项目：%s" % project}
	var project_root := to_abs(FIRMWARE_DST).path_join("projects").path_join(project)
	var main_path := project_root.path_join("src/main.c")
	var main_file := FileAccess.open(main_path, FileAccess.WRITE)
	if main_file == null:
		return {"ok": false, "exit": -1, "log": "无法写入 SDCC main.c：%s" % main_path}
	main_file.store_string(code)
	main_file.close()

	var output := to_abs(FIRMWARE_DST).path_join("build").path_join(project)
	_remove_tree(output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		return {"ok": false, "exit": -1, "log": "无法创建 SDCC 输出目录：%s" % output}

	var source_info := _project_sources(manifest, project)
	if not bool(source_info.get("ok", false)):
		return {"ok": false, "exit": -1, "log": str(source_info.get("reason", "源码清单错误"))}
	var sources: Array = source_info.sources
	var library_sources: Array = source_info.library_sources
	var interrupt_header := output.path_join("generated_interrupt_declarations.h")
	var header_result := _write_interrupt_header(sources, interrupt_header)
	if not bool(header_result.get("ok", false)):
		return {"ok": false, "exit": -1, "log": str(header_result.get("reason", "中断声明生成失败"))}

	var include_args: Array[String] = []
	include_args.append("-I" + to_abs(TOOLCHAIN_DST).path_join("include"))
	include_args.append("-I" + to_abs(TOOLCHAIN_DST).path_join("include/mcs51"))
	for relative_dir in manifest.get("include_dirs", []):
		include_args.append("-I" + to_abs(FIRMWARE_DST).path_join(str(relative_dir)))
	include_args.append("-I" + project_root.path_join("inc"))

	var direct_objects: Array[String] = []
	var library_objects: Array[String] = []
	var all_log: Array[String] = []
	for relative_source in sources:
		var source_abs := to_abs(FIRMWARE_DST).path_join(str(relative_source))
		if not FileAccess.file_exists(source_abs):
			return {"ok": false, "exit": -1, "log": "SDCC 工程源文件缺失：%s" % source_abs}
		var object_path := output.path_join(source_abs.get_file().get_basename() + ".rel")
		var args: Array[String] = []
		for flag in manifest.get("compile_flags", []):
			args.append(str(flag))
		args.append_array(include_args)
		if source_abs.replace("\\", "/") == main_path.replace("\\", "/"):
			args.append_array(["--include", interrupt_header])
		args.append_array(["-o", object_path, source_abs])
		var run := _run_sdcc(args)
		all_log.append(str(run.log))
		if not bool(run.ok):
			return {"ok": false, "exit": int(run.exit), "log": "\n".join(all_log)}
		if str(relative_source) in library_sources:
			library_objects.append(object_path)
		else:
			direct_objects.append(object_path)

	var shared_library := output.path_join("stc32g_shared.lib")
	var archive := FileAccess.open(shared_library, FileAccess.WRITE)
	if archive == null:
		return {"ok": false, "exit": -1, "log": "无法创建 SDCC 共享库清单"}
	for object_path in library_objects:
		archive.store_line(object_path.get_file().get_basename())
	archive.close()

	var lib_dir := to_abs(TOOLCHAIN_DST).path_join("lib/mcs251-large-stack-auto")
	for library in manifest.get("runtime_libraries", []):
		if not FileAccess.file_exists(lib_dir.path_join(str(library))):
			return {"ok": false, "exit": -1, "log": "SDCC 运行库缺失：%s" % library}
	var hex_path := output.path_join(project + ".hex")
	var link_args: Array[String] = []
	for flag in manifest.get("link_flags", []):
		link_args.append(str(flag))
	link_args.append_array(["-L" + output, "-L" + lib_dir])
	link_args.append_array(include_args)
	link_args.append_array(direct_objects)
	link_args.append("stc32g_shared.lib")
	for library in manifest.get("runtime_libraries", []):
		link_args.append(str(library))
	link_args.append_array(["-o", hex_path])
	var link := _run_sdcc(link_args)
	all_log.append(str(link.log))
	if not bool(link.ok):
		return {"ok": false, "exit": int(link.exit), "log": "\n".join(all_log)}
	var map_path := hex_path.get_basename() + ".map"
	var layout := validate_layout(hex_path, map_path)
	all_log.append(str(layout.get("log", "")))
	if not bool(layout.get("ok", false)):
		return {"ok": false, "exit": -1, "log": "\n".join(all_log)}
	var copied := _atomic_copy(hex_path, canonical_hex)
	if not copied:
		return {"ok": false, "exit": -1, "log": "\n".join(all_log) + "\n无法保存统一 HEX 产物"}
	return {"ok": true, "exit": 0, "log": "\n".join(all_log), "hex": canonical_hex}


func _project_sources(manifest: Dictionary, project: String) -> Dictionary:
	var groups: Dictionary = manifest.get("source_groups", {})
	var projects: Dictionary = manifest.get("projects", {})
	var spec: Dictionary = projects.get(project, {})
	var sources: Array = []
	var library_sources: Array = []
	for source in groups.get("common", []):
		_append_unique(sources, str(source))
	_append_unique(sources, "projects/%s/src/isr.c" % project)
	_append_unique(sources, "projects/%s/src/main.c" % project)
	for group_name in spec.get("library_groups", []):
		if not groups.has(str(group_name)):
			return {"ok": false, "reason": "未知 SDCC 源码组：%s" % group_name}
		for source in groups[str(group_name)]:
			_append_unique(sources, str(source))
			_append_unique(library_sources, str(source))
	return {"ok": true, "sources": sources, "library_sources": library_sources}


func _append_unique(values: Array, value: String) -> void:
	if not value in values:
		values.append(value)


func _write_interrupt_header(sources: Array, output_path: String) -> Dictionary:
	var regex := RegEx.new()
	var error := regex.compile("(?m)^\\s*(?:static\\s+)?void\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*void\\s*\\)\\s*__interrupt\\s*\\(\\s*([^)]*?)\\s*\\)")
	if error != OK:
		return {"ok": false, "reason": "无法创建中断声明正则"}
	var declarations: Dictionary = {}
	for relative_source in sources:
		var source_path := to_abs(FIRMWARE_DST).path_join(str(relative_source))
		if not FileAccess.file_exists(source_path):
			return {"ok": false, "reason": "源文件缺失：%s" % source_path}
		var source_text := FileAccess.get_file_as_string(source_path)
		for match in regex.search_all(source_text):
			var name := match.get_string(1)
			var vector := match.get_string(2).strip_edges()
			declarations[name + "|" + vector] = "void %s(void) __interrupt (%s);" % [name, vector]
	var keys := declarations.keys()
	keys.sort()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "无法写入中断声明头文件"}
	file.store_line("#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H")
	file.store_line("#define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H")
	file.store_line("#include \"STC32Gxx.h\"")
	file.store_line("#include <stdlib.h>")
	for key in keys:
		file.store_line(str(declarations[key]))
	file.store_line("#endif")
	file.close()
	return {"ok": true, "count": declarations.size()}


func _run_sdcc(args: Array[String]) -> Dictionary:
	var output: Array = []
	var executable := _sdcc_path()
	var exit_code := OS.execute(executable, args, output, true)
	var text := "\n".join(PackedStringArray(output))
	return {"ok": exit_code == 0, "exit": exit_code, "log": text}


func validate_layout(hex_path: String, map_path: String) -> Dictionary:
	if not FileAccess.file_exists(hex_path) or not FileAccess.file_exists(map_path):
		return {"ok": false, "log": "SDCC 未生成完整 HEX/MAP"}
	var parsed_hex := _parse_hex(hex_path)
	if not bool(parsed_hex.get("ok", false)):
		return parsed_hex
	var image: Dictionary = parsed_hex.data
	for address in range(VECTOR_BASE, VECTOR_BASE + 3):
		if not image.has(address):
			return {"ok": false, "log": "复位向量 0xFF0000 不完整"}
	if int(image[VECTOR_BASE]) != 0x02:
		return {"ok": false, "log": "复位向量不是 LJMP (0x02)"}
	var app_addresses: Array[int] = []
	var high_addresses: Array[int] = []
	for key in image.keys():
		var address := int(key)
		if address >= VECTOR_BASE:
			high_addresses.append(address)
		elif address >= APP_BASE:
			app_addresses.append(address)
	if app_addresses.is_empty():
		return {"ok": false, "log": "0xFE0000-0xFEFFFF 没有用户代码"}
	if not high_addresses.is_empty() and high_addresses.max() >= VECTOR_LIMIT:
		return {"ok": false, "log": "向量数据越过 0xFF1000"}
	var map_text := FileAccess.get_file_as_string(map_path)
	var map_result := _validate_map_areas(map_text)
	if not bool(map_result.get("ok", false)):
		return map_result
	for symbol in ["__sdcc_mcs251_reset_trampoline", "__sdcc_gsinit_startup", "_Default_Isr"]:
		if not map_text.contains(symbol):
			return {"ok": false, "log": "MAP 缺少启动符号：%s" % symbol}
	return {"ok": true, "log": "[PASS] SDCC 布局校验：%d 字节" % image.size()}


func _parse_hex(path: String) -> Dictionary:
	var image: Dictionary = {}
	var upper := 0
	var line_number := 0
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		line_number += 1
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if not line.begins_with(":") or ((line.length() - 1) % 2) != 0:
			return {"ok": false, "log": "HEX 第 %d 行格式无效" % line_number}
		var bytes: Array[int] = []
		for pos in range(1, line.length(), 2):
			bytes.append(line.substr(pos, 2).hex_to_int())
		if bytes.size() < 5:
			return {"ok": false, "log": "HEX 第 %d 行过短" % line_number}
		var checksum := 0
		for value in bytes:
			checksum = (checksum + value) & 0xFF
		if checksum != 0:
			return {"ok": false, "log": "HEX 第 %d 行校验和错误" % line_number}
		var count := bytes[0]
		if bytes.size() != count + 5:
			return {"ok": false, "log": "HEX 第 %d 行长度错误" % line_number}
		var address := (bytes[1] << 8) | bytes[2]
		var record_type := bytes[3]
		if record_type == 0:
			for offset in range(count):
				image[upper + address + offset] = bytes[4 + offset]
		elif record_type == 4 and count == 2:
			upper = ((bytes[4] << 8) | bytes[5]) << 16
		elif record_type == 1:
			break
	if image.is_empty():
		return {"ok": false, "log": "HEX 不包含数据"}
	return {"ok": true, "data": image}


func _validate_map_areas(map_text: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("(?m)^\\s*(HOME|GSINIT|GSFINAL|CSEG|CONST|XINIT|XISEG|DSEG|SSEG|PSEG|XSEG)\\s+([0-9A-Fa-f]{8})\\s+([0-9A-Fa-f]{8})\\s+=") != OK:
		return {"ok": false, "log": "无法解析 MAP"}
	for match in regex.search_all(map_text):
		var name := match.get_string(1)
		var start := match.get_string(2).hex_to_int()
		var length := match.get_string(3).hex_to_int()
		var end := start + length
		if name == "HOME" and (start != VECTOR_BASE or end > VECTOR_LIMIT):
			return {"ok": false, "log": "HOME 区域越界"}
		if name in ["GSINIT", "GSFINAL", "CSEG", "CONST", "XINIT"] and length > 0 \
				and not (start >= APP_BASE and start < VECTOR_BASE and end <= VECTOR_BASE):
			return {"ok": false, "log": "%s 区域越界" % name}
		if name in ["XSEG", "XISEG"] and length > 0 \
				and not (start >= XRAM_BASE and end <= XRAM_LIMIT):
			return {"ok": false, "log": "%s 超出 XRAM" % name}
		if name in ["DSEG", "SSEG", "PSEG"] and length > 0 \
				and not (start >= 0 and end <= IRAM_LIMIT):
			return {"ok": false, "log": "%s 超出 EDATA" % name}
	return {"ok": true}


func _resolve_bundle_source() -> String:
	var override := OS.get_environment(SDCC_ENV_VAR).strip_edges()
	if not override.is_empty() and DirAccess.dir_exists_absolute(override):
		return override
	if DirAccess.dir_exists_absolute(to_abs(TOOLCHAIN_SRC)):
		return TOOLCHAIN_SRC
	return ""


func _bundle_version(source: String) -> String:
	var path := source.path_join(BUNDLE_MANIFEST)
	if not FileAccess.file_exists(path):
		return ""
	var parsed := _read_json_dictionary(path)
	return str(parsed.get("version", ""))


static func _read_json_dictionary(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


func _sdcc_path() -> String:
	return to_abs(TOOLCHAIN_DST).path_join("bin/sdcc.exe")


func _deployment_complete() -> bool:
	return FileAccess.file_exists(_sdcc_path()) \
		and FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join("bin/sdcpp.exe")) \
		and FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join("bin/sdas251.exe")) \
		and FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join("bin/sdld.exe")) \
		and FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join(
			"libexec/sdcc/x86_64-pc-mingw64/12.1.0/cc1.exe")) \
		and FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join("lib/mcs251-large-stack-auto/mcs251.lib")) \
		and FileAccess.file_exists(to_abs(FIRMWARE_DST).path_join("build_manifest.json"))


func _copy_tree(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(to_abs(destination)) != OK:
		return false
	var directory := DirAccess.open(source)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry in [".", ".."] or entry.begins_with(".") or entry == "build":
			entry = directory.get_next()
			continue
		var source_item := source.path_join(entry)
		var destination_item := destination.path_join(entry)
		if directory.current_is_dir():
			if not _copy_tree(source_item, destination_item):
				directory.list_dir_end()
				return false
		else:
			var input := FileAccess.open(source_item, FileAccess.READ)
			var output := FileAccess.open(to_abs(destination_item), FileAccess.WRITE)
			if input == null or output == null:
				directory.list_dir_end()
				return false
			output.store_buffer(input.get_buffer(input.get_length()))
			input.close()
			output.close()
		entry = directory.get_next()
	directory.list_dir_end()
	return true


func _remove_tree(path: String) -> void:
	var absolute := to_abs(path)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var item := absolute.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(item)
		else:
			DirAccess.remove_absolute(item)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)


func _remove_file(path: String) -> void:
	var absolute := to_abs(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _atomic_copy(source: String, destination: String) -> bool:
	var destination_abs := to_abs(destination)
	if DirAccess.make_dir_recursive_absolute(destination_abs.get_base_dir()) != OK:
		return false
	var temporary := destination_abs + ".tmp"
	_remove_file(temporary)
	var input := FileAccess.open(source, FileAccess.READ)
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if input == null or output == null:
		return false
	output.store_buffer(input.get_buffer(input.get_length()))
	input.close()
	output.close()
	_remove_file(destination_abs)
	return DirAccess.rename_absolute(temporary, destination_abs) == OK
