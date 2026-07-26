extends RefCounted
## 项目文件（.pieproj）读写与项目类型定义。
##
## 一个 .pieproj 是自包含的 JSON 单文件，可以直接拷给同学：
##   - kind            项目类型，新建时定死，之后不可转换
##   - stage           1 = 图形化配置阶段；2 = AI 编辑阶段（只能 1 -> 2 单向推进）
##   - config          图形化配置快照（节点相对路径 -> 值），进入阶段二后冻结
##   - active_tab      TabContainer 索引，工程项目用于区分「工程 / 工程逆解算」
##   - main_c_stage1   阶段一图形化生成的 C 源，进入阶段二时冻结
##   - main_c_ai       阶段二 AI / 手工编辑后的 C 源
##
## user://stc32g/.../main.c 退化为编译用的工作副本，真相源在 .pieproj 里。

## 文件扩展名（不含点）
const EXT: String = "pieproj"
## 格式版本，将来迁移用
const FORMAT_VERSION: int = 1

# ------------------------------------------------------------------ 项目类型
const KIND_INFANTRY: String = "infantry"
const KIND_ENGINEER: String = "engineer"
const KIND_DEBUG: String = "debug"

## 全部合法类型（新建对话框按此顺序列出）
const KINDS: Array = [KIND_INFANTRY, KIND_ENGINEER, KIND_DEBUG]

## 类型 -> 中文显示名
const KIND_LABELS: Dictionary = {
	KIND_INFANTRY: "步兵",
	KIND_ENGINEER: "工程",
	KIND_DEBUG: "调试",
}

## 类型 -> 该类型可见的 TabContainer 页索引。
## Tab 顺序：0=步兵, 1=工程, 2=工程逆解算, 3=调试。
## 「工程逆解算」属于工程项目，故工程能看到 1 和 2 两页。
## 这里是类型与 Tab 映射的唯一真相源，ui.gd 一律调用本文件，不要另写一份。
const KIND_TABS: Dictionary = {
	KIND_INFANTRY: [0],
	KIND_ENGINEER: [1, 2],
	KIND_DEBUG: [3],
}


## 类型的中文显示名，未知类型回退到「步兵」
static func kind_label(kind: String) -> String:
	return KIND_LABELS.get(kind, KIND_LABELS[KIND_INFANTRY])


## 该类型可见的 Tab 索引数组（返回副本，避免调用方改到常量）
static func kind_tabs(kind: String) -> Array:
	return (KIND_TABS.get(kind, KIND_TABS[KIND_INFANTRY]) as Array).duplicate()


## 该类型进入时默认选中的 Tab
static func kind_default_tab(kind: String) -> int:
	var tabs: Array = kind_tabs(kind)
	return int(tabs[0]) if not tabs.is_empty() else 0


## Tab 索引反查项目类型（给旧上下文兜底用）
static func tab_to_kind(tab: int) -> String:
	for kind in KINDS:
		if tab in KIND_TABS[kind]:
			return kind
	return KIND_INFANTRY


## kind 是否合法
static func is_valid_kind(kind: String) -> bool:
	return kind in KINDS


## 阶段号的中文显示名
static func stage_label(stage: int) -> String:
	return "阶段二 · AI 编辑" if stage >= 2 else "阶段一 · 图形化配置"


# ------------------------------------------------------------------ 数据结构
## 新建一份空项目数据
static func new_data(kind: String) -> Dictionary:
	var k: String = kind if is_valid_kind(kind) else KIND_INFANTRY
	return {
		"format_version": FORMAT_VERSION,
		"kind": k,
		"stage": 1,
		"active_tab": kind_default_tab(k),
		"config": {},
		"main_c_stage1": "",
		"main_c_ai": "",
	}


## 把任意来源的字典规整成合法项目数据（缺字段补默认值，非法值纠正）
static func normalize(raw: Dictionary) -> Dictionary:
	var kind: String = str(raw.get("kind", KIND_INFANTRY))
	if not is_valid_kind(kind):
		kind = KIND_INFANTRY
	var data: Dictionary = new_data(kind)
	# 阶段只有 1 / 2 两个合法值
	var stage: int = int(raw.get("stage", 1))
	data["stage"] = 2 if stage >= 2 else 1
	# active_tab 必须落在该类型可见的 Tab 内，否则回到该类型的默认页
	var tab: int = int(raw.get("active_tab", data["active_tab"]))
	data["active_tab"] = tab if tab in kind_tabs(kind) else kind_default_tab(kind)
	var cfg: Variant = raw.get("config", {})
	data["config"] = normalize_config(cfg) if cfg is Dictionary else {}
	data["main_c_stage1"] = str(raw.get("main_c_stage1", ""))
	data["main_c_ai"] = str(raw.get("main_c_ai", ""))
	return data


## 规整配置快照里每一项的类型。
## JSON 没有整数概念，`{"i": 3}` 存盘再读回会变成 `3.0`；
## 不归一化的话「快照 == 读回的配置」这类比较永远不成立。
static func normalize_config(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw.keys():
		var v: Variant = raw[key]
		if not v is Dictionary:
			continue
		var item: Dictionary = v
		var norm: Dictionary = {}
		if item.has("i"):
			norm["i"] = int(item["i"])
		if item.has("s"):
			norm["s"] = str(item["s"])
		if item.has("t"):
			norm["t"] = str(item["t"])
		if item.has("b"):
			norm["b"] = bool(item["b"])
		if not norm.is_empty():
			out[str(key)] = norm
	return out


## 取项目当前应当编译 / 展示的 C 源：阶段二优先用 AI 版本
static func current_main_c(data: Dictionary) -> String:
	if int(data.get("stage", 1)) >= 2:
		var ai: String = str(data.get("main_c_ai", ""))
		if not ai.is_empty():
			return ai
	return str(data.get("main_c_stage1", ""))


## 从路径取项目显示名（去目录与扩展名）
static func display_name(path: String) -> String:
	if path.is_empty():
		return "未命名"
	return path.get_file().get_basename()


# ------------------------------------------------------------------ 磁盘 IO
## 读取 .pieproj。返回 {ok: bool, err: String, data: Dictionary}。
## 文件缺失 / 非法 JSON / 顶层不是对象都返回 ok=false，不抛异常。
static func load_from(path: String) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "err": "项目路径为空", "data": {}}
	if not FileAccess.file_exists(path):
		return {"ok": false, "err": "文件不存在：%s" % path, "data": {}}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "err": "无法打开文件（错误码 %d）" % FileAccess.get_open_error(),
			"data": {}}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "err": "文件内容不是合法的项目 JSON", "data": {}}
	var raw: Dictionary = parsed
	var ver: int = int(raw.get("format_version", 0))
	if ver > FORMAT_VERSION:
		return {"ok": false,
			"err": "项目格式版本 %d 高于本程序支持的 %d，请升级程序" % [ver, FORMAT_VERSION],
			"data": {}}
	return {"ok": true, "err": "", "data": normalize(raw)}


## 写入 .pieproj。返回 {ok: bool, err: String}
static func save_to(path: String, data: Dictionary) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "err": "项目路径为空"}
	var out: Dictionary = normalize(data)
	out["format_version"] = FORMAT_VERSION
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false,
			"err": "无法写入 %s（错误码 %d）" % [path, FileAccess.get_open_error()]}
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return {"ok": true, "err": ""}


## 确保路径带 .pieproj 扩展名（原生保存对话框可能不自动补）
static func ensure_ext(path: String) -> String:
	if path.is_empty():
		return path
	if path.get_extension().to_lower() == EXT:
		return path
	return path + "." + EXT


## 新建并落盘一个空项目。config 留空，由图形化界面用场景默认值补齐。
## 返回 {ok: bool, err: String, data: Dictionary}
static func create_new(path: String, kind: String) -> Dictionary:
	var data: Dictionary = new_data(kind)
	var res: Dictionary = save_to(path, data)
	if not res["ok"]:
		return {"ok": false, "err": res["err"], "data": {}}
	return {"ok": true, "err": "", "data": data}


# ------------------------------------------------------------------ 最近打开
## 最近打开列表存这里（与项目文件本身分离，属于本机偏好）
const RECENT_PATH: String = "user://recent_projects.json"
## 最多记住多少个
const RECENT_MAX: int = 10


## 读最近打开列表。已被删除 / 移走的条目会被过滤掉。
static func recent_list() -> Array:
	if not FileAccess.file_exists(RECENT_PATH):
		return []
	var f: FileAccess = FileAccess.open(RECENT_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Array:
		return []
	var out: Array = []
	for item in parsed:
		if item is String and FileAccess.file_exists(item):
			out.append(item)
	return out


## 把某个项目提到最近列表首位
static func recent_add(path: String) -> void:
	if path.is_empty():
		return
	var list: Array = recent_list()
	list.erase(path)
	list.insert(0, path)
	if list.size() > RECENT_MAX:
		list.resize(RECENT_MAX)
	_recent_write(list)


## 从最近列表移除（打不开的项目就别一直摆在那）
static func recent_remove(path: String) -> void:
	var list: Array = recent_list()
	list.erase(path)
	_recent_write(list)


static func _recent_write(list: Array) -> void:
	var f: FileAccess = FileAccess.open(RECENT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(list, "\t"))
	f.close()
