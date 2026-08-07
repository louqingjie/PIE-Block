class_name SafeArea
extends RefCounted

## 移动端安全区适配（圆角屏 / 刘海 / 挖孔）。
##
## 圆角屏会把屏幕四角的内容裁掉，位于角落的按钮难以点击。
## 用 DisplayServer.get_display_safe_area() 上报的安全区（包含圆角内缩）
## 把根控件整体内缩，让所有子控件退出圆角区域。
##
## 桌面端安全区等于整个窗口，计算恒为 0，不会影响 PC 版。

## 计算安全区内缩量（canvas 坐标单位）。非移动端恒返回全 0。
static func compute_insets(root: Control) -> Dictionary:
	var zero := {"left": 0, "top": 0, "right": 0, "bottom": 0}
	var ds_name: String = DisplayServer.get_name().to_lower()
	if ds_name != "android" and ds_name != "ios":
		return zero
	var vp := root.get_viewport()
	if vp == null:
		return zero
	var win_size := DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0:
		return zero
	var view_rect := vp.get_visible_rect()
	if view_rect.size.x <= 0 or view_rect.size.y <= 0:
		return zero
	var safe := DisplayServer.get_display_safe_area()
	var win_pos := DisplayServer.window_get_position()
	# 窗口像素 -> canvas 坐标（canvas_items 拉伸模式下按比例换算）
	var scale_x := float(win_size.x) / float(view_rect.size.x)
	var scale_y := float(win_size.y) / float(view_rect.size.y)
	return {
		"left": maxi(0, ceili((safe.position.x - win_pos.x) / scale_x)),
		"top": maxi(0, ceili((safe.position.y - win_pos.y) / scale_y)),
		"right": maxi(0, ceili((win_pos.x + win_size.x - (safe.position.x + safe.size.x)) / scale_x)),
		"bottom": maxi(0, ceili((win_pos.y + win_size.y - (safe.position.y + safe.size.y)) / scale_y)),
	}


## 把安全区内缩应用到根控件（根必须是 anchors_preset=15 的全屏 Control）。
## 返回实际内缩量；桌面端返回全 0 且不改动控件。
static func apply_to_root(root: Control) -> Dictionary:
	var inset := compute_insets(root)
	if inset.left > 0 or inset.top > 0 or inset.right > 0 or inset.bottom > 0:
		root.offset_left = inset.left
		root.offset_top = inset.top
		root.offset_right = -inset.right
		root.offset_bottom = -inset.bottom
	return inset
