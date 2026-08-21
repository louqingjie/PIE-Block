class_name Toolchain
extends RefCounted

## Keil C251 工具链管理。
## 从 ui.gd 抽出，供图形化界面、AI 代码编辑器、以及后续编译 MCP 共用。
##
## 职责：
##   - 把 res://（导出后是 PCK 只读）中的项目模板/库文件部署到 user://（可写）
##   - 管理用户指定的外部 Keil 目录（校验、持久化到 user://keil_settings.json）
##   - 探测外部 Keil 的 uVision.com / UV4.exe
##   - 同步执行编译并返回日志
##
## 编译只使用用户指定的外部 Keil 安装。
## 外部目录来源：环境变量 PIEBLOCK_KEIL > user://keil_settings.json。
##
## 日志通过构造时传入的 Callable 输出（一般接到 output.gd 的 append_line），
## 这样非 UI 调用方（如 MCP 工具）也能复用同一套逻辑。


# ------------------------------------------------------------------ 路径常量
## 外部 Keil 目录配置文件（user://，记录用户指定的 Keil 安装根目录）。
## JSON 格式 {"path": "C:\\Keil_v5"}；环境变量 PIEBLOCK_KEIL 优先级更高。
const KEIL_SETTINGS_PATH: String = "user://keil_settings.json"
## 首次启动自动探测状态（JSON：{"completed": true}）。
const KEIL_SCAN_STATE_PATH: String = "user://keil_scan_state.json"
## 指定外部 Keil 目录的环境变量（headless/CLI/CI 用，优先级高于配置文件）
const KEIL_ENV_VAR: String = "PIEBLOCK_KEIL"
## 云端编译服务器配置（user://，记录 Base URL 与 API Key）。
## JSON 格式 {"base_url": "https://build.pieblock.asia", "api_key": "..."}
## 用于"云端编译"：本机不装 Keil，把工程打包上传到编译服务器编译并取回 hex。
const CLOUD_SETTINGS_PATH: String = "user://cloud_settings.json"
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
## v7: 删除蓝牙烧录与自建 bootloader（UART 触发字 / IAP / DFU 全移除），
##     固件走芯片 ROM bootloader 的 USB-HID 烧录（pie_block_hid.py）。
const PROJECT_VERSION: String = "proj_v8_engineer_modes"

## STC 烧录脚本路径（Python）
const STCFLASH_SRC: String = "res://stc32g/toolchain/stcflash"
## 烧录脚本部署目标
const STCFLASH_DST: String = "user://stcflash"

## _run_python_logged 在「用户取消」/「硬超时」时返回的哨兵退出码。
## 进程是被 taskkill 树杀的，get_process_exit_code 不可靠，用哨兵区分；
## 调用方据此把失败阶段标成 canceled / timeout，而不是按日志乱猜。
const EXIT_CANCELED: int = -2
const EXIT_TIMEOUT: int = -3

## UV4 可执行文件候选名，按优先级排序：
## uVision.com 是控制台子系统版本，-b 批处理时不会弹出 GUI 窗口盖住本程序；
## UV4.exe 是 GUI 子系统版本，会弹窗抢焦点，仅作回退。
## 注：PackedStringArray 字面量不是常量表达式，故用 var 而非 const
var UV4_CANDIDATES: PackedStringArray = PackedStringArray(["uVision.com", "UV4.exe"])

## 全盘探测时跳过的高风险/高容量目录名。比较时不区分大小写。
var KEIL_SCAN_SKIP_DIRS: PackedStringArray = PackedStringArray([
	"$recycle.bin", "system volume information", "windows", "winnt",
	"node_modules", ".git", ".godot", "android", "library", "programdata",
])
## 探测只递归到有限深度，避免首次启动无界遍历整个文件系统。
const KEIL_SCAN_MAX_DEPTH: int = 6

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
## 确保项目模板与库文件已从 res://（PCK 只读）部署到 user://（可写）。
## 此处只部署项目模板与库文件；编译器由 resolve_keil_root 提供。
## 首次运行或版本变更时执行全量复制；通过版本标记文件判断是否需要重新部署。
## 返回 true 表示就绪，false 表示失败（错误信息已通过日志回调输出）。
func ensure_deployed() -> bool:
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

	# 复制前先探测 user:// 可写性（用与复制相同的绝对路径写一个小文件）。
	# 不探测的话，失败只会笼统提示“请检查磁盘空间”，
	# 权限类问题（Android 应用数据目录异常、磁盘满）完全看不出来。
	if need_redeploy or not _all_projects_deployed():
		var probe: Dictionary = _probe_user_writable()
		if not probe.ok:
			_emit("[Error] user:// 目录不可写：%s" % probe.reason)
			_emit("       请检查设备存储空间是否已满；若空间充足，")
			_emit("       在系统设置里清除本应用的存储/缓存后重试（会删除已生成的工程文件）。")
			return false

	for pair in [
		[PROJECT_SRC, PROJECT_DST, "项目模板"],
		[PROJECT_ENGINEER_SRC, PROJECT_ENGINEER_DST, "工程项目模板"],
	]:
		if need_redeploy or not _project_deployed(str(pair[1])):
			if not _copy_dir_recursive(str(pair[0]), str(pair[1])):
				_emit("[Error] 无法复制%s到 user://，请检查磁盘空间%s"
					% [str(pair[2]), _space_hint()])
				return false

	# 库文件（uvproj 用相对路径引用 Libraries）
	if need_redeploy or not FileAccess.file_exists(
			to_abs(LIBRARIES_DST).path_join("startup/inc/STC32Gxx.h")):
		if not _copy_dir_recursive(LIBRARIES_SRC, LIBRARIES_DST):
			_emit("[Error] 无法复制库文件到 user://，请检查磁盘空间%s"
				% _space_hint())
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


## 两个项目模板是否全部部署过（任一缺失都返回 false）
func _all_projects_deployed() -> bool:
	for pair in [
		[PROJECT_DST],
		[PROJECT_ENGINEER_DST],
	]:
		if not _project_deployed(str(pair[0])):
			return false
	return true


## 探测 user:// 是否可写（与复制用同样的绝对路径方式写文件），并报告剩余空间。
## 返回 {ok: bool, space: int, reason: String}；space 为字节数，未知为 -1。
## Android 上 user:// 是应用私有数据目录，写不进去只有两种可能：
## 磁盘满、或系统存储层出问题（Godot 按 StorageScope 判定可写范围，
## 该路径不在应用数据目录内时一律拒绝）。
func _probe_user_writable() -> Dictionary:
	var probe_abs: String = to_abs("user://.pie_block_write_probe")
	var f: FileAccess = FileAccess.open(probe_abs, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "space": -1,
			"reason": "无法写入 %s（错误码 %d）" % [probe_abs, FileAccess.get_open_error()]}
	f.store_string("probe")
	f.close()
	if FileAccess.file_exists(probe_abs):
		DirAccess.remove_absolute(probe_abs)
	var space: int = -1
	var da: DirAccess = DirAccess.open(to_abs("user://"))
	if da != null:
		space = da.get_space_left()
	return {"ok": true, "space": space, "reason": ""}


## user:// 剩余空间的提示后缀；未知时返回空串。
func _space_hint() -> String:
	var probe: Dictionary = _probe_user_writable()
	var space: int = int(probe.get("space", -1))
	if space < 0:
		return ""
	return "（user:// 剩余空间约 %d MB）" % int(space / (1024 * 1024))


## 递归复制目录（res:// -> user:// 或任意路径组合）
func _copy_dir_recursive(src_path: String, dst_path: String) -> bool:
	var dst_abs: String = to_abs(dst_path)
	if not DirAccess.dir_exists_absolute(dst_abs):
		var err: int = DirAccess.make_dir_recursive_absolute(dst_abs)
		if err != OK:
			err = _make_dir_fallback(dst_abs)
		if err != OK:
			_emit("[Error] 无法创建目录 %s（错误码 %d，剩余空间%s）"
				% [dst_abs, err, _space_hint()])
			return false
	# 源用 res:// 虚拟路径打开（导出后是 PCK，globalize 成 OS 路径会失败）
	var da: DirAccess = DirAccess.open(src_path)
	if da == null:
		_emit("[Error] 无法打开源目录: %s（请检查应用包是否完整，或重新安装）"
			% src_path)
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


## 逐级建目录（回退方案）。
## Windows 上 make_dir_recursive_absolute 基本不会失败，此回退是保险。
## Android 上不做逐级回退：其文件系统访问被 StorageScope 限定在应用数据
## 目录内，逐级建目录会先命中不可访问的上级路径（如 /data）而误报，
## 递归 mkdirs 失败就是真实存储问题，直接按失败上报。
## 返回 OK 或 FAILED。
func _make_dir_fallback(dst_abs: String) -> int:
	if OS.has_feature("android"):
		return FAILED
	var parts: PackedStringArray = dst_abs.split("/", false)
	if parts.is_empty():
		return FAILED
	var acc: String = ""
	if parts[0].ends_with(":"):
		# Windows 盘符：C: 开头，先固定根再逐级拼
		acc = parts[0] + "/"
		parts.remove_at(0)
	elif dst_abs.begins_with("/"):
		acc = "/"
	for part in parts:
		acc = acc.path_join(part)
		if DirAccess.dir_exists_absolute(acc):
			continue
		var parent_da: DirAccess = DirAccess.open(acc.get_base_dir())
		if parent_da == null:
			return FAILED
		if parent_da.make_dir(acc.get_file()) != OK:
			return FAILED
	return OK


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
	var dst_abs: String = to_abs(dst_path)
	# 源用 res:// 虚拟路径读（导出后是 PCK）
	var src_f: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	if src_f == null:
		_emit("[Error] 无法读取源文件: %s（错误码 %d）"
			% [src_path, FileAccess.get_open_error()])
		return false
	var dst_f: FileAccess = FileAccess.open(dst_abs, FileAccess.WRITE)
	if dst_f == null:
		_emit("[Error] 无法写入: %s（错误码 %d，剩余空间%s）"
			% [dst_abs, FileAccess.get_open_error(), _space_hint()])
		src_f.close()
		return false
	var buf_size: int = 65536
	while src_f.get_position() < src_f.get_length():
		dst_f.store_buffer(src_f.get_buffer(buf_size))
	src_f.close()
	dst_f.close()
	return true


# ------------------------------------------------------------------ 外部 Keil 目录
## 读取用户配置的外部 Keil 根目录（user://keil_settings.json 的 {"path": "..."}）。
## 返回绝对路径；未配置或文件非法返回空串。不做存在性校验。
func get_configured_keil_path() -> String:
	if not FileAccess.file_exists(KEIL_SETTINGS_PATH):
		return ""
	var text: String = FileAccess.get_file_as_string(KEIL_SETTINGS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return ""
	return str(parsed.get("path", "")).strip_edges()


## 写入用户配置的外部 Keil 根目录。path 为空表示清除配置。
## 返回是否写入成功。
func set_configured_keil_path(path: String) -> bool:
	var f: FileAccess = FileAccess.open(KEIL_SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 Keil 目录配置: %s（%s）"
			% [KEIL_SETTINGS_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"path": path}))
	f.close()
	return true


## 是否已经完成过首次启动自动探测。
func is_keil_auto_scan_completed() -> bool:
	if not FileAccess.file_exists(KEIL_SCAN_STATE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KEIL_SCAN_STATE_PATH))
	return parsed is Dictionary and bool(parsed.get("completed", false))


## 记录首次启动自动探测已完成。找不到 Keil 时也要记录，避免每次启动重复扫盘。
func mark_keil_auto_scan_completed() -> bool:
	var f: FileAccess = FileAccess.open(KEIL_SCAN_STATE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 Keil 探测状态: %s（%s）"
			% [KEIL_SCAN_STATE_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"completed": true}))
	f.close()
	return true


## 判断本次启动是否需要自动探测。环境变量和用户配置优先，不会被扫描覆盖。
func should_auto_scan_keil() -> bool:
	if OS.get_name() != "Windows":
		return false
	if not OS.get_environment(KEIL_ENV_VAR).strip_edges().is_empty():
		return false
	if not get_configured_keil_path().is_empty():
		return false
	return not is_keil_auto_scan_completed()


## 扫描 Keil 安装目录并返回所有通过 validate_keil_dir 的根目录。
## roots 非空时只扫描传入根目录，供单元测试注入临时目录；为空时扫描 Windows 文件系统盘。
func scan_keil_installations(roots: PackedStringArray = PackedStringArray()) -> Array[String]:
	var scan_roots: PackedStringArray = roots
	if scan_roots.is_empty():
		scan_roots = _default_keil_scan_roots()
	var candidates: Dictionary = {}
	var visited: Dictionary = {}
	for root in scan_roots:
		var root_abs: String = str(root).strip_edges().replace("\\", "/")
		if root_abs.is_empty() or not DirAccess.dir_exists_absolute(root_abs):
			continue
		_scan_keil_tree(root_abs, 0, visited, candidates)
	var result: Array[String] = []
	for path in candidates.keys():
		result.append(str(path))
	result.sort_custom(func(a: String, b: String) -> bool:
		return a.to_lower() < b.to_lower())
	return result


## 从扫描结果中选择最佳安装：优先标准布局和控制台版 uVision.com，
## 再优先路径更浅、TOOLS.INI 更新的安装，最后用路径保证结果稳定。
func choose_best_keil_path(candidates: Array[String]) -> String:
	var ranked: Array[Dictionary] = []
	for raw_path in candidates:
		var path: String = str(raw_path).strip_edges().replace("\\", "/")
		if path.is_empty():
			continue
		var check: Dictionary = validate_keil_dir(path)
		if not check.ok:
			continue
		var score: int = 0
		if FileAccess.file_exists(path.path_join("UV4/uVision.com")):
			score += 100
		if FileAccess.file_exists(path.path_join("C251/BIN/C251.EXE")):
			score += 50
		var uv4_path: String = str(check.get("uv4", "")).to_lower()
		if uv4_path.ends_with("/uvision.com"):
			score += 25
		var tools_ini: String = str(check.get("tools_ini", ""))
		var mtime: int = FileAccess.get_modified_time(tools_ini) if not tools_ini.is_empty() else 0
		ranked.append({
			"path": path,
			"score": score,
			"depth": path.count("/"),
			"mtime": mtime,
		})
	if ranked.is_empty():
		return ""
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.score) != int(b.score):
			return int(a.score) > int(b.score)
		if int(a.depth) != int(b.depth):
			return int(a.depth) < int(b.depth)
		if int(a.mtime) != int(b.mtime):
			return int(a.mtime) > int(b.mtime)
		return str(a.path).to_lower() < str(b.path).to_lower()
	)
	return str(ranked[0].path)


## 默认扫描根目录：先覆盖所有 Godot 可枚举的 Windows 文件系统盘，
## 再补充常见安装位置；visited 会合并重复根目录。
func _default_keil_scan_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	for drive_index in range(DirAccess.get_drive_count()):
		var drive: String = DirAccess.get_drive_name(drive_index)
		roots.append(drive)
		for rel in ["Keil", "Keil_v5", "MDK", "Program Files/Keil", "Program Files (x86)/Keil"]:
			roots.append(drive.path_join(rel))
	for env_name in ["ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"]:
		var base: String = OS.get_environment(env_name).strip_edges()
		if not base.is_empty():
			roots.append(base.path_join("Keil"))
			roots.append(base.path_join("Keil_v5"))
			roots.append(base.path_join("MDK"))
	return roots


func _scan_keil_tree(
	dir_abs: String, depth: int, visited: Dictionary, candidates: Dictionary) -> void:
	if depth > KEIL_SCAN_MAX_DEPTH:
		return
	var normalized: String = dir_abs.replace("\\", "/").trim_suffix("/").to_lower()
	if normalized.is_empty() or visited.has(normalized):
		return
	visited[normalized] = true
	if _is_keil_candidate_dir(dir_abs):
		var check: Dictionary = validate_keil_dir(dir_abs)
		if check.ok:
			candidates[dir_abs] = true
	if depth == KEIL_SCAN_MAX_DEPTH:
		return
	var da: DirAccess = DirAccess.open(dir_abs)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if da.current_is_dir() and not _is_keil_scan_skip_dir(entry):
			_scan_keil_tree(dir_abs.path_join(entry), depth + 1, visited, candidates)
		entry = da.get_next()
	da.list_dir_end()


## 只有目录名带 Keil/MDK，或包含 UV4/C251 标记目录时才做完整校验，
## 避免对文件系统中的每个目录触发递归查找。
func _is_keil_candidate_dir(dir_abs: String) -> bool:
	var lower: String = dir_abs.get_file().to_lower()
	if lower.contains("keil") or lower.contains("mdk"):
		return true
	return DirAccess.dir_exists_absolute(dir_abs.path_join("UV4")) \
		or DirAccess.dir_exists_absolute(dir_abs.path_join("C251"))


func _is_keil_scan_skip_dir(name: String) -> bool:
	var lower: String = name.to_lower()
	for blocked in KEIL_SCAN_SKIP_DIRS:
		if lower == str(blocked).to_lower():
			return true
	return false


## 校验一个目录是否是合法的 Keil C251 安装根：
##   - UV4/uVision.com（回退 UV4.exe）
##   - C251/BIN/C251.EXE
##   - TOOLS.INI（存在性；[C251] PATH 由安装程序配置，不在此处改写）
## 返回 {ok: bool, reason: String, uv4: String, c251: String, tools_ini: String}
func validate_keil_dir(dir_abs: String) -> Dictionary:
	var empty: Dictionary = {"ok": false, "reason": "", "uv4": "", "c251": "", "tools_ini": ""}
	if dir_abs.is_empty():
		empty["reason"] = "目录为空"
		return empty
	if not DirAccess.dir_exists_absolute(dir_abs):
		empty["reason"] = "目录不存在: %s" % dir_abs
		return empty
	# UV4 标准布局 UV4/，回退递归扫描
	var uv4: String = ""
	var uv4_dir: String = dir_abs.path_join("UV4")
	for cand in UV4_CANDIDATES:
		var p: String = uv4_dir.path_join(cand)
		if FileAccess.file_exists(p):
			uv4 = p
			break
	if uv4.is_empty():
		uv4 = _find_named_abs(dir_abs, "uVision.com")
	if uv4.is_empty():
		uv4 = _find_named_abs(dir_abs, "UV4.exe")
	# C251 标准布局 C251/BIN/
	var c251: String = dir_abs.path_join("C251").path_join("BIN").path_join("C251.EXE")
	if not FileAccess.file_exists(c251):
		c251 = _find_named_abs(dir_abs, "C251.EXE")
	# TOOLS.INI
	var tools_ini: String = dir_abs.path_join("TOOLS.INI")
	if not FileAccess.file_exists(tools_ini):
		tools_ini = ""

	empty["uv4"] = uv4
	empty["c251"] = c251
	empty["tools_ini"] = tools_ini
	if uv4.is_empty():
		empty["reason"] = "未找到 uVision.com / UV4.exe（不是有效的 Keil 安装）"
		return empty
	if c251.is_empty():
		empty["reason"] = "未找到 C251.EXE（该安装没有 C251 工具链）"
		return empty
	empty["ok"] = true
	return empty


## 递归找指定名字的文件（作回退扫描，正常布局不触发）。返回绝对路径或空串。
func _find_named_abs(dir_abs: String, name: String, depth: int = 0) -> String:
	if depth > 6:
		return ""
	var da: DirAccess = DirAccess.open(dir_abs)
	if da == null:
		return ""
	da.list_dir_begin()
	var found: String = ""
	var entry: String = da.get_next()
	while entry != "" and found.is_empty():
		if not entry.begins_with("."):
			var item: String = dir_abs.path_join(entry)
			if da.current_is_dir():
				found = _find_named_abs(item, name, depth + 1)
			elif entry.to_lower() == name.to_lower():
				found = item
		entry = da.get_next()
	da.list_dir_end()
	return found


## 当前生效的 Keil 根目录。
## 优先级：环境变量 PIEBLOCK_KEIL > user://keil_settings.json；
## 返回第一个通过 validate_keil_dir 校验的绝对路径，否则返回空串。
func resolve_keil_root() -> String:
	var candidates: Array[String] = []
	var env_path: String = OS.get_environment(KEIL_ENV_VAR).strip_edges()
	if not env_path.is_empty():
		candidates.append(env_path)
	var cfg_path: String = get_configured_keil_path()
	if not cfg_path.is_empty():
		candidates.append(cfg_path)
	for cand in candidates:
		if validate_keil_dir(cand).ok:
			return cand
	return ""


## 检查当前是否具备可用的外部 Keil（编译前置条件）。
## 返回 {ok: bool, reason: String}；ok=false 时 reason 区分「未指定」与「已失效」。
func ensure_external_keil_ready() -> Dictionary:
	var env_path: String = OS.get_environment(KEIL_ENV_VAR).strip_edges()
	if not env_path.is_empty():
		var check: Dictionary = validate_keil_dir(env_path)
		if check.ok:
			return {"ok": true, "reason": ""}
		return {"ok": false, "reason": "环境变量 %s 指向的目录失效：%s" % [KEIL_ENV_VAR, check.reason]}
	var cfg_path: String = get_configured_keil_path()
	if cfg_path.is_empty():
		return {"ok": false, "reason": "未指定 Keil 目录"}
	var check_cfg: Dictionary = validate_keil_dir(cfg_path)
	if check_cfg.ok:
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "已配置的 Keil 目录失效（%s）：%s" % [cfg_path, check_cfg.reason]}


# ------------------------------------------------------------------ 云端编译服务器
## 读取云端编译配置，返回 {ok, base_url, api_key, reason}。
func get_cloud_config() -> Dictionary:
	var empty := {"ok": false, "base_url": "", "api_key": "", "reason": ""}
	if not FileAccess.file_exists(CLOUD_SETTINGS_PATH):
		empty["reason"] = "未配置云端编译服务器"
		return empty
	var text: String = FileAccess.get_file_as_string(CLOUD_SETTINGS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		empty["reason"] = "云端配置格式非法"
		return empty
	return {
		"ok": true,
		"base_url": str(parsed.get("base_url", "")).strip_edges(),
		"api_key": str(parsed.get("api_key", "")).strip_edges(),
		"reason": "",
	}


## 写入云端编译配置。base_url / api_key 传空表示清除。返回是否写入成功。
func set_cloud_config(base_url: String, api_key: String) -> bool:
	var f: FileAccess = FileAccess.open(CLOUD_SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("无法写入云端配置: %s（%s）" % [CLOUD_SETTINGS_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({
		"base_url": base_url.strip_edges(),
		"api_key": api_key.strip_edges(),
	}))
	f.close()
	return true


## 校验云端配置是否可用于编译。
## 返回 {ok: bool, reason: String}；ok=false 时 reason 区分「未配置」与「已配置但无效」。
func ensure_cloud_ready() -> Dictionary:
	var cfg: Dictionary = get_cloud_config()
	if not cfg.ok:
		return {"ok": false, "reason": cfg.reason}
	if str(cfg.base_url).is_empty():
		return {"ok": false, "reason": "云端 Base URL 未填写"}
	if str(cfg.api_key).is_empty():
		return {"ok": false, "reason": "云端 API Key 未填写"}
	if not _is_valid_http_url(str(cfg.base_url)):
		return {"ok": false, "reason": "Base URL 不是合法的 http(s) 地址: %s" % str(cfg.base_url)}
	return {"ok": true, "reason": ""}


## Base URL 是否形如 http:// 或 https://（不校验可达性，编译时再报错）。
func _is_valid_http_url(url: String) -> bool:
	var u: String = url.strip_edges().to_lower()
	return u.begins_with("http://") or u.begins_with("https://")


# ------------------------------------------------------------------ 编译器探测
## 在当前生效的外部 Keil 根目录中探测命令行编译器；找不到返回空串。
## 优先 uVision.com（控制台子系统，-b 不弹 GUI 窗口），回退 UV4.exe（GUI 子系统，会弹窗）
func find_uv4() -> String:
	var dir_abs: String = resolve_keil_root()
	if dir_abs.is_empty():
		return ""
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


# ------------------------------------------------------------------ C251 许可证
## Keil C251 的许可证序列号放在外部 Keil 安装的 TOOLS.INI [C251] 段 LIC0= 行。
## 这台机器上装了对应许可证就能全量编译；没有时 Keil 退回 2KB 评估限制
## （RESTRICTED VERSION / ERROR L250）。以下函数用于应用内读取/写入该序列号。
## 注意：许可证按机器发放，学生机需各自有效的免费密钥（keil.com 可领）。

## 把许可证序列号写入当前生效 Keil 根的 TOOLS.INI [C251] 段 LIC0=（没有则插入该行）。
## 写完后直接生效，无需重启。返回是否成功。
func apply_license_key(key: String) -> bool:
	var root: String = resolve_keil_root().replace("/", "\\")
	if root.is_empty():
		return false
	var ini_abs: String = root + "\\TOOLS.INI"
	if not FileAccess.file_exists(ini_abs):
		return false
	var lines: PackedStringArray = FileAccess.get_file_as_string(ini_abs).split("\n", false)
	var in_c251: bool = false
	var replaced: bool = false
	var out: PackedStringArray = PackedStringArray()
	for line in lines:
		var stripped: String = line.strip_edges(true, true)
		if stripped.to_upper() == "[C251]":
			in_c251 = true
		elif in_c251 and stripped.begins_with("[") and stripped.ends_with("]"):
			in_c251 = false
		if in_c251 and stripped.to_upper().begins_with("LIC0="):
			out.append("LIC0=%s" % key)
			replaced = true
		else:
			out.append(line)
	if not replaced:
		var insert_at: int = 0
		for i in range(out.size()):
			if out[i].strip_edges(true, true).to_upper() == "[C251]":
				insert_at = i + 1
				break
		out.insert(insert_at, "LIC0=%s" % key)
	var f: FileAccess = FileAccess.open(ini_abs, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 TOOLS.INI: %s" % ini_abs)
		return false
	f.store_string("\n".join(out) + "\n")
	f.close()
	return true


## 编译日志里是否出现 Keil 许可证受限/缺失的典型特征。
func detect_license_failure(build_log: String) -> bool:
	if build_log.is_empty():
		return false
	return build_log.find("RESTRICTED VERSION") >= 0 \
		or build_log.find("LICENSE ERROR") >= 0 \
		or build_log.find("ERROR L250") >= 0


# ------------------------------------------------------------------ main.c 读写
## 返回指定项目的 main.c 绝对路径。
## AI 终端、编辑器和编译器都通过同一条路径工作，避免各自拼接出不同目录。
func main_c_path(project_dst: String) -> String:
	return to_abs(project_dst.path_join("USER/src/main.c"))


## 把代码写入指定项目的 USER/src/main.c
func write_main_c(project_dst: String, code: String) -> bool:
	var abs_path: String = main_c_path(project_dst)
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 main.c: %s（%s）" % [abs_path, FileAccess.get_open_error()])
		return false
	f.store_string(code)
	f.close()
	return true


## 读取指定项目的 main.c；文件不存在返回空串
func read_main_c(project_dst: String) -> String:
	var abs_path: String = main_c_path(project_dst)
	if not FileAccess.file_exists(abs_path):
		return ""
	return FileAccess.get_file_as_string(abs_path)


## main.c 的内容签名；文件不存在返回特殊值。
## 不能只依赖 get_modified_time()：Windows 文件时间精度可能只有秒，
## AI 在同一秒内连续写入时编辑器会漏掉外部修改。
func main_c_signature(project_dst: String) -> String:
	var abs_path: String = main_c_path(project_dst)
	if not FileAccess.file_exists(abs_path):
		return "<missing>"
	return FileAccess.get_file_as_string(abs_path).sha256_text()


## main.c 的最后修改时间（秒）；文件不存在返回 0。用于检测 AI 是否改动过文件
func main_c_mtime(project_dst: String) -> int:
	var abs_path: String = main_c_path(project_dst)
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
	# 必须用 -r（rebuild）而非 -b（build）：-b 会跳过重编译，
	# 连续编译不同 main.c 时返回陈旧结果（Program Size 与上次一模一样）。
	# 实测：4 关节全 Pitch 与 6 关节含 Roll 两次编译报出完全相同的 code=33465，
	# 6 关节产物从未真正编译。判据：不同构型的尺寸必须各不相同。
	var exit_code: int = OS.execute(uv4_win, ["-r", uvproj_abs, "-o", log_abs], output, true)
	var log_text: String = ""
	if FileAccess.file_exists(log_abs):
		log_text = FileAccess.get_file_as_string(log_abs)
	return {
		"exit": exit_code,
		"log": log_text,
		"ok": (not log_text.is_empty()) and log_text.find("0 Error(s)") >= 0,
	}


## 一步到位的编译入口：校验外部 Keil -> 部署项目/库 -> 写盘 -> 编译。
## 供 MCP 工具等非 UI 调用方使用（同步阻塞）。
## 返回 {exit, log, ok} 或 {ok: false, log: "<错误说明>"}
func build_project(project_dst: String, code: String = "") -> Dictionary:
	var keil_ready: Dictionary = ensure_external_keil_ready()
	if not keil_ready.ok:
		return {"ok": false, "exit": - 1, "log": keil_ready.reason
			+ "（请配置 Keil 目录：GUI 编译时引导选择，或写 %s，或设环境变量 %s）"
			% [KEIL_SETTINGS_PATH, KEIL_ENV_VAR]}
	if not ensure_deployed():
		return {"ok": false, "exit": - 1, "log": "项目部署失败"}
	if not code.is_empty():
		if not write_main_c(project_dst, code):
			return {"ok": false, "exit": - 1, "log": "写入 main.c 失败"}
	var uv4_abs: String = find_uv4()
	if uv4_abs.is_empty():
		return {"ok": false, "exit": - 1, "log": "未找到 uVision.com / UV4.exe"}
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


## 探测 Python 可执行文件路径。
##
## 优先使用项目自带 .venv 的 python（保证有烧录所需的 hid / intelhex 依赖），
## 其次回退到系统 python / py / python3。
## 返回绝对路径，找不到返回空串。
func find_python() -> String:
	# 项目 .venv（Windows: .venv/Scripts/python.exe；其他平台: .venv/bin/python）
	var venv_py: String = ProjectSettings.globalize_path("res://.venv/Scripts/python.exe") \
		if OS.get_name() == "Windows" else ProjectSettings.globalize_path("res://.venv/bin/python")
	if FileAccess.file_exists(venv_py):
		return venv_py

	var candidates := PackedStringArray(["python", "py", "python3"] \
		if OS.get_name() == "Windows" else ["python3", "python", "py"])
	for name in candidates:
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


## 走 USB-HID 烧录 hex（当前板子只支持 USB-HID，无串口/蓝牙路径）
##
## 通过标准 USB-HID 与 STC32G ROM bootloader 通信（VID 0x34BF / PID 0x1001）。
## 优先走 GDExtension 插件裸 HID（Android: PieBlockUsb；Windows: PieBlockHidWindows，
## 协议层都是 scripts/hid_flasher.gd），插件不可用时降级 Python 兜底
## （pie_block_hid.py，仅限开发机）。
##
## 返回 {ok: bool, exit: int, log: String, stage: String}
##   stage 用于失败时定位，取值：env/connect/erase/program/verify/hex/canceled/timeout/done
func flash_hid(hex_path: String,
		on_log_line: Callable = Callable(),
		token = null,
		timeout_sec: float = 0.0) -> Dictionary:
	var port = _make_usb_port()
	if port != null:
		return flash_hid_usb(hex_path, on_log_line, token, timeout_sec)
	var py: String = find_python()
	if py.is_empty():
		return {"ok": false, "exit": - 1, "log": "未找到 Python", "stage": "env"}
	if not ensure_stcflash_deployed():
		return {"ok": false, "exit": - 1, "log": "烧录脚本部署失败", "stage": "env"}

	var script: String = to_abs(STCFLASH_DST).path_join("pie_block_hid.py")
	var log_abs: String = to_abs(STCFLASH_DST).path_join(DOWNLOAD_LOG_NAME)
	var exit_code: int = _run_python_logged(
		py, [script, hex_path], log_abs,
		on_log_line, token, timeout_sec)
	var log_text: String = _read_log(log_abs)

	if exit_code == EXIT_CANCELED:
		return {"ok": false, "exit": exit_code, "log": log_text, "stage": "canceled"}
	if exit_code == EXIT_TIMEOUT:
		return {"ok": false, "exit": exit_code, "log": log_text, "stage": "timeout"}

	var ok: bool = (exit_code == 0) or log_text.contains("烧录成功")
	var stage: String = "done" if ok else _classify_hid_failure(log_text)
	return {
		"ok": ok,
		"exit": exit_code,
		"log": log_text,
		"stage": stage,
		"streamed": on_log_line.is_valid(),
	}


## 插件分支（Android: PieBlockUsb；Windows: PieBlockHidWindows）：
## 不走 Python / cmd.exe，改用 HID 插件 + HidFlasher（GDScript 协议移植，
## 见 scripts/hid_flasher.gd）。
## 与 Python 分支返回相同结构 {ok, exit, log, stage, streamed, canceled}，
## download_controller 的进度/提示/取消逻辑完全复用。
func flash_hid_usb(hex_path: String,
		on_log_line: Callable = Callable(),
		token = null,
		timeout_sec: float = 0.0) -> Dictionary:
	var port = _make_usb_port()
	if port == null:
		_emit_usb_line(on_log_line, "[Error] 烧录插件不可用（PieBlockUsb 未加载）")
		return {"ok": false, "exit": - 1, "log": "", "stage": "env", "streamed": true,
			"canceled": false}
	if not port.has_usb_host():
		_emit_usb_line(on_log_line, "[Error] 本机不支持 USB Host（OTG）")
		return {"ok": false, "exit": - 1, "log": "", "stage": "connect", "streamed": true,
			"canceled": false}
	if not port.find_device():
		_emit_usb_line(on_log_line,
			"错误：未找到 STC USB-HID 设备 (VID=34BF PID=1001)。请确认板子处于 ISP 模式（上电冷启动）。")
		return {"ok": false, "exit": - 1, "log": "", "stage": "connect", "streamed": true,
			"canceled": false}
	if not port.ensure_permission():
		_emit_usb_line(on_log_line, "[Error] USB 授权被拒绝或超时，无法访问板子")
		return {"ok": false, "exit": - 1, "log": "", "stage": "connect", "streamed": true,
			"canceled": false}
	# 硬超时：与 Python 分支的 DOWNLOAD_HARD_TIMEOUT 语义一致，超时即请求取消
	var deadline_ms: int = 0
	if timeout_sec > 0.0:
		deadline_ms = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var on_progress: Callable = Callable()
	if token != null and deadline_ms > 0:
		on_progress = func(_stage: String, _total: int, _done: int, _bytes: int) -> void:
			if Time.get_ticks_msec() > deadline_ms:
				token.request_cancel()
	var flasher = HidFlasher.new(
		func(line: String) -> void: _emit_usb_line(on_log_line, line))
	var result: Dictionary = flasher.flash(hex_path, port, token, true, on_progress)
	return {
		"ok": bool(result.ok),
		"exit": 0 if bool(result.ok) else - 1,
		"log": "",
		"stage": str(result.stage),
		"streamed": true,
		"canceled": bool(result.canceled),
	}


func _make_usb_port():
	if OS.has_feature("android"):
		if not Engine.has_singleton("PieBlockUsb"):
			return null
		return preload("res://scripts/usb_port_android.gd").new()
	if OS.get_name() == "Windows" and ensure_hid_plugin_loaded():
		return preload("res://scripts/usb_port_windows.gd").new()
	return null


## 确保 Windows HID 插件（PieBlockHidWindows）已加载。幂等。
##
## 为什么需要运行时部署：Windows 导出的单文件 exe（embed_pck）里，
## 引擎不会自动从 pck 解包/加载 GDExtension 的 dll（只认真实文件或 exe 同目录）。
## 所以这里把 dll 从 res://（pck 内可读）拷到 user://，再生成 .gdextension
## 用 GDExtensionManager.load_extension 显式加载——不依赖引擎导出内部行为，跨版本稳定。
##
## 非 Windows / dll 缺失 / 加载失败时返回 false，调用方降级到 Python 兜底。
func ensure_hid_plugin_loaded() -> bool:
	if Engine.has_singleton("PieBlockHidWindows"):
		return true
	if OS.get_name() != "Windows":
		return false

	var dll_src: String = to_abs("res://addons/pieblock_usb/win/pieblock_hid.dll")
	if not FileAccess.file_exists(dll_src):
		_emit("[Warn] HID 插件 dll 缺失（%s），使用 Python 兜底路径" % dll_src)
		return false

	var dst_dir: String = to_abs("user://pieblock_hid")
	if not DirAccess.dir_exists_absolute(dst_dir):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(dst_dir)
		if mk_err != OK:
			_emit("[Error] 无法创建 HID 插件目录（错误码 %d）" % mk_err)
			return false
	# 每次都覆盖拷贝：dll 随版本更新，避免旧文件残留导致加载的是过期版本。
	var dll_dst: String = dst_dir.path_join("pieblock_hid.dll")
	var copy_err: int = DirAccess.copy_absolute(dll_src, dll_dst)
	if copy_err != OK:
		_emit("[Error] HID 插件 dll 部署失败（错误码 %d）" % copy_err)
		return false

	var gd_path: String = dst_dir.path_join("pieblock_hid.gdextension")
	if not FileAccess.file_exists(gd_path):
		var f: FileAccess = FileAccess.open(gd_path, FileAccess.WRITE)
		if f == null:
			_emit("[Error] 无法写入 HID 插件配置")
			return false
		f.store_string(
			"[configuration]\n"
			+ "entry_symbol = \"pieblock_hid_library_init\"\n"
			+ "compatibility_minimum = \"4.1\"\n"
			+ "reloadable = false\n\n"
			+ "[libraries]\n"
			+ "windows.debug.x86_64   = \"pieblock_hid.dll\"\n"
			+ "windows.release.x86_64 = \"pieblock_hid.dll\"\n")
		f.close()

	var load_status: int = GDExtensionManager.load_extension(gd_path)
	# LOAD_STATUS_OK=0 / LOAD_STATUS_ALREADY_LOADED=2 都算成功
	if load_status != 0 and load_status != 2:
		_emit("[Error] HID 插件加载失败（状态码 %d），使用 Python 兜底路径" % load_status)
		return false
	return true


func _emit_usb_line(on_log_line: Callable, line_text: String) -> void:
	if on_log_line.is_valid():
		on_log_line.call(line_text)


## 从 HID 烧录日志判断失败阶段，用于给出针对性提示。
func _classify_hid_failure(log_text: String) -> String:
	if log_text.contains("info OK") and log_text.contains("unlock OK") \
			and log_text.contains("写块") and log_text.contains("失败"):
		return "program"
	if log_text.contains("erase OK"):
		return "program" if log_text.contains("写块") else "erase"
	if log_text.contains("未找到 STC USB-HID 设备"):
		return "connect"
	if log_text.contains("hex 不存在") or log_text.contains("Loading flash"):
		return "hex" if log_text.contains("错误") else "connect"
	return "unknown"


## 探测 USB-HID 烧录设备（STC32G bootloader，VID 0x34BF / PID 0x1001）是否在线。
## 板子需处于 ISP 模式（上电冷启动进入）才会枚举为该 HID 设备。
## 优先 GDExtension 插件；插件不可用时降级 Python（enumerate_hid.py，开发机兜底）。
func detect_hid_device() -> bool:
	var port = _make_usb_port()
	if port != null:
		return port.find_device()
	var py: String = find_python()
	if py.is_empty():
		return false
	if not ensure_stcflash_deployed():
		return false

	var script: String = to_abs(STCFLASH_DST).path_join("enumerate_hid.py")
	var output: Array = []
	var exit_code: int = OS.execute(py.replace("/", "\\"), [script], output, true)
	if exit_code != 0 or output.is_empty():
		return false
	# enumerate_hid.py 找到 STC 设备时输出 "Found N STC HID device(s):" 或
	# "vid=34bf pid=1001 ..."；没找到输出 "NO STC (0x34BF) HID DEVICE FOUND"
	var text: String = str(output[0])
	return text.contains("vid=34bf") and not text.contains("NO STC")



## 跑 Python 脚本并把输出重定向到文件，返回退出码。
##
## 为什么不用 OS.execute 的 output 参数：那个数组在 Windows 上按系统代码页
## （中文环境是 GBK）解码，而我们的脚本输出 UTF-8，直接读会得到乱码
## （实测下载日志全是"鍥轰欢 30252 瀛楄妭"这种）。
## 编译路径一直是读日志文件所以没这个问题，这里跟它对齐。
func _run_python_logged(py: String, args: Array, log_abs: String,
		on_log_line: Callable = Callable(),
		token = null,
		timeout_sec: float = 0.0) -> int:
	# 用 cmd /c 做重定向。PYTHONIOENCODING 保证脚本内的 print 输出 UTF-8，
	# 不依赖控制台代码页。
	var parts: PackedStringArray = PackedStringArray()
	parts.append("\"" + py.replace("/", "\\") + "\"")
	for a in args:
		parts.append("\"" + str(a).replace("/", "\\") + "\"")
	var cmd_line: String = "set PYTHONIOENCODING=utf-8 && " \
		+" ".join(parts) + " > \"" + log_abs.replace("/", "\\") + "\" 2>&1"
	if FileAccess.file_exists(log_abs):
		DirAccess.remove_absolute(log_abs)
	var pid: int = OS.create_process("cmd.exe", ["/c", cmd_line], false)
	if pid <= 0:
		return -1
	# 把 pid 记进取消令牌，取消时可立即树杀（下面 30ms 轮询也兜底）。
	if token != null:
		token.set_pid(pid)

	var deadline: int = 0
	if timeout_sec > 0.0:
		deadline = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var log_offset: int = 0
	while OS.is_process_running(pid):
		# 取消或硬超时：树杀进程（cmd 连同 python 子进程一起死），
		# 轮询随后退出，worker 线程即可收尾，不再无限阻塞。
		var canceled: bool = token != null and token.is_canceled()
		var timed_out: bool = timeout_sec > 0.0 and Time.get_ticks_msec() > deadline
		if canceled or timed_out:
			kill_process_tree(pid)
			return EXIT_CANCELED if canceled else EXIT_TIMEOUT
		log_offset = _emit_complete_log_lines(log_abs, log_offset, on_log_line, false)
		OS.delay_msec(30)
	_emit_complete_log_lines(log_abs, log_offset, on_log_line, true)
	return OS.get_process_exit_code(pid)


## 树杀子进程（taskkill /T /F）。cmd.exe 会带着它拉起的 python 一起退出；
## 只杀 cmd 的话 python 会变成孤儿进程，继续锁着串口，重启也无法重试。
func kill_process_tree(pid: int) -> void:
	if pid <= 0:
		return
	var out: Array = []
	OS.execute("taskkill.exe", ["/T", "/F", "/PID", str(pid)], out, false)


## 增量发送日志中的完整行。每次从上一个换行位置重新读取完整 UTF-8 文件，
## 避免恰好读到一个中文字符的半个字节时产生乱码。
func _emit_complete_log_lines(log_abs: String, offset: int,
		on_log_line: Callable, flush_tail: bool) -> int:
	if not on_log_line.is_valid() or not FileAccess.file_exists(log_abs):
		return offset
	var content: String = FileAccess.get_file_as_string(log_abs)
	var next_offset: int = offset
	var newline: int = content.find("\n", next_offset)
	while newline >= 0:
		var line: String = content.substr(next_offset, newline - next_offset).trim_suffix("\r")
		on_log_line.call(line)
		next_offset = newline + 1
		newline = content.find("\n", next_offset)
	if flush_tail and next_offset < content.length():
		on_log_line.call(content.substr(next_offset).trim_suffix("\r"))
		return content.length()
	return next_offset


## 读日志文件。Godot 的 get_file_as_string 按 UTF-8 解析，与脚本输出一致。
func _read_log(log_abs: String) -> String:
	if not FileAccess.file_exists(log_abs):
		return ""
	return FileAccess.get_file_as_string(log_abs)


## 把 HID 烧录失败阶段翻译成给用户看的排查建议。
## 目标用户没有嵌入式背景，所以每条都给可执行的动作而不是术语。
func hid_failure_hint(stage: String) -> PackedStringArray:
	match stage:
		"connect":
			return PackedStringArray([
				"没有检测到 USB-HID 设备。请确认：",
				"  · 板子已通过 USB 线连接到电脑",
				"  · 板子处于 ISP 模式（拔下 USB 再插上，冷启动进入）",
			])
		"erase":
			return PackedStringArray([
				"擦除失败。板上的程序可能已被清除，但这不会损坏板子 ——",
				"引导程序会停在下载模式，直接再点一次下载即可。",
				"若反复失败，请重新插拔 USB 让板子回到 ISP 模式。",
			])
		"program", "verify":
			return PackedStringArray([
				"写入中断。板上的程序可能已被清除，但这不会损坏板子 ——",
				"重新插拔 USB 让板子回到 ISP 模式，再点一次下载即可。",
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
## 为什么要带识别信息：电脑上往往同时存在多个串口/虚拟串口
## （其他设备、扩展坞等），"取最后一个"这种猜法会连错。
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
