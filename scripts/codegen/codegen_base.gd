class_name CodeGenBase
extends RefCounted

## 代码生成器基类。
## 定义所有代码生成器共享的接口与工具函数。
## 子类必须重写 generate()，根据配置字典生成完整的 main.c 代码字符串。

## App 的 UART1 波特率（拓展板通信，230400）。
## 写入生成的 C 代码，与各构型 UART_Init 的配置一致。
const APP_BAUD: int = 230400

## 生成 main.c 代码。子类必须重写此方法。
func generate(cfg: Dictionary) -> String:
	push_error("CodeGenBase.generate() 必须由子类重写")
	return ""


## 不会永久阻塞启动流程的 NRF24L01 初始化函数。
## 库里的 remote_control_init() 使用无限循环，模块未接或故障时整个 App
## 永远无法进入主循环。这里有限重试约 200ms，失败后让其余功能继续启动。
const REMOTE_CONTROL_INIT_CODE: String = \
	"static void remoteControlInitWithTimeout(void)\n" \
	+"{\n" \
	+"    uint8_t retry;\n\n" \
	+"    for (retry = 0; retry < 20; retry++)\n" \
	+"    {\n" \
	+"        if (NRF24L01_Init())\n" \
	+"        {\n" \
	+"            Ms_Delay(200);\n" \
	+"            return;\n" \
	+"        }\n" \
	+"        Ms_Delay(10);\n" \
	+"    }\n" \
	+"}\n\n"


# ============================================================ 共享修复（实测发现）
## UART1 查询发送函数（不依赖 UART1 TX 中断）。
## 库的 UART_PutChar 靠 UART_BUSY + TX 中断清忙：一旦 TX 中断被 NRF 的
## P2.6 高优先级中断抢占，while(UART_BUSY) 永久死锁。查询 TI 用硬件标志，
## 与中断无关，发送必定完成。所有 ExpansionBoradControl 用它。
const UART_TX_QUERY_CODE: String = \
	"// UART1 查询发送一字节：不依赖 UART1 TX 中断（避免 UART_PutChar 的\n" \
	+"// UART_BUSY 死锁——TX 中断被 NRF P2.6 高优先级中断抢占时 BUSY 永远清不掉）。\n" \
	+"// 发送期间临时关串口中断，轮询硬件 TI 标志。要求 UART1 已 UART_Init 初始化。\n" \
	+"static void Uart1TxQuery(uint8_t dat)\n" \
	+"{\n" \
	+"    ES = 0;          // 关 UART1 中断，避免中断抢先清 TI 导致死锁\n" \
	+"    SBUF = dat;      // 启动发送\n" \
	+"    while (!TI)      // 等硬件发送完成（TI 与中断无关，必定置位）\n" \
	+"        ;\n" \
	+"    TI = 0;          // 清发送完成标志\n" \
	+"    ES = 1;          // 恢复 UART1 中断\n" \
	+"}\n\n"


## 安全的 NRF 遥控器初始化调用（替代裸 remoteControlInitWithTimeout()）。
## 修复两个死锁：
##   1. 初始化期间 EA=0 关全局中断：P2.6 高优先级中断在 ISR 里做 SPI
##      （nrf_readbuf 是 reentrant），抢先会破坏 nrf_link_check 的 SPI 校验，
##      导致 NRF24L01_Init 一直失败（遥控器开着必卡初始化）。
##   2. 初始化后关 P2.6 外部中断（P2INTE &= ~GPIO_Pin_6）：遥控器接收改由
##      主循环轮询 nrf_handler()，彻底避免 ISR 里 SPI/reentrant 死锁。
## 要求：主循环必须调用 _gen_nrf_poll()，否则遥控器收不到数据。
func _gen_nrf_init_safe() -> String:
	return ("    // NRF 遥控器初始化：全程关中断 + 初始化后关 P2.6 EXTI\n"
		+ "    // （P2.6 高优先级中断在 ISR 里做 SPI/reentrant，遥控器开着会卡死；\n"
		+ "    //  接收改为主循环轮询 nrf_handler()，见主循环开头）\n"
		+ "    EA = 0;\n"
		+ "    remoteControlInitWithTimeout();\n"
		+ "    P2INTE &= ~GPIO_Pin_6; // 关 P2.6 EXTI：接收改主循环轮询\n"
		+ "    EA = 1;\n")


## 主循环开头的 NRF 轮询接收（P2.6 中断已关，靠这里读遥控器数据）。
## 必须放在主循环最开头、任何控制逻辑之前。
func _gen_nrf_poll() -> String:
	return ("        nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）\n")


## 生成初始化诊断工具：3 颗 LED + 蜂鸣器，把初始化分步、每步 LED 编码定位。
##   - LED1/2/3 默认 P35/P36/P37（低电平点亮 0=亮）；P34 保留给 NRF CE。
##   - 蜂鸣器用 PWM（buzzer_ch 默认 PWMB_CH3_P33）。
##   - StepBegin(n)：进入某步前显示编码（阻塞时 LED 停在该编码）；
##     StepDone(n)：该步成功后响推进音（音调随步骤递增）。
## 放在 main() 之前。All_Init 里用 StepBegin/StepDone 分步。
func _gen_led_diag_tools(led_port: String = "GPIO_P3",
		led1: String = "GPIO_Pin_5", led2: String = "GPIO_Pin_6",
		led3: String = "GPIO_Pin_7",
		buzzer_ch: String = "PWMB_CH3_P33") -> String:
	var code: String = ""
	code += "// ==================== 初始化诊断：3 颗 LED + 蜂鸣器 ====================\n"
	code += "// 3 颗 LED（低电平点亮）+ 蜂鸣器（PWM 驱动），把初始化拆成多步，\n"
	code += "// 每步用 LED 编码 + 蜂鸣器音调双重定位：\n"
	code += "//   - 进入某步前：LED 显示该步编码（3 bit 二进制，P35=bit0 P36=bit1 P37=bit2）\n"
	code += "//   - 该步成功后：蜂鸣器响一声推进确认音（音调随步骤递增）\n"
	code += "//   - 若某步阻塞：LED 停在编码、听不到后续确认音 -> 对照编码表定位\n"
	code += "#define LED_PORT %s\n" % led_port
	code += "#define LED1_PIN %s   // 编码 bit0\n" % led1
	code += "#define LED2_PIN %s   // 编码 bit1\n" % led2
	code += "#define LED3_PIN %s   // 编码 bit2\n" % led3
	code += "#define BUZZER_CH %s  // 蜂鸣器（PWM 驱动）\n\n" % buzzer_ch
	code += "// LED 显示步骤编码 0~7（低电平点亮：0=亮 1=灭）\n"
	code += "static void LedShow(uint8_t show)\n{\n"
	code += "    GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);\n"
	code += "    GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);\n"
	code += "    GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);\n}\n\n"
	code += "// 蜂鸣器响一声（PWM 驱动，freq 音调 / ms 时长）\n"
	code += "static void Beep(uint16_t freq, uint16_t ms)\n{\n"
	code += "    PWM_SET_Frequency(BUZZER_CH, freq, 500);\n"
	code += "    Ms_Delay(ms);\n"
	code += "    PWM_SET_Frequency(BUZZER_CH, freq, 0);\n}\n\n"
	code += "// 进入某步：先显示编码（若该步阻塞，LED 就停在这里）\n"
	code += "static void StepBegin(uint8_t step)\n{\n"
	code += "    LedShow(step & 0x07);\n}\n\n"
	code += "// 某步初始化成功：蜂鸣器推进确认音（音调随步骤递增，可听声定位）\n"
	code += "static void StepDone(uint8_t step)\n{\n"
	code += "    Beep(500 + (uint16_t)(step % 8) * 60, 60);\n}\n\n"
	return code


## 生成 All_Init 开头的 LED GPIO 初始化（三颗 LED 推挽输出 + 全亮自检）。
func _gen_led_diag_init() -> String:
	return ("    // 诊断 LED（P35/P36/P37）推挽输出，全亮自检后熄灭\n"
		+ "    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);\n"
		+ "    LedShow(7);\n"
		+ "    Ms_Delay(200);\n"
		+ "    LedShow(0);\n")


## 生成串口初始化，**必须放在所有外设初始化之前**。
##
## 原因：UART1 是扩展板控制的唯一通道。若串口在外设之后才初始化，
## 任何一个外设初始化卡住（裸板没接遥控器时 remote_control_init 就会卡、
## 扩展板没接时 ExpansionBoradControl 也会等），扩展板控制就彻底失效。
##
## 把串口提前不解决外设本身的问题，但保证了扩展板通信这条底线。
## 这对目标用户尤其重要：他们的接线错误是常态，不该因此就要拆机器。
##
## 波特率必须与扩展板固件约定一致（230400）。
func _gen_uart_init_first() -> String:
	var code: String = ""
	code += "    // 串口必须最先初始化：UART1 是扩展板控制的唯一通道。\n"
	code += "    // 放在外设之后的话，一旦某个外设没接好卡住初始化，\n"
	code += "    // 扩展板控制就彻底失效了。\n"
	code += "    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, %d, TIM1);\n" % APP_BAUD
	return code


# ============================================================ 初始化完成提示音
## 生成初始化完成提示音（P33 蜂鸣器，上行琶音）。
## buzzer 形参为构型自己的蜂鸣器函数名：Buzzer_Play（调试）。
func _gen_init_done(buzzer: String) -> String:
	return ("    // 初始化完成提示音：P33 蜂鸣器演奏上行琶音\n"
		+ "    %s(523, 120);\n" % buzzer
		+ "    %s(659, 120);\n" % buzzer
		+ "    %s(784, 120);\n" % buzzer
		+ "    %s(1047, 240);\n" % buzzer)


# ============================================================ 共享工具函数
## 从 IO 对字符串中提取通信脚（前半），如 "P77 P27" -> "P77"
func _parse_io_pair(text: String) -> String:
	var parts: PackedStringArray = text.split(" ")
	if parts.size() > 0:
		return parts[0]
	return text


## 取整数配置项：非法或越界时回退到默认值，保证生成的 C 代码总能编译。
## text 用 Variant：JSON 传数字（如 36.0）或布尔时也能安全兜底，不崩溃。
func _int_or_default(text: Variant, default_val: int, lo: int, hi: int) -> String:
	var s: String = str(text).strip_edges()
	if not s.is_valid_int():
		return str(default_val)
	return str(clampi(s.to_int(), lo, hi))


## IO 引脚名映射到拓展板槽位序号
## P60->0(拨弹), P62->1(空), P64->2(摩擦L), P66->3(摩擦R),
## P74->4(LF), P75->5(LR), P76->6(RF), P77->7(RR)
func _io_to_exp_slot(pin: String) -> int:
	var mapping: Dictionary = {
		"P60": 0, "P62": 1, "P64": 2, "P66": 3,
		"P74": 4, "P75": 5, "P76": 6, "P77": 7,
	}
	return mapping.get(pin, -1)


## 按键名称映射到 C 代码中的 KEY_OFFSET 宏名
## 注意：右方向键在不同界面里分别写作 "→"(U+2192) 和 "->"，两种写法都要覆盖
func _key_name_to_offset(name: String) -> String:
	var mapping: Dictionary = {
		"R": "KEY_OFFSET_1",
		"↑": "KEY_OFFSET_UP",
		"↓": "KEY_OFFSET_DOWN",
		"←": "KEY_OFFSET_LEFT",
		"→": "KEY_OFFSET_RIGHT",
		"->": "KEY_OFFSET_RIGHT",
		"A": "KEY_OFFSET_A",
		"B": "KEY_OFFSET_B",
		"C": "KEY_OFFSET_C",
		"D": "KEY_OFFSET_D",
	}
	if not mapping.has(name):
		push_warning("_key_name_to_offset: 未知按键名 %s，已回退到 R 键" % name)
	return mapping.get(name, "KEY_OFFSET_1")


## 方向文本映射到 C 代码中的整数值（Dir_Change_Order: 1=正, 0=负）
func _dir_to_int(text: String) -> int:
	if text == "正向":
		return 1
	return 0


## 主控板专用舵机引脚（只能驱动舵机，不在扩展板上）
const MAIN_BOARD_SERVO_PINS: Array = ["MP74", "MP03"]

## 舵机占空比范围（50Hz 下，万分比。PRECISION=10000，duty/10000*20ms 即脉宽）：
## 250 = 0.5ms 脉宽 = 行程一端（-90°）
## 750 = 1.5ms = 中位（0°）
## 1250 = 2.5ms = 行程另一端（+90°）
## 注：这是实测的舵机可用行程，不是标准 RC 舵机的 1~2ms 区间。
## 改这三个常量即可整体调整映射，其余生成器一律由此派生，勿再另写副本。
const SERVO_DUTY_MIN: int = 250
const SERVO_DUTY_MID: int = 750
const SERVO_DUTY_MAX: int = 1250
## 所有舵机角度参数均为「相对中位的偏移角」，有效区间 [-90, +90]
const SERVO_MAX_OFFSET_DEG: int = 90


## 相对中位的偏移角（-90~90）映射到占空比，0° -> 750
func _servo_angle_to_duty(angle: int) -> int:
	# ±90° 共 180° 行程对应整个 duty 跨度
	var span: int = SERVO_DUTY_MAX - SERVO_DUTY_MIN
	var duty: int = SERVO_DUTY_MID + int(round(
		float(angle) * float(span) / float(SERVO_MAX_OFFSET_DEG * 2)))
	return clampi(duty, SERVO_DUTY_MIN, SERVO_DUTY_MAX)


## 角度差（度）换算成占空比差，不做中位偏移。用于限幅幅度、按键步长等
func _servo_deg_to_duty_delta(deg: float) -> int:
	var span: int = SERVO_DUTY_MAX - SERVO_DUTY_MIN
	return int(round(deg * float(span) / float(SERVO_MAX_OFFSET_DEG * 2)))


## IO 引脚名映射到 PWM 通道枚举
## MP74 / MP03 是主控板舵机端口，与扩展板 P74 不同
func _pin_to_pwm_channel(pin: String) -> String:
	var mapping: Dictionary = {
		"MP74": "PWMB_CH1_P74",
		"MP03": "PWMB_CH4_P03",
		"P24": "PWMA_CH3P_P24",
		"P25": "PWMA_CH3N_P25",
		"P26": "PWMA_CH4P_P26",
		"P27": "PWMA_CH4N_P27",
		"P74": "PWMB_CH1_P74",
		"P75": "PWMB_CH2_P75",
		"P76": "PWMB_CH3_P76",
		"P77": "PWMB_CH4_P77",
		"P03": "PWMB_CH4_P03",
		"P20": "PWMB_CH1_P20",
		"P21": "PWMB_CH2_P21",
		"P22": "PWMB_CH3_P22",
		"P23": "PWMB_CH4_P23",
		"P00": "PWMB_CH1_P00",
		"P01": "PWMB_CH2_P01",
		"P02": "PWMB_CH3_P02",
		"P17": "PWMB_CH1_P17",
		"P33": "PWMB_CH3_P33",
		"P34": "PWMB_CH4_P34",
		"P54": "PWMB_CH2_P54",
	}
	var ch: String = mapping.get(pin, "")
	if ch.is_empty():
		push_warning("_pin_to_pwm_channel: 未知引脚 %s，请确认是主控板舵机端口 MP74 或 MP03" % pin)
		return "PWMB_CH1_P74" # 兜底，实际应被静态检查拦截
	return ch
