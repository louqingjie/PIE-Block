extends SceneTree

## 渲染核对：实例化步兵仿真，让 SubViewport 出图并存 PNG，人工核对车体与云台朝向。
## 运行方式（必须带图形后端，不能 --headless）：
##   godot --path . --script scripts/dev_infantry_sim_shot.gd

func _cfg(yaw_drive: String, pitch_drive: String) -> Dictionary:
	return {
		"channel": "36", "deadzone": "10",
		"l1_io": "P74 P24", "l1_dir": "正向",
		"l2_io": "P75 P25", "l2_dir": "正向",
		"r1_io": "P76 P26", "r1_dir": "正向",
		"r2_io": "P77 P27", "r2_dir": "正向",
		"normal_speed": "4000", "sprint_speed": "8000", "sprint_enabled": true,
		"booster_io": "P60 P61", "booster_dir": "正向",
		"yaw_drive": yaw_drive, "yaw_io": "MP74", "yaw_dir": "正向",
		"pitch_drive": pitch_drive, "pitch_io": "MP03", "pitch_dir": "正向",
		"yaw_mid_offset": "0", "pitch_mid_offset": "0",
		"arrow_key": "移动", "trigger_key": "E",
		"trigger_speed": "10000", "trigger_time": "250",
		"booster_key": "A", "zero_enabled": true,
	}


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/infantry_sim.tscn") as PackedScene
	# 三张图：静止正视 / 云台偏转 / 开火后弹道
	for case in [["idle", 0.0, 0.0, false], ["gimbal", 35.0, 20.0, false],
			["fire", 10.0, 15.0, true]]:
		var sim: Node = packed.instantiate()
		sim.set_config(_cfg("舵机", "舵机"))
		root.add_child(sim)
		# SubViewport 需要至少两帧才有稳定的贴图
		await process_frame
		await process_frame
		await process_frame
		# 直接摆云台角度，绕过摇杆输入
		sim._yaw_deg = case[1]
		sim._pitch_deg = case[2]
		sim._render_robot()
		if case[3]:
			# 摩擦轮拉满再连打几发，看弹道
			sim._status_booster = 1
			sim._duty_booster = 800
			for i in range(3):
				sim._fire()
				for j in range(12):
					await process_frame
		sim._reset_view()
		# 稍微拉远一点，把车和弹道一起装进画面
		sim._cam_dist = 3.0 if case[3] else 0.9
		sim._follow = false
		sim._update_camera()
		await process_frame
		await process_frame
		var vp: SubViewport = sim.get_node("Sim/SubViewport")
		var img: Image = vp.get_texture().get_image()
		var path: String = "res://_tmp_inf_%s.png" % case[0]
		img.save_png(path)
		print("saved %s  size=%s  bullets=%d" % [path, str(img.get_size()), sim._bullets.size()])
		root.remove_child(sim)
		sim.free()
	quit(0)
