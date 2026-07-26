extends SyntaxHighlighter
## C 代码预览高亮器（状态机正则，第二代 TextMate 式）。
## 跨行记住"块注释 / 字符串"状态，避免逐行孤立正则的常见错位：
##   - 块注释里的引号、字符串里的 /* 不再误高亮
##   - 行注释 // 优先级高于一切
##   - 预处理指令（#include / #define 等）着色，行内字符串/数字仍可覆盖
## 着色分色：
##   注释     -> 灰绿    字符串  -> 橙
##   关键字   -> 蓝      预处理  -> 粉
##   数字     -> 青      宏标识  -> 黄
##   函数名   -> 浅蓝    默认    -> 浅灰


# ------------------------------------------------------------------ 配色
const COLOR_COMMENT: Color = Color(0.50, 0.55, 0.45) # 灰绿
const COLOR_STRING: Color = Color(0.85, 0.65, 0.40) # 橙
const COLOR_KEYWORD: Color = Color(0.50, 0.70, 0.95) # 蓝
const COLOR_PREPROC: Color = Color(0.85, 0.55, 0.75) # 粉
const COLOR_NUMBER: Color = Color(0.55, 0.85, 0.85) # 青
const COLOR_MACRO: Color = Color(0.85, 0.80, 0.45) # 黄
const COLOR_FUNC: Color = Color(0.60, 0.85, 0.95) # 浅蓝
const COLOR_DEFAULT: Color = Color(0.82, 0.84, 0.88) # 浅灰

# C 关键字（C89/99 常用子集 + 嵌入式 stdint 别名）
# 注：PackedStringArray 字面量不是常量表达式，故用 var 而非 const
var KEYWORDS: PackedStringArray = PackedStringArray([
	"auto", "break", "case", "char", "const", "continue", "default", "do",
	"double", "else", "enum", "extern", "float", "for", "goto", "if",
	"inline", "int", "long", "register", "restrict", "return", "short",
	"signed", "sizeof", "static", "struct", "switch", "typedef", "union",
	"unsigned", "void", "volatile", "while",
	"uint8_t", "uint16_t", "uint32_t", "uint64_t",
	"int8_t", "int16_t", "int32_t", "int64_t",
	"bool", "true", "false", "NULL",
])


# ------------------------------------------------------------------ 跨行状态
# 是否处在块注释中。_clear_highlighting_cache 在文本整体替换时被调用，
# 重置状态后 Godot 会从第 0 行起按顺序调用 _get_line_syntax_highlighting，
# 状态自然向下传播。
var _in_block_comment: bool = false


# ------------------------------------------------------------------ 对外接口
func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var te: TextEdit = get_text_edit()
	if te == null:
		return {}
	var raw: String = te.get_line(line)
	var result: Dictionary = {}
	var i: int = 0
	var n: int = raw.length()
	while i < n:
		if _in_block_comment:
			# 在块注释中：寻找 */
			var end_pos: int = raw.find("*/", i)
			if end_pos == -1:
				# 整行剩余都是注释
				_add_span(result, i, COLOR_COMMENT)
				i = n
			else:
				_add_span(result, i, COLOR_COMMENT)
				i = end_pos + 2
				_in_block_comment = false
		else:
			i = _scan_normal(raw, i, result)
	return result


func _clear_highlighting_cache() -> void:
	_in_block_comment = false


# ------------------------------------------------------------------ 扫描非注释段
# 返回处理完后的新位置
func _scan_normal(raw: String, start: int, result: Dictionary) -> int:
	var n: int = raw.length()
	var i: int = start
	var def_start: int = -1 # 当前默认色段起始，-1 表示不在默认色段中

	# 行首预处理指令：# 到指令词尾着色为预处理，行内其余部分仍走正常扫描
	if _is_line_start(raw, start):
		var j: int = i
		while j < n and (raw[j] == ' ' or raw[j] == '\t'):
			j += 1
		if j < n and raw[j] == '#':
			var hash_pos: int = j
			# 前导空白标为默认色
			if hash_pos > start:
				_add_span(result, start, COLOR_DEFAULT)
			j += 1
			while j < n and (raw[j] == ' ' or raw[j] == '\t'):
				j += 1
			while j < n and _is_ident_part(raw[j]):
				j += 1
			_add_span(result, hash_pos, COLOR_PREPROC)
			i = j

	# 逐 token 扫描
	while i < n:
		var c: String = raw[i]
		# 行注释 //
		if c == '/' and i + 1 < n and raw[i + 1] == '/':
			def_start = _flush_default(result, def_start, i)
			_add_span(result, i, COLOR_COMMENT)
			return n
		# 块注释开始 /*
		if c == '/' and i + 1 < n and raw[i + 1] == '*':
			def_start = _flush_default(result, def_start, i)
			var end_pos: int = raw.find("*/", i + 2)
			if end_pos == -1:
				_add_span(result, i, COLOR_COMMENT)
				_in_block_comment = true
				return n
			_add_span(result, i, COLOR_COMMENT)
			i = end_pos + 2
			continue
		# 字符串 "..."
		if c == '"':
			def_start = _flush_default(result, def_start, i)
			i = _scan_string(raw, i, result, '"')
			continue
		# 字符 '...'
		if c == "'":
			def_start = _flush_default(result, def_start, i)
			i = _scan_string(raw, i, result, "'")
			continue
		# 数字
		if c.is_valid_int() or (c == '.' and i + 1 < n and raw[i + 1].is_valid_int()):
			def_start = _flush_default(result, def_start, i)
			i = _scan_number(raw, i, result)
			continue
		# 标识符
		if _is_ident_start(c):
			def_start = _flush_default(result, def_start, i)
			i = _scan_ident(raw, i, result)
			continue
		# 其它符号 / 空白：归入默认色段
		if def_start == -1:
			def_start = i
		i += 1
	# 行末 flush 剩余默认色段
	_flush_default(result, def_start, i)
	return i


# ------------------------------------------------------------------ 字符串
func _scan_string(raw: String, start: int, result: Dictionary, quote: String) -> int:
	var n: int = raw.length()
	var i: int = start + 1
	while i < n:
		if raw[i] == '\\':
			i += 2
			continue
		if raw[i] == quote:
			_add_span(result, start, COLOR_STRING)
			return i + 1
		i += 1
	# 未闭合
	_add_span(result, start, COLOR_STRING)
	return n


# ------------------------------------------------------------------ 数字
func _scan_number(raw: String, start: int, result: Dictionary) -> int:
	var n: int = raw.length()
	var i: int = start
	# 0x / 0X 十六进制
	if raw[i] == '0' and i + 1 < n and (raw[i + 1] == 'x' or raw[i + 1] == 'X'):
		i += 2
		while i < n and _is_hex(raw[i]):
			i += 1
	else:
		# 十进制（含小数）
		while i < n and (raw[i].is_valid_int() or raw[i] == '.'):
			i += 1
		# 指数
		if i < n and (raw[i] == 'e' or raw[i] == 'E'):
			i += 1
			if i < n and (raw[i] == '+' or raw[i] == '-'):
				i += 1
			while i < n and raw[i].is_valid_int():
				i += 1
	# 后缀 u/U/l/L/f/F
	while i < n and (raw[i] == 'u' or raw[i] == 'U' or raw[i] == 'l'
			or raw[i] == 'L' or raw[i] == 'f' or raw[i] == 'F'):
		i += 1
	_add_span(result, start, COLOR_NUMBER)
	return i


# ------------------------------------------------------------------ 标识符
func _scan_ident(raw: String, start: int, result: Dictionary) -> int:
	var n: int = raw.length()
	var i: int = start
	while i < n and _is_ident_part(raw[i]):
		i += 1
	var word: String = raw.substr(start, i - start)
	if KEYWORDS.has(word):
		_add_span(result, start, COLOR_KEYWORD)
	elif _is_macro_name(word):
		_add_span(result, start, COLOR_MACRO)
	else:
		# 函数名：标识符后跟 ( （允许中间有空白）
		var j: int = i
		while j < n and (raw[j] == ' ' or raw[j] == '\t'):
			j += 1
		if j < n and raw[j] == '(':
			_add_span(result, start, COLOR_FUNC)
		else:
			_add_span(result, start, COLOR_DEFAULT)
	return i


# ------------------------------------------------------------------ 工具
func _is_macro_name(word: String) -> bool:
	if word.length() < 2:
		return false
	var has_letter: bool = false
	for c in word:
		if c >= 'a' and c <= 'z':
			return false
		if c >= 'A' and c <= 'Z':
			has_letter = true
	return has_letter


func _is_ident_start(c: String) -> bool:
	return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'


func _is_ident_part(c: String) -> bool:
	return _is_ident_start(c) or (c >= '0' and c <= '9')


func _is_hex(c: String) -> bool:
	return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')


func _is_line_start(raw: String, pos: int) -> bool:
	var i: int = pos - 1
	while i >= 0:
		if raw[i] != ' ' and raw[i] != '\t':
			return false
		i -= 1
	return true


# ------------------------------------------------------------------ flush 默认色段
# 将累积的默认色字符（符号 / 空白）写入 result，返回 -1 重置状态
func _flush_default(result: Dictionary, def_start: int, cur_pos: int) -> int:
	if def_start != -1 and cur_pos > def_start:
		_add_span(result, def_start, COLOR_DEFAULT)
	return -1


# ------------------------------------------------------------------ 写入 span
# Godot SyntaxHighlighter 约定：key=起始位置(int)，value={color:...}，
# 颜色从该位置作用到下一个 key 之前（或行尾）。
func _add_span(result: Dictionary, start: int, color: Color) -> void:
	result[start] = {"color": color}
