Godot Engine v4.7.stable.mono.official.5b4e0cb0f - https://godotengine.org

// 宸ョ▼鏈哄櫒浜烘搷浣滀唬鐮侊紙鐢?Pie-Block 閰嶇疆鐢熸垚鍣ㄨ嚜鍔ㄧ敓鎴愶級
#include "main.h"
#include "MATH.H"
// ========================= 鍙傛暟鍖?=========================
uint8_t Channal = 36;                          // NRF24L01 閫氫俊閫氶亾锛?-125锛夛紝涓庨仴鎺у櫒涓€鑷?
uint16_t maxSpeed = 4000;                         // 搴曠洏鏅€氶€熷害
uint16_t ultraSpeed = 8000;                       // 搴曠洏鍐插埡閫熷害
uint16_t deadBandOfLeft = 10;                   // 宸︽憞鏉嗕腑蹇冩鍖?
uint16_t deadBandOfRight = 10;                  // 鍙虫憞鏉嗕腑蹇冩鍖?
#define LIMIT_VALUE(x, min, max) \
    do                           \
    {                            \
        if ((x) < (min))         \
            (x) = (min);         \
        else if ((x) > (max))    \
            (x) = (max);         \
    } while (0)
/*甯уご甯у熬锛屽唴閮ㄨ皟鐢紝鏃犻渶鍏冲績*/
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
/*鍛戒护鐮?/
#define Init_Order 0xAA        // 鍒濆鍖栨ā寮?
#define Duty_Change_Order 0xBB // 淇敼鍗犵┖姣?
#define Freq_Change_Order 0xCC // 淇敼棰戠巼
#define Dir_Change_Order 0xDD  // 淇敼鏂瑰悜 1涓烘 0涓鸿礋 璁剧疆涓€娆″嵆鍙?
#define Zero_Order 0xEE        // 0鍛戒护
/*鍐呴儴璋冪敤鍙橀噺锛屾棤闇€鍏冲績锛岃鍕垮畾涔夊悓鍚嶅彉閲?/
uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;
// 鑷畾涔夊彉閲?
float floatDutyOfServo[2];   // 鎵╁睍鏉胯埖鏈烘诞鐐瑰崰绌烘瘮
uint16_t dutyOfServo[2];      // 鎵╁睍鏉胯埖鏈哄崰绌烘瘮
int dutyOfMotor[6];          // 鐢垫満鎺у埗鍊硷紙搴曠洏+鍏朵粬锛?
float floatDutyOfMainServo0; // 涓绘帶鏉胯埖鏈?MP03
uint16_t dutyOfMainServo0;
float floatDutyOfMainServo1; // 涓绘帶鏉胯埖鏈?MP74
uint16_t dutyOfMainServo1;
uint8_t valueOfKey[3][4];
uint8_t valueOfRKey;
uint8_t i, j;
int valueOfRoker[2][2] // 宸︽憞鏉嗘按骞炽€佺珫鐩达紱鍙虫憞鏉嗘按骞炽€佺珫鐩?
    ,
    baseSpeed, turnSpeed;
static const uint8_t keyOffsets[3][4] = {
    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},
    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},
    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 瀹為檯鍙湁2涓?
};

void All_Init();
void Read_Controller_Inputs();
void Calculate_Motor_Controls();
void Calculate_Servo_Controls();
uint8_t Get_Dir(int rawdata);
uint16_t Angle_To_Duty(int angle);
void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo);
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77);

void main()
{
    All_Init();
    for (i = 0; i < 2; i++)
    {
        dutyOfServo[i] = 750;
        floatDutyOfServo[i] = 750.0f;
    }
    floatDutyOfMainServo0 = 750.0f;
    floatDutyOfMainServo1 = 750.0f;
    while (1)
    {
        // 娴嬭瘯鎵嬫焺杩炴帴鐘舵€?
        if (RcKeyValueRead(KEY_OFFSET_UP))
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);
        else
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);

        Read_Controller_Inputs();
        Calculate_Motor_Controls();
        Calculate_Servo_Controls();
        LIMIT_VALUE(dutyOfMotor[0], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[1], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[2], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[3], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[4], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[5], -10000, 10000);
        for (i = 0; i < 2; i++)
            LIMIT_VALUE(floatDutyOfServo[i], 500, 1000);
        LIMIT_VALUE(floatDutyOfMainServo0, 500, 1000);
        LIMIT_VALUE(floatDutyOfMainServo1, 500, 1000);

        for (i = 0; i < 2; i++)
            dutyOfServo[i] = (uint16_t)floatDutyOfServo[i];
        dutyOfMainServo0 = (uint16_t)floatDutyOfMainServo0;
        dutyOfMainServo1 = (uint16_t)floatDutyOfMainServo1;

        Main_Countrol(dutyOfMotor, dutyOfServo);
        Ms_Delay(10);
    }
}

uint8_t Get_Dir(int rawdata)
{
    if (rawdata >= 0)
        return 1;
    else
        return 0;
}

/// @brief 鑸垫満鐩稿涓綅鐨勫亸绉昏锛?90~90锛夎浆鎹负鍗犵┖姣旓紙500~1000锛屼腑浣?750锛?
uint16_t Angle_To_Duty(int angle)
{
    int duty = 750 + angle * 500 / 180;
    if (duty < 500)
        duty = 500;
    if (duty > 1000)
        duty = 1000;
    return (uint16_t)duty;
}

void All_Init()
{
    Board_Init();
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);
    remote_control_init();
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    ExpansionBoradControl(Init_Order,
                          50, 50,
                          10000, 10000,
                          10000, 10000,
                          10000, 10000); // p60,p62,p64,p66,p74,p75,p76,p77
    Ms_Delay(20);
    PWM_Init(PWMB_CH4_P03, 50, 750); // MP03 鑸垫満褰掍腑
    PWM_Init(PWMB_CH1_P74, 50, 750); // MP74 鑸垫満褰掍腑
}

void Read_Controller_Inputs()
{
    // 鎽囨潌璇绘暟璇诲彇
    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
    // 姝诲尯杩囨护
    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)
        valueOfRoker[0][0] = 0;
    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)
        valueOfRoker[0][1] = 0;
    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)
        valueOfRoker[1][0] = 0;
    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)
        valueOfRoker[1][1] = 0;

    for (i = 0; i < 3; i++)
    {
        for (j = 0; j < 4; j++)
        {
            if (i == 2 && j >= 2)
                break;
            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);
        }
    }
    valueOfRKey = RcKeyValueRead(KEY_OFFSET_1);
}

void Calculate_Motor_Controls()
{
    baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);
    turnSpeed = -(int)((float)valueOfRoker[0][0] * maxSpeed / 2047);

    dutyOfMotor[0] = -baseSpeed - turnSpeed;
    dutyOfMotor[1] = -baseSpeed - turnSpeed;
    dutyOfMotor[2] = baseSpeed - turnSpeed;
    dutyOfMotor[3] = baseSpeed - turnSpeed;

    // 鎸夐敭鏄犲皠锛氱數鏈烘帶鍒?
    dutyOfMotor[4] = (int)((float)valueOfRoker[1][0] * 10000 / 2047);
    if (valueOfKey[0][0])
        dutyOfMotor[4] = 5000;
    dutyOfMotor[5] = (int)((float)valueOfRoker[1][1] * 10000 / 2047);
    if (valueOfKey[0][1])
        dutyOfMotor[5] = 5000;
}

void Calculate_Servo_Controls()
{
    // 鎸夐敭鏄犲皠锛氳埖鏈烘帶鍒?
    if (valueOfKey[1][0])
        floatDutyOfServo[0] += 500;
    if (valueOfKey[1][1])
        floatDutyOfServo[0] += -500;
    if (valueOfKey[1][2])
        floatDutyOfServo[1] = (float)Angle_To_Duty(90);
    if (valueOfKey[1][3])
        floatDutyOfServo[1] = (float)Angle_To_Duty(-90);
    if (valueOfKey[0][2])
        floatDutyOfMainServo0 += 250;
    if (valueOfKey[0][3])
        floatDutyOfMainServo0 += -250;
    if (valueOfRKey)
        floatDutyOfMainServo1 = (float)Angle_To_Duty(0);

}

void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo)
{
    ExpansionBoradControl(Dir_Change_Order,
                          1, 1,
                          Get_Dir(dutyOfMotor[4]), Get_Dir(dutyOfMotor[5]),
                          Get_Dir(dutyOfMotor[0]), Get_Dir(dutyOfMotor[1]),
                          Get_Dir(dutyOfMotor[2]), Get_Dir(dutyOfMotor[3]));
    Ms_Delay(5);
    ExpansionBoradControl(Duty_Change_Order,
                          dutyOfServo[0], dutyOfServo[1],
                          (uint16_t)abs(dutyOfMotor[4]), (uint16_t)abs(dutyOfMotor[5]),
                          (uint16_t)abs(dutyOfMotor[0]), (uint16_t)abs(dutyOfMotor[1]),
                          (uint16_t)abs(dutyOfMotor[2]), (uint16_t)abs(dutyOfMotor[3]));
    Ms_Delay(5);
    PWM_SET_Frequency(PWMB_CH4_P03, 50, dutyOfMainServo0);
    PWM_SET_Frequency(PWMB_CH1_P74, 50, dutyOfMainServo1);
}

/// @brief 鏉块棿閫氫俊鍑芥暟锛岀敤浜庝富鎺х粰鎷撳睍鐗堝彂閫?
/// @param control_cmd
/// @param data_p60
/// @param data_p62
/// @param data_p64
/// @param data_p66
/// @param data_p74
/// @param data_p75
/// @param data_p76
/// @param data_p77
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77)
{
    uint8_t i = 0;
    uint8_t control_frame_pack[21] = {0};
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    control_frame_pack[2] = control_cmd;
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
    for (i = 0; i < 21; i++)
        UART_PutChar(UART_1, control_frame_pack[i]);
}

