extends SceneTree

## 验证 AI 工作区按构型生成 AGENTS.md 与 .gitignore（方案C）。
## 运行：godot --headless --path . --script scripts/test_ai_workspace.gd

const AT = preload("res://scripts/agent_terminal.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _run() -> void:
	var at: Node = AT.new()
	root.add_child(at)
	var ws: String = "user://_test_ai_ws"

	# ---- 步兵构型 ----
	_check("ensure_workspace(infantry) 成功", at.ensure_workspace(ws, "infantry"))
	var agents: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(ws).path_join("AGENTS.md"))
	_check("步兵 AGENTS 标明当前构型", agents.contains("当前构型：步兵"), agents.substr(0, 200))
	_check("步兵 AGENTS 指明唯一 main.c", agents.contains("Projects/ROBOMASTER_INFANTRY/USER/src/main.c"))
	_check("步兵 AGENTS 禁止工程目录", agents.contains("Projects/ROBOMASTER_ENGINEER/"))
	_check("步兵 AGENTS 禁止工程逆解算目录", agents.contains("Projects/ROBOMASTER_ENGINEER_SIM/"))
	_check("步兵 AGENTS 不出现占位符", not agents.contains("{{"))
	var gi: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(ws).path_join(".gitignore"))
	_check("步兵 gitignore 隐藏工程", gi.contains("Projects/ROBOMASTER_ENGINEER/"))
	_check("步兵 gitignore 隐藏工程逆解算", gi.contains("Projects/ROBOMASTER_ENGINEER_SIM/"))
	_check("步兵 gitignore 保留步兵项目", not gi.contains("Projects/ROBOMASTER_INFANTRY/"))

	# ---- 工程构型 ----
	_check("ensure_workspace(engineer) 成功", at.ensure_workspace(ws, "engineer"))
	agents = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(ws).path_join("AGENTS.md"))
	_check("工程 AGENTS 标明当前构型", agents.contains("当前构型：工程"), agents.substr(0, 200))
	_check("工程 AGENTS 指明唯一 main.c", agents.contains("Projects/ROBOMASTER_ENGINEER/USER/src/main.c"))
	_check("工程 AGENTS 禁止步兵目录", agents.contains("Projects/ROBOMASTER_INFANTRY/"))
	gi = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(ws).path_join(".gitignore"))
	_check("工程 gitignore 隐藏步兵", gi.contains("Projects/ROBOMASTER_INFANTRY/"))
	_check("工程 gitignore 保留工程项目", not gi.contains("Projects/ROBOMASTER_ENGINEER/"))

	# ---- 调试构型（共用步兵模板） ----
	_check("ensure_workspace(debug) 成功", at.ensure_workspace(ws, "debug"))
	agents = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(ws).path_join("AGENTS.md"))
	_check("调试 AGENTS 标明当前构型", agents.contains("当前构型：调试"))
	_check("调试 AGENTS 指向步兵 main.c", agents.contains("Projects/ROBOMASTER_INFANTRY/USER/src/main.c"))

	# 清理测试目录
	var abs: String = ProjectSettings.globalize_path(ws)
	if DirAccess.dir_exists_absolute(abs):
		DirAccess.remove_absolute(abs)

	print("=== 结果：%d 项失败 ===" % _fail)
	quit(1 if _fail > 0 else 0)


func _initialize() -> void:
	_run()