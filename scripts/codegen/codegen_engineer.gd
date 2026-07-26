class_name CodeGenEngineer
extends CodeGenBase

## 工程机器人代码生成器（占位）。
## 未来实现时重写 generate()，根据配置字典生成工程机器人 main.c 代码。
## 可复用 CodeGenBase 中的共享工具函数（_parse_io_pair、_io_to_exp_slot、
## _key_name_to_offset、_dir_to_int、_pin_to_pwm_channel）。


## 生成 main.c 代码。子类必须重写此方法。
func generate(_cfg: Dictionary) -> String:
	push_error("CodeGenEngineer.generate() 尚未实现，请完成工程机器人代码生成逻辑")
	return "// TODO: 工程机器人代码生成器尚未实现\n" \
		+ "// 请在 scripts/codegen/codegen_engineer.gd 中完成 generate() 方法\n"
