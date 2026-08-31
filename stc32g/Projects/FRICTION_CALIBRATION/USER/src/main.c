#include "main.h"

/* 板间通信命令 */
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Dir_Change_Order 0xDD

/* 摩擦轮参数：Duty 是万分比，P64/P66 使用 50Hz 输出。 */
#define FRICTION_START_DUTY 500
#define FRICTION_MAX_DUTY 1100
#define FRICTION_STEP_DUTY 10
#define FRICTION_RAMP_STEP 1
#define FRICTION_P64_DIRECTION 0
#define FRICTION_P66_DIRECTION 0
#define EXPANSION_MOTOR_FREQUENCY 10000
#define FRICTION_FREQUENCY 50
#define EXPANSION_FRAME_GAP_MS 5
#define MAIN_LOOP_DELAY_MS 10

/* 主控板按键：按下为高电平，外部下拉。 */
#define KEY_P07_PORT GPIO_P0
#define KEY_P07_PIN GPIO_Pin_7
#define KEY_P06_PORT GPIO_P0
#define KEY_P06_PIN GPIO_Pin_6
#define KEY_P42_PORT GPIO_P4
#define KEY_P42_PIN GPIO_Pin_2
#define KEY_P46_PORT GPIO_P4
#define KEY_P46_PIN GPIO_Pin_6
#define KEY_P45_PORT GPIO_P4
#define KEY_P45_PIN GPIO_Pin_5
#define KEY_P41_PORT GPIO_P4
#define KEY_P41_PIN GPIO_Pin_1
#define KEY_P27_PORT GPIO_P2
#define KEY_P27_PIN GPIO_Pin_7
#define BUTTON_STABLE_SAMPLES 2

#define BUZZER_CH PWMB_CH3_P33

typedef struct
{
    GPIO_Port_enum port;
    GPIO_Pin_enum pin;
    uint8_t raw_level;
    uint8_t stable_level;
    uint8_t stable_samples;
} ButtonState;

typedef struct
{
    uint8_t increase;
    uint8_t decrease;
    uint8_t preset500;
    uint8_t preset600;
    uint8_t preset700;
    uint8_t preset800;
    uint8_t preset900;
} ButtonEdges;

uint16_t currentDuty = 0;
uint16_t targetDuty = 0;

uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;

static ButtonState buttonP07 = {KEY_P07_PORT, KEY_P07_PIN, 0, 0, 0};
static ButtonState buttonP06 = {KEY_P06_PORT, KEY_P06_PIN, 0, 0, 0};
static ButtonState buttonP42 = {KEY_P42_PORT, KEY_P42_PIN, 0, 0, 0};
static ButtonState buttonP46 = {KEY_P46_PORT, KEY_P46_PIN, 0, 0, 0};
static ButtonState buttonP45 = {KEY_P45_PORT, KEY_P45_PIN, 0, 0, 0};
static ButtonState buttonP41 = {KEY_P41_PORT, KEY_P41_PIN, 0, 0, 0};
static ButtonState buttonP27 = {KEY_P27_PORT, KEY_P27_PIN, 0, 0, 0};

void All_Init(void);
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62,
                           uint16_t data_p64, uint16_t data_p66, uint16_t data_p74,
                           uint16_t data_p75, uint16_t data_p76, uint16_t data_p77);

static void Uart1SendFrameQuery(const uint8_t *frame, uint8_t length)
{
    uint8_t i;
    uint8_t globalInterruptEnabled = EA;
    uint8_t uart1InterruptEnabled = ES;
    EA = 0;
    ES = 0;
    for (i = 0; i < length; i++)
    {
        TI = 0;
        SBUF = frame[i];
        while (!TI)
            ;
    }
    TI = 0;
    ES = uart1InterruptEnabled;
    EA = globalInterruptEnabled;
}

static uint8_t Button_ReadPressedEdge(ButtonState *button)
{
    uint8_t level;
    uint8_t edge;

    level = GPIO_Read_Bit(button->port, button->pin) ? 1 : 0;
    edge = 0;
    if (level != button->raw_level)
    {
        button->raw_level = level;
        button->stable_samples = 0;
    }
    else if (button->stable_samples < BUTTON_STABLE_SAMPLES)
        button->stable_samples++;

    if (button->stable_samples >= BUTTON_STABLE_SAMPLES
            && button->stable_level != button->raw_level)
    {
        button->stable_level = button->raw_level;
        if (button->stable_level)
            edge = 1;
    }
    return edge;
}

static void Button_Init(void)
{
    GPIO_Init(KEY_P07_PORT, KEY_P07_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P06_PORT, KEY_P06_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P42_PORT, KEY_P42_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P46_PORT, KEY_P46_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P45_PORT, KEY_P45_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P41_PORT, KEY_P41_PIN, GPIO_HighZ);
    GPIO_Init(KEY_P27_PORT, KEY_P27_PIN, GPIO_HighZ);
}

static void ReadControlKeys(ButtonEdges *edges)
{
    edges->increase = Button_ReadPressedEdge(&buttonP07);
    edges->decrease = Button_ReadPressedEdge(&buttonP06);
    edges->preset500 = Button_ReadPressedEdge(&buttonP42);
    edges->preset600 = Button_ReadPressedEdge(&buttonP46);
    edges->preset700 = Button_ReadPressedEdge(&buttonP45);
    edges->preset800 = Button_ReadPressedEdge(&buttonP41);
    edges->preset900 = Button_ReadPressedEdge(&buttonP27);
}

static void ApplyControlKeys(const ButtonEdges *edges)
{
    uint8_t preset_count;

    preset_count = edges->preset500 + edges->preset600 + edges->preset700
            + edges->preset800 + edges->preset900;
    if (preset_count == 1)
    {
        if (edges->preset500)
            targetDuty = 500;
        else if (edges->preset600)
            targetDuty = 600;
        else if (edges->preset700)
            targetDuty = 700;
        else if (edges->preset800)
            targetDuty = 800;
        else
            targetDuty = 900;
        return;
    }

    /* 快捷键与增减键同周期触发时，以快捷键为准；多个快捷键则忽略。 */
    if (preset_count != 0)
        return;
    if (edges->increase && !edges->decrease)
    {
        if (targetDuty == 0)
            targetDuty = FRICTION_START_DUTY;
        else if (targetDuty < FRICTION_MAX_DUTY)
        {
            targetDuty += FRICTION_STEP_DUTY;
            if (targetDuty > FRICTION_MAX_DUTY)
                targetDuty = FRICTION_MAX_DUTY;
        }
    }
    else if (edges->decrease && !edges->increase)
    {
        if (targetDuty > FRICTION_START_DUTY)
            targetDuty -= FRICTION_STEP_DUTY;
        else
            targetDuty = 0;
    }
}

static uint8_t UpdateFrictionDuty(void)
{
    uint16_t previousDuty;

    previousDuty = currentDuty;
    if (currentDuty == 0 && targetDuty >= FRICTION_START_DUTY)
        currentDuty = FRICTION_START_DUTY;
    else if (currentDuty < targetDuty)
        currentDuty += FRICTION_RAMP_STEP;
    else if (currentDuty > targetDuty)
    {
        if (targetDuty == 0 && currentDuty <= FRICTION_START_DUTY)
            currentDuty = 0;
        else
            currentDuty -= FRICTION_RAMP_STEP;
    }
    return currentDuty != previousDuty;
}

static void UpdateBuzzer(void)
{
    if (currentDuty != targetDuty)
        PWM_SET_Frequency(BUZZER_CH, currentDuty, 5000);
    else
        PWM_SET_Frequency(BUZZER_CH, 500, 0);
}

static void ShowDutyOnLcd(uint16_t duty)
{
    /* 先清理整行，避免 1100 降到个位数时残留旧数字。 */
    LCD_P6x8Str(0, 0, "Duty:           ");
    LCD_PrintU16(36, 0, duty);
}

static void SendFrictionOutput(uint16_t duty)
{
    /* P64/P66 的方向沿用现有实测配置：两个摩擦轮方向位均为 0。 */
    ExpansionBoradControl(Dir_Change_Order, 0, 0,
                          FRICTION_P64_DIRECTION, FRICTION_P66_DIRECTION,
                          0, 0, 0, 0);
    Ms_Delay(EXPANSION_FRAME_GAP_MS);
    ExpansionBoradControl(Duty_Change_Order, 0, 0, duty, duty, 0, 0, 0, 0);
    Ms_Delay(EXPANSION_FRAME_GAP_MS);
}

void All_Init(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    PWM_Init(BUZZER_CH, 500, 0);
    Button_Init();
    LCD_Init();

    /* 所有拓展板通道的初始化频率必须非零；P64/P66 使用 50Hz。 */
    ExpansionBoradControl(Init_Order,
                          EXPANSION_MOTOR_FREQUENCY, EXPANSION_MOTOR_FREQUENCY,
                          FRICTION_FREQUENCY, FRICTION_FREQUENCY,
                          EXPANSION_MOTOR_FREQUENCY, EXPANSION_MOTOR_FREQUENCY,
                          EXPANSION_MOTOR_FREQUENCY, EXPANSION_MOTOR_FREQUENCY);
    Ms_Delay(1000);
    ExpansionBoradControl(Dir_Change_Order, 0, 0,
                          FRICTION_P64_DIRECTION, FRICTION_P66_DIRECTION,
                          0, 0, 0, 0);
    Ms_Delay(EXPANSION_FRAME_GAP_MS);
    ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
    Ms_Delay(EXPANSION_FRAME_GAP_MS);
    ShowDutyOnLcd(0);
}

void main(void)
{
    ButtonEdges edges;
    uint8_t duty_changed;

    All_Init();
    while (1)
    {
        ReadControlKeys(&edges);
        ApplyControlKeys(&edges);
        duty_changed = UpdateFrictionDuty();
        SendFrictionOutput(currentDuty);
        UpdateBuzzer();
        if (duty_changed)
            ShowDutyOnLcd(currentDuty);
        Ms_Delay(MAIN_LOOP_DELAY_MS);
    }
}

void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62,
                           uint16_t data_p64, uint16_t data_p66, uint16_t data_p74,
                           uint16_t data_p75, uint16_t data_p76, uint16_t data_p77)
{
    uint8_t i;
    uint8_t control_frame_pack[21] = {0};

    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = control_cmd;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);
    Uart1SendFrameQuery(control_frame_pack, 21);
}
