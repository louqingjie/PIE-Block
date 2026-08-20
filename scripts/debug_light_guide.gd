extends Control

## Debug 灯说明界面（模态覆盖层，结构参照 first_flash_guide.tscn）。
##
## 主控板 4 颗 Debug 灯从上到下 P37/P36/P35/P34。初始化诊断用上三颗
## 组成 3 位二进制编码（亮=1 灭=0，P37 是最高位），卡在哪步灯就停在
## 哪步编码；P34 保留给 NRF 通信，不参与诊断。
## 编码表与 codegen_base.gd 的 _gen_led_diag_tools / 各生成器 All_Init
## 中的 StepBegin 步骤一一对应。

const P_CLOSE: NodePath = "Dim/Center/Panel/Content/Close"


func _ready() -> void:
	var close: Node = get_node_or_null(P_CLOSE)
	if close is BaseButton:
		close.pressed.connect(queue_free)
