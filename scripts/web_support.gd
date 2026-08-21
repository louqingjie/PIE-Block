extends RefCounted
## Web 平台工具（浏览器导出版专用）。
##
## 浏览器里没有桌面子进程 / 原生终端 / 串口 / 真实文件对话框，
## 所有平台差异判断与「浏览器下载文件」都收敛到这里，
## 桌面版调用这些函数时自动空操作，行为完全不变。

## 当前是否 Web 导出版（浏览器）
static func is_web() -> bool:
	return DisplayServer.get_name() == "web"


## 是否桌面平台（浏览器 / Android / iOS 都不算）
static func is_desktop() -> bool:
	if is_web():
		return false
	var name: String = DisplayServer.get_name()
	return name != "android" and name != "ios"


## 桌面专属功能提示弹窗（非桌面端调用：弹窗告知并退出）
static func popup_desktop_only(root: Node, feature: String) -> void:
	if is_desktop():
		return
	var dlg := AcceptDialog.new()
	dlg.title = "仅桌面端可用"
	dlg.dialog_text = "%s 仅桌面端可用。\n请在 Windows 版 PIEBlock 中使用该功能。" % feature
	dlg.ok_button_text = "知道了"
	root.add_child(dlg)
	dlg.popup_centered()
	dlg.close_requested.connect(dlg.queue_free)


## 浏览器版不可用的功能按钮统一置灰
static func disable_buttons(root: Node, paths: Array, tip: String = "浏览器版不可用（请使用本地程序）") -> void:
	if not is_web():
		return
	for p in paths:
		var btn: Node = root.get_node_or_null(p)
		if btn is BaseButton:
			btn.disabled = true
			btn.tooltip_text = tip


## 在浏览器里触发文件下载（桌面版空操作）。
## hex / .pieproj / main.c 等小文件直接用；大文件可后续换 base64。
static func download_bytes(bytes: PackedByteArray, filename: String) -> void:
	if not is_web():
		return
	# PackedByteArray -> JSON 数字数组（几百 KB 内可行）
	var json_arr: String = JSON.stringify(bytes)
	var safe_name: String = JSON.stringify(filename)
	JavaScriptBridge.eval("""
		var b = new Uint8Array(%s);
		var u = URL.createObjectURL(new Blob([b], {type: 'application/octet-stream'}));
		var a = document.createElement('a');
		a.href = u; a.download = %s;
		document.body.appendChild(a); a.click(); a.remove();
		setTimeout(function(){ URL.revokeObjectURL(u); }, 5000);
	""" % [json_arr, safe_name])


## 读取一个文本文件并下载（.pieproj / .c）
static func download_text(text: String, filename: String) -> void:
	if not is_web():
		return
	var safe_name: String = JSON.stringify(filename)
	# 用 JSON 转义嵌入字符串，避免引号/换行破坏 JS 代码
	var payload: String = JSON.stringify(text)
	JavaScriptBridge.eval("""
		var b = new Blob([%s], {type: 'text/plain;charset=utf-8'});
		var u = URL.createObjectURL(b);
		var a = document.createElement('a');
		a.href = u; a.download = %s;
		document.body.appendChild(a); a.click(); a.remove();
		setTimeout(function(){ URL.revokeObjectURL(u); }, 5000);
	""" % [payload, safe_name])
