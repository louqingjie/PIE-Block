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
## 下载日志文件名。放在 STCFLASH_DST 下。
## 走文件而不是 OS.execute 的 output 数组：后者在 Windows 中文环境按 GBK
## 解码，我们的脚本输出 UTF-8，直接读会乱码。
const DOWNLOAD_LOG_NAME: String = "pie_block_download.log"
## 工具链版本标记（内容变更时触发重新解压）
const TOOLCHAIN_VERSION: String = "keil_noarm_v3"

## 项目模板版本。**改动 uvproj 或库文件后必须跡这个字符串**，
## 否则已经跑过一次的用户那里 user:// 不会更新，他们会拿旧配置编译
## 而且没有任何提示。
##
## 这个机制是踩过坑才加的：原先项目模板“目录存在就跳过”，
## 给四个 App 打完 bootloader 共存配置后，user:// 里仍是旧版，
## 表现为下载时报“0xFF1000 已被占用”—— 错误信息距真因很远。
##
## v2: 四个 App uvproj 加上 bootloader 共存所需的五项配置
##     （RomSize=4 / Ocm1 / INTVECTOR / 链接器 CLASSES / HexSelection）
## v3: 链接器 CODE 起点 0xFF1003 -> 0xFF1200。前者会让链接器把
##     ?CO?MAIN（命令字常量）填进 0xFF1003，而那里是 interrupt 0
##     的中断入口（bootloader 蹦床 MAPISR 0003H 的转发目标）。
##     必须跳过整个中断向量表区（67 个入口 x 8 字节 = 536）。
const PROJECT_VERSION: String = "proj_v3_code_after_vectors"

## STC 烧录脚本路径（Python）
const STCFLASH_SRC: String = "res://stc32g/toolchain/stcflash"
## 烧录脚本部署目标
const STCFLASH_DST: String = "user://stcflash"

## bootloader 的波特率。它在 PIE_BOOTLOADER/USER/inc/config.h 里由
## `BAUD = 65536 - FOSC/4/115200` 编译期写死，改那边必须同步改这里。
## 蓝牙模块也必须配成同一个波特率。
const DEFAULT_BOOT_BAUD: int = 115200
## App 的 UART1 波特率，用于发 @PIEIAP# 触发命令。
##
## 230400 是项目既有约定（见 docs/RM电控指南.md 与四个生成器的 UART_Init），
## 不要为了迁就 bootloader 而改它 —— 那个数值可能还牵涉遥控器与调试工具。
## 触发字必须按这个波特率发，否则 App 的 UART1 中断收不到，
## 表现为"bootloader 没有响应"（踩过：把它改成 115200 后下载全失败）。
##
## 于是下载过程有一次波特率切换：230400 发触发字 → 115200 跟 bootloader 通信。
## **蓝牙链路上这个切换做不到**（模块波特率配死），所以走蓝牙时必须让
## App 与 bootloader 同为 115200，见 bluetooth_baud_note()。
const DEFAULT_APP_BAUD: int = 230400

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
	# 项目模板与库文件：版本不匹配或内容缺失时重新部署。
	#
	# 两个判据都必要：
	#   版本不匹配 —— uvproj 改了但 user:// 仍是旧的（踩过）
	#   内容缺失 —— 目录在但文件没了（手工清理过、复制中途失败）
	# 只查目录存在的话，前者会让用户拿旧配置编译且毫无提示，
	# 后者会卡在“写 main.c 失败”这类下游错误上。
	var proj_ver_file: String = to_abs(WORKSPACE_DST).path_join(".pie_block_proj_version")
	var proj_ver: String = ""
	if FileAccess.file_exists(proj_ver_file):
		proj_ver = FileAccess.get_file_as_string(proj_ver_file).strip_edges()
	var need_redeploy: bool = (proj_ver != PROJECT_VERSION)
	if need_redeploy and not proj_ver.is_empty():
		_emit("项目模板有更新，正在重新部署（%s → %s）…"
			% [proj_ver, PROJECT_VERSION])

	for pair in [
		[PROJECT_SRC, PROJECT_DST, "项目模板"],
		[PROJECT_ENGINEER_SRC, PROJECT_ENGINEER_DST, "工程项目模板"],
	]:
		if need_redeploy or not _project_deployed(str(pair[1])):
			if not _copy_dir_recursive(str(pair[0]), str(pair[1])):
				_emit("[Error] 无法复制%s到 user://，请检查磁盘空间" % str(pair[2]))
				return false

	# 库文件（uvproj 用相对路径引用 Libraries）
	if need_redeploy or not FileAccess.file_exists(
			to_abs(LIBRARIES_DST).path_join("startup/inc/STC32Gxx.h")):
		if not _copy_dir_recursive(LIBRARIES_SRC, LIBRARIES_DST):
			_emit("[Error] 无法复制库文件到 user://，请检查磁盘空间")
			return false

	if need_redeploy:
		var vf: FileAccess = FileAccess.open(proj_ver_file, FileAccess.WRITE)
		if vf != null:
			vf.store_string(PROJECT_VERSION)
			vf.close()
	return true


## 判断一个项目是否完整部署过。
## 查 uvproj 与 main.c 所在目录 —— 前者是编译入口，后者是写代码的目标，
## 缺任何一个后续都会失败。
func _project_deployed(project_dst: String) -> bool:
	var base: String = to_abs(project_dst)
	if not FileAccess.file_exists(base.path_join("MDK/Project_Template.uvproj")):
		return false
	if not DirAccess.dir_exists_absolute(base.path_join("USER/src")):
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
		return {"ok": false, "exit": - 1, "log": "工具链部署失败"}
	if not code.is_empty():
		if not write_main_c(project_dst, code):
			return {"ok": false, "exit": - 1, "log": "写入 main.c 失败"}
	var uv4_abs: String = find_uv4()
	if uv4_abs.is_empty():
		return {"ok": false, "exit": - 1, "log": "未找到 uVision.com / UV4.exe"}
	if not generate_tools_ini():
		_emit("[Warn] TOOLS.INI 生成失败，编译可能报错")
	return build_sync(uv4_abs, project_dst)


# ------------------------------------------------------------------ 烧录
## 部署烧录脚本到 user://stcflash/
func ensure_stcflash_deployed() -> bool:
	var dst_abs: String = to_abs(STCFLASH_DST)
	# 每次都覆盖复制，避免旧脚本残留（尤其是协议脚本迭代期）
	if DirAccess.dir_exists_absolute(dst_abs):
		_remove_dir_recursive(STCFLASH_DST)
	if not _copy_dir_recursive(STCFLASH_SRC, STCFLASH_DST):
		_emit("[Error] 无法复制烧录脚本到 user://stcflash/")
		return false
	return true


## 探测系统 Python 可执行文件路径。
## 优先级：python3 > python > py
## 返回绝对路径，找不到返回空串。
func find_python() -> String:
	for name in ["python3", "python", "py"]:
		var output: Array = []
		var exit_code: int = OS.execute(name, ["--version"], output, true)
		if exit_code == 0:
			# 获取绝对路径
			var which_out: Array = []
			if name == "py":
				OS.execute("where", ["py"], which_out, true)
			else:
				OS.execute("where", [name], which_out, true)
			if which_out.size() > 0:
				var path: String = which_out[0].strip_edges().split("\n")[0].strip_edges()
				if not path.is_empty() and FileAccess.file_exists(path):
					return path
			return name
	return ""


## 获取编译产物 hex 文件路径
func get_hex_path(project_dst: String) -> String:
	var mdk_abs: String = to_abs(project_dst).path_join("MDK")
	return mdk_abs.path_join("Objects").path_join("Project_Template.hex")


## 检查 hex 文件是否存在
func hex_exists(project_dst: String) -> bool:
	return FileAccess.file_exists(get_hex_path(project_dst))


## 向串口发送 @STCISP# 命令触发芯片软复位进 ISP 模式
## 返回 true 表示发送成功
func trigger_isp(com_port: String) -> bool:
	var py: String = find_python()
	if py.is_empty():
		_emit("[Error] 未找到 Python，无法发送 ISP 触发命令")
		return false
	if not ensure_stcflash_deployed():
		return false

	var script: String = to_abs(STCFLASH_DST).path_join("trigger_isp.py")
	var f: FileAccess = FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		_emit("[Error] 无法创建 trigger_isp.py")
		return false
	f.store_string("""
import sys
import time
try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed")
    sys.exit(1)

port = sys.argv[1]
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 230400
try:
    ser = serial.Serial(port, baud, timeout=0.5, parity=serial.PARITY_NONE)
    ser.reset_input_buffer()
    ser.write(b"@STCISP#")
    ser.flush()
    time.sleep(0.1)
    ser.close()
    print("OK")
except Exception as e:
    print("ERROR: " + str(e))
    sys.exit(1)
""")
	f.close()

	var output: Array = []
	var cmd: String = py.replace("/", "\\")
	# 用户程序 UART1 默认 230400；必须匹配，否则 @STCISP# 收不到
	var exit_code: int = OS.execute(cmd, [script, com_port, "230400"], output, true)
	var result: String = ""
	if output.size() > 0:
		result = output[0].strip_edges()

	if exit_code != 0 or not result.contains("OK"):
		_emit("[Error] 发送 ISP 触发命令失败: %s" % result)
		return false

	_emit("已发送 @STCISP# 命令，芯片将软复位进 ISP 模式")
	return true


## 走芯片 ROM ISP + stcgal 烧录 hex。**日常下载不要用这个，用 download_hex_iap。**
##
## 保留它的理由：ROM ISP 是芯片固化的，任何情况下都能用，
## 属于兜底手段。但它有三个硬伤，正是我们做自建 bootloader 的动因：
##   · 依赖 IRC 频率校准，trim 不准就连不上
##   · 握手固定 2400 波特率，蓝牙模块波特率配死后无法切换
##   · 必须在上电瞬间介入，意味着每次都要断电或按 Reset
## 出厂烧底走的是官方 STC-ISP 软件，也不经这个函数。
##
## 返回 {ok: bool, log: String}
## app_baud: 用户程序串口波特率（发 @STCISP#）
## isp_baud: ISP 监控程序通信波特率（发 0x7F / 协议包）
## mode: "uart" 软复位触发；"uart-power" 等待断电上电
func download_hex_uart(hex_path: String, com_port: String, app_baud: int = 230400, isp_baud: int = 115200, mode: String = "uart") -> Dictionary:
	var py: String = find_python()
	if py.is_empty():
		return {"ok": false, "log": "未找到 Python"}
	if not ensure_stcflash_deployed():
		return {"ok": false, "log": "烧录脚本部署失败"}

	var script: String = to_abs(STCFLASH_DST).path_join("pie_block_flash.py")
	var cmd: String = py.replace("/", "\\")
	var output: Array = []
	var args: PackedStringArray = PackedStringArray()
	if mode == "uart-power":
		args = PackedStringArray([script, "uart-power", hex_path, com_port, str(isp_baud)])
	else:
		args = PackedStringArray([script, "uart", hex_path, com_port, str(app_baud), str(isp_baud)])
	var exit_code: int = OS.execute(cmd, args, output, true)

	var log_text: String = ""
	if output.size() > 0:
		log_text = output[0]

	# stcgal 在管道场景下退出码可能非 0，但日志含 Disconnected!/Setting options 即视为成功
	var ok: bool = (exit_code == 0) \
		or (log_text.find("Disconnected!") >= 0) \
		or (log_text.find("Setting options: done") >= 0) \
		or (log_text.find("烧录成功") >= 0)

	return {
		"ok": ok,
		"exit": exit_code,
		"log": log_text,
	}


## 通过自建 bootloader 的 IAP 协议烧录 hex（日常下载路径）
##
## 与 download_hex_uart 的区别：对话对象是常驻 0xFF0000 的自己的 bootloader，
## 不经 ROM ISP，因此不受 IRC trim 与 2400 握手波特率影响，
## 也不需要断电或按 Reset。物理链路可以是蓝牙串口。
## 前提是芯片出厂时已用官方 STC-ISP 烧过一次 bootloader
## （参数见 stc32g/Projects/PIE_BOOTLOADER/dist/README.md）。
##
## app_baud: App 的 UART1 波特率（发 @PIEIAP# 触发命令用）
## boot_baud: bootloader 的波特率，编译期写死在 config.h 里
## 返回 {ok: bool, exit: int, log: String, stage: String}
##   stage 用于失败时定位卡在哪一步，取值见 _classify_iap_failure
func download_hex_iap(hex_path: String, com_port: String,
		app_baud: int = DEFAULT_APP_BAUD,
		boot_baud: int = DEFAULT_BOOT_BAUD) -> Dictionary:
	var py: String = find_python()
	if py.is_empty():
		return {"ok": false, "exit": -1, "log": "未找到 Python", "stage": "env"}
	if not ensure_stcflash_deployed():
		return {"ok": false, "exit": -1, "log": "烧录脚本部署失败", "stage": "env"}

	var script: String = to_abs(STCFLASH_DST).path_join("pie_block_iap.py")
	var log_abs: String = to_abs(STCFLASH_DST).path_join(DOWNLOAD_LOG_NAME)
	var exit_code: int = _run_python_logged(
		py, [script, hex_path, com_port, str(app_baud), str(boot_baud)], log_abs)
	var log_text: String = _read_log(log_abs)

	# 脚本退出码可控，以它为准；日志关键字只作兜底
	var ok: bool = (exit_code == 0) or log_text.contains("烧录成功")

	return {
		"ok": ok,
		"exit": exit_code,
		"log": log_text,
		"stage": "done" if ok else _classify_iap_failure(log_text),
	}


## 跑 Python 脚本并把输出重定向到文件，返回退出码。
##
## 为什么不用 OS.execute 的 output 参数：那个数组在 Windows 上按系统代码页
## （中文环境是 GBK）解码，而我们的脚本输出 UTF-8，直接读会得到乱码
## （实测下载日志全是"鍥轰欢 30252 瀛楄妭"这种）。
## 编译路径一直是读日志文件所以没这个问题，这里跟它对齐。
func _run_python_logged(py: String, args: Array, log_abs: String) -> int:
	# 用 cmd /c 做重定向。PYTHONIOENCODING 保证脚本内的 print 输出 UTF-8，
	# 不依赖控制台代码页。
	var parts: PackedStringArray = PackedStringArray()
	parts.append("\"" + py.replace("/", "\\") + "\"")
	for a in args:
		parts.append("\"" + str(a).replace("/", "\\") + "\"")
	var cmd_line: String = "set PYTHONIOENCODING=utf-8 && " \
		+ " ".join(parts) + " > \"" + log_abs.replace("/", "\\") + "\" 2>&1"
	var output: Array = []
	return OS.execute("cmd.exe", ["/c", cmd_line], output, true)


## 读日志文件。Godot 的 get_file_as_string 按 UTF-8 解析，与脚本输出一致。
func _read_log(log_abs: String) -> String:
	if not FileAccess.file_exists(log_abs):
		return ""
	return FileAccess.get_file_as_string(log_abs)


## 从下载日志判断失败发生在哪一阶段，用于给出针对性提示。
##
## 顺序很重要：越靠后的阶段先判，因为日志是累积的 ——
## 卡在 PROGRAM 时日志里同样有前面 CONNECT 成功的字样。
func _classify_iap_failure(log_text: String) -> String:
	if log_text.contains("读回校验失败"):
		return "verify"
	if log_text.contains("PROGRAM"):
		return "program"
	if log_text.contains("ERASE"):
		return "erase"
	if log_text.contains("bootloader 没有响应"):
		return "connect"
	if log_text.contains("读取固件失败"):
		return "hex"
	if log_text.contains("打开串口"):
		return "port"
	return "unknown"


## 把失败阶段翻译成给用户看的排查建议。
## 目标用户没有嵌入式背景，所以每条都给可执行的动作而不是术语。
func iap_failure_hint(stage: String) -> PackedStringArray:
	match stage:
		"port":
			return PackedStringArray([
				"串口打不开。可能是：",
				"  · 端口被别的程序占用（串口助手、另一个 pie-block 窗口）",
				"  · 蓝牙已断开，重新配对一次",
			])
		"connect":
			return PackedStringArray([
				"联系不上板子上的引导程序。按顺序检查：",
				"  · 板子是否通电",
				"  · 选的串口是否正确（换个端口再试）",
				"  · 蓝牙模块波特率是否是 115200",
				"  · 这块板子是否烧过引导程序（新板需要出厂烧录一次）",
				"救急办法：把 P32 接到 GND 再上电，可强制进入下载模式",
			])
		"erase", "program":
			return PackedStringArray([
				"写入过程中断。板上的程序已被清除，但这不会损坏板子 ——",
				"引导程序会停在下载模式，直接再点一次下载即可。",
				"若反复失败，检查蓝牙信号或换用 USB 线。",
			])
		"verify":
			return PackedStringArray([
				"写入后读回校验不一致，固件未生效。",
				"引导程序仍在下载模式，可以直接重试。",
				"蓝牙链路丢包较多时容易出现，建议改用 USB 线。",
			])
		"hex":
			return PackedStringArray([
				"固件文件有问题，请重新编译。",
				"若反复出现，可能是工程配置被改动过。",
			])
		"env":
			return PackedStringArray([
				"运行环境缺少组件，请联系维护者。",
			])
		_:
			return PackedStringArray()


## 跑 IAP 协议脚本的自测（不需要串口，也不需要板子）
## 返回 {ok: bool, log: String}，供开发期回归用
func run_iap_selftest() -> Dictionary:
	var py: String = find_python()
	if py.is_empty():
		return {"ok": false, "log": "未找到 Python"}
	if not ensure_stcflash_deployed():
		return {"ok": false, "log": "烧录脚本部署失败"}

	var script: String = to_abs(STCFLASH_DST).path_join("pie_block_iap.py")
	var output: Array = []
	var exit_code: int = OS.execute(py.replace("/", "\\"), [script, "--selftest"], output, true)
	var log_text: String = ""
	if output.size() > 0:
		log_text = output[0]
	return {"ok": exit_code == 0, "log": log_text}


## 列举可用串口（只返回 COM 口名，保留给旧调用点）
func list_serial_ports() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for info in list_serial_ports_detailed():
		result.append(str(info.get("device", "")))
	return result


## 列举可用串口并带上识别信息。
##
## 返回 Array[Dictionary]，每项含：
##   device      COM 口名，如 "COM11"
##   description 描述串，如 "USB-SERIAL CH340 (COM11)"
##   hwid        硬件 ID，含 VID/PID
##   kind        我们归类出的类型：见下面 _classify_port
##   label       给用户看的一行说明
##
## 为什么要带识别信息：蓝牙场景下电脑上往往同时存在多个虚拟串口
## （蓝牙服务自带的、其他设备的），"取最后一个"这种猜法会连错。
func list_serial_ports_detailed() -> Array:
	var py: String = find_python()
	if py.is_empty():
		return []

	var script: String = to_abs("user://list_ports.py")
	var f: FileAccess = FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		return []
	# 用 \t 分隔而不是 JSON：描述串里可能有各种符号，
	# 制表符在 Windows 串口描述里不会出现，解析最省事。
	f.store_string("""
import sys
try:
    import serial.tools.list_ports
except ImportError:
    sys.exit(0)
for p in serial.tools.list_ports.comports():
    fields = [
        p.device or "",
        p.description or "",
        p.hwid or "",
        p.manufacturer or "",
    ]
    print("\\t".join(x.replace("\\t", " ") for x in fields))
""")
	f.close()

	var output: Array = []
	OS.execute(py.replace("/", "\\"), [script], output, true)
	if output.is_empty():
		return []

	var ports: Array = []
	for line in str(output[0]).split("\n", false):
		var row: String = line.strip_edges()
		if row.is_empty():
			continue
		var cols: PackedStringArray = row.split("\t")
		if cols.is_empty() or cols[0].strip_edges().is_empty():
			continue
		var device: String = cols[0].strip_edges()
		var desc: String = cols[1].strip_edges() if cols.size() > 1 else ""
		var hwid: String = cols[2].strip_edges() if cols.size() > 2 else ""
		var maker: String = cols[3].strip_edges() if cols.size() > 3 else ""
		var kind: String = _classify_port(desc, hwid, maker)
		ports.append({
			"device": device,
			"description": desc,
			"hwid": hwid,
			"manufacturer": maker,
			"kind": kind,
			"label": "%s  %s" % [device, desc if not desc.is_empty() else kind],
		})
	return ports


## 端口分类。用于把"能烧录的口"与"系统里凑数的虚拟口"分开。
##
## 分类值与优先级（数字越小越优先，见 pick_download_port）：
##   "usb_serial"  USB 转串口芯片，最可靠
##   "bluetooth"   蓝牙串口，无线烧录走这个
##   "unknown"     认不出来的，仍可尝试
##   "virtual"     系统自带的虚拟口，基本不是板子
func _classify_port(description: String, hwid: String, manufacturer: String) -> String:
	var hay: String = ("%s %s %s" % [description, hwid, manufacturer]).to_lower()

	# USB 转串口芯片。VID 比描述串可靠（描述会随驱动版本变）。
	# 1a86=沁恒(CH340/CH341)，0403=FTDI，10c4=SiLabs(CP210x)，
	# 067b=Prolific(PL2303)，1a86 之外国产板也常见 0403。
	for vid in ["1a86", "0403", "10c4", "067b"]:
		if hay.contains("vid_" + vid) or hay.contains("vid:pid=" + vid):
			return "usb_serial"
	for kw in ["ch340", "ch341", "cp210", "ft232", "pl2303", "usb-serial", "usb serial"]:
		if hay.contains(kw):
			return "usb_serial"

	# 蓝牙串口。Windows 上 HC-05/HC-06 配对后表现为
	# "标准串行over蓝牙链接"或 "Bluetooth Serial Port"。
	for kw in ["bluetooth", "蓝牙", "bthenum", "rfcomm", "spp"]:
		if hay.contains(kw):
			return "bluetooth"

	# 系统凑数的虚拟口：Windows 自带的通信端口、串行鼠标之类
	for kw in ["standard port", "communications port", "ports (com & lpt)"]:
		if hay.contains(kw):
			return "virtual"

	return "unknown"


## 从端口列表里挑一个用于下载。
##
## 返回 {ok: bool, device: String, reason: String, candidates: Array}
##
## 挑选规则：先按类型优先级过滤，同类型里若只剩一个就直接用；
## 若同类型有多个则**不猜**，返回 ok=false 让调用方询问用户 ——
## 连错口可能把数据发给别的设备，猜错的代价比多问一句大。
func pick_download_port(ports: Array = []) -> Dictionary:
	var list: Array = ports if not ports.is_empty() else list_serial_ports_detailed()
	if list.is_empty():
		return {
			"ok": false,
			"device": "",
			"reason": "未检测到任何串口",
			"candidates": [],
		}

	# 按可信度分组
	var groups: Dictionary = {"usb_serial": [], "bluetooth": [], "unknown": [], "virtual": []}
	for info in list:
		var kind: String = str(info.get("kind", "unknown"))
		if not groups.has(kind):
			kind = "unknown"
		groups[kind].append(info)

	for kind in ["usb_serial", "bluetooth", "unknown"]:
		var bucket: Array = groups[kind]
		if bucket.is_empty():
			continue
		if bucket.size() == 1:
			return {
				"ok": true,
				"device": str(bucket[0].get("device", "")),
				"reason": "识别为%s：%s" % [_kind_name(kind), bucket[0].get("label", "")],
				"candidates": bucket,
			}
		# 同类型多个，不猜
		return {
			"ok": false,
			"device": "",
			"reason": "检测到 %d 个%s，无法自动判断用哪个" % [bucket.size(), _kind_name(kind)],
			"candidates": bucket,
		}

	return {
		"ok": false,
		"device": "",
		"reason": "只找到系统虚拟串口，未发现板子",
		"candidates": groups["virtual"],
	}


func _kind_name(kind: String) -> String:
	match kind:
		"usb_serial":
			return "USB 转串口"
		"bluetooth":
			return "蓝牙串口"
		"virtual":
			return "系统虚拟串口"
		_:
			return "未知类型串口"


## 走蓝牙时的波特率限制说明。
##
## 下载过程正常需要两段波特率：230400 发触发字给 App，
## 115200 跟 bootloader 通信。USB 转串口可以随时切，蓝牙模块不行 ——
## 它的波特率在配对时就固定了，中途切换会让链路直接失联。
##
## 所以蓝牙链路要么把 App 也改成 115200（改四个生成器的 UART_Init），
## 要么把 bootloader 改成 230400（改 config.h 后重新烧底）。
## 两者都需要人工决定，不能在下载时自动处理，故只给提示。
func bluetooth_baud_note() -> PackedStringArray:
	return PackedStringArray([
		"检测到走蓝牙链路。注意波特率限制：",
		"  下载需要先用 %d 发触发命令，再用 %d 与引导程序通信，"
			% [DEFAULT_APP_BAUD, DEFAULT_BOOT_BAUD],
		"  而蓝牙模块的波特率是配对时固定的，中途切不了。",
		"  若下载失败，需要把两端统一成同一个波特率（改代码后重新烧底）。",
	])


## 探测某个串口上的 bootloader 是否在线。
##
## 用途：下载前确认端口选对了、板子上有 bootloader，
## 这样失败时能给出确切原因，而不是让用户面对一堆下载日志猜。
##
## 注意：正常情况下芯片跑的是 App 而不是 bootloader，直接发 CONNECT
## 会被 App 当成普通串口数据（实测会收到 App 自己的输出）。
## 所以这里必须先发触发字让 App 交出控制权 —— 与 download_hex_iap
## 的第一步是同一套逻辑，复用 pie_block_iap.py 的 connect 流程。
##
## 副作用：探测成功后芯片停在 bootloader 的下载模式，不再跑 App。
## 要恢复运行需重新下载固件或断电重启。因此不要在后台轮询调用它。
##
## 返回 {ok: bool, version: int, log: String}
func probe_bootloader(com_port: String, app_baud: int = DEFAULT_APP_BAUD,
		boot_baud: int = DEFAULT_BOOT_BAUD) -> Dictionary:
	var py: String = find_python()
	if py.is_empty():
		return {"ok": false, "version": 0, "log": "未找到 Python"}
	if not ensure_stcflash_deployed():
		return {"ok": false, "version": 0, "log": "烧录脚本部署失败"}

	var script: String = to_abs(STCFLASH_DST).path_join("pie_block_probe.py")
	var f: FileAccess = FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "version": 0, "log": "无法写探测脚本"}
	# 复用 pie_block_iap 的会话逻辑：trigger 让 App 复位，再 connect。
	# 写成独立脚本而不是给 pie_block_iap.py 加子命令，是为了让
	# 那个文件保持"只做下载"的单一职责。
	f.store_string("""
import sys
sys.path.insert(0, sys.argv[1])
import pie_block_iap as m

port = sys.argv[2]
app_baud = int(sys.argv[3])
boot_baud = int(sys.argv[4])

sess = m.IapSession(port, app_baud, boot_baud, verbose=True)
try:
    sess.open()
except Exception as exc:
    print("打开串口 %s 失败: %s" % (port, exc))
    sys.exit(1)
try:
    sess.trigger()
    ver = sess.connect()
    print("PROBE_OK version=0x%04X" % ver)
    sys.exit(0)
except m.ProtocolError as exc:
    print("探测失败: %s" % exc)
    sys.exit(1)
finally:
    sess.close()
""")
	f.close()

	var log_abs: String = to_abs(STCFLASH_DST).path_join("pie_block_probe.log")
	var exit_code: int = _run_python_logged(
		py,
		[script, to_abs(STCFLASH_DST), com_port, str(app_baud), str(boot_baud)],
		log_abs)
	var log_text: String = _read_log(log_abs)

	var version: int = 0
	var marker: String = "PROBE_OK version=0x"
	var idx: int = log_text.find(marker)
	if idx >= 0:
		version = log_text.substr(idx + marker.length(), 4).hex_to_int()

	return {
		"ok": exit_code == 0 and version > 0,
		"version": version,
		"log": log_text,
	}
