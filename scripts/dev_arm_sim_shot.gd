extends SceneTree

## 渲染核对：实例化仿真视图，让 SubViewport 出图并存 PNG，人工核对连杆朝向。
## 运行方式（必须带图形后端，不能 --headless）：
##   godot --path . --script scripts/dev_arm_sim_shot.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/arm_sim.tscn") as PackedScene
	for case in [[2, "2axis"], [3, "3axis"], [4, "4axis"]]:
		var sim: Node = packed.instantiate()
		var joints: Array = []
		for i in range(case[0]):
			joints.append({"io": "P60", "dir": "正向",
				"axis": "Yaw" if i == 0 else "Pitch",
				"len": str([100, 80, 60, 40][i]),
				"zero": "25", "min": "-80", "max": "80"})
		sim.set_config({"ik": {
			"joint_count": case[0],
			"joints": joints, "presets": [],
			"joy_scale": "5", "keymove_speed": "2", "keymove": [],
		}, "engineer": {}, "editable": true})
		root.add_child(sim)
		# SubViewport 需要至少两帧才有稳定的贴图
		await process_frame
		await process_frame
		await process_frame
		# 把机械臂装到底盘偏前的位置，核对底盘朝向与安装座
		sim._mount = Vector3(60.0, 0.0, 90.0)
		# 2 轴那张压到贴地（核对支臂消失），4 轴用较高车身（核对悬挂）
		if case[0] == 2:
			sim._chassis_height = 16.0
		elif case[0] == 4:
			sim._chassis_height = 130.0
			# 4 关节构形把最后一段设为 0，核对零长连杆时夹爪仍然渲染。
			# 注意总臂长变小后可达范围随之缩小，必须把目标拉回范围内，
			# 否则会触发越界反馈（连杆变红 + 幽灵球），干扰对夹爪的核对。
			sim._on_param_changed(0.0, "len3", null)
			sim._on_mode_selected(1) # 标定模式：由关节角推末端，必然可达
		sim._build_chassis()
		sim._build_grid()
		sim._reset_view()
		await process_frame
		await process_frame
		var vp: SubViewport = sim.get_node("Sim/SubViewport")
		var img: Image = vp.get_texture().get_image()
		var path: String = "res://_tmp_shot_%s.png" % case[1]
		img.save_png(path)
		print("saved %s  size=%s" % [path, str(img.get_size())])
		root.remove_child(sim)
		sim.free()
	quit(0)
