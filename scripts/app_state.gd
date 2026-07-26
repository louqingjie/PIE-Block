extends Node

## 全局状态（autoload）。
## 在图形化界面与 AI 代码编辑器之间传递当前项目上下文。
##
## 项目本身的真相源是磁盘上的 .pieproj 文件（见 scripts/project_file.gd），
## 这里只保存「当前打开的是哪个项目、处在哪个阶段」这类跨场景需要的信息。

const PF = preload("res://scripts/project_file.gd")
const TC = preload("res://scripts/toolchain.gd")

## 项目部署路径（Toolchain.PROJECT_DST 或 PROJECT_ENGINEER_DST）
var project_dst: String = ""
## 构型标识，用于界面显示与日志（infantry / engineer / debug）
var project_kind: String = "infantry"
## 来源 Tab 索引，返回图形化界面时恢复
var source_tab: int = 0
## 当前 .pieproj 的绝对路径，空表示尚无项目
var project_path: String = ""
## 项目阶段：1 = 图形化配置，2 = AI 编辑
var stage: int = 1
## 跨场景待办动作（"" / "create" / "open"）。
## 在 AI 编辑器里点「新建 / 打开」时置位，切回图形化界面后由 ui.gd 消费。
var pending_action: String = ""


## 进入 AI 编辑器前记录上下文
func set_context(dst: String, kind: String, tab: int) -> void:
	project_dst = dst
	project_kind = kind
	source_tab = tab


## 清空全部状态（新建项目前调用）
func reset() -> void:
	project_dst = ""
	project_kind = PF.KIND_INFANTRY
	source_tab = 0
	project_path = ""
	stage = 1
	pending_action = ""


## 取出并清空待办动作
func take_pending_action() -> String:
	var action: String = pending_action
	pending_action = ""
	return action


## 是否已打开一个项目
func has_project() -> bool:
	return not project_path.is_empty()


## 构型对应的项目部署路径（工程走 ENGINEER 模板，步兵与调试走 INFANTRY 模板）
func project_dst_for_kind(kind: String) -> String:
	if kind == PF.KIND_ENGINEER:
		return TC.PROJECT_ENGINEER_DST
	return TC.PROJECT_DST


## 构型的中文显示名
func kind_label() -> String:
	return PF.kind_label(project_kind)


## 项目显示名（取文件名去扩展名）
func project_name() -> String:
	return PF.display_name(project_path)
