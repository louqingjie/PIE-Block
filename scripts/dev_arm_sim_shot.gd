extends SceneTree

## 渲染核对：实例化仿真视图，让 SubViewport 出图并存 PNG，人工核对连杆朝向。
## 运行方式（必须带图形后端，不能 --headless）：
##   godot --path . --script scripts/dev_arm_sim_shot.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/arm_sim.tscn") as PackedScene
	for case in [[0, 2, "2axis"], [1, 3, "3axis"], [2, 4, "4axis"]]:
		var sim: Node = packed.instantiate()
		var joints: Array = []
		for i in range(case[1]):
			joints.append({"io": "P60", "dir": "正向", "zero": "25", "min": "-80", "max": "80"})
		sim.set_config({
			"config_type": case[0], "joint_count": case[1],
			"L1": "120", "L2": "90", "L3": "40",
			"joints": joints, "presets": [],
			"joy_scale": "5", "keymove_speed": "2", "keymove": [],
		})
		root.add_child(sim)
		# SubViewport 需要至少两帧才有稳定的贴图
		await process_frame
		await process_frame
		await process_frame
		# 把机械臂装到底盘偏前的位置，核对底盘朝向与安装座
		sim._mount = Vector3(60.0, 0.0, 90.0)
		# 4 轴那张用高车身，2/3 轴用默认，便于一次核对不同车高
		if case[0] == 2:
			sim._chassis_height = 260.0
		sim._build_chassis()
		sim._build_grid()
		sim._reset_view()
		await process_frame
		await process_frame
		var vp: SubViewport = sim.get_node("Sim/SubViewport")
		var img: Image = vp.get_texture().get_image()
		var path: String = "res://_tmp_shot_%s.png" % case[2]
		img.save_png(path)
		print("saved %s  size=%s" % [path, str(img.get_size())])
		root.remove_child(sim)
		sim.free()
	quit(0)
