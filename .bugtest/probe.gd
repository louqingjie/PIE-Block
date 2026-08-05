extends SceneTree

## 复现：res:// 只由外部 pck 提供（模拟导出 exe）时，toolchain.gd 用
## globalize_path 判目录/读文件是否失效。--path 指向空项目，磁盘上没有 stc32g。
const PACK := "C:/Users/louqi/Desktop/pie-block/.bugtest/verify.pck"


func _initialize() -> void:
	var err := ProjectSettings.load_resource_pack(PACK)
	print("load_pack err=", err)
	var tc = load("res://scripts/toolchain.gd").new()
	var deployed: bool = tc.ensure_deployed()
	print("ensure_deployed=", deployed)
	var uv4: String = tc.find_uv4()
	print("find_uv4=", uv4)
	print("user://keil/UV4/uVision.com 存在=",
		FileAccess.file_exists("user://keil/UV4/uVision.com"))
	quit(0 if (deployed and not uv4.is_empty()) else 1)
