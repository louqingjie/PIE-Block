extends RefCounted
## 项目文件（.pieproj）读写与项目类型定义。
##
## 一个 .pieproj 是自包含的 JSON 单文件，可以直接拷给同学：
##   - kind            项目类型，新建时定死，之后不可转换
##   - stage           1 = 图形化配置阶段；2 = AI 编辑阶段（只能 1 -> 2 单向推进）
##   - config          图形化配置快照（节点相对路径 -> 值），进入阶段二后冻结
##   - active_tab      TabContainer 索引，工程项目使用「工程」页
##   - main_c_stage1   阶段一图形化生成的 C 源，进入阶段二时冻结
##   - main_c_ai       阶段二 AI / 手工编辑后的 C 源
##   - workflow        七步引导进度，以及检查/编译/烧录对应的代码哈希
##
## user://stc32g/.../main.c 退化为编译用的工作副本，真相源在 .pieproj 里。

## 文件扩展名（不含点）
const EXT: String = "pieproj"
## 格式版本，将来迁移用
const FORMAT_VERSION: int = 10
const GUIDE_STEP_COUNT: int = 7
const MUSIC_MAX_SEGMENTS: int = 8192
const MUSIC_MAX_DURATION_MS: int = 20 * 60 * 1000
const MUSIC_MAX_VOICES: int = 4

# ------------------------------------------------------------------ 项目类型
const KIND_INFANTRY: String = "infantry"
const KIND_ENGINEER: String = "engineer"
const KIND_DEBUG: String = "debug"
const KIND_MUSIC: String = "music"

## 全部合法类型（新建对话框按此顺序列出）
const KINDS: Array = [KIND_INFANTRY, KIND_ENGINEER, KIND_DEBUG, KIND_MUSIC]

## 类型 -> 中文显示名
const KIND_LABELS: Dictionary = {
	KIND_INFANTRY: "步兵",
	KIND_ENGINEER: "工程",
	KIND_DEBUG: "调试",
	KIND_MUSIC: "音乐",
}

## 类型 -> 该类型可见的 TabContainer 页索引。
## 逻辑页顺序：0=步兵, 1=工程, 2=调试, 3=音乐。
## 这里是类型与 Tab 映射的唯一真相源，ui.gd 一律调用本文件，不要另写一份。
const KIND_TABS: Dictionary = {
	KIND_INFANTRY: [0],
	KIND_ENGINEER: [1],
	KIND_DEBUG: [2],
	KIND_MUSIC: [3],
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
		"music": _default_music(),
		"main_c_stage1": "",
		"main_c_ai": "",
		"workflow": _default_workflow(),
}


static func _default_music() -> Dictionary:
	return {
		"source_name": "",
		"polyphonic": false,
		"track_index": -1,
		"track_indices": [],
		"track_name": "",
		"track_names": [],
		"track_count": 0,
		"duration_ms": 0,
		"segments": [],
	}


## 规整音乐模式的解析结果。原始 MIDI 不嵌入项目，只保存选中轨道的播放片段。
static func normalize_music(raw: Variant) -> Dictionary:
	var out: Dictionary = _default_music()
	if not raw is Dictionary:
		return out
	var source: Dictionary = raw
	out["source_name"] = str(source.get("source_name", ""))
	out["polyphonic"] = bool(source.get("polyphonic", false))
	out["track_count"] = maxi(0, int(source.get("track_count", 0)))
	var raw_indices: Variant = source.get("track_indices", [])
	var candidate_indices: Array = []
	if raw_indices is Array and not (raw_indices as Array).is_empty():
		candidate_indices = raw_indices
	elif source.has("track_index"):
		candidate_indices = [source.get("track_index", -1)]
	var selected_indices: Array = []
	for value in candidate_indices:
		var index: int = int(value)
		if index < 0 or index >= int(out["track_count"]) or index in selected_indices:
			continue
		selected_indices.append(index)
	if not bool(out["polyphonic"]) and selected_indices.size() > 1:
		selected_indices = [selected_indices[0]]
	out["track_indices"] = selected_indices
	out["track_index"] = int(selected_indices[0]) if not selected_indices.is_empty() else -1

	var raw_names: Variant = source.get("track_names", [])
	var names: Array = []
	if raw_names is Array:
		for index in range(selected_indices.size()):
			var name: String = str(raw_names[index]) if index < raw_names.size() else ""
			if name.is_empty() and index == 0:
				name = str(source.get("track_name", ""))
			names.append(name)
	else:
		for index in selected_indices:
			names.append(str(source.get("track_name", "")) if index == selected_indices[0] else "")
	out["track_names"] = names
	out["track_name"] = str(names[0]) if not names.is_empty() else ""

	var segments_value: Variant = source.get("segments", [])
	if segments_value is Array:
		var segments: Array = []
		var total_ms: int = 0
		for value in segments_value:
			if not value is Dictionary or segments.size() >= MUSIC_MAX_SEGMENTS:
				continue
			var item: Dictionary = value
			var duration_ms: int = int(item.get("duration_ms", 0))
			if duration_ms < 1:
				continue
			var segment: Dictionary = {"duration_ms": duration_ms, "notes": []}
			if item.has("notes") and item["notes"] is Array:
				var note_values: Array = []
				for note_value in item["notes"]:
					var note: int = int(note_value)
					if note >= 1 and note <= 127 and note not in note_values:
						note_values.append(note)
				note_values.sort()
				note_values.reverse()
				if note_values.size() > MUSIC_MAX_VOICES:
					note_values = note_values.slice(0, MUSIC_MAX_VOICES)
				segment["notes"] = note_values
			elif item.has("note"):
				var old_note: int = int(item.get("note", -1))
				if old_note < 0 or old_note > 127:
					continue
				segment["notes"] = [] if old_note == 0 else [old_note]
			else:
				continue
			segments.append(segment)
			total_ms += duration_ms
		out["segments"] = segments
		out["duration_ms"] = mini(total_ms, MUSIC_MAX_DURATION_MS)
	if int(out["track_index"]) < 0:
		out["segments"] = []
		out["duration_ms"] = 0
	if (out["segments"] as Array).is_empty():
		out["duration_ms"] = 0
	return out


static func _default_workflow() -> Dictionary:
	return {
		"hardware_confirmed": false,
		"ai_enabled": false,
		"checked_hash": "",
		"built_hash": "",
		"flashed_hash": "",
		"hardware_tested": false,
		"guide_completed": [false, false, false, false, false, false, false],
	}


static func normalize_workflow(raw: Variant) -> Dictionary:
	var workflow: Dictionary = _default_workflow()
	if not raw is Dictionary:
		return workflow
	workflow["hardware_confirmed"] = bool(raw.get("hardware_confirmed", false))
	workflow["ai_enabled"] = bool(raw.get("ai_enabled", false))
	workflow["checked_hash"] = str(raw.get("checked_hash", ""))
	workflow["built_hash"] = str(raw.get("built_hash", ""))
	workflow["flashed_hash"] = str(raw.get("flashed_hash", ""))
	workflow["hardware_tested"] = bool(raw.get("hardware_tested", false))
	var raw_progress: Variant = raw.get("guide_completed", [])
	if raw_progress is Array:
		var progress: Array[bool] = []
		for i in range(GUIDE_STEP_COUNT):
			progress.append(bool(raw_progress[i]) if i < raw_progress.size() else false)
		workflow["guide_completed"] = progress
	return workflow


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
	data["music"] = normalize_music(raw.get("music", {}))
	data["main_c_stage1"] = str(raw.get("main_c_stage1", ""))
	data["main_c_ai"] = str(raw.get("main_c_ai", ""))
	data["workflow"] = normalize_workflow(raw.get("workflow", {}))
	return data


## 规整配置快照里每一项的类型。
## JSON 没有整数概念，`{"i": 3}` 存盘再读回会变成 `3.0`；
## 不归一化的话「快照 == 读回的配置」这类比较永远不成立。
static func normalize_config(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw.keys():
		var original_path: String = str(key)
		# 工程页已从 Engineer/Engineer 展平为 Engineer。旧快照在读取时
		# 重定位到新控件路径，避免普通工程配置因纯 UI 层级调整而丢失。
		if original_path == "Engineer":
			continue # 旧外层 TabContainer 的 current_tab 已无意义
		var path: String = original_path
		if path.begins_with("Engineer/Engineer/"):
			path = "Engineer/" + path.trim_prefix("Engineer/Engineer/")
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
			# 同时存在新旧路径时以新路径为准。
			if path == original_path or not out.has(path):
				out[path] = norm
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
