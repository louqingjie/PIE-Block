class_name Toolchain
extends RefCounted

## Keil C251 工具链管理。
## 从 ui.gd 抽出，供图形化界面、AI 代码编辑器、以及后续编译 MCP 共用。
##
## 职责：
##   - 把 res://（导出后是 PCK 只读）中的工具链/项目模板/库文件部署到 user://（可写）
##   - 动态生成 TOOLS.INI（PATH 必须是绝对路径 + 反斜杠）
##   - 探测 uVision.com / UV4.exe
##   - 同步执行编译并返回日志
##
## 日志通过构造时传入的 Callable 输出（一般接到 output.gd 的 append_line），
## 这样非 UI 调用方（如 MCP 工具）也能复用同一套逻辑。


# ------------------------------------------------------------------ 路径常量
## Keil 工具链源路径（res://，打包进 pck，只读）
const TOOLCHAIN_SRC: String = "res://stc32g/toolchain/Keil_noarm"
## 工具链解压目标路径（user://，可写，TOOLS.INI 需动态生成绝对路径）
const TOOLCHAIN_DST: String = "user://keil"
## 步兵项目模板
const PROJECT_SRC: String = "res://stc32g/Projects/ROBOMASTER_INFANTRY"
const PROJECT_DST: String = "user://stc32g/Projects/ROBOMASTER_INFANTRY"
## 工程师项目模板
const PROJECT_ENGINEER_SRC: String = "res://stc32g/Projects/ROBOMASTER_ENGINEER"
const PROJECT_ENGINEER_DST: String = "user://stc32g/Projects/ROBOMASTER_ENGINEER"
## 库文件（uvproj 通过 ..\..\..\Libraries\ 相对引用，必须保持 stc32g/ 层级）
const LIBRARIES_SRC: String = "res://stc32g/Libraries"
const LIBRARIES_DST: String = "user://stc32g/Libraries"
## AI 编辑器的工作区根（opencode 以此为项目根，能读到 Libraries 头文件）
const WORKSPACE_DST: String = "user://stc32g"
## 编译日志文件名
const BUILD_LOG_NAME: String = "pie_block_build.log"
## 工具链版本标记（内容变更时触发重新解压）
const TOOLCHAIN_VERSION: String = "keil_noarm_v2"

## UV4 可执行文件候选名，按优先级排序：
## uVision.com 是控制台子系统版本，-b 批处理时不会弹出 GUI 窗口盖住本程序；
## UV4.exe 是 GUI 子系统版本，会弹窗抢焦点，仅作回退。
## 注：PackedStringArray 字面量不是常量表达式，故用 var 而非 const
var UV4_CANDIDATES: PackedStringArray = PackedStringArray(["uVision.com", "UV4.exe"])

## 日志输出回调，签名 func(line: String) -> void
var _log: Callable


func _init(log_sink: Callable = Callable()) -> void:
	_log = log_sink


func _emit(line_text: String) -> void:
	if _log.is_valid():
		_log.call(line_text)


# ------------------------------------------------------------------ 路径工具
## res:// 或 user:// 路径转 OS 绝对路径（供 OS.execute / FileAccess 使用）
static func to_abs(virt_path: String) -> String:
	return ProjectSettings.globalize_path(virt_path)


# ------------------------------------------------------------------ 部署
## 确保工具链和项目模板已从 res://（PCK 只读）解压到 user://（可写）。
## 首次运行或版本变更时执行全量复制；通过版本标记文件判断是否需要重新解压。
## 返回 true 表示就绪，false 表示失败（错误信息已通过日志回调输出）。
func ensure_deployed() -> bool:
	var ver_file: String = to_abs("user://keil/.pie_block_version")
	var need_extract: bool = true
	if FileAccess.file_exists(ver_file):
		var cur_ver: String = FileAccess.get_file_as_string(ver_file).strip_edges()
		if cur_ver == TOOLCHAIN_VERSION:
			# 工具链已解压且版本一致，检查关键文件是否还在
			if FileAccess.file_exists(to_abs(TOOLCHAIN_DST).path_join("UV4/uVision.com")):
				need_extract = false
	if need_extract:
		if not _extract_toolchain():
			return false
	# 项目模板始终确保存在（体积小，不做版本检查）
	if not DirAccess.dir_exists_absolute(to_abs(PROJECT_DST)):
		if not _copy_dir_recursive(PROJECT_SRC, PROJECT_DST):
			_emit("[Error] 无法复制项目模板到 user://，请检查磁盘空间")
			return false
	if not DirAccess.dir_exists_absolute(to_abs(PROJECT_ENGINEER_DST)):
		if not _copy_dir_recursive(PROJECT_ENGINEER_SRC, PROJECT_ENGINEER_DST):
			_emit("[Error] 无法复制工程师项目模板到 user://，请检查磁盘空间")
			return false
	# 库文件也需复制（uvproj 用相对路径引用 Libraries）
	if not DirAccess.dir_exists_absolute(to_abs(LIBRARIES_DST)):
		if not _copy_dir_recursive(LIBRARIES_SRC, LIBRARIES_DST):
			_emit("[Error] 无法复制库文件到 user://，请检查磁盘空间")
			return false
	return true


## 从 res://stc32g/toolchain/Keil_noarm 递归复制到 user://keil/
func _extract_toolchain() -> bool:
	_emit("首次运行：正在解压 Keil 工具链到 user://（约 68MB，请稍候）…")
	var src_abs: String = to_abs(TOOLCHAIN_SRC)
	var dst_abs: String = to_abs(TOOLCHAIN_DST)
	if not DirAccess.dir_exists_absolute(src_abs):
		_emit("[Error] 工具链源目录不存在: %s" % src_abs)
		return false
	if DirAccess.dir_exists_absolute(dst_abs):
		_remove_dir_recursive(TOOLCHAIN_DST)
	if not _copy_dir_recursive(TOOLCHAIN_SRC, TOOLCHAIN_DST):
		_emit("[Error] 工具链解压失败")
		return false
	var vf: FileAccess = FileAccess.open("user://keil/.pie_block_version", FileAccess.WRITE)
	if vf:
		vf.store_string(TOOLCHAIN_VERSION)
		vf.close()
	_emit("工具链解压完成")
	return true


## 递归复制目录（res:// -> user:// 或任意路径组合）
func _copy_dir_recursive(src_path: String, dst_path: String) -> bool:
	var src_abs: String = to_abs(src_path)
	var dst_abs: String = to_abs(dst_path)
	if not DirAccess.dir_exists_absolute(dst_abs):
		var err: int = DirAccess.make_dir_recursive_absolute(dst_abs)
		if err != OK:
			push_error("无法创建目录 %s（错误码 %d）" % [dst_abs, err])
			return false
	var da: DirAccess = DirAccess.open(src_abs)
	if da == null:
		push_error("无法打开源目录: %s" % src_abs)
		return false
	da.list_dir_begin()
	var entry_name: String = da.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = da.get_next()
			continue
		var src_item: String = src_path.path_join(entry_name)
		var dst_item: String = dst_path.path_join(entry_name)
		if da.current_is_dir():
			if not _copy_dir_recursive(src_item, dst_item):
				da.list_dir_end()
				return false
		else:
			if not _copy_file(src_item, dst_item):
				da.list_dir_end()
				return false
		entry_name = da.get_next()
	da.list_dir_end()
	return true


## 递归删除目录（user:// 路径）
## 注：DirAccess.remove_absolute_or_user() 在 Godot 4.7 不存在，用实例方法 remove()
func _remove_dir_recursive(dir_path: String) -> void:
	var abs_path: String = to_abs(dir_path)
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry_name: String = da.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = da.get_next()
			continue
		var item_path: String = dir_path.path_join(entry_name)
		if da.current_is_dir():
			_remove_dir_recursive(item_path)
		else:
			var item_da: DirAccess = DirAccess.open(to_abs(dir_path))
			if item_da:
				item_da.remove(entry_name)
		entry_name = da.get_next()
	da.list_dir_end()
	# 删除空目录本身：打开父目录，用 remove 删本目录名
	var parent_path: String = dir_path.get_base_dir()
	var dir_name: String = dir_path.get_file()
	var parent_da: DirAccess = DirAccess.open(to_abs(parent_path))
	if parent_da:
		parent_da.remove(dir_name)


## 复制单个文件
func _copy_file(src_path: String, dst_path: String) -> bool:
	var src_abs: String = to_abs(src_path)
	var dst_abs: String = to_abs(dst_path)
	var src_f: FileAccess = FileAccess.open(src_abs, FileAccess.READ)
	if src_f == null:
		push_error("无法读取: %s" % src_abs)
		return false
	var dst_f: FileAccess = FileAccess.open(dst_abs, FileAccess.WRITE)
	if dst_f == null:
		push_error("无法写入: %s" % dst_abs)
		src_f.close()
		return false
	var buf_size: int = 65536
	while src_f.get_position() < src_f.get_length():
		dst_f.store_buffer(src_f.get_buffer(buf_size))
	src_f.close()
	dst_f.close()
	return true


# ------------------------------------------------------------------ 编译器探测
## 在 user://keil/ 中探测 Keil 命令行编译器；找不到返回空串
## 优先 uVision.com（控制台子系统，-b 不弹 GUI 窗口），回退 UV4.exe（GUI 子系统，会弹窗）
func find_uv4() -> String:
	var dir_abs: String = to_abs(TOOLCHAIN_DST)
	# UV4 子目录是标准布局
	var uv4_dir: String = dir_abs.path_join("UV4")
	for cand in UV4_CANDIDATES:
		var candidate: String = uv4_dir.path_join(cand)
		if FileAccess.file_exists(candidate):
			return candidate
	# 回退：深度优先递归扫描（用户布局可能是 Keil_v5/UV4/ 两层深）
	return _find_uv4_recursive(dir_abs)


func _find_uv4_recursive(dir_abs: String) -> String:
	var da: DirAccess = DirAccess.open(dir_abs)
	if da == null:
		return ""
	da.list_dir_begin()
	var entry_name: String = da.get_next()
	var found: String = ""
	while entry_name != "" and found == "":
		if da.current_is_dir() and not entry_name.begins_with("."):
			var sub_dir: String = dir_abs.path_join(entry_name)
			for cand in UV4_CANDIDATES:
				var candidate: String = sub_dir.path_join(cand)
				if FileAccess.file_exists(candidate):
					found = candidate
					break
			if found == "":
				found = _find_uv4_recursive(sub_dir)
		entry_name = da.get_next()
	da.list_dir_end()
	return found


# ------------------------------------------------------------------ TOOLS.INI
## 动态生成 TOOLS.INI：PATH 用绝对路径指向 user://keil/C251/
## TOOLS.INI 必须与 uVision.com 同级或在其上级目录（UV4/ 的上级 = keil/）
## 注意：Keil C251 的 PATH 必须使用反斜杠（\\），正斜杠会导致
## "failed to execute C251.EXE" 错误。末尾必须以单个反斜杠结尾。
func generate_tools_ini() -> bool:
	var keil_abs: String = to_abs(TOOLCHAIN_DST).replace("/", "\\")
	var c251_path: String = keil_abs + "\\C251\\"
	var ini_abs: String = keil_abs + "\\TOOLS.INI"
	var template_abs: String = to_abs(TOOLCHAIN_SRC.path_join("TOOLS.INI"))
	var content: String = ""
	if FileAccess.file_exists(template_abs):
		content = FileAccess.get_file_as_string(template_abs)
	else:
		content = "[C251]\nPATH=\"\"\nVERSION=5.60\n"
	# 替换 [C251] 段的 PATH 为绝对路径。
	# 注意：源文件是 CRLF 换行，split("\n") 后行末残留 \r，
	# 因此 strip_edges 必须同时去掉首尾空白，否则段名匹配永远失败。
	var lines: PackedStringArray = content.split("\n", false)
	var in_c251: bool = false
	var output_lines: PackedStringArray = PackedStringArray()
	for line in lines:
		var stripped: String = line.strip_edges(true, true)
		if stripped.to_upper() == "[C251]":
			in_c251 = true
		elif stripped.begins_with("[") and stripped.ends_with("]") and in_c251:
			in_c251 = false
		if in_c251 and stripped.to_upper().begins_with("PATH="):
			output_lines.append('PATH="%s"' % c251_path)
		else:
			output_lines.append(line)
	var f: FileAccess = FileAccess.open(ini_abs, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 TOOLS.INI: %s" % ini_abs)
		return false
	f.store_string("\n".join(output_lines) + "\n")
	f.close()
	return true


# ------------------------------------------------------------------ main.c 读写
## 把代码写入指定项目的 USER/src/main.c
func write_main_c(project_dst: String, code: String) -> bool:
	var abs_path: String = to_abs(project_dst.path_join("USER/src/main.c"))
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 main.c: %s（%s）" % [abs_path, FileAccess.get_open_error()])
		return false
	f.store_string(code)
	f.close()
	return true


## 读取指定项目的 main.c；文件不存在返回空串
func read_main_c(project_dst: String) -> String:
	var abs_path: String = to_abs(project_dst.path_join("USER/src/main.c"))
	if not FileAccess.file_exists(abs_path):
		return ""
	return FileAccess.get_file_as_string(abs_path)


## main.c 的最后修改时间（秒）；文件不存在返回 0。用于检测 AI 是否改动过文件
func main_c_mtime(project_dst: String) -> int:
	var abs_path: String = to_abs(project_dst.path_join("USER/src/main.c"))
	if not FileAccess.file_exists(abs_path):
		return 0
	return FileAccess.get_modified_time(abs_path)


# ------------------------------------------------------------------ 编译
## 同步执行编译。会阻塞调用线程，UI 侧务必放在 Thread 里跑。
## 返回 {exit: int, log: String, ok: bool}
##
## 成功判据用日志里的 "0 Error(s)" 而非退出码：
## UV4 批处理实测即使有警告也返回 0，退出码不可靠。
func build_sync(uv4_abs: String, project_dst: String) -> Dictionary:
	# OS.execute 不支持设工作目录，Godot 进程 cwd 是项目根而非 MDK，
	# 因此 uvproj 和日志都必须传绝对路径，且转反斜杠兼容 Windows 原生程序。
	var mdk_abs: String = to_abs(project_dst).path_join("MDK").replace("/", "\\")
	var uvproj_abs: String = mdk_abs + "\\Project_Template.uvproj"
	var log_abs: String = mdk_abs + "\\" + BUILD_LOG_NAME
	var uv4_win: String = uv4_abs.replace("/", "\\")
	var output: Array = []
	var exit_code: int = OS.execute(uv4_win, ["-b", uvproj_abs, "-o", log_abs], output, true)
	var log_text: String = ""
	if FileAccess.file_exists(log_abs):
		log_text = FileAccess.get_file_as_string(log_abs)
	return {
		"exit": exit_code,
		"log": log_text,
		"ok": (not log_text.is_empty()) and log_text.find("0 Error(s)") >= 0,
	}


## 一步到位的编译入口：部署 -> 写盘 -> 生成 TOOLS.INI -> 编译。
## 供 MCP 工具等非 UI 调用方使用（同步阻塞）。
## 返回 {exit, log, ok} 或 {ok: false, log: "<错误说明>"}
func build_project(project_dst: String, code: String = "") -> Dictionary:
	if not ensure_deployed():
		return {"ok": false, "exit": -1, "log": "工具链部署失败"}
	if not code.is_empty():
		if not write_main_c(project_dst, code):
			return {"ok": false, "exit": -1, "log": "写入 main.c 失败"}
	var uv4_abs: String = find_uv4()
	if uv4_abs.is_empty():
		return {"ok": false, "exit": -1, "log": "未找到 uVision.com / UV4.exe"}
	if not generate_tools_ini():
		_emit("[Warn] TOOLS.INI 生成失败，编译可能报错")
	return build_sync(uv4_abs, project_dst)
