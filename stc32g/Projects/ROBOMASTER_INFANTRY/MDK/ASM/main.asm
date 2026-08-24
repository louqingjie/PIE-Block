C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE main
OBJECT MODULE PLACED IN .\Objects\ASM\main.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\USER\src\main.c XSMALL ROM(HUGE) BROWSE INCDIR(..\..\..\Libraries\b
                    -oards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X1000) DEBUG CODE PRINT(
                    -.\ASM\main.asm) TABS(2) OBJECT(.\Objects\ASM\main.obj) 

stmt  level    source

    1          // 步兵机器人操作代码（由 Pie-Block 配置生成器自动生成）
    2          #include "main.h"
    3          #include "MATH.H"
    4          // ========================= 参数区 =========================
    5          uint8_t Channal = 36;                          // NRF24L01 通信通道（0-125），与遥控器一致
    6          uint16_t maxSpeed = 4000;
    7          uint16_t ultraSpeed = 8000;
    8          uint16_t deadBandOfLeft = 10;                   // 左摇杆中心死区
    9          uint16_t deadBandOfRight = 10;                  // 右摇杆中心死区
   10          // 舵机占空比：250=-90°，750=中位(0°)，1250=+90°，总行程 180°
   11          #define SERVO_DUTY_MIN     250
   12          #define SERVO_DUTY_MID     750
   13          #define SERVO_DUTY_MAX     1250
   14          // 每度对应的占空比增量（1000 duty / 180°）
   15          #define SERVO_DUTY_PER_DEG 5.555556f
   16          uint16_t midDutyOfServo[2] = {750, 750};        // 云台水平/垂直舵机中值（归中角 +0° / +0�
             -�）
   17          // 摇杆可摆动幅度 ±60°（相对归中位置）
   18          uint16_t maxChangeDutyOfServo[2] = {333, 333};
   19          uint16_t singleChangeDutyOfBooster = 100;       // 按下按键单次占空比改变量
   20          uint16_t maxDutyOfBooster = 1100;               // 摩擦轮最大占空比（指南上限，不得提高
             -）
   21          uint16_t minDutyOfBooster = 500;                // 摩擦轮最低有效占空比
   22          uint16_t boosterDutyOfFeed = 6000;             // 拨弹电机单发转动占空比
   23          uint16_t boosterFeedDelayMs = 100;              // 拨弹电机单发转动时长(ms)
   24          // 摇杆推到底时云台每周期转过 2.0°
   25          float changeRateOfServo[2] = {0.005428, 0.005428};
   26          
   27          #define LIMIT_VALUE(x, min, max) \
   28              do                           \
   29              {                            \
   30                  if ((x) < (min))         \
   31                      (x) = (min);         \
   32                  else if ((x) > (max))    \
   33                      (x) = (max);         \
   34              } while (0)
   35          /*帧头帧尾，内部调用，无需关心*/
   36          #define COMM_HEADER_1 0xAB
   37          #define COMM_HEADER_2 0xBC
   38          #define COMM_END_1 0xCD
   39          #define COMM_END_2 0xDE
   40          /*命令码*/
   41          #define Init_Order 0xAA        // 初始化模式
   42          #define Duty_Change_Order 0xBB // 修改占空比
   43          #define Freq_Change_Order 0xCC // 修改频率
   44          #define Dir_Change_Order 0xDD  // 修改方向：1为正、0为负，电机换向时需更新
   45          #define Zero_Order 0xEE        // 0命令
   46          // 拓展板需要帧间处理时间；连续命令之间不得删除此间隔
   47          #define EXPANSION_FRAME_GAP_MS 5
   48          /*内部调用变量，无需关心，请勿定义同名变量*/
   49          uint16_t control_data[8] = {0};
   50          uint16_t motor_dir[8] = {0};
   51          uint8_t control_command = 0x00;
   52          // 自定义变量
   53          float floatDutyOfServo[2]; // 云台舵机
   54          uint16_t dutyOfServo[2];
   55          int dutyOfMotor[5]; // 底盘电机、供弹电机、云台电机（如有）
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 2   

   56          uint16_t dutyOfBooster = 0, expectDutyOfBooster = 0;
   57          uint16_t levelDutyOfBooster = 1100; // 摩擦轮目标转速档位（B/C 键微调）
   58          uint8_t valueOfKey[3][4];
   59          uint8_t valueOfEKey;
   60          uint8_t triggerKeyValue, lastTriggerKeyValue, boosterKeyValue, lastBoosterKeyValue;
   61          uint8_t lastBoosterUpKeyValue = 0, lastBoosterDownKeyValue = 0;
   62          uint8_t statusOfBooster = 0;
   63          uint8_t i, j;
   64          int valueOfRoker[2][2] // 左摇杆水平、竖直；右摇杆水平、竖直
   65              ,
   66              baseSpeed, turnSpeed;
   67          static const uint8_t keyOffsets[3][4] = {
   68              {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},
   69              {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},
   70              {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个
   71          };
   72          
   73          void All_Init();
   74          void ReadControllerInputs();
   75          void CalculateMotorControls();
   76          void CalculateGimbalControls();
   77          void CalculateBoosterControl();
   78          uint8_t Get_Dir(int rawdata);
   79          void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster);
   80          void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
   81                                     uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
   82                                     uint16_t data_p77);
   83          
   84          static void remoteControlInitWithTimeout(void)
   85          {
   86   1          uint8_t retry;
   87   1      
   88   1          for (retry = 0; retry < 20; retry++)
   89   1          {
   90   2              if (NRF24L01_Init())
   91   2              {
   92   3                  Ms_Delay(200);
   93   3                  return;
   94   3              }
   95   2              Ms_Delay(10);
   96   2          }
   97   1      }
   98          
   99          // ==================== 初始化诊断：3 颗 LED + 蜂鸣器 ====================
  100          // 3 颗 LED（低电平点亮）+ 蜂鸣器（PWM 驱动），把初始化拆成多步，
  101          // 每步用 LED 编码 + 蜂鸣器音调双重定位：
  102          //   - 进入某步前：LED 显示该步编码（3 bit 二进制，P35=bit0 P36=bit1 P37=bit2）
  103          //   - 该步成功后：蜂鸣器响一声推进确认音（音调随步骤递增）
  104          //   - 若某步阻塞：LED 停在编码、听不到后续确认音 -> 对照编码表定位
  105          #define LED_PORT GPIO_P3
  106          #define LED1_PIN GPIO_Pin_5   // 编码 bit0
  107          #define LED2_PIN GPIO_Pin_6   // 编码 bit1
  108          #define LED3_PIN GPIO_Pin_7   // 编码 bit2
  109          #define BUZZER_CH PWMB_CH3_P33  // 蜂鸣器（PWM 驱动）
  110          
  111          // LED 显示步骤编码 0~7（低电平点亮：0=亮 1=灭）
  112          static void LedShow(uint8_t show)
  113          {
  114   1          GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);
  115   1          GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);
  116   1          GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);
  117   1      }
  118          
  119          // 蜂鸣器响一声（PWM 驱动，freq 音调 / ms 时长）
  120          static void Beep(uint16_t freq, uint16_t ms)
  121          {
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 3   

  122   1          PWM_SET_Frequency(BUZZER_CH, freq, 5000);
  123   1          Ms_Delay(ms);
  124   1          PWM_SET_Frequency(BUZZER_CH, freq, 0);
  125   1      }
  126          
  127          // 进入某步：先显示编码（若该步阻塞，LED 就停在这里）
  128          static void StepBegin(uint8_t step)
  129          {
  130   1          LedShow(step & 0x07);
  131   1      }
  132          
  133          // 某步初始化成功：蜂鸣器推进确认音（音调随步骤递增，可听声定位）
  134          static void StepDone(uint8_t step)
  135          {
  136   1          Beep(500 + (uint16_t)(step % 8) * 60, 60);
  137   1      }
  138          
  139          // UART1 查询发送一字节：不依赖 UART1 TX 中断（避免 UART_PutChar 的
  140          // UART_BUSY 死锁——TX 中断被 NRF P2.6 高优先级中断抢占时 BUSY 永远清不掉）。
  141          // 发送期间临时关串口中断，轮询硬件 TI 标志。要求 UART1 已 UART_Init 初始化。
  142          static void Uart1TxQuery(uint8_t dat)
  143          {
  144   1          uint8_t uart1InterruptEnabled = ES;
  145   1      
  146   1          ES = 0;          // 关 UART1 中断，避免中断抢先清 TI 导致死锁
  147   1          TI = 0;          // 丢弃可能残留的发送完成标志
  148   1          SBUF = dat;      // 启动发送
  149   1          while (!TI)      // 等硬件发送完成（TI 与中断无关，必定置位）
  150   1              ;
  151   1          TI = 0;          // 清发送完成标志
  152   1          ES = uart1InterruptEnabled; // 恢复调用前的 UART1 中断状态
  153   1      }
  154          
  155          void main()
  156          {
  157   1          All_Init();
  158   1          floatDutyOfServo[0] = midDutyOfServo[0];
  159   1          floatDutyOfServo[1] = midDutyOfServo[1];
  160   1          while (1)
  161   1          {
  162   2              nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）
  163   2              // 测试手柄连接状态
  164   2              if (RcKeyValueRead(KEY_OFFSET_UP))
  165   2                  GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);
  166   2              else
  167   2                  GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);
  168   2      
  169   2              ReadControllerInputs();    // 统一读取输入
  170   2              CalculateMotorControls();  // 计算电机控制
  171   2              CalculateGimbalControls(); // 计算云台控制
  172   2              CalculateBoosterControl(); // 计算摩擦轮控制
  173   2              LIMIT_VALUE(dutyOfMotor[0], -10000, 10000);
  174   2              LIMIT_VALUE(dutyOfMotor[1], -10000, 10000);
  175   2              LIMIT_VALUE(dutyOfMotor[2], -10000, 10000);
  176   2              LIMIT_VALUE(dutyOfMotor[3], -10000, 10000);
  177   2              LIMIT_VALUE(dutyOfMotor[4], 0, 10000);
  178   2              // Yaw 限幅 417~1083（归中 +0° ±60°，已收敛到舵机行程内）
  179   2              LIMIT_VALUE(floatDutyOfServo[0], 417, 1083);
  180   2              // Pitch 限幅 417~1083（归中 +0° ±60°，已收敛到舵机行程内）
  181   2              LIMIT_VALUE(floatDutyOfServo[1], 417, 1083);
  182   2              // 扳机键单发拨弹：上升沿触发，拨弹电机转动 boosterFeedDelayMs 后停转，�
             -�间阻塞主线程
  183   2              if (triggerKeyValue && !lastTriggerKeyValue)
  184   2              {
  185   3                  dutyOfMotor[4] = boosterDutyOfFeed;
  186   3                  // 注意：此处保持 dutyOfBooster 不变，不能跳变到目标值，
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 4   

  187   3                  // 否则会违反摩擦轮占空比渐变要求
  188   3                  Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
  189   3                  Ms_Delay(boosterFeedDelayMs);
  190   3                  dutyOfMotor[4] = 0;
  191   3                  Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
  192   3              }
  193   2              lastTriggerKeyValue = triggerKeyValue;
  194   2      
  195   2              // 摩擦轮占空比平滑变化
  196   2              // 每轮至少包含方向/占空比帧间隔各 5ms，加循环尾延时 10ms，
  197   2              // 因此周期至少 20ms；每周期变化 1，即每秒最多变化 50，占空比渐变符合
             -指南上限。
  198   2              // 从静止启动时先跳到 500（指南：启停不考虑 0~5% 区间）
  199   2              if (expectDutyOfBooster >= 500 && dutyOfBooster < 500)
  200   2                  dutyOfBooster = 500;
  201   2              else if (dutyOfBooster < expectDutyOfBooster)
  202   2                  dutyOfBooster++;
  203   2              else if (dutyOfBooster > expectDutyOfBooster)
  204   2              {
  205   3                  // 降到 500 以下时直接停机，避免在低占空比区间长时间堵转
  206   3                  if (dutyOfBooster <= 500 && expectDutyOfBooster == 0)
  207   3                      dutyOfBooster = 0;
  208   3                  else
  209   3                      dutyOfBooster--;
  210   3              }
  211   2      
  212   2              // 发送控制函数
  213   2              Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
  214   2              Ms_Delay(10);
  215   2          }
  216   1      }
  217          
  218          uint8_t Get_Dir(int rawdata)
  219          {
  220   1          if (rawdata >= 0)
  221   1              return 1;
  222   1          else
  223   1              return 0;
  224   1      }
  225          
  226          void All_Init()
  227          {
  228   1          // 初始化诊断分步：卡在哪步，LED 就停在对应编码（P37 P36 P35 二进制）
  229   1          //   000 上电   001 Board_Init   010 UART1   011 LED 自检
  230   1          //   100 NRF遥控 101 拓展板 Init 110 PWM/舵机 111 完成
  231   1          StepBegin(0);
  232   1          Board_Init();
  233   1          StepDone(0);
  234   1          StepBegin(1);
  235   1          // 串口必须最先初始化：UART1 是扩展板控制的唯一通道。
  236   1          // 放在外设之后的话，一旦某个外设没接好卡住初始化，
  237   1          // 扩展板控制就彻底失效了。
  238   1          UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
  239   1          StepDone(1);
  240   1          StepBegin(2);
  241   1          // 诊断 LED（P35/P36/P37）推挽输出，全亮自检后熄灭
  242   1          GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
  243   1          LedShow(7);
  244   1          Ms_Delay(200);
  245   1          LedShow(0);
  246   1          // 蜂鸣器通道必须 PWM_Init（使能输出+启动定时器），否则 Beep 无声
  247   1          PWM_Init(BUZZER_CH, 500, 0);
  248   1          StepDone(2);
  249   1          StepBegin(3);
  250   1          // NRF 遥控器初始化：全程关中断 + 初始化后关 P2.6 EXTI
  251   1          // （P2.6 高优先级中断在 ISR 里做 SPI/reentrant，遥控器开着会卡死；
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 5   

  252   1          //  接收改为主循环轮询 nrf_handler()，见主循环开头）
  253   1          EA = 0;
  254   1          remoteControlInitWithTimeout();
  255   1          P2INTE &= ~GPIO_Pin_6; // 关 P2.6 EXTI：接收改主循环轮询
  256   1          EA = 1;
  257   1          StepDone(3);
  258   1          StepBegin(4);
  259   1          ExpansionBoradControl(Init_Order,
  260   1                                10000, 0,
  261   1                                50, 50,
  262   1                                10000, 10000,
  263   1                                10000, 10000); // p60,p62,p64,p66,p74,p75,p76,p77
  264   1          // 摩擦轮初始化后必须留 >=1000ms 硬件反应时间（见《RM电控指南》），不得�
             -�短
  265   1          Ms_Delay(1000);
  266   1          StepDone(4);
  267   1          StepBegin(5);
  268   1          PWM_Init(PWMB_CH1_P74, 50, midDutyOfServo[0]); // 云台水平舵机
  269   1          PWM_Init(PWMB_CH4_P03, 50, midDutyOfServo[1]); // 云台垂直舵机
  270   1          StepDone(5);
  271   1          // 初始化完成提示音：P33 蜂鸣器演奏上行琶音
  272   1          Beep(523, 120);
  273   1          Beep(659, 120);
  274   1          Beep(784, 120);
  275   1          Beep(1047, 240);
  276   1      }
  277          
  278          void ReadControllerInputs()
  279          {
  280   1          // 摇杆读数读取
  281   1          valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
  282   1          valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
  283   1          valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
  284   1          valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
  285   1          // 死区过滤
  286   1          if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)
  287   1              valueOfRoker[0][0] = 0;
  288   1          if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)
  289   1              valueOfRoker[0][1] = 0;
  290   1          if (abs(valueOfRoker[1][0]) <= deadBandOfRight)
  291   1              valueOfRoker[1][0] = 0;
  292   1          if (abs(valueOfRoker[1][1]) <= deadBandOfRight)
  293   1              valueOfRoker[1][1] = 0;
  294   1      
  295   1          for (i = 0; i < 3; i++)
  296   1          {
  297   2              for (j = 0; j < 4; j++)
  298   2              {
  299   3                  if (i == 2 && j >= 2)
  300   3                      break; // 第三行只有2个按键
  301   3                  valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);
  302   3              }
  303   2          }
  304   1          // 读取扳机键和摩擦轮开关键
  305   1          triggerKeyValue = RcKeyValueRead(KEY_OFFSET_1);
  306   1          boosterKeyValue = RcKeyValueRead(KEY_OFFSET_A);
  307   1      }
  308          
  309          void CalculateMotorControls()
  310          {
  311   1      
  312   1          // 冲刺模式：按下左摇杆时使用冲刺速度
  313   1          if (valueOfKey[2][0])
  314   1          {
  315   2              baseSpeed = (int)((float)valueOfRoker[0][1] * ultraSpeed / 2047);
  316   2              turnSpeed = (int)((float)valueOfRoker[0][0] * ultraSpeed / 2047);
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 6   

  317   2          }
  318   1          else
  319   1          {
  320   2              baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);
  321   2              turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);
  322   2          }
  323   1      
  324   1          // 方向键设为移动
  325   1          if (valueOfKey[0][0] == 1)
  326   1              baseSpeed = maxSpeed;
  327   1          if (valueOfKey[0][1] == 1)
  328   1              baseSpeed = -maxSpeed;
*** WARNING C115 IN LINE 328 OF ..\USER\src\main.c: '-' applied to unsigned type, result still unsigned
  329   1          if (valueOfKey[0][2] == 1)
  330   1              turnSpeed = -maxSpeed;
*** WARNING C115 IN LINE 330 OF ..\USER\src\main.c: '-' applied to unsigned type, result still unsigned
  331   1          if (valueOfKey[0][3] == 1)
  332   1              turnSpeed = maxSpeed;
  333   1          dutyOfMotor[0] = -baseSpeed - turnSpeed;
  334   1          dutyOfMotor[1] = -baseSpeed - turnSpeed;
  335   1          dutyOfMotor[2] = baseSpeed - turnSpeed;
  336   1          dutyOfMotor[3] = baseSpeed - turnSpeed;
  337   1      
  338   1          // 供弹电机控制值计算
  339   1          if (valueOfKey[1][3])
  340   1              dutyOfMotor[4] = 0;
  341   1      }
  342          
  343          void CalculateBoosterControl()
  344          {
  345   1          // B/C 键上升沿微调摩擦轮目标转速档位（不是直接改 expectDutyOfBooster，
  346   1          // 否则会被下面的开关逻辑覆盖）。档位限制在 500~1100，上限由指南规定
  347   1          if (valueOfKey[1][1] && !lastBoosterUpKeyValue)
  348   1          {
  349   2              if (levelDutyOfBooster + singleChangeDutyOfBooster <= maxDutyOfBooster)
  350   2                  levelDutyOfBooster += singleChangeDutyOfBooster;
  351   2              else
  352   2                  levelDutyOfBooster = maxDutyOfBooster;
  353   2          }
  354   1          if (valueOfKey[1][2] && !lastBoosterDownKeyValue)
  355   1          {
  356   2              if (levelDutyOfBooster >= minDutyOfBooster + singleChangeDutyOfBooster)
  357   2                  levelDutyOfBooster -= singleChangeDutyOfBooster;
  358   2              else
  359   2                  levelDutyOfBooster = minDutyOfBooster;
  360   2          }
  361   1          lastBoosterUpKeyValue = valueOfKey[1][1];
  362   1          lastBoosterDownKeyValue = valueOfKey[1][2];
  363   1      
  364   1          // 摩擦轮开关由 A 上升沿翻转
  365   1          if (boosterKeyValue && !lastBoosterKeyValue)
  366   1          {                                       // 检测上升沿
  367   2              statusOfBooster = !statusOfBooster; // 翻转状态
  368   2          }
  369   1          lastBoosterKeyValue = boosterKeyValue;
  370   1      
  371   1          if (statusOfBooster)
  372   1              expectDutyOfBooster = levelDutyOfBooster;
  373   1          else
  374   1              expectDutyOfBooster = 0;
  375   1      }
  376          
  377          void CalculateGimbalControls()
  378          {
  379   1          // 云台舵机控制值计算
  380   1          floatDutyOfServo[0] += valueOfRoker[1][0] * changeRateOfServo[0];
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 7   

  381   1          floatDutyOfServo[1] += valueOfRoker[1][1] * changeRateOfServo[1];
  382   1          dutyOfServo[0] = (uint16_t)floatDutyOfServo[0];
  383   1          dutyOfServo[1] = (uint16_t)floatDutyOfServo[1];
  384   1      }
  385          
  386          void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster)
  387          {
  388   1          // 底盘方向会随摇杆实时变化，必须先发方向帧；拓展板处理完成后再发占�
             -�比帧
  389   1          ExpansionBoradControl(Dir_Change_Order,
  390   1                                1, 1,
  391   1                                0, 0,
  392   1                                Get_Dir(dutyOfMotor[0]), Get_Dir(dutyOfMotor[1]),
  393   1                                Get_Dir(dutyOfMotor[2]), Get_Dir(dutyOfMotor[3]));
  394   1          Ms_Delay(EXPANSION_FRAME_GAP_MS);
  395   1          ExpansionBoradControl(Duty_Change_Order, dutyOfMotor[4], 0,
  396   1                                dutyOfBooster, dutyOfBooster,
  397   1                                (uint16_t)abs(dutyOfMotor[0]), (uint16_t)abs(dutyOfMotor[1]),
  398   1                                (uint16_t)abs(dutyOfMotor[2]), (uint16_t)abs(dutyOfMotor[3]));
  399   1          Ms_Delay(EXPANSION_FRAME_GAP_MS);
  400   1          PWM_SET_Frequency(PWMB_CH1_P74, 50, dutyOfServo[0]);
  401   1          PWM_SET_Frequency(PWMB_CH4_P03, 50, dutyOfServo[1]);
  402   1      }
  403          
  404          /// @brief 板间通信函数，用于主控给拓展版发送
  405          /// @param control_cmd
  406          /// @param data_p60 供弹电机
  407          /// @param data_p62 空
  408          /// @param data_p64 摩擦轮L
  409          /// @param data_p66 摩擦轮R
  410          /// @param data_p74 左前电机
  411          /// @param data_p75 左后电机
  412          /// @param data_p76 右前电机
  413          /// @param data_p77 右后电机
  414          void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
  415                                     uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
  416                                     uint16_t data_p77)
  417          {
  418   1          uint8_t i = 0;
  419   1          uint8_t control_frame_pack[21] = {0};
  420   1          control_frame_pack[0] = COMM_HEADER_1;
  421   1          control_frame_pack[1] = COMM_HEADER_2;
  422   1          control_frame_pack[19] = COMM_END_1;
  423   1          control_frame_pack[20] = COMM_END_2;
  424   1          control_frame_pack[2] = control_cmd;
  425   1          control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);
  426   1          control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);
  427   1          control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);
  428   1          control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);
  429   1          control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);
  430   1          control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);
  431   1          control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);
  432   1          control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);
  433   1          control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);
  434   1          control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);
  435   1          control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);
  436   1          control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);
  437   1          control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);
  438   1          control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);
  439   1          control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);
  440   1          control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);
  441   1          for (i = 0; i < 21; i++)
  442   1              Uart1TxQuery(control_frame_pack[i]); // 查询发送，不依赖 TX 中断
  443   1      }
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 8   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION remoteControlInitWithTimeout (BEGIN)
                                                ; SOURCE LINE # 84
000000 CAF8           PUSH     R15
                                                ; SOURCE LINE # 85
                                                ; SOURCE LINE # 88
000002 7EF014         MOV      R15,#014H
;---- Variable 'retry' assigned to Register 'R15' ----
               ?C0004:
                                                ; SOURCE LINE # 90
000005 9A000000    E  ECALL    NRF24L01_Init?
000009 600A           JZ       ?C0006
                                                ; SOURCE LINE # 92
00000B 7E3400C8       MOV      WR6,#0C8H
00000F 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 93
000013 800C           SJMP     ?C0007
                                                ; SOURCE LINE # 94
               ?C0006:
                                                ; SOURCE LINE # 95
000015 7E34000A       MOV      WR6,#0AH
000019 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 96
00001D 1BF0           DEC      R15,#01H
00001F 78E4           JNE      ?C0004
                                                ; SOURCE LINE # 97
               ?C0007:
000021 DAF8           POP      R15
000023 22             RET      
;       FUNCTION remoteControlInitWithTimeout (END)

;       FUNCTION LedShow (BEGIN)
                                                ; SOURCE LINE # 112
000024 CAF8           PUSH     R15
000026 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'show' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 114
000028 7E340003       MOV      WR6,#03H
00002C 7E240020       MOV      WR4,#020H
000030 5401           ANL      A,#01H           ; A=R11
000032 0A1B           MOVZ     WR2,R11          ; A=R11
000034 4D11           ORL      WR2,WR2
000036 6803           JE       ?C0008
000038 E4             CLR      A                ; A=R11
000039 8002           SJMP     ?C0009
               ?C0008:
00003B 7401           MOV      A,#01H           ; A=R11
               ?C0009:
00003D 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 115
000041 7E340003       MOV      WR6,#03H
000045 7E240040       MOV      WR4,#040H
000049 7CBF           MOV      R11,R15          ; A=R11
00004B 5402           ANL      A,#02H           ; A=R11
00004D 0A1B           MOVZ     WR2,R11          ; A=R11
00004F 4D11           ORL      WR2,WR2
000051 6803           JE       ?C0010
000053 E4             CLR      A                ; A=R11
000054 8002           SJMP     ?C0011
               ?C0010:
000056 7401           MOV      A,#01H           ; A=R11
               ?C0011:
000058 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 116
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 9   

00005C 7E340003       MOV      WR6,#03H
000060 7E240080       MOV      WR4,#080H
000064 7CBF           MOV      R11,R15          ; A=R11
000066 5404           ANL      A,#04H           ; A=R11
000068 0A1B           MOVZ     WR2,R11          ; A=R11
00006A 4D11           ORL      WR2,WR2
00006C 6803           JE       ?C0012
00006E E4             CLR      A                ; A=R11
00006F 8002           SJMP     ?C0013
               ?C0012:
000071 7401           MOV      A,#01H           ; A=R11
               ?C0013:
000073 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 117
000077 DAF8           POP      R15
000079 22             RET      
;       FUNCTION LedShow (END)

;       FUNCTION Beep (BEGIN)
                                                ; SOURCE LINE # 120
00007A CA3B           PUSH     DR12
00007C 7D62           MOV      WR12,WR4
;---- Variable 'ms' assigned to Register 'WR12' ----
00007E 7D73           MOV      WR14,WR6
;---- Variable 'freq' assigned to Register 'WR14' ----
                                                ; SOURCE LINE # 122
000080 7E181388       MOV      DR4,#01388H
000084 7A1F0000    E  MOV      ?PWM_SET_Frequency??BYTE+6,DR4
000088 7E340061       MOV      WR6,#061H
00008C 7D17           MOV      WR2,WR14
00008E 6D00           XRL      WR0,WR0
000090 9A000000    E  ECALL    PWM_SET_Frequency?
                                                ; SOURCE LINE # 123
000094 7D36           MOV      WR6,WR12
000096 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 124
00009A 9F11           SUB      DR4,DR4
00009C 7A1F0000    E  MOV      ?PWM_SET_Frequency??BYTE+6,DR4
0000A0 7E340061       MOV      WR6,#061H
0000A4 7D17           MOV      WR2,WR14
0000A6 6D00           XRL      WR0,WR0
0000A8 9A000000    E  ECALL    PWM_SET_Frequency?
                                                ; SOURCE LINE # 125
0000AC DA3B           POP      DR12
0000AE 22             RET      
;       FUNCTION Beep (END)

;       FUNCTION StepBegin (BEGIN)
                                                ; SOURCE LINE # 128
;---- Variable 'step' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 130
0000AF 5407           ANL      A,#07H           ; A=R11
0000B1 020000      R  LJMP     LedShow
;       FUNCTION StepBegin (END)

;       FUNCTION StepDone (BEGIN)
                                                ; SOURCE LINE # 134
;---- Variable 'step' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 136
0000B4 0A0B           MOVZ     WR0,R11          ; A=R11
0000B6 5E040007       ANL      WR0,#07H
0000BA 7E24003C       MOV      WR4,#03CH
0000BE 7D10           MOV      WR2,WR0
0000C0 AD12           MUL      WR2,WR4
0000C2 7D31           MOV      WR6,WR2
0000C4 2E3401F4       ADD      WR6,#01F4H
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 10  

0000C8 020000      R  LJMP     Beep
;       FUNCTION StepDone (END)

;       FUNCTION Uart1TxQuery (BEGIN)
                                                ; SOURCE LINE # 142
0000CB 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'dat' assigned to Register 'R10' ----
                                                ; SOURCE LINE # 143
                                                ; SOURCE LINE # 144
0000CD A2AC           MOV      C,ES
0000CF E4             CLR      A                ; A=R11
0000D0 33             RLC      A                ; A=R11
;---- Variable 'uart1InterruptEnabled' assigned to Register 'R11' ----
                                                ; SOURCE LINE # 146
0000D1 C2AC           CLR      ES
                                                ; SOURCE LINE # 147
0000D3 C299           CLR      TI
                                                ; SOURCE LINE # 148
0000D5 7AA199         MOV      SBUF,R10
                                                ; SOURCE LINE # 149
                                                ; SOURCE LINE # 150
               ?C0014:
0000D8 3099FD         JNB      TI,?C0014
                                                ; SOURCE LINE # 151
0000DB C299           CLR      TI
                                                ; SOURCE LINE # 152
0000DD 24FF           ADD      A,#0FFH          ; A=R11
0000DF 92AC           MOV      ES,C
                                                ; SOURCE LINE # 153
0000E1 22             RET      
;       FUNCTION Uart1TxQuery (END)

;       FUNCTION main? (BEGIN)
                                                ; SOURCE LINE # 155
                                                ; SOURCE LINE # 157
0000E2 9A000000    R  ECALL    All_Init?
                                                ; SOURCE LINE # 158
0000E6 7E270000    R  MOV      WR4,midDutyOfServo
0000EA E4             CLR      A                ; A=R11
0000EB 9A000000    E  ECALL    ?C?FCASTI?
0000EF 7A1F0000    R  MOV      floatDutyOfServo,DR4
                                                ; SOURCE LINE # 159
0000F3 7E270000    R  MOV      WR4,midDutyOfServo+2
0000F7 E4             CLR      A                ; A=R11
0000F8 9A000000    E  ECALL    ?C?FCASTI?
0000FC 7A1F0000    R  MOV      floatDutyOfServo+4,DR4
                                                ; SOURCE LINE # 160
               ?C0020:
                                                ; SOURCE LINE # 162
000100 9A000000    E  ECALL    nrf_handler?
                                                ; SOURCE LINE # 164
000104 7E340002       MOV      WR6,#02H
000108 9A000000    E  ECALL    RcKeyValueRead?
00010C 600B           JZ       ?C0022
                                                ; SOURCE LINE # 165
00010E 7E340003       MOV      WR6,#03H
000112 7E240080       MOV      WR4,#080H
000116 E4             CLR      A                ; A=R11
000117 800A           SJMP     ?C0122
               ?C0022:
                                                ; SOURCE LINE # 167
000119 7E340003       MOV      WR6,#03H
00011D 7E240080       MOV      WR4,#080H
000121 7401           MOV      A,#01H           ; A=R11
               ?C0122:
000123 9A000000    E  ECALL    GPIO_Write_Bit?
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 11  

                                                ; SOURCE LINE # 169
000127 9A000000    R  ECALL    ReadControllerInputs?
                                                ; SOURCE LINE # 170
00012B 9A000000    R  ECALL    CalculateMotorControls?
                                                ; SOURCE LINE # 171
00012F 9A000000    R  ECALL    CalculateGimbalControls?
                                                ; SOURCE LINE # 172
000133 9A000000    R  ECALL    CalculateBoosterControl?
                                                ; SOURCE LINE # 173
000137 7E370000    R  MOV      WR6,dutyOfMotor
00013B BE34D8F0       CMP      WR6,#0D8F0H
00013F 580A           JSGE     ?C0028
000141 7E24D8F0       MOV      WR4,#0D8F0H
000145 7A270000    R  MOV      dutyOfMotor,WR4
000149 800E           SJMP     ?C0032
               ?C0028:
00014B BE342710       CMP      WR6,#02710H
00014F 0808           JSLE     ?C0032
000151 7E342710       MOV      WR6,#02710H
000155 7A370000    R  MOV      dutyOfMotor,WR6
                                                ; SOURCE LINE # 174
               ?C0032:
000159 7E370000    R  MOV      WR6,dutyOfMotor+2
00015D BE34D8F0       CMP      WR6,#0D8F0H
000161 580A           JSGE     ?C0035
000163 7E24D8F0       MOV      WR4,#0D8F0H
000167 7A270000    R  MOV      dutyOfMotor+2,WR4
00016B 800E           SJMP     ?C0039
               ?C0035:
00016D BE342710       CMP      WR6,#02710H
000171 0808           JSLE     ?C0039
000173 7E342710       MOV      WR6,#02710H
000177 7A370000    R  MOV      dutyOfMotor+2,WR6
                                                ; SOURCE LINE # 175
               ?C0039:
00017B 7E370000    R  MOV      WR6,dutyOfMotor+4
00017F BE34D8F0       CMP      WR6,#0D8F0H
000183 580A           JSGE     ?C0042
000185 7E24D8F0       MOV      WR4,#0D8F0H
000189 7A270000    R  MOV      dutyOfMotor+4,WR4
00018D 800E           SJMP     ?C0046
               ?C0042:
00018F BE342710       CMP      WR6,#02710H
000193 0808           JSLE     ?C0046
000195 7E342710       MOV      WR6,#02710H
000199 7A370000    R  MOV      dutyOfMotor+4,WR6
                                                ; SOURCE LINE # 176
               ?C0046:
00019D 7E370000    R  MOV      WR6,dutyOfMotor+6
0001A1 BE34D8F0       CMP      WR6,#0D8F0H
0001A5 580A           JSGE     ?C0049
0001A7 7E24D8F0       MOV      WR4,#0D8F0H
0001AB 7A270000    R  MOV      dutyOfMotor+6,WR4
0001AF 800E           SJMP     ?C0053
               ?C0049:
0001B1 BE342710       CMP      WR6,#02710H
0001B5 0808           JSLE     ?C0053
0001B7 7E342710       MOV      WR6,#02710H
0001BB 7A370000    R  MOV      dutyOfMotor+6,WR6
                                                ; SOURCE LINE # 177
               ?C0053:
0001BF 7E370000    R  MOV      WR6,dutyOfMotor+8
0001C3 BE340000       CMP      WR6,#00H
0001C7 5808           JSGE     ?C0056
0001C9 6D22           XRL      WR4,WR4
0001CB 7A270000    R  MOV      dutyOfMotor+8,WR4
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 12  

0001CF 800E           SJMP     ?C0060
               ?C0056:
0001D1 BE342710       CMP      WR6,#02710H
0001D5 0808           JSLE     ?C0060
0001D7 7E342710       MOV      WR6,#02710H
0001DB 7A370000    R  MOV      dutyOfMotor+8,WR6
                                                ; SOURCE LINE # 179
               ?C0060:
0001DF 7EF48000       MOV      WR30,#08000H
0001E3 7EE443D0       MOV      WR28,#043D0H
0001E7 7E5F0000    R  MOV      DR20,floatDutyOfServo
0001EB 7F15           MOV      DR4,DR20
0001ED 7F07           MOV      DR0,DR28
0001EF 9A000000    E  ECALL    ?C?FPCMP3?
0001F3 5006           JNC      ?C0063
0001F5 7A7F0000    R  MOV      floatDutyOfServo,DR28
0001F9 8016           SJMP     ?C0067
               ?C0063:
0001FB 7ED46000       MOV      WR26,#06000H
0001FF 7EC44487       MOV      WR24,#04487H
000203 7F15           MOV      DR4,DR20
000205 7F06           MOV      DR0,DR24
000207 9A000000    E  ECALL    ?C?FPCMP3?
00020B 2804           JLE      ?C0067
00020D 7A6F0000    R  MOV      floatDutyOfServo,DR24
                                                ; SOURCE LINE # 181
               ?C0067:
000211 7E6F0000    R  MOV      DR24,floatDutyOfServo+4
000215 7F16           MOV      DR4,DR24
000217 7F07           MOV      DR0,DR28
000219 9A000000    E  ECALL    ?C?FPCMP3?
00021D 5002           JNC      ?C0070
00021F 8012           SJMP     ?C0123
               ?C0070:
000221 7EF46000       MOV      WR30,#06000H
000225 7EE44487       MOV      WR28,#04487H
000229 7F16           MOV      DR4,DR24
00022B 7F07           MOV      DR0,DR28
00022D 9A000000    E  ECALL    ?C?FPCMP3?
000231 2804           JLE      ?C0069
               ?C0123:
000233 7A7F0000    R  MOV      floatDutyOfServo+4,DR28
               ?C0069:
                                                ; SOURCE LINE # 183
000237 7EB30000    R  MOV      R11,triggerKeyValue
00023B 6044           JZ       ?C0073
00023D 7EB30000    R  MOV      R11,lastTriggerKeyValue
000241 703E           JNZ      ?C0073
                                                ; SOURCE LINE # 185
000243 7E370000    R  MOV      WR6,boosterDutyOfFeed
000247 7A370000    R  MOV      dutyOfMotor+8,WR6
                                                ; SOURCE LINE # 188
00024B 7E370000    R  MOV      WR6,dutyOfBooster
00024F 7A370000    R  MOV      ?Main_Countrol??BYTE+8,WR6
000253 7E000000    R  MOV      DR0,#WORD0 dutyOfMotor
000257 7E100000    R  MOV      DR4,#WORD0 dutyOfServo
00025B 9A000000    R  ECALL    Main_Countrol?
                                                ; SOURCE LINE # 189
00025F 7E370000    R  MOV      WR6,boosterFeedDelayMs
000263 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 190
000267 6D33           XRL      WR6,WR6
000269 7A370000    R  MOV      dutyOfMotor+8,WR6
                                                ; SOURCE LINE # 191
00026D 7E370000    R  MOV      WR6,dutyOfBooster
000271 7A370000    R  MOV      ?Main_Countrol??BYTE+8,WR6
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 13  

000275 7E000000    R  MOV      DR0,#WORD0 dutyOfMotor
000279 7E100000    R  MOV      DR4,#WORD0 dutyOfServo
00027D 9A000000    R  ECALL    Main_Countrol?
                                                ; SOURCE LINE # 192
               ?C0073:
                                                ; SOURCE LINE # 193
000281 7E730000    R  MOV      R7,triggerKeyValue
000285 7A730000    R  MOV      lastTriggerKeyValue,R7
                                                ; SOURCE LINE # 199
000289 7E270000    R  MOV      WR4,expectDutyOfBooster
00028D BE2401F4       CMP      WR4,#01F4H
000291 4010           JC       ?C0074
000293 7E370000    R  MOV      WR6,dutyOfBooster
000297 BE3401F4       CMP      WR6,#01F4H
00029B 5006           JNC      ?C0074
                                                ; SOURCE LINE # 200
00029D 7E3401F4       MOV      WR6,#01F4H
0002A1 802C           SJMP     ?C0125
               ?C0074:
                                                ; SOURCE LINE # 201
0002A3 BE270000    R  CMP      WR4,dutyOfBooster
0002A7 2808           JLE      ?C0076
                                                ; SOURCE LINE # 202
0002A9 7E370000    R  MOV      WR6,dutyOfBooster
0002AD 0B34           INC      WR6,#01H
0002AF 801E           SJMP     ?C0125
               ?C0076:
                                                ; SOURCE LINE # 203
0002B1 BE270000    R  CMP      WR4,dutyOfBooster
0002B5 501C           JNC      ?C0075
                                                ; SOURCE LINE # 206
0002B7 7E370000    R  MOV      WR6,dutyOfBooster
0002BB BE3401F4       CMP      WR6,#01F4H
0002BF 380C           JG       ?C0079
0002C1 4D22           ORL      WR4,WR4
0002C3 7808           JNE      ?C0079
                                                ; SOURCE LINE # 207
0002C5 6D22           XRL      WR4,WR4
0002C7 7A270000    R  MOV      dutyOfBooster,WR4
0002CB 8006           SJMP     ?C0075
               ?C0079:
                                                ; SOURCE LINE # 209
0002CD 1B34           DEC      WR6,#01H
               ?C0125:
0002CF 7A370000    R  MOV      dutyOfBooster,WR6
                                                ; SOURCE LINE # 210
               ?C0075:
                                                ; SOURCE LINE # 213
0002D3 7E370000    R  MOV      WR6,dutyOfBooster
0002D7 7A370000    R  MOV      ?Main_Countrol??BYTE+8,WR6
0002DB 7E000000    R  MOV      DR0,#WORD0 dutyOfMotor
0002DF 7E100000    R  MOV      DR4,#WORD0 dutyOfServo
0002E3 9A000000    R  ECALL    Main_Countrol?
                                                ; SOURCE LINE # 214
0002E7 7E34000A       MOV      WR6,#0AH
0002EB 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 215
0002EF 020000      R  LJMP     ?C0020
;       FUNCTION main? (END)

;       FUNCTION Get_Dir? (BEGIN)
                                                ; SOURCE LINE # 218
;---- Variable 'rawdata' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 220
0002F2 BE340000       CMP      WR6,#00H
0002F6 4803           JSL      ?C0081
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 14  

                                                ; SOURCE LINE # 221
0002F8 7401           MOV      A,#01H           ; A=R11
0002FA AA             ERET     
               ?C0081:
                                                ; SOURCE LINE # 223
0002FB E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 224
0002FC AA             ERET     
;       FUNCTION Get_Dir? (END)

;       FUNCTION All_Init? (BEGIN)
                                                ; SOURCE LINE # 226
                                                ; SOURCE LINE # 231
0002FD E4             CLR      A                ; A=R11
0002FE 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 232
000301 9A000000    E  ECALL    Board_Init?
                                                ; SOURCE LINE # 233
000305 E4             CLR      A                ; A=R11
000306 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 234
000309 7401           MOV      A,#01H           ; A=R11
00030B 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 238
00030E 7E348400       MOV      WR6,#08400H
000312 7E240003       MOV      WR4,#03H
000316 7A1F0000    E  MOV      ?UART_Init??BYTE+6,DR4
00031A 6D22           XRL      WR4,WR4
00031C 6D33           XRL      WR6,WR6
00031E 7E040001       MOV      WR0,#01H
000322 7D10           MOV      WR2,WR0
000324 9A000000    E  ECALL    UART_Init?
                                                ; SOURCE LINE # 239
000328 7401           MOV      A,#01H           ; A=R11
00032A 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 240
00032D 7402           MOV      A,#02H           ; A=R11
00032F 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 242
000332 7E140003       MOV      WR2,#03H
000336 7D31           MOV      WR6,WR2
000338 7E2400E0       MOV      WR4,#0E0H
00033C 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 243
000340 7407           MOV      A,#07H           ; A=R11
000342 120000      R  LCALL    LedShow
                                                ; SOURCE LINE # 244
000345 7E3400C8       MOV      WR6,#0C8H
000349 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 245
00034D E4             CLR      A                ; A=R11
00034E 120000      R  LCALL    LedShow
                                                ; SOURCE LINE # 247
000351 9F11           SUB      DR4,DR4
000353 7A1F0000    E  MOV      ?PWM_Init??BYTE+6,DR4
000357 7E340061       MOV      WR6,#061H
00035B 7E0801F4       MOV      DR0,#01F4H
00035F 9A000000    E  ECALL    PWM_Init?
                                                ; SOURCE LINE # 248
000363 7402           MOV      A,#02H           ; A=R11
000365 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 249
000368 7403           MOV      A,#03H           ; A=R11
00036A 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 253
00036D C2AF           CLR      EA
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 15  

                                                ; SOURCE LINE # 254
00036F 120000      R  LCALL    remoteControlInitWithTimeout
                                                ; SOURCE LINE # 255
000372 7E34FD02       MOV      WR6,#0FD02H
000376 7E24007E       MOV      WR4,#07EH
00037A 7E1BB0         MOV      R11,@DR4         ; A=R11
00037D 54BF           ANL      A,#0BFH          ; A=R11
00037F 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 256
000382 D2AF           SETB     EA
                                                ; SOURCE LINE # 257
000384 7403           MOV      A,#03H           ; A=R11
000386 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 258
000389 7404           MOV      A,#04H           ; A=R11
00038B 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 259
00038E 7E342710       MOV      WR6,#02710H
000392 7A370000    R  MOV      ?ExpansionBoradControl??BYTE+9,WR6
000396 7A370000    R  MOV      ?ExpansionBoradControl??BYTE+11,WR6
00039A 7A370000    R  MOV      ?ExpansionBoradControl??BYTE+13,WR6
00039E 7A370000    R  MOV      ?ExpansionBoradControl??BYTE+15,WR6
0003A2 74AA           MOV      A,#0AAH          ; A=R11
0003A4 6D22           XRL      WR4,WR4
0003A6 7E040032       MOV      WR0,#032H
0003AA 7D10           MOV      WR2,WR0
0003AC 9A000000    R  ECALL    ExpansionBoradControl?
                                                ; SOURCE LINE # 265
0003B0 7E3403E8       MOV      WR6,#03E8H
0003B4 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 266
0003B8 7404           MOV      A,#04H           ; A=R11
0003BA 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 267
0003BD 7405           MOV      A,#05H           ; A=R11
0003BF 120000      R  LCALL    StepBegin
                                                ; SOURCE LINE # 268
0003C2 7E370000    R  MOV      WR6,midDutyOfServo
0003C6 6D22           XRL      WR4,WR4
0003C8 7A1F0000    E  MOV      ?PWM_Init??BYTE+6,DR4
0003CC 7E340043       MOV      WR6,#043H
0003D0 7E080032       MOV      DR0,#032H
0003D4 9A000000    E  ECALL    PWM_Init?
                                                ; SOURCE LINE # 269
0003D8 7E370000    R  MOV      WR6,midDutyOfServo+2
0003DC 6D22           XRL      WR4,WR4
0003DE 7A1F0000    E  MOV      ?PWM_Init??BYTE+6,DR4
0003E2 7E340072       MOV      WR6,#072H
0003E6 7E080032       MOV      DR0,#032H
0003EA 9A000000    E  ECALL    PWM_Init?
                                                ; SOURCE LINE # 270
0003EE 7405           MOV      A,#05H           ; A=R11
0003F0 120000      R  LCALL    StepDone
                                                ; SOURCE LINE # 272
0003F3 7E34020B       MOV      WR6,#020BH
0003F7 7E240078       MOV      WR4,#078H
0003FB 120000      R  LCALL    Beep
                                                ; SOURCE LINE # 273
0003FE 7E340293       MOV      WR6,#0293H
000402 7E240078       MOV      WR4,#078H
000406 120000      R  LCALL    Beep
                                                ; SOURCE LINE # 274
000409 7E340310       MOV      WR6,#0310H
00040D 7E240078       MOV      WR4,#078H
000411 120000      R  LCALL    Beep
                                                ; SOURCE LINE # 275
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 16  

000414 7E340417       MOV      WR6,#0417H
000418 7E2400F0       MOV      WR4,#0F0H
00041C 120000      R  LCALL    Beep
                                                ; SOURCE LINE # 276
00041F AA             ERET     
;       FUNCTION All_Init? (END)

;       FUNCTION ReadControllerInputs? (BEGIN)
                                                ; SOURCE LINE # 278
                                                ; SOURCE LINE # 281
000420 7E340001       MOV      WR6,#01H
000424 9A000000    E  ECALL    RcRockerValueRead?
000428 7A370000    R  MOV      valueOfRoker,WR6
                                                ; SOURCE LINE # 282
00042C 6D33           XRL      WR6,WR6
00042E 9A000000    E  ECALL    RcRockerValueRead?
000432 7A370000    R  MOV      valueOfRoker+2,WR6
                                                ; SOURCE LINE # 283
000436 7E340003       MOV      WR6,#03H
00043A 9A000000    E  ECALL    RcRockerValueRead?
00043E 7A370000    R  MOV      valueOfRoker+4,WR6
                                                ; SOURCE LINE # 284
000442 7E340002       MOV      WR6,#02H
000446 9A000000    E  ECALL    RcRockerValueRead?
00044A 7A370000    R  MOV      valueOfRoker+6,WR6
                                                ; SOURCE LINE # 286
00044E 7E370000    R  MOV      WR6,valueOfRoker
000452 9A000000    E  ECALL    abs??
000456 BE370000    R  CMP      WR6,deadBandOfLeft
00045A 3806           JG       ?C0084
                                                ; SOURCE LINE # 287
00045C 6D33           XRL      WR6,WR6
00045E 7A370000    R  MOV      valueOfRoker,WR6
               ?C0084:
                                                ; SOURCE LINE # 288
000462 7E370000    R  MOV      WR6,valueOfRoker+2
000466 9A000000    E  ECALL    abs??
00046A BE370000    R  CMP      WR6,deadBandOfLeft
00046E 3806           JG       ?C0085
                                                ; SOURCE LINE # 289
000470 6D33           XRL      WR6,WR6
000472 7A370000    R  MOV      valueOfRoker+2,WR6
               ?C0085:
                                                ; SOURCE LINE # 290
000476 7E370000    R  MOV      WR6,valueOfRoker+4
00047A 9A000000    E  ECALL    abs??
00047E BE370000    R  CMP      WR6,deadBandOfRight
000482 3806           JG       ?C0086
                                                ; SOURCE LINE # 291
000484 6D33           XRL      WR6,WR6
000486 7A370000    R  MOV      valueOfRoker+4,WR6
               ?C0086:
                                                ; SOURCE LINE # 292
00048A 7E370000    R  MOV      WR6,valueOfRoker+6
00048E 9A000000    E  ECALL    abs??
000492 BE370000    R  CMP      WR6,deadBandOfRight
000496 3806           JG       ?C0092
                                                ; SOURCE LINE # 293
000498 6D33           XRL      WR6,WR6
00049A 7A370000    R  MOV      valueOfRoker+6,WR6
                                                ; SOURCE LINE # 295
               ?C0092:
00049E E4             CLR      A                ; A=R11
00049F 7AB30000    R  MOV      i,R11            ; A=R11
                                                ; SOURCE LINE # 297
               ?C0097:
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 17  

0004A3 E4             CLR      A                ; A=R11
0004A4 7AB30000    R  MOV      j,R11            ; A=R11
               ?C0096:
                                                ; SOURCE LINE # 299
0004A8 7E730000    R  MOV      R7,i
0004AC A5BF0209       CJNE     R7,#02H,?C0098
0004B0 7E630000    R  MOV      R6,j
0004B4 BE6002         CMP      R6,#02H
0004B7 5046           JNC      ?C0094
                                                ; SOURCE LINE # 300
               ?C0098:
                                                ; SOURCE LINE # 301
0004B9 0A37           MOVZ     WR6,R7
0004BB 6D22           XRL      WR4,WR4
0004BD 7F01           MOV      DR0,DR4
0004BF 2F00           ADD      DR0,DR0
0004C1 2F00           ADD      DR0,DR0
0004C3 7E730000    R  MOV      R7,j
0004C7 2F10           ADD      DR4,DR0
0004C9 2E240000    R  ADD      WR4,#WORD2 keyOffsets
0004CD 2E180000    R  ADD      DR4,#WORD0 keyOffsets
0004D1 7E1B70         MOV      R7,@DR4
0004D4 0A37           MOVZ     WR6,R7
0004D6 9A000000    E  ECALL    RcKeyValueRead?
0004DA 7C7B           MOV      R7,R11           ; A=R11
0004DC 7E630000    R  MOV      R6,i
0004E0 7E5004         MOV      R5,#04H
0004E3 AC56           MUL      R5,R6
0004E5 7EB30000    R  MOV      R11,j            ; A=R11
0004E9 0A1B           MOVZ     WR2,R11          ; A=R11
0004EB 2D21           ADD      WR4,WR2
0004ED 19720000    R  MOV      @WR4+valueOfKey,R7
                                                ; SOURCE LINE # 302
0004F1 04             INC      A                ; A=R11
0004F2 7AB30000    R  MOV      j,R11            ; A=R11
0004F6 7E730000    R  MOV      R7,j
0004FA BE7004         CMP      R7,#04H
0004FD 40A9           JC       ?C0096
               ?C0094:
                                                ; SOURCE LINE # 303
0004FF 7EB30000    R  MOV      R11,i            ; A=R11
000503 04             INC      A                ; A=R11
000504 7AB30000    R  MOV      i,R11            ; A=R11
000508 7E730000    R  MOV      R7,i
00050C BE7003         CMP      R7,#03H
00050F 4092           JC       ?C0097
                                                ; SOURCE LINE # 305
000511 7E340001       MOV      WR6,#01H
000515 9A000000    E  ECALL    RcKeyValueRead?
000519 7AB30000    R  MOV      triggerKeyValue,R11
                                                ; SOURCE LINE # 306
00051D 7E340006       MOV      WR6,#06H
000521 9A000000    E  ECALL    RcKeyValueRead?
000525 7AB30000    R  MOV      boosterKeyValue,R11
                                                ; SOURCE LINE # 307
000529 AA             ERET     
;       FUNCTION ReadControllerInputs? (END)

;       FUNCTION CalculateMotorControls? (BEGIN)
                                                ; SOURCE LINE # 309
                                                ; SOURCE LINE # 313
00052A 7EB30000    R  MOV      R11,valueOfKey+8 ; A=R11
00052E 6006           JZ       ?C0099
                                                ; SOURCE LINE # 315
000530 7E270000    R  MOV      WR4,ultraSpeed
                                                ; SOURCE LINE # 316
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 18  

                                                ; SOURCE LINE # 317
000534 8004           SJMP     ?C0126
               ?C0099:
                                                ; SOURCE LINE # 320
000536 7E270000    R  MOV      WR4,maxSpeed
               ?C0126:
00053A E4             CLR      A                ; A=R11
00053B 9A000000    E  ECALL    ?C?FCASTI?
00053F 7F61           MOV      DR24,DR4
000541 7E270000    R  MOV      WR4,valueOfRoker+2
000545 7CB4           MOV      R11,R4           ; A=R11
000547 9A000000    E  ECALL    ?C?FCASTI?
00054B 7F06           MOV      DR0,DR24
00054D 9A000000    E  ECALL    ?C?FPMUL?
000551 7EF4E000       MOV      WR30,#0E000H
000555 7EE444FF       MOV      WR28,#044FFH
000559 7F07           MOV      DR0,DR28
00055B 9A000000    E  ECALL    ?C?FPDIV?
00055F 9A000000    E  ECALL    ?C?CASTF?
000563 7A370000    R  MOV      baseSpeed,WR6
                                                ; SOURCE LINE # 321
000567 7E270000    R  MOV      WR4,valueOfRoker
00056B 7CB4           MOV      R11,R4           ; A=R11
00056D 9A000000    E  ECALL    ?C?FCASTI?
000571 7F06           MOV      DR0,DR24
000573 9A000000    E  ECALL    ?C?FPMUL?
000577 7F07           MOV      DR0,DR28
000579 9A000000    E  ECALL    ?C?FPDIV?
00057D 9A000000    E  ECALL    ?C?CASTF?
000581 7A370000    R  MOV      turnSpeed,WR6
                                                ; SOURCE LINE # 322
                                                ; SOURCE LINE # 325
000585 7EB30000    R  MOV      R11,valueOfKey   ; A=R11
000589 B40108         CJNE     A,#01H,?C0101    ; A=R11
                                                ; SOURCE LINE # 326
00058C 7E370000    R  MOV      WR6,maxSpeed
000590 7A370000    R  MOV      baseSpeed,WR6
               ?C0101:
                                                ; SOURCE LINE # 327
000594 7EB30000    R  MOV      R11,valueOfKey+1 ; A=R11
000598 B4010A         CJNE     A,#01H,?C0102    ; A=R11
                                                ; SOURCE LINE # 328
00059B 6D33           XRL      WR6,WR6
00059D 9E370000    R  SUB      WR6,maxSpeed
0005A1 7A370000    R  MOV      baseSpeed,WR6
               ?C0102:
                                                ; SOURCE LINE # 329
0005A5 7EB30000    R  MOV      R11,valueOfKey+2 ; A=R11
0005A9 B4010A         CJNE     A,#01H,?C0103    ; A=R11
                                                ; SOURCE LINE # 330
0005AC 6D33           XRL      WR6,WR6
0005AE 9E370000    R  SUB      WR6,maxSpeed
0005B2 7A370000    R  MOV      turnSpeed,WR6
               ?C0103:
                                                ; SOURCE LINE # 331
0005B6 7EB30000    R  MOV      R11,valueOfKey+3 ; A=R11
0005BA B40108         CJNE     A,#01H,?C0104    ; A=R11
                                                ; SOURCE LINE # 332
0005BD 7E370000    R  MOV      WR6,maxSpeed
0005C1 7A370000    R  MOV      turnSpeed,WR6
               ?C0104:
                                                ; SOURCE LINE # 333
0005C5 6D33           XRL      WR6,WR6
0005C7 9E370000    R  SUB      WR6,baseSpeed
0005CB 9E370000    R  SUB      WR6,turnSpeed
0005CF 7A370000    R  MOV      dutyOfMotor,WR6
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 19  

                                                ; SOURCE LINE # 334
0005D3 7A370000    R  MOV      dutyOfMotor+2,WR6
                                                ; SOURCE LINE # 335
0005D7 7E370000    R  MOV      WR6,baseSpeed
0005DB 9E370000    R  SUB      WR6,turnSpeed
0005DF 7A370000    R  MOV      dutyOfMotor+4,WR6
                                                ; SOURCE LINE # 336
0005E3 7A370000    R  MOV      dutyOfMotor+6,WR6
                                                ; SOURCE LINE # 339
0005E7 7EB30000    R  MOV      R11,valueOfKey+7 ; A=R11
0005EB 6006           JZ       ?C0105
                                                ; SOURCE LINE # 340
0005ED 6D33           XRL      WR6,WR6
0005EF 7A370000    R  MOV      dutyOfMotor+8,WR6
               ?C0105:
                                                ; SOURCE LINE # 341
0005F3 AA             ERET     
;       FUNCTION CalculateMotorControls? (END)

;       FUNCTION CalculateBoosterControl? (BEGIN)
                                                ; SOURCE LINE # 343
                                                ; SOURCE LINE # 347
0005F4 7E730000    R  MOV      R7,valueOfKey+5
0005F8 4C77           ORL      R7,R7
0005FA 681E           JE       ?C0106
0005FC 7EB30000    R  MOV      R11,lastBoosterUpKeyValue
000600 7018           JNZ      ?C0106
                                                ; SOURCE LINE # 349
000602 7E270000    R  MOV      WR4,singleChangeDutyOfBooster
000606 2E270000    R  ADD      WR4,levelDutyOfBooster
00060A BE270000    R  CMP      WR4,maxDutyOfBooster
00060E 3802           JG       ?C0107
                                                ; SOURCE LINE # 350
000610 8004           SJMP     ?C0127
               ?C0107:
                                                ; SOURCE LINE # 352
000612 7E270000    R  MOV      WR4,maxDutyOfBooster
               ?C0127:
000616 7A270000    R  MOV      levelDutyOfBooster,WR4
                                                ; SOURCE LINE # 353
               ?C0106:
                                                ; SOURCE LINE # 354
00061A 7EA30000    R  MOV      R10,valueOfKey+6
00061E 4CAA           ORL      R10,R10
000620 6826           JE       ?C0109
000622 7EB30000    R  MOV      R11,lastBoosterDownKeyValue
000626 7020           JNZ      ?C0109
                                                ; SOURCE LINE # 356
000628 7E270000    R  MOV      WR4,singleChangeDutyOfBooster
00062C 2E270000    R  ADD      WR4,minDutyOfBooster
000630 BE270000    R  CMP      WR4,levelDutyOfBooster
000634 380A           JG       ?C0110
                                                ; SOURCE LINE # 357
000636 7E270000    R  MOV      WR4,levelDutyOfBooster
00063A 9E270000    R  SUB      WR4,singleChangeDutyOfBooster
00063E 8004           SJMP     ?C0128
               ?C0110:
                                                ; SOURCE LINE # 359
000640 7E270000    R  MOV      WR4,minDutyOfBooster
               ?C0128:
000644 7A270000    R  MOV      levelDutyOfBooster,WR4
                                                ; SOURCE LINE # 360
               ?C0109:
                                                ; SOURCE LINE # 361
000648 7A730000    R  MOV      lastBoosterUpKeyValue,R7
                                                ; SOURCE LINE # 362
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 20  

00064C 7AA30000    R  MOV      lastBoosterDownKeyValue,R10
                                                ; SOURCE LINE # 365
000650 7EA30000    R  MOV      R10,boosterKeyValue
000654 4CAA           ORL      R10,R10
000656 6815           JE       ?C0112
000658 7EB30000    R  MOV      R11,lastBoosterKeyValue
00065C 700F           JNZ      ?C0112
                                                ; SOURCE LINE # 367
00065E 7EB30000    R  MOV      R11,statusOfBooster
000662 7004           JNZ      ?C0113
000664 7401           MOV      A,#01H           ; A=R11
000666 8001           SJMP     ?C0114
               ?C0113:
000668 E4             CLR      A                ; A=R11
               ?C0114:
000669 7AB30000    R  MOV      statusOfBooster,R11
                                                ; SOURCE LINE # 368
               ?C0112:
                                                ; SOURCE LINE # 369
00066D 7AA30000    R  MOV      lastBoosterKeyValue,R10
                                                ; SOURCE LINE # 371
000671 7EB30000    R  MOV      R11,statusOfBooster
000675 6006           JZ       ?C0115
                                                ; SOURCE LINE # 372
000677 7E370000    R  MOV      WR6,levelDutyOfBooster
00067B 8002           SJMP     ?C0129
               ?C0115:
                                                ; SOURCE LINE # 374
00067D 6D33           XRL      WR6,WR6
               ?C0129:
00067F 7A370000    R  MOV      expectDutyOfBooster,WR6
                                                ; SOURCE LINE # 375
000683 AA             ERET     
;       FUNCTION CalculateBoosterControl? (END)

;       FUNCTION CalculateGimbalControls? (BEGIN)
                                                ; SOURCE LINE # 377
                                                ; SOURCE LINE # 380
000684 7E270000    R  MOV      WR4,valueOfRoker+4
000688 7CB4           MOV      R11,R4           ; A=R11
00068A 9A000000    E  ECALL    ?C?FCASTI?
00068E 7E0F0000    R  MOV      DR0,changeRateOfServo
000692 9A000000    E  ECALL    ?C?FPMUL?
000696 7E0F0000    R  MOV      DR0,floatDutyOfServo
00069A 9A000000    E  ECALL    ?C?FPADD?
00069E 7A1F0000    R  MOV      floatDutyOfServo,DR4
                                                ; SOURCE LINE # 381
0006A2 7E270000    R  MOV      WR4,valueOfRoker+6
0006A6 7CB4           MOV      R11,R4           ; A=R11
0006A8 9A000000    E  ECALL    ?C?FCASTI?
0006AC 7E0F0000    R  MOV      DR0,changeRateOfServo+4
0006B0 9A000000    E  ECALL    ?C?FPMUL?
0006B4 7E0F0000    R  MOV      DR0,floatDutyOfServo+4
0006B8 9A000000    E  ECALL    ?C?FPADD?
0006BC 7A1F0000    R  MOV      floatDutyOfServo+4,DR4
                                                ; SOURCE LINE # 382
0006C0 7E1F0000    R  MOV      DR4,floatDutyOfServo
0006C4 9A000000    E  ECALL    ?C?CASTF?
0006C8 7A370000    R  MOV      dutyOfServo,WR6
                                                ; SOURCE LINE # 383
0006CC 7E1F0000    R  MOV      DR4,floatDutyOfServo+4
0006D0 9A000000    E  ECALL    ?C?CASTF?
0006D4 7A370000    R  MOV      dutyOfServo+2,WR6
                                                ; SOURCE LINE # 384
0006D8 AA             ERET     
;       FUNCTION CalculateGimbalControls? (END)
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 21  


;       FUNCTION Main_Countrol? (BEGIN)
                                                ; SOURCE LINE # 386
0006D9 CA3B           PUSH     DR12
0006DB 7A1F0000    R  MOV      dutyOfServo,DR4
0006DF 7A0F0000    R  MOV      dutyOfMotor,DR0
                                                ; SOURCE LINE # 389
0006E3 7E1F0000    R  MOV      DR4,dutyOfMotor
0006E7 0B1A30         MOV      WR6,@DR4
0006EA 9A000000    R  ECALL    Get_Dir?
0006EE 0A7B           MOVZ     WR14,R11         ; A=R11
0006F0 7E1F0000    R  MOV      DR4,dutyOfMotor
0006F4 69310002       MOV      WR6,@DR4+0x2
0006F8 9A000000    R  ECALL    Get_Dir?
0006FC 0A6B           MOVZ     WR12,R11         ; A=R11
0006FE 7E1F0000    R  MOV      DR4,dutyOfMotor
000702 69310004       MOV      WR6,@DR4+0x4
000706 9A000000    R  ECALL    Get_Dir?
00070A 0A4B           MOVZ     WR8,R11          ; A=R11
00070C CA49           PUSH     WR8
00070E 7E1F0000    R  MOV      DR4,dutyOfMotor
000712 69310006       MOV      WR6,@DR4+0x6
000716 9A000000    R  ECALL    Get_Dir?
00071A 0A4B           MOVZ     WR8,R11          ; A=R11
00071C 74DD           MOV      A,#0DDH          ; A=R11
00071E 7E240001       MOV      WR4,#01H
000722 7D32           MOV      WR6,WR4
000724 6D00           XRL      WR0,WR0
000726 6D11           XRL      WR2,WR2
000728 7A470000    R  MOV      ?ExpansionBoradControl??BYTE+15,WR8
00072C DA49           POP      WR8
00072E 7A470000    R  MOV      ?ExpansionBoradControl??BYTE+13,WR8
000732 7A670000    R  MOV      ?ExpansionBoradControl??BYTE+11,WR12
000736 7A770000    R  MOV      ?ExpansionBoradControl??BYTE+9,WR14
00073A 9A000000    R  ECALL    ExpansionBoradControl?
                                                ; SOURCE LINE # 394
00073E 7E340005       MOV      WR6,#05H
000742 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 395
000746 7E1F0000    R  MOV      DR4,dutyOfMotor
00074A 0B1A30         MOV      WR6,@DR4
00074D 9A000000    E  ECALL    abs??
000751 7D73           MOV      WR14,WR6
000753 7E1F0000    R  MOV      DR4,dutyOfMotor
000757 69310002       MOV      WR6,@DR4+0x2
00075B 9A000000    E  ECALL    abs??
00075F 7D63           MOV      WR12,WR6
000761 7E1F0000    R  MOV      DR4,dutyOfMotor
000765 69310004       MOV      WR6,@DR4+0x4
000769 9A000000    E  ECALL    abs??
00076D CA39           PUSH     WR6
00076F 7E1F0000    R  MOV      DR4,dutyOfMotor
000773 69310006       MOV      WR6,@DR4+0x6
000777 9A000000    E  ECALL    abs??
00077B 7D43           MOV      WR8,WR6
00077D 74BB           MOV      A,#0BBH          ; A=R11
00077F 7E1F0000    R  MOV      DR4,dutyOfMotor
000783 69310008       MOV      WR6,@DR4+0x8
000787 6D22           XRL      WR4,WR4
000789 7E070000    R  MOV      WR0,dutyOfBooster
00078D 7D10           MOV      WR2,WR0
00078F 7A470000    R  MOV      ?ExpansionBoradControl??BYTE+15,WR8
000793 DA49           POP      WR8
000795 7A470000    R  MOV      ?ExpansionBoradControl??BYTE+13,WR8
000799 7A670000    R  MOV      ?ExpansionBoradControl??BYTE+11,WR12
00079D 7A770000    R  MOV      ?ExpansionBoradControl??BYTE+9,WR14
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 22  

0007A1 9A000000    R  ECALL    ExpansionBoradControl?
                                                ; SOURCE LINE # 399
0007A5 7E340005       MOV      WR6,#05H
0007A9 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 400
0007AD 7E1F0000    R  MOV      DR4,dutyOfServo
0007B1 0B1A30         MOV      WR6,@DR4
0007B4 6D22           XRL      WR4,WR4
0007B6 7A1F0000    E  MOV      ?PWM_SET_Frequency??BYTE+6,DR4
0007BA 7E340043       MOV      WR6,#043H
0007BE 7E080032       MOV      DR0,#032H
0007C2 9A000000    E  ECALL    PWM_SET_Frequency?
                                                ; SOURCE LINE # 401
0007C6 7E1F0000    R  MOV      DR4,dutyOfServo
0007CA 69310002       MOV      WR6,@DR4+0x2
0007CE 6D22           XRL      WR4,WR4
0007D0 7A1F0000    E  MOV      ?PWM_SET_Frequency??BYTE+6,DR4
0007D4 7E340072       MOV      WR6,#072H
0007D8 7E080032       MOV      DR0,#032H
0007DC 9A000000    E  ECALL    PWM_SET_Frequency?
                                                ; SOURCE LINE # 402
0007E0 DA3B           POP      DR12
0007E2 AA             ERET     
;       FUNCTION Main_Countrol? (END)

;       FUNCTION ExpansionBoradControl? (BEGIN)
                                                ; SOURCE LINE # 414
0007E3 CAF8           PUSH     R15
0007E5 7D40           MOV      WR8,WR0
;---- Variable 'data_p66' assigned to Register 'WR8' ----
0007E7 7DF1           MOV      WR30,WR2
;---- Variable 'data_p64' assigned to Register 'WR30' ----
0007E9 7DE2           MOV      WR28,WR4
;---- Variable 'data_p62' assigned to Register 'WR28' ----
0007EB 7DD3           MOV      WR26,WR6
;---- Variable 'data_p60' assigned to Register 'WR26' ----
0007ED 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'control_cmd' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 417
                                                ; SOURCE LINE # 418
                                                ; SOURCE LINE # 419
0007EF 7E340000    R  MOV      WR6,#WORD0 ?tpl?0001
0007F3 7E240000    R  MOV      WR4,#WORD2 ?tpl?0001
0007F7 7E140000    R  MOV      WR2,#WORD0 control_frame_pack
0007FB 7415           MOV      A,#015H          ; A=R11
0007FD 9A000000    E  ECALL    ?C?BMOVENP8?
                                                ; SOURCE LINE # 420
000801 74AB           MOV      A,#0ABH          ; A=R11
000803 7AB30000    R  MOV      control_frame_pack,R11
                                                ; SOURCE LINE # 421
000807 74BC           MOV      A,#0BCH          ; A=R11
000809 7AB30000    R  MOV      control_frame_pack+1,R11
                                                ; SOURCE LINE # 422
00080D 74CD           MOV      A,#0CDH          ; A=R11
00080F 7AB30000    R  MOV      control_frame_pack+19,R11
                                                ; SOURCE LINE # 423
000813 74DE           MOV      A,#0DEH          ; A=R11
000815 7AB30000    R  MOV      control_frame_pack+20,R11
                                                ; SOURCE LINE # 424
000819 7AF30000    R  MOV      control_frame_pack+2,R15
                                                ; SOURCE LINE # 425
00081D 7D3D           MOV      WR6,WR26
00081F 0A36           MOVZ     WR6,R6
000821 7A730000    R  MOV      control_frame_pack+3,R7
                                                ; SOURCE LINE # 426
000825 7D3D           MOV      WR6,WR26
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 23  

000827 7A730000    R  MOV      control_frame_pack+4,R7
                                                ; SOURCE LINE # 427
00082B 7D3E           MOV      WR6,WR28
00082D 0A36           MOVZ     WR6,R6
00082F 7A730000    R  MOV      control_frame_pack+5,R7
                                                ; SOURCE LINE # 428
000833 7D3E           MOV      WR6,WR28
000835 7A730000    R  MOV      control_frame_pack+6,R7
                                                ; SOURCE LINE # 429
000839 7D3F           MOV      WR6,WR30
00083B 0A36           MOVZ     WR6,R6
00083D 7A730000    R  MOV      control_frame_pack+7,R7
                                                ; SOURCE LINE # 430
000841 7D3F           MOV      WR6,WR30
000843 7A730000    R  MOV      control_frame_pack+8,R7
                                                ; SOURCE LINE # 431
000847 7A830000    R  MOV      control_frame_pack+9,R8
                                                ; SOURCE LINE # 432
00084B 7A930000    R  MOV      control_frame_pack+10,R9
                                                ; SOURCE LINE # 433
00084F 7E370000    R  MOV      WR6,data_p74
000853 7A630000    R  MOV      control_frame_pack+11,R6
                                                ; SOURCE LINE # 434
000857 7A730000    R  MOV      control_frame_pack+12,R7
                                                ; SOURCE LINE # 435
00085B 7E370000    R  MOV      WR6,data_p75
00085F 7A630000    R  MOV      control_frame_pack+13,R6
                                                ; SOURCE LINE # 436
000863 7A730000    R  MOV      control_frame_pack+14,R7
                                                ; SOURCE LINE # 437
000867 7E370000    R  MOV      WR6,data_p76
00086B 7A630000    R  MOV      control_frame_pack+15,R6
                                                ; SOURCE LINE # 438
00086F 7A730000    R  MOV      control_frame_pack+16,R7
                                                ; SOURCE LINE # 439
000873 7E370000    R  MOV      WR6,data_p77
000877 7A630000    R  MOV      control_frame_pack+17,R6
                                                ; SOURCE LINE # 440
00087B 7A730000    R  MOV      control_frame_pack+18,R7
                                                ; SOURCE LINE # 441
00087F 6CFF           XRL      R15,R15
;---- Variable 'i' assigned to Register 'R15' ----
               ?C0120:
                                                ; SOURCE LINE # 442
000881 0A3F           MOVZ     WR6,R15
000883 09B30000    R  MOV      R11,@WR6+control_frame_pack
000887 120000      R  LCALL    Uart1TxQuery
00088A 0BF0           INC      R15,#01H
00088C BEF015         CMP      R15,#015H
00088F 40F0           JC       ?C0120
                                                ; SOURCE LINE # 443
000891 DAF8           POP      R15
000893 AA             ERET     
;       FUNCTION ExpansionBoradControl? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      2196     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =       130         39
C251 COMPILER V5.60.0,  main                                                               24/08/26  10:23:16  PAGE 24  

  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =       198     ------
End of Module Information.


C251 COMPILATION COMPLETE.  2 WARNING(S),  0 ERROR(S)
