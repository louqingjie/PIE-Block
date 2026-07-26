extends Node

## 全局状态（autoload）。
## 在图形化界面与 AI 代码编辑器之间传递当前构型和项目路径。
##
## 注：第一期不做图形化配置的序列化，从 code_edit.tscn 返回 ui.tscn 时
## 配置控件会回到默认值。source_tab 只用于恢复 TabContainer 的选中页。

## 项目部署路径（Toolchain.PROJECT_DST 或 PROJECT_ENGINEER_DST）
var project_dst: String = ""
## 构型标识，用于界面显示与日志
var project_kind: String = "infantry"
## 来源 Tab 索引，返回图形化界面时恢复
var source_tab: int = 0


## 进入 AI 编辑器前记录上下文
func set_context(dst: String, kind: String, tab: int) -> void:
	project_dst = dst
	project_kind = kind
	source_tab = tab


## 构型的中文显示名
func kind_label() -> String:
	return "工程" if project_kind == "engineer" else "步兵"
