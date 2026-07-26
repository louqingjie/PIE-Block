class_name CodeGenDebug
extends CodeGenBase

## 调试模式代码生成器（占位）。
## 未来实现时重写 generate()，根据调试界面配置生成调试用 main.c 代码。
## 可复用 CodeGenBase 中的共享工具函数。


## 生成 main.c 代码。子类必须重写此方法。
func generate(cfg: Dictionary) -> String:
	push_error("CodeGenDebug.generate() 尚未实现，请完成调试模式代码生成逻辑")
	return "// TODO: 调试模式代码生成器尚未实现\n" \
		+ "// 请在 scripts/codegen/codegen_debug.gd 中完成 generate() 方法\n"
