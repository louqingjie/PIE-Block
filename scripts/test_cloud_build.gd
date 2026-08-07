extends SceneTree
## 云端编译端到端测试（headless）：
## 配置云端（Base URL + API Key）-> 用 codegen 生成 main.c -> CloudCompiler 全流程
## （打包 -> base64 上传 -> 轮询 -> 下载 hex）-> 验证 hex 生成。
##
## 运行：
##   godot --headless --no-header --path . --script scripts/test_cloud_build.gd

func _init() -> void:
	# 1. 工具链 + 云端编译器
	var tc = load("res://scripts/toolchain.gd").new()
	var cloud = load("res://scripts/cloud_compiler.gd").new(tc)
	# 2. 配置云端（Base URL + API Key）
	var base_url: String = "http://127.0.0.1:8000"
	var api_key: String = OS.get_environment("PIEBLOCK_KEIL_API_KEY")
	if api_key.is_empty():
		api_key = "_5lPe-FDxwcuQlse" # 当前服务器的正式管理员 key
	tc.set_cloud_config(base_url, api_key)
	var ready: Dictionary = tc.ensure_cloud_ready()
	print("cloud ready: ", JSON.stringify(ready))
	if not ready.ok:
		quit(1)
		return
	# 3. 生成 main.c（步兵默认配置）
	var cfg_text: String = FileAccess.get_file_as_string("res://tools/test_infantry_config.json")
	var cfg: Variant = JSON.parse_string(cfg_text)
	var cg = load("res://scripts/codegen/codegen_infantry.gd").new()
	var code: String = cg.generate(cfg if cfg is Dictionary else {})
	print("code len: ", code.length())
	if code.strip_edges().is_empty():
		quit(2)
		return
	# 4. 云端编译（同步阻塞，走 CloudCompiler 全流程）
	var dst := "user://stc32g/Projects/ROBOMASTER_INFANTRY"
	var result: Dictionary = cloud._run_cloud_build(dst, code)
	var ok: bool = bool(result.get("ok", false))
	var hex_ok: bool = bool(result.get("hex_exists", false))
	print("hex path: ", result.get("hex", ""))
	print("ok=", ok, " hex_exists=", hex_ok)
	if not ok:
		print("--- log ---")
		print(str(result.get("log", "")))
	quit(0 if (ok and hex_ok) else 1)
