extends SceneTree

## 内置 OpenCode 运行时部署测试：使用小型夹具验证原子部署、版本替换和损坏恢复。

const RUNTIME = preload("res://scripts/opencode_runtime.gd")
const SRC := "user://_test_opencode_source"
const DST := "user://_test_opencode_runtime"

var _fail := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if not detail.is_empty() else ""])
		_fail += 1


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _write_manifest(version: String, bytes: PackedByteArray, sha_override: String = "") -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var sha: String = context.finish().hex_encode() if sha_override.is_empty() else sha_override
	var file := FileAccess.open(SRC.path_join("bundle_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": version,
		"platform": "windows",
		"architecture": "x86_64",
		"executable": "opencode.exe",
		"sha256": sha,
	}, "  "))
	file.close()


func _initialize() -> void:
	var runtime = RUNTIME.new()
	runtime._remove_tree(SRC)
	runtime._remove_tree(DST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SRC))
	var v1 := "fake-opencode-v1".to_utf8_buffer()
	_write(SRC.path_join("opencode.exe"), v1)
	_write(SRC.path_join("LICENSE.txt"), "MIT fixture".to_utf8_buffer())
	_write_manifest("1.0.0", v1)
	runtime.manifest_src = SRC.path_join("bundle_manifest.json")
	runtime.runtime_src = SRC
	runtime.runtime_dst = DST

	var first: Dictionary = runtime.ensure_deployed()
	_check("首次部署成功", bool(first.get("ok", false)), str(first.get("reason", "")))
	_check("返回固定版本", str(first.get("version", "")) == "1.0.0")
	_check("部署内容正确", FileAccess.get_file_as_bytes(DST.path_join("opencode.exe")) == v1)
	var first_mtime := FileAccess.get_modified_time(DST.path_join("opencode.exe"))
	var second: Dictionary = runtime.ensure_deployed()
	_check("完整运行时重复调用幂等", bool(second.get("ok", false))
		and FileAccess.get_modified_time(DST.path_join("opencode.exe")) == first_mtime)

	_write(DST.path_join("opencode.exe"), "tampered".to_utf8_buffer())
	var repaired: Dictionary = runtime.ensure_deployed()
	_check("部署文件被修改后自动恢复", bool(repaired.get("ok", false))
		and FileAccess.get_file_as_bytes(DST.path_join("opencode.exe")) == v1)

	var v2 := "fake-opencode-v2".to_utf8_buffer()
	_write(SRC.path_join("opencode.exe"), v2)
	_write_manifest("2.0.0", v2)
	var upgraded: Dictionary = runtime.ensure_deployed()
	_check("清单升级后原子替换", bool(upgraded.get("ok", false))
		and str(upgraded.get("version", "")) == "2.0.0"
		and FileAccess.get_file_as_bytes(DST.path_join("opencode.exe")) == v2)

	_write_manifest("2.0.0", v2, "0".repeat(64))
	var bad_hash: Dictionary = runtime.ensure_deployed()
	_check("内置源哈希错误时拒绝部署", not bool(bad_hash.get("ok", true))
		and str(bad_hash.get("reason", "")).contains("校验失败"))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SRC.path_join("opencode.exe")))
	var missing: Dictionary = runtime.ensure_deployed()
	_check("内置源缺失时给出重装提示", not bool(missing.get("ok", true))
		and str(missing.get("reason", "")).contains("重新安装"))

	runtime._remove_tree(SRC)
	runtime._remove_tree(DST)
	print("=== 结果：%d 项失败 ===" % _fail)
	quit(1 if _fail > 0 else 0)
