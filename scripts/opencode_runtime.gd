class_name OpenCodeRuntime
extends RefCounted

## PIEBlock 内置的 OpenCode Windows x64 运行时。
## 发布物位于只读 res://（导出后在内嵌 PCK 中），首次使用时原子部署到 user://。

const MANIFEST_SRC := "res://vendor/opencode-runtime/bundle_manifest.json"
const RUNTIME_SRC := "res://vendor/opencode-runtime"
const RUNTIME_DST := "user://opencode/runtime"
const VERSION_FILE := ".runtime_version"

var manifest_src: String = MANIFEST_SRC
var runtime_src: String = RUNTIME_SRC
var runtime_dst: String = RUNTIME_DST
var _log: Callable


func _init(log_sink: Callable = Callable()) -> void:
	_log = log_sink


func _emit(text: String) -> void:
	if _log.is_valid():
		_log.call(text)


static func to_abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(manifest_src):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_src))
	return parsed if parsed is Dictionary else {}


## 确保固定版本已部署并且内容哈希正确。
## 返回 {ok, executable, version, reason}。
func ensure_deployed() -> Dictionary:
	if OS.get_name() != "Windows":
		return _failure("内置 OpenCode 当前仅支持 Windows x64")
	var manifest := load_manifest()
	if manifest.is_empty():
		return _failure("OpenCode 运行时清单缺失；请重新安装 PIEBlock")
	if str(manifest.get("platform", "")) != "windows" \
			or str(manifest.get("architecture", "")) != "x86_64":
		return _failure("OpenCode 运行时平台与当前发布版不匹配")
	var version := str(manifest.get("version", ""))
	var executable_name := str(manifest.get("executable", ""))
	var expected_sha := str(manifest.get("sha256", "")).to_lower()
	if version.is_empty() or executable_name.is_empty() or expected_sha.length() != 64:
		return _failure("OpenCode 运行时清单损坏；请重新安装 PIEBlock")
	var source_executable := runtime_src.path_join(executable_name)
	if not FileAccess.file_exists(source_executable):
		return _failure("内置 OpenCode 文件缺失；请重新安装 PIEBlock")
	if FileAccess.get_sha256(source_executable).to_lower() != expected_sha:
		return _failure("内置 OpenCode 校验失败；文件可能已损坏，请重新安装 PIEBlock")

	var deployed_executable := runtime_dst.path_join(executable_name)
	if _deployment_complete(version, deployed_executable, expected_sha):
		return _success(version, deployed_executable)

	var suffix := str(OS.get_process_id())
	var pending := runtime_dst + ".pending." + suffix
	var backup := runtime_dst + ".backup." + suffix
	_remove_tree(pending)
	_remove_tree(backup)
	if DirAccess.make_dir_recursive_absolute(to_abs(pending)) != OK:
		return _failure("无法创建 OpenCode 运行时目录，请检查磁盘空间")
	_emit("正在准备内置 OpenCode %s…" % version)
	if not _copy_file(source_executable, pending.path_join(executable_name)):
		_remove_tree(pending)
		return _failure("无法解包 OpenCode，请检查磁盘空间")
	var license_src := runtime_src.path_join("LICENSE.txt")
	if FileAccess.file_exists(license_src) \
			and not _copy_file(license_src, pending.path_join("LICENSE.txt")):
		_remove_tree(pending)
		return _failure("无法部署 OpenCode 许可证文件")
	var version_file := FileAccess.open(pending.path_join(VERSION_FILE), FileAccess.WRITE)
	if version_file == null:
		_remove_tree(pending)
		return _failure("无法写入 OpenCode 运行时版本")
	version_file.store_string(version)
	version_file.close()
	if FileAccess.get_sha256(pending.path_join(executable_name)).to_lower() != expected_sha:
		_remove_tree(pending)
		return _failure("OpenCode 解包后的完整性校验失败")

	# 另一 PIEBlock 实例可能在本实例复制大文件期间已经完成部署。
	if _deployment_complete(version, deployed_executable, expected_sha):
		_remove_tree(pending)
		return _success(version, deployed_executable)
	if DirAccess.dir_exists_absolute(to_abs(runtime_dst)) \
			and DirAccess.rename_absolute(to_abs(runtime_dst), to_abs(backup)) != OK:
		_remove_tree(pending)
		return _failure("无法替换旧 OpenCode 运行时")
	if DirAccess.rename_absolute(to_abs(pending), to_abs(runtime_dst)) != OK:
		if DirAccess.dir_exists_absolute(to_abs(backup)):
			DirAccess.rename_absolute(to_abs(backup), to_abs(runtime_dst))
		_remove_tree(pending)
		return _failure("无法启用内置 OpenCode 运行时")
	_remove_tree(backup)
	if not _deployment_complete(version, deployed_executable, expected_sha):
		return _failure("OpenCode 部署后完整性检查失败")
	return _success(version, deployed_executable)


func _success(version: String, executable: String) -> Dictionary:
	return {
		"ok": true,
		"executable": to_abs(executable).replace("\\", "/"),
		"version": version,
		"reason": "",
	}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "executable": "", "version": "", "reason": reason}


func _deployment_complete(version: String, executable: String, expected_sha: String) -> bool:
	var version_path := runtime_dst.path_join(VERSION_FILE)
	return FileAccess.file_exists(version_path) \
		and FileAccess.get_file_as_string(version_path).strip_edges() == version \
		and FileAccess.file_exists(executable) \
		and FileAccess.get_sha256(executable).to_lower() == expected_sha


func _copy_file(source: String, destination: String) -> bool:
	var src := FileAccess.open(source, FileAccess.READ)
	if src == null:
		return false
	var dst := FileAccess.open(destination, FileAccess.WRITE)
	if dst == null:
		src.close()
		return false
	while src.get_position() < src.get_length():
		dst.store_buffer(src.get_buffer(1024 * 1024))
	src.close()
	dst.close()
	return true


func _remove_tree(path: String) -> void:
	var absolute := to_abs(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := absolute.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)
