extends CodeEdit
## 「问题 & 输出」代码框。
## 通过自定义 SyntaxHighlighter 对以 [Error]/[Warn] 等前缀开头的行进行着色：
##   Error -> 红色，Warn -> 黄色，其余 -> 默认浅色。


# ------------------------------------------------------------------ 高亮器
class IssueHighlighter extends SyntaxHighlighter:
	var error_color: Color = Color(1.0, 0.27, 0.27)
	var warn_color: Color = Color(1.0, 0.83, 0.20)
	var info_color: Color = Color(0.80, 0.85, 0.92)

	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var te: TextEdit = get_text_edit()
		if te == null:
			return {}
		var raw: String = te.get_line(line)
		var trimmed: String = raw.lstrip(" \t")
		var color: Color = info_color
		# 行首以 [Error] 或 Error: / 错误 等开头视为错误
		if trimmed.begins_with("[Error]") or trimmed.begins_with("Error") \
				or trimmed.begins_with("错误") or trimmed.begins_with("✗"):
			color = error_color
		elif trimmed.begins_with("[Warn]") or trimmed.begins_with("Warn") \
				or trimmed.begins_with("警告") or trimmed.begins_with("⚠"):
			color = warn_color
		# key=起始字符位置，value=属性字典；只设 0 即可作用到行尾
		return {0: {"color": color}}

	func _clear_highlighting_cache() -> void:
		pass


# ------------------------------------------------------------------ 生命周期
var _highlighter: IssueHighlighter


func _ready() -> void:
	_highlighter = IssueHighlighter.new()
	syntax_highlighter = _highlighter


# ------------------------------------------------------------------ 对外接口
func clear_output() -> void:
	text = ""


func append_line(line_text: String) -> void:
	if text == "":
		text = line_text
	else:
		text += "\n" + line_text


func set_issues(issues: Array) -> void:
	clear_output()
	if issues.is_empty():
		append_line("✓ 配置检查通过，未发现问题")
		return
	var errors: int = 0
	var warns: int = 0
	var infos: int = 0
	for i in issues:
		match i.get("type", ""):
			"Error":
				errors += 1
			"Info":
				infos += 1
			_:
				warns += 1
	if infos > 0:
		append_line("共发现 %d 个错误，%d 个警告，%d 条提示" % [errors, warns, infos])
	else:
		append_line("共发现 %d 个错误，%d 个警告" % [errors, warns])
	append_line("")
	for i in issues:
		append_line("[%s] %s" % [i.get("type", "?"), i.get("msg", "")])
