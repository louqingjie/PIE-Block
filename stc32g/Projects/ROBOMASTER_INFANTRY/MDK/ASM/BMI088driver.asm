C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE BMI088driver
OBJECT MODULE PLACED IN .\Objects\ASM\BMI088driver.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\BMI088driver.c XSMALL ROM(HUGE) BROWSE I
                    -NCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR
                    -(0X1000) DEBUG CODE PRINT(.\ASM\BMI088driver.asm) TABS(2) OBJECT(.\Objects\ASM\BMI088driver.obj) 

stmt  level    source

    1          #include "BMI088driver.h"
    2          #include "BMI088reg.h"
    3          #include "BMI088Middleware.h"
    4          
    5          
    6          float BMI088_ACCEL_SEN = BMI088_ACCEL_3G_SEN;
    7          float BMI088_GYRO_SEN = BMI088_GYRO_2000_SEN;
    8          
    9          
   10          
   11          #if defined(BMI088_USE_SPI)
   12          
   13          #define BMI088_accel_write_single_reg(reg, data_t) \
   14              {                                            \
   15                  BMI088_ACCEL_NS_L();                     \
   16                  BMI088_write_single_reg((reg), (data_t));  \
   17                  BMI088_ACCEL_NS_H();                     \
   18              }
   19          #define BMI088_accel_read_single_reg(reg, data_t) \
   20              {                                           \
   21                  BMI088_ACCEL_NS_L();                    \
   22                  BMI088_read_write_byte((reg) | 0x80);   \
   23                  BMI088_read_write_byte(0x55);           \
   24                  (data_t) = BMI088_read_write_byte(0x55);  \
   25                  BMI088_ACCEL_NS_H();                    \
   26              }
   27          //#define BMI088_accel_write_muli_reg( reg,  data, len) { BMI088_ACCEL_NS_L(); BMI088_write_muli_reg(reg,
             - data, len); BMI088_ACCEL_NS_H(); }
   28          #define BMI088_accel_read_muli_reg(reg, data_t, len) \
   29              {                                              \
   30                  BMI088_ACCEL_NS_L();                       \
   31                  BMI088_read_write_byte((reg) | 0x80);      \
   32                  BMI088_read_muli_reg(reg, data_t, len);      \
   33                  BMI088_ACCEL_NS_H();                       \
   34              }
   35          
   36          #define BMI088_gyro_write_single_reg(reg, data_t) \
   37              {                                           \
   38                  BMI088_GYRO_NS_L();                     \
   39                  BMI088_write_single_reg((reg), (data_t)); \
   40                  BMI088_GYRO_NS_H();                     \
   41              }
   42          #define BMI088_gyro_read_single_reg(reg, data_t)  \
   43              {                                           \
   44                  BMI088_GYRO_NS_L();                     \
   45                  BMI088_read_single_reg((reg), &(data_t)); \
   46                  BMI088_GYRO_NS_H();                     \
   47              }
   48          //#define BMI088_gyro_write_muli_reg( reg,  data, len) { BMI088_GYRO_NS_L(); BMI088_write_muli_reg( ( reg
             - ), ( data ), ( len ) ); BMI088_GYRO_NS_H(); }
   49          #define BMI088_gyro_read_muli_reg(reg, data_t, len)   \
   50              {                                               \
   51                  BMI088_GYRO_NS_L();                         \
   52                  BMI088_read_muli_reg((reg), (data_t), (len)); \
   53                  BMI088_GYRO_NS_H();                         \
   54              }
   55          
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 2   

   56          static void BMI088_write_single_reg(uint8_t reg, uint8_t data_t);
   57          static void BMI088_read_single_reg(uint8_t reg, uint8_t *return_data);
   58          //static void BMI088_write_muli_reg(uint8_t reg, uint8_t* buf, uint8_t len );
   59          static void BMI088_read_muli_reg(uint8_t reg, uint8_t *buf, uint8_t len);
   60          
   61          #elif defined(BMI088_USE_IIC)
               
               
               #endif
   65          
   66          static uint8_t write_BMI088_accel_reg_data_error[BMI088_WRITE_ACCEL_REG_NUM][3] =
   67              {
   68                  {BMI088_ACC_PWR_CTRL, BMI088_ACC_ENABLE_ACC_ON, BMI088_ACC_PWR_CTRL_ERROR},
   69                  {BMI088_ACC_PWR_CONF, BMI088_ACC_PWR_ACTIVE_MODE, BMI088_ACC_PWR_CONF_ERROR},
   70                  {BMI088_ACC_CONF,  BMI088_ACC_NORMAL| BMI088_ACC_800_HZ | BMI088_ACC_CONF_MUST_Set, BMI088_ACC_CO
             -NF_ERROR},
   71                  {BMI088_ACC_RANGE, BMI088_ACC_RANGE_3G, BMI088_ACC_RANGE_ERROR},
   72                  {BMI088_INT1_IO_CTRL, BMI088_ACC_INT1_IO_ENABLE | BMI088_ACC_INT1_GPIO_PP | BMI088_ACC_INT1_GPIO_
             -LOW, BMI088_INT1_IO_CTRL_ERROR},
   73                  {BMI088_INT_MAP_DATA, BMI088_ACC_INT1_DRDY_INTERRUPT, BMI088_INT_MAP_DATA_ERROR}
   74          
   75          };
   76          
   77          static uint8_t write_BMI088_gyro_reg_data_error[BMI088_WRITE_GYRO_REG_NUM][3] =
   78              {
   79                  {BMI088_GYRO_RANGE, BMI088_GYRO_2000, BMI088_GYRO_RANGE_ERROR},
   80                  {BMI088_GYRO_BANDWIDTH, BMI088_GYRO_1000_116_HZ | BMI088_GYRO_BANDWIDTH_MUST_Set, BMI088_GYRO_BAN
             -DWIDTH_ERROR},
   81                  {BMI088_GYRO_LPM1, BMI088_GYRO_NORMAL_MODE, BMI088_GYRO_LPM1_ERROR},
   82                  {BMI088_GYRO_CTRL, BMI088_DRDY_ON, BMI088_GYRO_CTRL_ERROR},
   83                  {BMI088_GYRO_INT3_INT4_IO_CONF, BMI088_GYRO_INT3_GPIO_PP | BMI088_GYRO_INT3_GPIO_LOW, BMI088_GYRO
             -_INT3_INT4_IO_CONF_ERROR},
   84                  {BMI088_GYRO_INT3_INT4_IO_MAP, BMI088_GYRO_DRDY_IO_INT3, BMI088_GYRO_INT3_INT4_IO_MAP_ERROR}
   85          
   86          };
   87          
   88          uint8_t BMI088_init(void)
   89          {
   90   1          uint8_t error = BMI088_NO_ERROR;
   91   1          // GPIO and SPI  Init .
   92   1          BMI088_GPIO_init();
   93   1          BMI088_com_init();
   94   1      
   95   1          // self test pass and init
   96   1          if (bmi088_accel_self_test() != BMI088_NO_ERROR)
   97   1          {
   98   2              error |= BMI088_SELF_TEST_ACCEL_ERROR;
   99   2          }
  100   1          else
  101   1          {
  102   2              error |= bmi088_accel_init();
  103   2          }
  104   1      
  105   1          if (bmi088_gyro_self_test() != BMI088_NO_ERROR)
  106   1          {
  107   2              error |= BMI088_SELF_TEST_GYRO_ERROR;
  108   2          }
  109   1          else
  110   1          {
  111   2              error |= bmi088_gyro_init();
  112   2          }
  113   1      
  114   1          return error;
  115   1      }
  116          
  117          uint8_t bmi088_accel_init(void)
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 3   

  118          {
  119   1          volatile uint8_t res = 0;
  120   1          uint8_t write_reg_num = 0;
  121   1      
  122   1          //check commiunication
  123   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  124   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  125   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  126   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  127   1      
  128   1          //accel software reset
  129   1          BMI088_accel_write_single_reg(BMI088_ACC_SOFTRESET, BMI088_ACC_SOFTRESET_VALUE);
  130   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  131   1      
  132   1          //check commiunication is normal after reset
  133   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  134   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  135   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  136   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  137   1      
  138   1          // check the "who am I"
  139   1          if (res != BMI088_ACC_CHIP_ID_VALUE)
  140   1          {
  141   2              return BMI088_NO_SENSOR;
  142   2          }
  143   1      
  144   1          //set accel sonsor config and check
  145   1          for (write_reg_num = 0; write_reg_num < BMI088_WRITE_ACCEL_REG_NUM; write_reg_num++)
  146   1          {
  147   2      
  148   2              BMI088_accel_write_single_reg(write_BMI088_accel_reg_data_error[write_reg_num][0], write_BMI088_a
             -ccel_reg_data_error[write_reg_num][1]);
  149   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  150   2      
  151   2              BMI088_accel_read_single_reg(write_BMI088_accel_reg_data_error[write_reg_num][0], res);
  152   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  153   2      
  154   2              if (res != write_BMI088_accel_reg_data_error[write_reg_num][1])
  155   2              {
  156   3                  return write_BMI088_accel_reg_data_error[write_reg_num][2];
  157   3              }
  158   2          }
  159   1          return BMI088_NO_ERROR;
  160   1      }
  161          
  162          uint8_t bmi088_gyro_init(void)
  163          {
  164   1          uint8_t write_reg_num = 0;
  165   1          uint8_t res = 0;
  166   1      
  167   1          //check commiunication
  168   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  169   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  170   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  171   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  172   1      
  173   1          //reset the gyro sensor
  174   1          BMI088_gyro_write_single_reg(BMI088_GYRO_SOFTRESET, BMI088_GYRO_SOFTRESET_VALUE);
  175   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  176   1          //check commiunication is normal after reset
  177   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  178   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  179   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  180   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  181   1      
  182   1          // check the "who am I"
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 4   

  183   1          if (res != BMI088_GYRO_CHIP_ID_VALUE)
  184   1          {
  185   2              return BMI088_NO_SENSOR;
  186   2          }
  187   1      
  188   1          //set gyro sonsor config and check
  189   1          for (write_reg_num = 0; write_reg_num < BMI088_WRITE_GYRO_REG_NUM; write_reg_num++)
  190   1          {
  191   2      
  192   2              BMI088_gyro_write_single_reg(write_BMI088_gyro_reg_data_error[write_reg_num][0], write_BMI088_gyr
             -o_reg_data_error[write_reg_num][1]);
  193   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  194   2      
  195   2              BMI088_gyro_read_single_reg(write_BMI088_gyro_reg_data_error[write_reg_num][0], res);
  196   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  197   2      
  198   2              if (res != write_BMI088_gyro_reg_data_error[write_reg_num][1])
  199   2              {
  200   3                  return write_BMI088_gyro_reg_data_error[write_reg_num][2];
  201   3              }
  202   2          }
  203   1      
  204   1          return BMI088_NO_ERROR;
  205   1      }
  206          
  207          uint8_t bmi088_accel_self_test(void)
  208          {
  209   1      
  210   1          int16_t self_test_accel[2][3];
  211   1      
  212   1          uint8_t buf[6] = {0, 0, 0, 0, 0, 0};
  213   1          volatile uint8_t res = 0;
  214   1      
  215   1          uint8_t write_reg_num = 0;
  216   1      
  217   1          static const uint8_t write_BMI088_ACCEL_self_test_Reg_Data_Error[6][3] =
  218   1              {
  219   1                  {BMI088_ACC_CONF, BMI088_ACC_NORMAL | BMI088_ACC_1600_HZ | BMI088_ACC_CONF_MUST_Set, BMI088_A
             -CC_CONF_ERROR},
  220   1                  {BMI088_ACC_PWR_CTRL, BMI088_ACC_ENABLE_ACC_ON, BMI088_ACC_PWR_CTRL_ERROR},
  221   1                  {BMI088_ACC_RANGE, BMI088_ACC_RANGE_24G, BMI088_ACC_RANGE_ERROR},
  222   1                  {BMI088_ACC_PWR_CONF, BMI088_ACC_PWR_ACTIVE_MODE, BMI088_ACC_PWR_CONF_ERROR},
  223   1                  {BMI088_ACC_SELF_TEST, BMI088_ACC_SELF_TEST_POSITIVE_SIGNAL, BMI088_ACC_PWR_CONF_ERROR},
  224   1                  {BMI088_ACC_SELF_TEST, BMI088_ACC_SELF_TEST_NEGATIVE_SIGNAL, BMI088_ACC_PWR_CONF_ERROR}
  225   1      
  226   1              };
  227   1      
  228   1          //check commiunication is normal
  229   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  230   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  231   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  232   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  233   1      
  234   1          // reset  bmi088 accel sensor and wait for > 50ms
  235   1          BMI088_accel_write_single_reg(BMI088_ACC_SOFTRESET, BMI088_ACC_SOFTRESET_VALUE);
  236   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  237   1      
  238   1          //check commiunication is normal
  239   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  240   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  241   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  242   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  243   1      
  244   1          if (res != BMI088_ACC_CHIP_ID_VALUE)
  245   1          {
  246   2              return BMI088_NO_SENSOR;
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 5   

  247   2          }
  248   1      
  249   1          // set the accel register
  250   1          for (write_reg_num = 0; write_reg_num < 4; write_reg_num++)
  251   1          {
  252   2      
  253   2              BMI088_accel_write_single_reg(write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num][0], writ
             -e_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num][1]);
  254   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  255   2      
  256   2              BMI088_accel_read_single_reg(write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num][0], res);
  257   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  258   2      
  259   2              if (res != write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num][1])
  260   2              {
  261   3                  return write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num][2];
  262   3              }
  263   2              // accel conf and accel range  . the two register set need wait for > 50ms
  264   2              BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  265   2          }
  266   1      
  267   1          // self test include postive and negative
  268   1          for (write_reg_num = 0; write_reg_num < 2; write_reg_num++)
  269   1          {
  270   2      
  271   2              BMI088_accel_write_single_reg(write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num + 4][0], 
             -write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num + 4][1]);
  272   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  273   2      
  274   2              BMI088_accel_read_single_reg(write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num + 4][0], r
             -es);
  275   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  276   2      
  277   2              if (res != write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num + 4][1])
  278   2              {
  279   3                  return write_BMI088_ACCEL_self_test_Reg_Data_Error[write_reg_num + 4][2];
  280   3              }
  281   2              // accel conf and accel range  . the two register set need wait for > 50ms
  282   2              BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  283   2      
  284   2              // read response accel
  285   2              BMI088_accel_read_muli_reg(BMI088_ACCEL_XOUT_L, buf, 6);
  286   2      
  287   2              self_test_accel[write_reg_num][0] = (int16_t)((buf[1]) << 8) | buf[0];
  288   2              self_test_accel[write_reg_num][1] = (int16_t)((buf[3]) << 8) | buf[2];
  289   2              self_test_accel[write_reg_num][2] = (int16_t)((buf[5]) << 8) | buf[4];
  290   2          }
  291   1      
  292   1          //set self test off
  293   1          BMI088_accel_write_single_reg(BMI088_ACC_SELF_TEST, BMI088_ACC_SELF_TEST_OFF);
  294   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  295   1          BMI088_accel_read_single_reg(BMI088_ACC_SELF_TEST, res);
  296   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  297   1      
  298   1          if (res != (BMI088_ACC_SELF_TEST_OFF))
  299   1          {
  300   2              return BMI088_ACC_SELF_TEST_ERROR;
  301   2          }
  302   1      
  303   1          //reset the accel sensor
  304   1          BMI088_accel_write_single_reg(BMI088_ACC_SOFTRESET, BMI088_ACC_SOFTRESET_VALUE);
  305   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  306   1      
  307   1          if ((self_test_accel[0][0] - self_test_accel[1][0] < 1365) || (self_test_accel[0][1] - self_test_acce
             -l[1][1] < 1365) || (self_test_accel[0][2] - self_test_accel[1][2] < 680))
  308   1          {
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 6   

  309   2              return BMI088_SELF_TEST_ACCEL_ERROR;
  310   2          }
  311   1      
  312   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  313   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  314   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, res);
  315   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  316   1      
  317   1          return BMI088_NO_ERROR;
  318   1      }
  319          uint8_t bmi088_gyro_self_test(void)
  320          {
  321   1          uint8_t res = 0;
  322   1          uint8_t retry = 0;
  323   1          //check commiunication is normal
  324   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  325   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  326   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  327   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  328   1          //reset the gyro sensor
  329   1          BMI088_gyro_write_single_reg(BMI088_GYRO_SOFTRESET, BMI088_GYRO_SOFTRESET_VALUE);
  330   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  331   1          //check commiunication is normal after reset
  332   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  333   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  334   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, res);
  335   1          BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  336   1      
  337   1          BMI088_gyro_write_single_reg(BMI088_GYRO_SELF_TEST, BMI088_GYRO_TRIG_BIST);
  338   1          BMI088_delay_ms(BMI088_LONG_DELAY_TIME);
  339   1      
  340   1          do
  341   1          {
  342   2      
  343   2              BMI088_gyro_read_single_reg(BMI088_GYRO_SELF_TEST, res);
  344   2              BMI088_delay_us(BMI088_COM_WAIT_SENSOR_TIME);
  345   2              retry++;
  346   2          } while (!(res & BMI088_GYRO_BIST_RDY) && retry < 10);
  347   1      
  348   1          if (retry == 10)
  349   1          {
  350   2              return BMI088_SELF_TEST_GYRO_ERROR;
  351   2          }
  352   1      
  353   1          if (res & BMI088_GYRO_BIST_FAIL)
  354   1          {
  355   2              return BMI088_SELF_TEST_GYRO_ERROR;
  356   2          }
  357   1      
  358   1          return BMI088_NO_ERROR;
  359   1      }
  360          
  361          void BMI088_read_gyro_who_am_i(void)
  362          {
  363   1          uint8_t buf;
  364   1          BMI088_gyro_read_single_reg(BMI088_GYRO_CHIP_ID, buf);
  365   1      }
  366          
  367          
  368          void BMI088_read_accel_who_am_i(void)
  369          {
  370   1          volatile uint8_t buf;
  371   1          BMI088_accel_read_single_reg(BMI088_ACC_CHIP_ID, buf);
  372   1          buf = 0;
  373   1      
  374   1      }
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 7   

  375          
  376          
  377          
  378          
  379          
  380          void BMI088_temperature_read_over(uint8_t *rx_buf, float *temperate)
  381          {
  382   1          int16_t bmi088_raw_temp;
  383   1          bmi088_raw_temp = (int16_t)((rx_buf[0] << 3) | (rx_buf[1] >> 5));
  384   1      
  385   1          if (bmi088_raw_temp > 1023)
  386   1          {
  387   2              bmi088_raw_temp -= 2048;
  388   2          }
  389   1          *temperate = bmi088_raw_temp * BMI088_TEMP_FACTOR + BMI088_TEMP_OFFSET;
  390   1      
  391   1      }
  392          
  393          void BMI088_accel_read_over(uint8_t *rx_buf, float accel[3], float *time)
  394          {
  395   1          int16_t bmi088_raw_temp;
  396   1          uint32_t sensor_time;
  397   1          bmi088_raw_temp = (int16_t)((rx_buf[1]) << 8) | rx_buf[0];
  398   1          accel[0] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  399   1          bmi088_raw_temp = (int16_t)((rx_buf[3]) << 8) | rx_buf[2];
  400   1          accel[1] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  401   1          bmi088_raw_temp = (int16_t)((rx_buf[5]) << 8) | rx_buf[4];
  402   1          accel[2] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  403   1          sensor_time = (uint32_t)((rx_buf[8] << 16) | (rx_buf[7] << 8) | rx_buf[6]);
  404   1          *time = sensor_time * 39.0625f;
  405   1      
  406   1      }
  407          
  408          void BMI088_gyro_read_over(uint8_t *rx_buf, float gyro[3])
  409          {
  410   1          int16_t bmi088_raw_temp;
  411   1          bmi088_raw_temp = (int16_t)((rx_buf[1]) << 8) | rx_buf[0];
  412   1          gyro[0] = bmi088_raw_temp * BMI088_GYRO_SEN;
  413   1          bmi088_raw_temp = (int16_t)((rx_buf[3]) << 8) | rx_buf[2];
  414   1          gyro[1] = bmi088_raw_temp * BMI088_GYRO_SEN;
  415   1          bmi088_raw_temp = (int16_t)((rx_buf[5]) << 8) | rx_buf[4];
  416   1          gyro[2] = bmi088_raw_temp * BMI088_GYRO_SEN;
  417   1      }
  418          
  419          void BMI088_read(float gyro[3], float accel[3], float *temperate)
  420          {
  421   1          uint8_t buf[8] = {0, 0, 0, 0, 0, 0};
  422   1          int16_t bmi088_raw_temp;
  423   1      
  424   1          BMI088_accel_read_muli_reg(BMI088_ACCEL_XOUT_L, buf, 6);
  425   1      
  426   1          bmi088_raw_temp = (int16_t)((buf[1]) << 8) | buf[0];
  427   1          accel[0] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  428   1          bmi088_raw_temp = (int16_t)((buf[3]) << 8) | buf[2];
  429   1          accel[1] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  430   1          bmi088_raw_temp = (int16_t)((buf[5]) << 8) | buf[4];
  431   1          accel[2] = bmi088_raw_temp * BMI088_ACCEL_SEN;
  432   1      
  433   1          BMI088_gyro_read_muli_reg(BMI088_GYRO_CHIP_ID, buf, 8);
  434   1          if(buf[0] == BMI088_GYRO_CHIP_ID_VALUE)
  435   1          {
  436   2              bmi088_raw_temp = (int16_t)((buf[3]) << 8) | buf[2];
  437   2              gyro[0] = bmi088_raw_temp * BMI088_GYRO_SEN;
  438   2              bmi088_raw_temp = (int16_t)((buf[5]) << 8) | buf[4];
  439   2              gyro[1] = bmi088_raw_temp * BMI088_GYRO_SEN;
  440   2              bmi088_raw_temp = (int16_t)((buf[7]) << 8) | buf[6];
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 8   

  441   2              gyro[2] = bmi088_raw_temp * BMI088_GYRO_SEN;
  442   2          }
  443   1          BMI088_accel_read_muli_reg(BMI088_TEMP_M, buf, 2);
  444   1      
  445   1          bmi088_raw_temp = (int16_t)((buf[0] << 3) | (buf[1] >> 5));
  446   1      
  447   1          if (bmi088_raw_temp > 1023)
  448   1          {
  449   2              bmi088_raw_temp -= 2048;
  450   2          }
  451   1      
  452   1          *temperate = bmi088_raw_temp * BMI088_TEMP_FACTOR + BMI088_TEMP_OFFSET;
  453   1      }
  454          
  455          uint32_t get_BMI088_sensor_time(void)
  456          {
  457   1          uint32_t sensor_time = 0;
  458   1          uint8_t buf[3];
  459   1          BMI088_accel_read_muli_reg(BMI088_SENSORTIME_DATA_L, buf, 3);
  460   1      
  461   1          sensor_time = (uint32_t)((buf[2] << 16) | (buf[1] << 8) | (buf[0]));
  462   1      
  463   1          return sensor_time;
  464   1      }
  465          
  466          float get_BMI088_temperate(void)
  467          {
  468   1          uint8_t buf[2];
  469   1          float temperate;
  470   1          int16_t temperate_raw_temp;
  471   1      
  472   1          BMI088_accel_read_muli_reg(BMI088_TEMP_M, buf, 2);
  473   1      
  474   1          temperate_raw_temp = (int16_t)((buf[0] << 3) | (buf[1] >> 5));
  475   1      
  476   1          if (temperate_raw_temp > 1023)
  477   1          {
  478   2              temperate_raw_temp -= 2048;
  479   2          }
  480   1      
  481   1          temperate = temperate_raw_temp * BMI088_TEMP_FACTOR + BMI088_TEMP_OFFSET;
  482   1      
  483   1          return temperate;
  484   1      }
  485          
  486          void get_BMI088_gyro(int16_t gyro[3])
  487          {
  488   1          uint8_t buf[6] = {0, 0, 0, 0, 0, 0};
  489   1          int16_t gyro_raw_temp;
  490   1      
  491   1          BMI088_gyro_read_muli_reg(BMI088_GYRO_X_L, buf, 6);
  492   1      
  493   1          gyro_raw_temp = (int16_t)((buf[1]) << 8) | buf[0];
  494   1          gyro[0] = gyro_raw_temp ;
  495   1          gyro_raw_temp = (int16_t)((buf[3]) << 8) | buf[2];
  496   1          gyro[1] = gyro_raw_temp ;
  497   1          gyro_raw_temp = (int16_t)((buf[5]) << 8) | buf[4];
  498   1          gyro[2] = gyro_raw_temp ;
  499   1      }
  500          
  501          void get_BMI088_accel(float accel[3])
  502          {
  503   1          uint8_t buf[6] = {0, 0, 0, 0, 0, 0};
  504   1          int16_t accel_raw_temp;
  505   1      
  506   1          BMI088_accel_read_muli_reg(BMI088_ACCEL_XOUT_L, buf, 6);
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 9   

  507   1      
  508   1          accel_raw_temp = (int16_t)((buf[1]) << 8) | buf[0];
  509   1          accel[0] = accel_raw_temp * BMI088_ACCEL_SEN;
  510   1          accel_raw_temp = (int16_t)((buf[3]) << 8) | buf[2];
  511   1          accel[1] = accel_raw_temp * BMI088_ACCEL_SEN;
  512   1          accel_raw_temp = (int16_t)((buf[5]) << 8) | buf[4];
  513   1          accel[2] = accel_raw_temp * BMI088_ACCEL_SEN;
  514   1      }
  515          
  516          #if defined(BMI088_USE_SPI)
  517          
  518          static void BMI088_write_single_reg(uint8_t reg, uint8_t data_t)
  519          {
  520   1          BMI088_read_write_byte(reg);
  521   1          BMI088_read_write_byte(data_t);
  522   1      }
  523          
  524          static void BMI088_read_single_reg(uint8_t reg, uint8_t *return_data)
  525          {
  526   1          BMI088_read_write_byte(reg | 0x80);
  527   1          *return_data = BMI088_read_write_byte(0x55);
  528   1      }
  529          
  530          //static void BMI088_write_muli_reg(uint8_t reg, uint8_t* buf, uint8_t len )
  531          //{
  532          //    BMI088_read_write_byte( reg );
  533          //    while( len != 0 )
  534          //    {
  535          
  536          //        BMI088_read_write_byte( *buf );
  537          //        buf ++;
  538          //        len --;
  539          //    }
  540          
  541          //}
  542          
  543          static void BMI088_read_muli_reg(uint8_t reg, uint8_t *buf, uint8_t len)
  544          {
  545   1          BMI088_read_write_byte(reg | 0x80);
  546   1      
  547   1          while (len != 0)
  548   1          {
  549   2      
  550   2              *buf = BMI088_read_write_byte(0x55);
  551   2              buf++;
  552   2              len--;
  553   2          }
  554   1      }
  555          #elif defined(BMI088_USE_IIC)
               
               #endif
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 10  

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION BMI088_init? (BEGIN)
                                                ; SOURCE LINE # 88
000000 CAF8           PUSH     R15
                                                ; SOURCE LINE # 89
                                                ; SOURCE LINE # 90
;---- Variable 'error' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 92
000002 9A000000    E  ECALL    BMI088_GPIO_init?
                                                ; SOURCE LINE # 93
000006 9A000000    E  ECALL    BMI088_com_init?
                                                ; SOURCE LINE # 96
00000A 9A000000    R  ECALL    bmi088_accel_self_test?
00000E 6005           JZ       ?C0001
                                                ; SOURCE LINE # 98
000010 7EF080         MOV      R15,#080H
                                                ; SOURCE LINE # 99
000013 8006           SJMP     ?C0002
               ?C0001:
                                                ; SOURCE LINE # 102
000015 9A000000    R  ECALL    bmi088_accel_init?
000019 7CFB           MOV      R15,R11          ; A=R11
                                                ; SOURCE LINE # 103
               ?C0002:
                                                ; SOURCE LINE # 105
00001B 9A000000    R  ECALL    bmi088_gyro_self_test?
00001F 6005           JZ       ?C0003
                                                ; SOURCE LINE # 107
000021 4EF040         ORL      R15,#040H
                                                ; SOURCE LINE # 108
000024 8006           SJMP     ?C0004
               ?C0003:
                                                ; SOURCE LINE # 111
000026 9A000000    R  ECALL    bmi088_gyro_init?
00002A 4CFB           ORL      R15,R11          ; A=R11
                                                ; SOURCE LINE # 112
               ?C0004:
                                                ; SOURCE LINE # 114
00002C 7CBF           MOV      R11,R15          ; A=R11
                                                ; SOURCE LINE # 115
00002E DAF8           POP      R15
000030 AA             ERET     
;       FUNCTION BMI088_init? (END)

;       FUNCTION bmi088_accel_init? (BEGIN)
                                                ; SOURCE LINE # 117
000031 CAF8           PUSH     R15
                                                ; SOURCE LINE # 118
                                                ; SOURCE LINE # 119
000033 E4             CLR      A                ; A=R11
000034 7AB30000    R  MOV      res,R11          ; A=R11
                                                ; SOURCE LINE # 120
;---- Variable 'write_reg_num' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 123
000038 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00003C 7480           MOV      A,#080H          ; A=R11
00003E 9A000000    E  ECALL    BMI088_read_write_byte?
000042 7455           MOV      A,#055H          ; A=R11
000044 9A000000    E  ECALL    BMI088_read_write_byte?
000048 7455           MOV      A,#055H          ; A=R11
00004A 9A000000    E  ECALL    BMI088_read_write_byte?
00004E 7AB30000    R  MOV      res,R11          ; A=R11
000052 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 124
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 11  

000056 7E3400C8       MOV      WR6,#0C8H
00005A 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 125
00005E 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000062 7480           MOV      A,#080H          ; A=R11
000064 9A000000    E  ECALL    BMI088_read_write_byte?
000068 7455           MOV      A,#055H          ; A=R11
00006A 9A000000    E  ECALL    BMI088_read_write_byte?
00006E 7455           MOV      A,#055H          ; A=R11
000070 9A000000    E  ECALL    BMI088_read_write_byte?
000074 7AB30000    R  MOV      res,R11          ; A=R11
000078 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 126
00007C 7E3400C8       MOV      WR6,#0C8H
000080 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 129
000084 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000088 747E           MOV      A,#07EH          ; A=R11
00008A 7E70B6         MOV      R7,#0B6H
00008D 120000      R  LCALL    BMI088_write_single_reg
000090 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 130
000094 7E340050       MOV      WR6,#050H
000098 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 133
00009C 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0000A0 7480           MOV      A,#080H          ; A=R11
0000A2 9A000000    E  ECALL    BMI088_read_write_byte?
0000A6 7455           MOV      A,#055H          ; A=R11
0000A8 9A000000    E  ECALL    BMI088_read_write_byte?
0000AC 7455           MOV      A,#055H          ; A=R11
0000AE 9A000000    E  ECALL    BMI088_read_write_byte?
0000B2 7AB30000    R  MOV      res,R11          ; A=R11
0000B6 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 134
0000BA 7E3400C8       MOV      WR6,#0C8H
0000BE 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 135
0000C2 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0000C6 7480           MOV      A,#080H          ; A=R11
0000C8 9A000000    E  ECALL    BMI088_read_write_byte?
0000CC 7455           MOV      A,#055H          ; A=R11
0000CE 9A000000    E  ECALL    BMI088_read_write_byte?
0000D2 7455           MOV      A,#055H          ; A=R11
0000D4 9A000000    E  ECALL    BMI088_read_write_byte?
0000D8 7AB30000    R  MOV      res,R11          ; A=R11
0000DC 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 136
0000E0 7E3400C8       MOV      WR6,#0C8H
0000E4 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 139
0000E8 7EB30000    R  MOV      R11,res          ; A=R11
0000EC BEB01E         CMP      R11,#01EH        ; A=R11
0000EF 6804           JE       ?C0012
                                                ; SOURCE LINE # 141
0000F1 74FF           MOV      A,#0FFH          ; A=R11
0000F3 806C           SJMP     ?C0007
                                                ; SOURCE LINE # 142
                                                ; SOURCE LINE # 145
               ?C0012:
0000F5 6CFF           XRL      R15,R15
               ?C0011:
                                                ; SOURCE LINE # 148
0000F7 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0000FB 7E7003         MOV      R7,#03H
0000FE AC7F           MUL      R7,R15
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 12  

000100 09B30000    R  MOV      R11,@WR6+write_BMI088_accel_reg_data_error
000104 09730000    R  MOV      R7,@WR6+write_BMI088_accel_reg_data_error+0x1
000108 120000      R  LCALL    BMI088_write_single_reg
00010B 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 149
00010F 7E3400C8       MOV      WR6,#0C8H
000113 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 151
000117 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00011B 7403           MOV      A,#03H           ; A=R11
00011D ACBF           MUL      R11,R15          ; A=R11
00011F 09B50000    R  MOV      R11,@WR10+write_BMI088_accel_reg_data_error
000123 4480           ORL      A,#080H          ; A=R11
000125 9A000000    E  ECALL    BMI088_read_write_byte?
000129 7455           MOV      A,#055H          ; A=R11
00012B 9A000000    E  ECALL    BMI088_read_write_byte?
00012F 7455           MOV      A,#055H          ; A=R11
000131 9A000000    E  ECALL    BMI088_read_write_byte?
000135 7AB30000    R  MOV      res,R11          ; A=R11
000139 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 152
00013D 7E3400C8       MOV      WR6,#0C8H
000141 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 154
000145 7403           MOV      A,#03H           ; A=R11
000147 ACBF           MUL      R11,R15          ; A=R11
000149 09750000    R  MOV      R7,@WR10+write_BMI088_accel_reg_data_error+0x1
00014D BE730000    R  CMP      R7,res
000151 6806           JE       ?C0008
                                                ; SOURCE LINE # 156
000153 09B50000    R  MOV      R11,@WR10+write_BMI088_accel_reg_data_error+0x2
000157 8008           SJMP     ?C0007
                                                ; SOURCE LINE # 157
               ?C0008:
000159 0BF0           INC      R15,#01H
00015B BEF006         CMP      R15,#06H
00015E 4097           JC       ?C0011
                                                ; SOURCE LINE # 159
000160 E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 160
               ?C0007:
000161 DAF8           POP      R15
000163 AA             ERET     
;       FUNCTION bmi088_accel_init? (END)

;       FUNCTION bmi088_gyro_init? (BEGIN)
                                                ; SOURCE LINE # 162
000164 CAF8           PUSH     R15
                                                ; SOURCE LINE # 163
                                                ; SOURCE LINE # 164
;---- Variable 'write_reg_num' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 165
000166 E4             CLR      A                ; A=R11
000167 7AB30000    R  MOV      res,R11          ; A=R11
                                                ; SOURCE LINE # 168
00016B 9A000000    E  ECALL    BMI088_GYRO_NS_L?
00016F E4             CLR      A                ; A=R11
000170 7E000000    R  MOV      DR0,#WORD0 res
000174 120000      R  LCALL    BMI088_read_single_reg
000177 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 169
00017B 7E3400C8       MOV      WR6,#0C8H
00017F 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 170
000183 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000187 E4             CLR      A                ; A=R11
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 13  

000188 7E000000    R  MOV      DR0,#WORD0 res
00018C 120000      R  LCALL    BMI088_read_single_reg
00018F 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 171
000193 7E3400C8       MOV      WR6,#0C8H
000197 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 174
00019B 9A000000    E  ECALL    BMI088_GYRO_NS_L?
00019F 7414           MOV      A,#014H          ; A=R11
0001A1 7E70B6         MOV      R7,#0B6H
0001A4 120000      R  LCALL    BMI088_write_single_reg
0001A7 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 175
0001AB 7E340050       MOV      WR6,#050H
0001AF 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 177
0001B3 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0001B7 E4             CLR      A                ; A=R11
0001B8 7E000000    R  MOV      DR0,#WORD0 res
0001BC 120000      R  LCALL    BMI088_read_single_reg
0001BF 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 178
0001C3 7E3400C8       MOV      WR6,#0C8H
0001C7 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 179
0001CB 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0001CF E4             CLR      A                ; A=R11
0001D0 7E000000    R  MOV      DR0,#WORD0 res
0001D4 120000      R  LCALL    BMI088_read_single_reg
0001D7 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 180
0001DB 7E3400C8       MOV      WR6,#0C8H
0001DF 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 183
0001E3 7EB30000    R  MOV      R11,res          ; A=R11
0001E7 BEB00F         CMP      R11,#0FH         ; A=R11
0001EA 6804           JE       ?C0020
                                                ; SOURCE LINE # 185
0001EC 74FF           MOV      A,#0FFH          ; A=R11
0001EE 805D           SJMP     ?C0015
                                                ; SOURCE LINE # 186
                                                ; SOURCE LINE # 189
               ?C0020:
0001F0 6CFF           XRL      R15,R15
               ?C0019:
                                                ; SOURCE LINE # 192
0001F2 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0001F6 7E7003         MOV      R7,#03H
0001F9 AC7F           MUL      R7,R15
0001FB 09B30000    R  MOV      R11,@WR6+write_BMI088_gyro_reg_data_error
0001FF 09730000    R  MOV      R7,@WR6+write_BMI088_gyro_reg_data_error+0x1
000203 120000      R  LCALL    BMI088_write_single_reg
000206 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 193
00020A 7E3400C8       MOV      WR6,#0C8H
00020E 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 195
000212 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000216 7403           MOV      A,#03H           ; A=R11
000218 ACBF           MUL      R11,R15          ; A=R11
00021A 09B50000    R  MOV      R11,@WR10+write_BMI088_gyro_reg_data_error
00021E 7E000000    R  MOV      DR0,#WORD0 res
000222 120000      R  LCALL    BMI088_read_single_reg
000225 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 196
000229 7E3400C8       MOV      WR6,#0C8H
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 14  

00022D 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 198
000231 7403           MOV      A,#03H           ; A=R11
000233 ACBF           MUL      R11,R15          ; A=R11
000235 09750000    R  MOV      R7,@WR10+write_BMI088_gyro_reg_data_error+0x1
000239 BE730000    R  CMP      R7,res
00023D 6806           JE       ?C0016
                                                ; SOURCE LINE # 200
00023F 09B50000    R  MOV      R11,@WR10+write_BMI088_gyro_reg_data_error+0x2
000243 8008           SJMP     ?C0015
                                                ; SOURCE LINE # 201
               ?C0016:
000245 0BF0           INC      R15,#01H
000247 BEF006         CMP      R15,#06H
00024A 40A6           JC       ?C0019
                                                ; SOURCE LINE # 204
00024C E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 205
               ?C0015:
00024D DAF8           POP      R15
00024F AA             ERET     
;       FUNCTION bmi088_gyro_init? (END)

;       FUNCTION bmi088_accel_self_test? (BEGIN)
                                                ; SOURCE LINE # 207
000250 CAF8           PUSH     R15
                                                ; SOURCE LINE # 208
                                                ; SOURCE LINE # 212
000252 7E540000    R  MOV      WR10,#WORD0 ?tpl?0001
000256 7E440000    R  MOV      WR8,#WORD2 ?tpl?0001
00025A 69320004       MOV      WR6,@DR8+0x4
00025E 69220002       MOV      WR4,@DR8+0x2
000262 0B2A10         MOV      WR2,@DR8
000265 7A1F0000    R  MOV      buf+2,DR4
000269 7A170000    R  MOV      buf,WR2
                                                ; SOURCE LINE # 213
00026D E4             CLR      A                ; A=R11
00026E 7AB30000    R  MOV      res,R11          ; A=R11
                                                ; SOURCE LINE # 215
;---- Variable 'write_reg_num' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 229
000272 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000276 7480           MOV      A,#080H          ; A=R11
000278 9A000000    E  ECALL    BMI088_read_write_byte?
00027C 7455           MOV      A,#055H          ; A=R11
00027E 9A000000    E  ECALL    BMI088_read_write_byte?
000282 7455           MOV      A,#055H          ; A=R11
000284 9A000000    E  ECALL    BMI088_read_write_byte?
000288 7AB30000    R  MOV      res,R11          ; A=R11
00028C 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 230
000290 7E3400C8       MOV      WR6,#0C8H
000294 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 231
000298 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00029C 7480           MOV      A,#080H          ; A=R11
00029E 9A000000    E  ECALL    BMI088_read_write_byte?
0002A2 7455           MOV      A,#055H          ; A=R11
0002A4 9A000000    E  ECALL    BMI088_read_write_byte?
0002A8 7455           MOV      A,#055H          ; A=R11
0002AA 9A000000    E  ECALL    BMI088_read_write_byte?
0002AE 7AB30000    R  MOV      res,R11          ; A=R11
0002B2 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 232
0002B6 7E3400C8       MOV      WR6,#0C8H
0002BA 9A000000    E  ECALL    BMI088_delay_us?
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 15  

                                                ; SOURCE LINE # 235
0002BE 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0002C2 747E           MOV      A,#07EH          ; A=R11
0002C4 7E70B6         MOV      R7,#0B6H
0002C7 120000      R  LCALL    BMI088_write_single_reg
0002CA 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 236
0002CE 7E340050       MOV      WR6,#050H
0002D2 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 239
0002D6 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0002DA 7480           MOV      A,#080H          ; A=R11
0002DC 9A000000    E  ECALL    BMI088_read_write_byte?
0002E0 7455           MOV      A,#055H          ; A=R11
0002E2 9A000000    E  ECALL    BMI088_read_write_byte?
0002E6 7455           MOV      A,#055H          ; A=R11
0002E8 9A000000    E  ECALL    BMI088_read_write_byte?
0002EC 7AB30000    R  MOV      res,R11          ; A=R11
0002F0 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 240
0002F4 7E3400C8       MOV      WR6,#0C8H
0002F8 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 241
0002FC 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000300 7480           MOV      A,#080H          ; A=R11
000302 9A000000    E  ECALL    BMI088_read_write_byte?
000306 7455           MOV      A,#055H          ; A=R11
000308 9A000000    E  ECALL    BMI088_read_write_byte?
00030C 7455           MOV      A,#055H          ; A=R11
00030E 9A000000    E  ECALL    BMI088_read_write_byte?
000312 7AB30000    R  MOV      res,R11          ; A=R11
000316 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 242
00031A 7E3400C8       MOV      WR6,#0C8H
00031E 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 244
000322 7EB30000    R  MOV      R11,res          ; A=R11
000326 BEB01E         CMP      R11,#01EH        ; A=R11
000329 6805           JE       ?C0028
                                                ; SOURCE LINE # 246
00032B 74FF           MOV      A,#0FFH          ; A=R11
00032D 020000      R  LJMP     ?C0023
                                                ; SOURCE LINE # 247
                                                ; SOURCE LINE # 250
               ?C0028:
000330 6CFF           XRL      R15,R15
               ?C0027:
                                                ; SOURCE LINE # 253
000332 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000336 0A3F           MOVZ     WR6,R15
000338 6D22           XRL      WR4,WR4
00033A 7E140003       MOV      WR2,#03H
00033E 9A000000    E  ECALL    ?C?LIMUL?
000342 7F01           MOV      DR0,DR4
000344 2E040000    R  ADD      WR0,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error
000348 2E080000    R  ADD      DR0,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error
00034C 7E0BB0         MOV      R11,@DR0         ; A=R11
00034F 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+1
000353 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+1
000357 7E1B70         MOV      R7,@DR4
00035A 120000      R  LCALL    BMI088_write_single_reg
00035D 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 254
000361 7E3400C8       MOV      WR6,#0C8H
000365 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 256
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 16  

000369 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00036D 0A3F           MOVZ     WR6,R15
00036F 6D22           XRL      WR4,WR4
000371 7E140003       MOV      WR2,#03H
000375 9A000000    E  ECALL    ?C?LIMUL?
000379 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error
00037D 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error
000381 7E1BB0         MOV      R11,@DR4         ; A=R11
000384 4480           ORL      A,#080H          ; A=R11
000386 9A000000    E  ECALL    BMI088_read_write_byte?
00038A 7455           MOV      A,#055H          ; A=R11
00038C 9A000000    E  ECALL    BMI088_read_write_byte?
000390 7455           MOV      A,#055H          ; A=R11
000392 9A000000    E  ECALL    BMI088_read_write_byte?
000396 7AB30000    R  MOV      res,R11          ; A=R11
00039A 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 257
00039E 7E3400C8       MOV      WR6,#0C8H
0003A2 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 259
0003A6 0A3F           MOVZ     WR6,R15
0003A8 6D22           XRL      WR4,WR4
0003AA 7E140003       MOV      WR2,#03H
0003AE 9A000000    E  ECALL    ?C?LIMUL?
0003B2 7F01           MOV      DR0,DR4
0003B4 2E040000    R  ADD      WR0,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+1
0003B8 2E080000    R  ADD      DR0,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+1
0003BC 7E0B30         MOV      R3,@DR0
0003BF BE330000    R  CMP      R3,res
0003C3 680B           JE       ?C0029
                                                ; SOURCE LINE # 261
0003C5 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+2
0003C9 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+2
0003CD 020000      R  LJMP     ?C0057
                                                ; SOURCE LINE # 262
               ?C0029:
                                                ; SOURCE LINE # 264
0003D0 7E340050       MOV      WR6,#050H
0003D4 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 265
0003D8 0BF0           INC      R15,#01H
0003DA BEF004         CMP      R15,#04H
0003DD 5003        R  JNC      $ + 5H
0003DF 020000      R  LJMP     ?C0027
                                                ; SOURCE LINE # 268
0003E2 6CFF           XRL      R15,R15
               ?C0033:
                                                ; SOURCE LINE # 271
0003E4 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0003E8 0A3F           MOVZ     WR6,R15
0003EA 6D22           XRL      WR4,WR4
0003EC 7E140003       MOV      WR2,#03H
0003F0 9A000000    E  ECALL    ?C?LIMUL?
0003F4 7F01           MOV      DR0,DR4
0003F6 2E040000    R  ADD      WR0,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+12
0003FA 2E080000    R  ADD      DR0,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+12
0003FE 7E0BB0         MOV      R11,@DR0         ; A=R11
000401 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+13
000405 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+13
000409 7E1B70         MOV      R7,@DR4
00040C 120000      R  LCALL    BMI088_write_single_reg
00040F 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 272
000413 7E3400C8       MOV      WR6,#0C8H
000417 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 274
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 17  

00041B 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00041F 0A3F           MOVZ     WR6,R15
000421 6D22           XRL      WR4,WR4
000423 7E140003       MOV      WR2,#03H
000427 9A000000    E  ECALL    ?C?LIMUL?
00042B 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+12
00042F 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+12
000433 7E1BB0         MOV      R11,@DR4         ; A=R11
000436 4480           ORL      A,#080H          ; A=R11
000438 9A000000    E  ECALL    BMI088_read_write_byte?
00043C 7455           MOV      A,#055H          ; A=R11
00043E 9A000000    E  ECALL    BMI088_read_write_byte?
000442 7455           MOV      A,#055H          ; A=R11
000444 9A000000    E  ECALL    BMI088_read_write_byte?
000448 7AB30000    R  MOV      res,R11          ; A=R11
00044C 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 275
000450 7E3400C8       MOV      WR6,#0C8H
000454 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 277
000458 0A3F           MOVZ     WR6,R15
00045A 6D22           XRL      WR4,WR4
00045C 7E140003       MOV      WR2,#03H
000460 9A000000    E  ECALL    ?C?LIMUL?
000464 7F01           MOV      DR0,DR4
000466 2E040000    R  ADD      WR0,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+13
00046A 2E080000    R  ADD      DR0,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+13
00046E 7E0B30         MOV      R3,@DR0
000471 BE330000    R  CMP      R3,res
000475 680E           JE       ?C0035
                                                ; SOURCE LINE # 279
000477 2E240000    R  ADD      WR4,#WORD2 write_BMI088_ACCEL_self_test_Reg_Data_Error+14
00047B 2E180000    R  ADD      DR4,#WORD0 write_BMI088_ACCEL_self_test_Reg_Data_Error+14
               ?C0057:
00047F 7E1BB0         MOV      R11,@DR4         ; A=R11
000482 020000      R  LJMP     ?C0023
                                                ; SOURCE LINE # 280
               ?C0035:
                                                ; SOURCE LINE # 282
000485 7E340050       MOV      WR6,#050H
000489 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 285
00048D 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000491 7492           MOV      A,#092H          ; A=R11
000493 9A000000    E  ECALL    BMI088_read_write_byte?
000497 7412           MOV      A,#012H          ; A=R11
000499 7E000000    R  MOV      DR0,#WORD0 buf
00049D 7E7006         MOV      R7,#06H
0004A0 120000      R  LCALL    BMI088_read_muli_reg
0004A3 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 287
0004A7 7E730000    R  MOV      R7,buf+1
0004AB 7CA7           MOV      R10,R7
0004AD E4             CLR      A                ; A=R11
0004AE 7E730000    R  MOV      R7,buf
0004B2 0A47           MOVZ     WR8,R7
0004B4 4D45           ORL      WR8,WR10
0004B6 7406           MOV      A,#06H           ; A=R11
0004B8 ACBF           MUL      R11,R15          ; A=R11
0004BA 59450000    R  MOV      @WR10+self_test_accel,WR8
                                                ; SOURCE LINE # 288
0004BE 7E630000    R  MOV      R6,buf+3
0004C2 6C77           XRL      R7,R7
0004C4 7E530000    R  MOV      R5,buf+2
0004C8 0A45           MOVZ     WR8,R5
0004CA 4D43           ORL      WR8,WR6
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 18  

0004CC 59450000    R  MOV      @WR10+self_test_accel+0x2,WR8
                                                ; SOURCE LINE # 289
0004D0 7E730000    R  MOV      R7,buf+5
0004D4 7C47           MOV      R4,R7
0004D6 7E730000    R  MOV      R7,buf+4
0004DA 7C64           MOV      R6,R4
0004DC 59350000    R  MOV      @WR10+self_test_accel+0x4,WR6
                                                ; SOURCE LINE # 290
0004E0 0BF0           INC      R15,#01H
0004E2 BEF002         CMP      R15,#02H
0004E5 5003        R  JNC      $ + 5H
0004E7 020000      R  LJMP     ?C0033
                                                ; SOURCE LINE # 293
0004EA 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0004EE 746D           MOV      A,#06DH          ; A=R11
0004F0 6C77           XRL      R7,R7
0004F2 120000      R  LCALL    BMI088_write_single_reg
0004F5 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 294
0004F9 7E3400C8       MOV      WR6,#0C8H
0004FD 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 295
000501 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000505 74ED           MOV      A,#0EDH          ; A=R11
000507 9A000000    E  ECALL    BMI088_read_write_byte?
00050B 7455           MOV      A,#055H          ; A=R11
00050D 9A000000    E  ECALL    BMI088_read_write_byte?
000511 7455           MOV      A,#055H          ; A=R11
000513 9A000000    E  ECALL    BMI088_read_write_byte?
000517 7AB30000    R  MOV      res,R11          ; A=R11
00051B 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 296
00051F 7E3400C8       MOV      WR6,#0C8H
000523 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 298
000527 7EB30000    R  MOV      R11,res          ; A=R11
00052B 6005           JZ       ?C0036
                                                ; SOURCE LINE # 300
00052D 7404           MOV      A,#04H           ; A=R11
00052F 020000      R  LJMP     ?C0023
                                                ; SOURCE LINE # 301
               ?C0036:
                                                ; SOURCE LINE # 304
000532 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000536 747E           MOV      A,#07EH          ; A=R11
000538 7E70B6         MOV      R7,#0B6H
00053B 120000      R  LCALL    BMI088_write_single_reg
00053E 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 305
000542 7E340050       MOV      WR6,#050H
000546 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 307
00054A 7E370000    R  MOV      WR6,self_test_accel
00054E 9E370000    R  SUB      WR6,self_test_accel+6
000552 BE340555       CMP      WR6,#0555H
000556 481C           JSL      ?C0038
000558 7E370000    R  MOV      WR6,self_test_accel+2
00055C 9E370000    R  SUB      WR6,self_test_accel+8
000560 BE340555       CMP      WR6,#0555H
000564 480E           JSL      ?C0038
000566 7E370000    R  MOV      WR6,self_test_accel+4
00056A 9E370000    R  SUB      WR6,self_test_accel+10
00056E BE3402A8       CMP      WR6,#02A8H
000572 5804           JSGE     ?C0037
               ?C0038:
                                                ; SOURCE LINE # 309
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 19  

000574 7480           MOV      A,#080H          ; A=R11
000576 804D           SJMP     ?C0023
                                                ; SOURCE LINE # 310
               ?C0037:
                                                ; SOURCE LINE # 312
000578 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
00057C 7480           MOV      A,#080H          ; A=R11
00057E 9A000000    E  ECALL    BMI088_read_write_byte?
000582 7455           MOV      A,#055H          ; A=R11
000584 9A000000    E  ECALL    BMI088_read_write_byte?
000588 7455           MOV      A,#055H          ; A=R11
00058A 9A000000    E  ECALL    BMI088_read_write_byte?
00058E 7AB30000    R  MOV      res,R11          ; A=R11
000592 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 313
000596 7E3400C8       MOV      WR6,#0C8H
00059A 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 314
00059E 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0005A2 7480           MOV      A,#080H          ; A=R11
0005A4 9A000000    E  ECALL    BMI088_read_write_byte?
0005A8 7455           MOV      A,#055H          ; A=R11
0005AA 9A000000    E  ECALL    BMI088_read_write_byte?
0005AE 7455           MOV      A,#055H          ; A=R11
0005B0 9A000000    E  ECALL    BMI088_read_write_byte?
0005B4 7AB30000    R  MOV      res,R11          ; A=R11
0005B8 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 315
0005BC 7E3400C8       MOV      WR6,#0C8H
0005C0 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 317
0005C4 E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 318
               ?C0023:
0005C5 DAF8           POP      R15
0005C7 AA             ERET     
;       FUNCTION bmi088_accel_self_test? (END)

;       FUNCTION bmi088_gyro_self_test? (BEGIN)
                                                ; SOURCE LINE # 319
0005C8 CAF8           PUSH     R15
                                                ; SOURCE LINE # 320
                                                ; SOURCE LINE # 321
0005CA E4             CLR      A                ; A=R11
0005CB 7AB30000    R  MOV      res,R11          ; A=R11
                                                ; SOURCE LINE # 322
0005CF 6CFF           XRL      R15,R15
;---- Variable 'retry' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 324
0005D1 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0005D5 E4             CLR      A                ; A=R11
0005D6 7E000000    R  MOV      DR0,#WORD0 res
0005DA 120000      R  LCALL    BMI088_read_single_reg
0005DD 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 325
0005E1 7E3400C8       MOV      WR6,#0C8H
0005E5 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 326
0005E9 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0005ED E4             CLR      A                ; A=R11
0005EE 7E000000    R  MOV      DR0,#WORD0 res
0005F2 120000      R  LCALL    BMI088_read_single_reg
0005F5 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 327
0005F9 7E3400C8       MOV      WR6,#0C8H
0005FD 9A000000    E  ECALL    BMI088_delay_us?
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 20  

                                                ; SOURCE LINE # 329
000601 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000605 7414           MOV      A,#014H          ; A=R11
000607 7E70B6         MOV      R7,#0B6H
00060A 120000      R  LCALL    BMI088_write_single_reg
00060D 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 330
000611 7E340050       MOV      WR6,#050H
000615 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 332
000619 9A000000    E  ECALL    BMI088_GYRO_NS_L?
00061D E4             CLR      A                ; A=R11
00061E 7E000000    R  MOV      DR0,#WORD0 res
000622 120000      R  LCALL    BMI088_read_single_reg
000625 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 333
000629 7E3400C8       MOV      WR6,#0C8H
00062D 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 334
000631 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000635 E4             CLR      A                ; A=R11
000636 7E000000    R  MOV      DR0,#WORD0 res
00063A 120000      R  LCALL    BMI088_read_single_reg
00063D 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 335
000641 7E3400C8       MOV      WR6,#0C8H
000645 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 337
000649 9A000000    E  ECALL    BMI088_GYRO_NS_L?
00064D 743C           MOV      A,#03CH          ; A=R11
00064F 7E7001         MOV      R7,#01H
000652 120000      R  LCALL    BMI088_write_single_reg
000655 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 338
000659 7E340050       MOV      WR6,#050H
00065D 9A000000    E  ECALL    BMI088_delay_ms?
                                                ; SOURCE LINE # 340
               ?C0039:
                                                ; SOURCE LINE # 343
000661 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000665 743C           MOV      A,#03CH          ; A=R11
000667 7E000000    R  MOV      DR0,#WORD0 res
00066B 120000      R  LCALL    BMI088_read_single_reg
00066E 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 344
000672 7E3400C8       MOV      WR6,#0C8H
000676 9A000000    E  ECALL    BMI088_delay_us?
                                                ; SOURCE LINE # 345
00067A 0BF0           INC      R15,#01H
                                                ; SOURCE LINE # 346
00067C 7E730000    R  MOV      R7,res
000680 0A37           MOVZ     WR6,R7
000682 7D23           MOV      WR4,WR6
000684 5E240002       ANL      WR4,#02H
000688 7805           JNE      ?C0042
00068A BEF00A         CMP      R15,#0AH
00068D 40D2           JC       ?C0039
               ?C0042:
                                                ; SOURCE LINE # 348
00068F BEF00A         CMP      R15,#0AH
000692 7804           JNE      ?C0044
                                                ; SOURCE LINE # 350
000694 7440           MOV      A,#040H          ; A=R11
000696 800B           SJMP     ?C0045
                                                ; SOURCE LINE # 351
               ?C0044:
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 21  

                                                ; SOURCE LINE # 353
000698 5E340004       ANL      WR6,#04H
00069C 6804           JE       ?C0046
                                                ; SOURCE LINE # 355
00069E 7440           MOV      A,#040H          ; A=R11
0006A0 8001           SJMP     ?C0045
                                                ; SOURCE LINE # 356
               ?C0046:
                                                ; SOURCE LINE # 358
0006A2 E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 359
               ?C0045:
0006A3 DAF8           POP      R15
0006A5 AA             ERET     
;       FUNCTION bmi088_gyro_self_test? (END)

;       FUNCTION BMI088_read_gyro_who_am_i? (BEGIN)
                                                ; SOURCE LINE # 361
                                                ; SOURCE LINE # 362
                                                ; SOURCE LINE # 364
0006A6 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0006AA E4             CLR      A                ; A=R11
0006AB 7E000000    R  MOV      DR0,#WORD0 buf
0006AF 120000      R  LCALL    BMI088_read_single_reg
0006B2 8A000000    E  EJMP     BMI088_GYRO_NS_H?
;       FUNCTION BMI088_read_gyro_who_am_i? (END)

;       FUNCTION BMI088_read_accel_who_am_i? (BEGIN)
                                                ; SOURCE LINE # 368
                                                ; SOURCE LINE # 369
                                                ; SOURCE LINE # 371
0006B6 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0006BA 7480           MOV      A,#080H          ; A=R11
0006BC 9A000000    E  ECALL    BMI088_read_write_byte?
0006C0 7455           MOV      A,#055H          ; A=R11
0006C2 9A000000    E  ECALL    BMI088_read_write_byte?
0006C6 7455           MOV      A,#055H          ; A=R11
0006C8 9A000000    E  ECALL    BMI088_read_write_byte?
0006CC 7AB30000    R  MOV      buf,R11          ; A=R11
0006D0 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 372
0006D4 E4             CLR      A                ; A=R11
0006D5 7AB30000    R  MOV      buf,R11          ; A=R11
                                                ; SOURCE LINE # 374
0006D9 AA             ERET     
;       FUNCTION BMI088_read_accel_who_am_i? (END)

;       FUNCTION BMI088_temperature_read_over? (BEGIN)
                                                ; SOURCE LINE # 380
0006DA 7F71           MOV      DR28,DR4
;---- Variable 'temperate' assigned to Register 'DR28' ----
0006DC 7F20           MOV      DR8,DR0
;---- Variable 'rx_buf' assigned to Register 'DR8' ----
                                                ; SOURCE LINE # 381
                                                ; SOURCE LINE # 383
0006DE 7E2B70         MOV      R7,@DR8
0006E1 0A37           MOVZ     WR6,R7
0006E3 3E34           SLL      WR6
0006E5 3E34           SLL      WR6
0006E7 3E34           SLL      WR6
0006E9 29B20001       MOV      R11,@DR8+0x1     ; A=R11
0006ED C4             SWAP     A                ; A=R11
0006EE 03             RR       A                ; A=R11
0006EF 5407           ANL      A,#07H           ; A=R11
0006F1 0A2B           MOVZ     WR4,R11          ; A=R11
0006F3 4D23           ORL      WR4,WR6
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 22  

;---- Variable 'bmi088_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 385
0006F5 BE2403FF       CMP      WR4,#03FFH
0006F9 0804           JSLE     ?C0047
                                                ; SOURCE LINE # 387
0006FB 9E240800       SUB      WR4,#0800H
                                                ; SOURCE LINE # 388
               ?C0047:
                                                ; SOURCE LINE # 389
0006FF 7CB4           MOV      R11,R4           ; A=R11
000701 9A000000    E  ECALL    ?C?FCASTI?
000705 6D11           XRL      WR2,WR2
000707 7E043E00       MOV      WR0,#03E00H
00070B 9A000000    E  ECALL    ?C?FPMUL?
00070F 6D11           XRL      WR2,WR2
000711 7E0441B8       MOV      WR0,#041B8H
000715 9A000000    E  ECALL    ?C?FPADD?
000719 79370002       MOV      @DR28+0x2,WR6
00071D 1B7A20         MOV      @DR28,WR4
                                                ; SOURCE LINE # 391
000720 AA             ERET     
;       FUNCTION BMI088_temperature_read_over? (END)

;       FUNCTION BMI088_accel_read_over? (BEGIN)
                                                ; SOURCE LINE # 393
000721 7F61           MOV      DR24,DR4
;---- Variable 'accel' assigned to Register 'DR24' ----
000723 7F70           MOV      DR28,DR0
;---- Variable 'rx_buf' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 394
                                                ; SOURCE LINE # 397
000725 29670001       MOV      R6,@DR28+0x1
000729 7E7B50         MOV      R5,@DR28
00072C 7C46           MOV      R4,R6
;---- Variable 'bmi088_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 398
00072E 7CB6           MOV      R11,R6           ; A=R11
000730 9A000000    E  ECALL    ?C?FCASTI?
000734 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000738 9A000000    E  ECALL    ?C?FPMUL?
00073C 79360002       MOV      @DR24+0x2,WR6
000740 1B6A20         MOV      @DR24,WR4
                                                ; SOURCE LINE # 399
000743 29670003       MOV      R6,@DR28+0x3
000747 29570002       MOV      R5,@DR28+0x2
00074B 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 400
00074D 7CB6           MOV      R11,R6           ; A=R11
00074F 9A000000    E  ECALL    ?C?FCASTI?
000753 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000757 9A000000    E  ECALL    ?C?FPMUL?
00075B 79360006       MOV      @DR24+0x6,WR6
00075F 79260004       MOV      @DR24+0x4,WR4
                                                ; SOURCE LINE # 401
000763 29670005       MOV      R6,@DR28+0x5
000767 29570004       MOV      R5,@DR28+0x4
00076B 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 402
00076D 7CB6           MOV      R11,R6           ; A=R11
00076F 9A000000    E  ECALL    ?C?FCASTI?
000773 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000777 9A000000    E  ECALL    ?C?FPMUL?
00077B 7936000A       MOV      @DR24+0xA,WR6
00077F 79260008       MOV      @DR24+0x8,WR4
                                                ; SOURCE LINE # 403
000783 29670007       MOV      R6,@DR28+0x7
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 23  

000787 6C77           XRL      R7,R7
000789 29570008       MOV      R5,@DR28+0x8
00078D 0A25           MOVZ     WR4,R5
00078F 29770006       MOV      R7,@DR28+0x6
000793 6D22           XRL      WR4,WR4
;---- Variable 'sensor_time' assigned to Register 'DR4' ----
                                                ; SOURCE LINE # 404
000795 E4             CLR      A                ; A=R11
000796 9A000000    E  ECALL    ?C?FCASTL?
00079A 7E144000       MOV      WR2,#04000H
00079E 7E04421C       MOV      WR0,#0421CH
0007A2 9A000000    E  ECALL    ?C?FPMUL?
0007A6 7F01           MOV      DR0,DR4
0007A8 7E1F0000    R  MOV      DR4,time
0007AC 79110002       MOV      @DR4+0x2,WR2
0007B0 1B1A00         MOV      @DR4,WR0
                                                ; SOURCE LINE # 406
0007B3 AA             ERET     
;       FUNCTION BMI088_accel_read_over? (END)

;       FUNCTION BMI088_gyro_read_over? (BEGIN)
                                                ; SOURCE LINE # 408
0007B4 7F61           MOV      DR24,DR4
;---- Variable 'gyro' assigned to Register 'DR24' ----
0007B6 7F70           MOV      DR28,DR0
;---- Variable 'rx_buf' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 409
                                                ; SOURCE LINE # 411
0007B8 29670001       MOV      R6,@DR28+0x1
0007BC 7E7B50         MOV      R5,@DR28
0007BF 7C46           MOV      R4,R6
;---- Variable 'bmi088_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 412
0007C1 7CB6           MOV      R11,R6           ; A=R11
0007C3 9A000000    E  ECALL    ?C?FCASTI?
0007C7 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
0007CB 9A000000    E  ECALL    ?C?FPMUL?
0007CF 79360002       MOV      @DR24+0x2,WR6
0007D3 1B6A20         MOV      @DR24,WR4
                                                ; SOURCE LINE # 413
0007D6 29670003       MOV      R6,@DR28+0x3
0007DA 29570002       MOV      R5,@DR28+0x2
0007DE 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 414
0007E0 7CB6           MOV      R11,R6           ; A=R11
0007E2 9A000000    E  ECALL    ?C?FCASTI?
0007E6 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
0007EA 9A000000    E  ECALL    ?C?FPMUL?
0007EE 79360006       MOV      @DR24+0x6,WR6
0007F2 79260004       MOV      @DR24+0x4,WR4
                                                ; SOURCE LINE # 415
0007F6 29670005       MOV      R6,@DR28+0x5
0007FA 29570004       MOV      R5,@DR28+0x4
0007FE 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 416
000800 7CB6           MOV      R11,R6           ; A=R11
000802 9A000000    E  ECALL    ?C?FCASTI?
000806 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
00080A 9A000000    E  ECALL    ?C?FPMUL?
00080E 7936000A       MOV      @DR24+0xA,WR6
000812 79260008       MOV      @DR24+0x8,WR4
                                                ; SOURCE LINE # 417
000816 AA             ERET     
;       FUNCTION BMI088_gyro_read_over? (END)

;       FUNCTION BMI088_read? (BEGIN)
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 24  

                                                ; SOURCE LINE # 419
000817 CA3B           PUSH     DR12
000819 7F31           MOV      DR12,DR4
;---- Variable 'accel' assigned to Register 'DR12' ----
00081B 7A0F0000    R  MOV      gyro,DR0
                                                ; SOURCE LINE # 420
                                                ; SOURCE LINE # 421
00081F 7E540000    R  MOV      WR10,#WORD0 ?tpl?0002
000823 7E440000    R  MOV      WR8,#WORD2 ?tpl?0002
000827 69320006       MOV      WR6,@DR8+0x6
00082B 69220004       MOV      WR4,@DR8+0x4
00082F 69120002       MOV      WR2,@DR8+0x2
000833 0B2A00         MOV      WR0,@DR8
000836 7A1F0000    R  MOV      buf+4,DR4
00083A 7A0F0000    R  MOV      buf,DR0
                                                ; SOURCE LINE # 424
00083E 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000842 7492           MOV      A,#092H          ; A=R11
000844 9A000000    E  ECALL    BMI088_read_write_byte?
000848 7412           MOV      A,#012H          ; A=R11
00084A 7E000000    R  MOV      DR0,#WORD0 buf
00084E 7E7006         MOV      R7,#06H
000851 120000      R  LCALL    BMI088_read_muli_reg
000854 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 426
000858 7E630000    R  MOV      R6,buf+1
00085C 7E530000    R  MOV      R5,buf
000860 7C46           MOV      R4,R6
;---- Variable 'bmi088_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 427
000862 7CB6           MOV      R11,R6           ; A=R11
000864 9A000000    E  ECALL    ?C?FCASTI?
000868 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
00086C 9A000000    E  ECALL    ?C?FPMUL?
000870 79330002       MOV      @DR12+0x2,WR6
000874 1B3A20         MOV      @DR12,WR4
                                                ; SOURCE LINE # 428
000877 7E630000    R  MOV      R6,buf+3
00087B 7E530000    R  MOV      R5,buf+2
00087F 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 429
000881 7CB6           MOV      R11,R6           ; A=R11
000883 9A000000    E  ECALL    ?C?FCASTI?
000887 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
00088B 9A000000    E  ECALL    ?C?FPMUL?
00088F 79330006       MOV      @DR12+0x6,WR6
000893 79230004       MOV      @DR12+0x4,WR4
                                                ; SOURCE LINE # 430
000897 7E630000    R  MOV      R6,buf+5
00089B 7E530000    R  MOV      R5,buf+4
00089F 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 431
0008A1 7CB6           MOV      R11,R6           ; A=R11
0008A3 9A000000    E  ECALL    ?C?FCASTI?
0008A7 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
0008AB 9A000000    E  ECALL    ?C?FPMUL?
0008AF 7933000A       MOV      @DR12+0xA,WR6
0008B3 79230008       MOV      @DR12+0x8,WR4
                                                ; SOURCE LINE # 433
0008B7 9A000000    E  ECALL    BMI088_GYRO_NS_L?
0008BB E4             CLR      A                ; A=R11
0008BC 7E000000    R  MOV      DR0,#WORD0 buf
0008C0 7E7008         MOV      R7,#08H
0008C3 120000      R  LCALL    BMI088_read_muli_reg
0008C6 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 434
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 25  

0008CA 7EB30000    R  MOV      R11,buf          ; A=R11
0008CE B40F6D         CJNE     A,#0FH,?C0048    ; A=R11
                                                ; SOURCE LINE # 436
0008D1 7E630000    R  MOV      R6,buf+3
0008D5 7E530000    R  MOV      R5,buf+2
0008D9 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 437
0008DB 7CB6           MOV      R11,R6           ; A=R11
0008DD 9A000000    E  ECALL    ?C?FCASTI?
0008E1 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
0008E5 9A000000    E  ECALL    ?C?FPMUL?
0008E9 7F01           MOV      DR0,DR4
0008EB 7E1F0000    R  MOV      DR4,gyro
0008EF 79110002       MOV      @DR4+0x2,WR2
0008F3 1B1A00         MOV      @DR4,WR0
                                                ; SOURCE LINE # 438
0008F6 7E630000    R  MOV      R6,buf+5
0008FA 7E530000    R  MOV      R5,buf+4
0008FE 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 439
000900 7CB6           MOV      R11,R6           ; A=R11
000902 9A000000    E  ECALL    ?C?FCASTI?
000906 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
00090A 9A000000    E  ECALL    ?C?FPMUL?
00090E 7E0F0000    R  MOV      DR0,gyro
000912 79300006       MOV      @DR0+0x6,WR6
000916 79200004       MOV      @DR0+0x4,WR4
                                                ; SOURCE LINE # 440
00091A 7E630000    R  MOV      R6,buf+7
00091E 7E530000    R  MOV      R5,buf+6
000922 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 441
000924 7CB6           MOV      R11,R6           ; A=R11
000926 9A000000    E  ECALL    ?C?FCASTI?
00092A 7E0F0000    R  MOV      DR0,BMI088_GYRO_SEN
00092E 9A000000    E  ECALL    ?C?FPMUL?
000932 7E0F0000    R  MOV      DR0,gyro
000936 7930000A       MOV      @DR0+0xA,WR6
00093A 79200008       MOV      @DR0+0x8,WR4
                                                ; SOURCE LINE # 442
               ?C0048:
                                                ; SOURCE LINE # 443
00093E 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000942 74A2           MOV      A,#0A2H          ; A=R11
000944 9A000000    E  ECALL    BMI088_read_write_byte?
000948 7422           MOV      A,#022H          ; A=R11
00094A 7E000000    R  MOV      DR0,#WORD0 buf
00094E 7E7002         MOV      R7,#02H
000951 120000      R  LCALL    BMI088_read_muli_reg
000954 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 445
000958 7E730000    R  MOV      R7,buf
00095C 0A37           MOVZ     WR6,R7
00095E 3E34           SLL      WR6
000960 3E34           SLL      WR6
000962 3E34           SLL      WR6
000964 7EB30000    R  MOV      R11,buf+1        ; A=R11
000968 C4             SWAP     A                ; A=R11
000969 03             RR       A                ; A=R11
00096A 5407           ANL      A,#07H           ; A=R11
00096C 0A2B           MOVZ     WR4,R11          ; A=R11
00096E 4D23           ORL      WR4,WR6
                                                ; SOURCE LINE # 447
000970 BE2403FF       CMP      WR4,#03FFH
000974 0804           JSLE     ?C0049
                                                ; SOURCE LINE # 449
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 26  

000976 9E240800       SUB      WR4,#0800H
                                                ; SOURCE LINE # 450
               ?C0049:
                                                ; SOURCE LINE # 452
00097A 7CB4           MOV      R11,R4           ; A=R11
00097C 9A000000    E  ECALL    ?C?FCASTI?
000980 6D11           XRL      WR2,WR2
000982 7E043E00       MOV      WR0,#03E00H
000986 9A000000    E  ECALL    ?C?FPMUL?
00098A 6D11           XRL      WR2,WR2
00098C 7E0441B8       MOV      WR0,#041B8H
000990 9A000000    E  ECALL    ?C?FPADD?
000994 7F01           MOV      DR0,DR4
000996 7E1F0000    R  MOV      DR4,temperate
00099A 79110002       MOV      @DR4+0x2,WR2
00099E 1B1A00         MOV      @DR4,WR0
                                                ; SOURCE LINE # 453
0009A1 DA3B           POP      DR12
0009A3 AA             ERET     
;       FUNCTION BMI088_read? (END)

;       FUNCTION get_BMI088_sensor_time? (BEGIN)
                                                ; SOURCE LINE # 455
                                                ; SOURCE LINE # 456
                                                ; SOURCE LINE # 457
                                                ; SOURCE LINE # 459
0009A4 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0009A8 7498           MOV      A,#098H          ; A=R11
0009AA 9A000000    E  ECALL    BMI088_read_write_byte?
0009AE 7418           MOV      A,#018H          ; A=R11
0009B0 7E000000    R  MOV      DR0,#WORD0 buf
0009B4 7E7003         MOV      R7,#03H
0009B7 120000      R  LCALL    BMI088_read_muli_reg
0009BA 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 461
0009BE 7E630000    R  MOV      R6,buf+1
0009C2 6C77           XRL      R7,R7
0009C4 7E530000    R  MOV      R5,buf+2
0009C8 0A25           MOVZ     WR4,R5
0009CA 7E730000    R  MOV      R7,buf
0009CE 6D22           XRL      WR4,WR4
;---- Variable 'sensor_time' assigned to Register 'DR4' ----
                                                ; SOURCE LINE # 463
                                                ; SOURCE LINE # 464
0009D0 AA             ERET     
;       FUNCTION get_BMI088_sensor_time? (END)

;       FUNCTION get_BMI088_temperate? (BEGIN)
                                                ; SOURCE LINE # 466
                                                ; SOURCE LINE # 467
                                                ; SOURCE LINE # 472
0009D1 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
0009D5 74A2           MOV      A,#0A2H          ; A=R11
0009D7 9A000000    E  ECALL    BMI088_read_write_byte?
0009DB 7422           MOV      A,#022H          ; A=R11
0009DD 7E000000    R  MOV      DR0,#WORD0 buf
0009E1 7E7002         MOV      R7,#02H
0009E4 120000      R  LCALL    BMI088_read_muli_reg
0009E7 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 474
0009EB 7E730000    R  MOV      R7,buf
0009EF 0A37           MOVZ     WR6,R7
0009F1 3E34           SLL      WR6
0009F3 3E34           SLL      WR6
0009F5 3E34           SLL      WR6
0009F7 7EB30000    R  MOV      R11,buf+1        ; A=R11
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 27  

0009FB C4             SWAP     A                ; A=R11
0009FC 03             RR       A                ; A=R11
0009FD 5407           ANL      A,#07H           ; A=R11
0009FF 0A2B           MOVZ     WR4,R11          ; A=R11
000A01 4D23           ORL      WR4,WR6
;---- Variable 'temperate_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 476
000A03 BE2403FF       CMP      WR4,#03FFH
000A07 0804           JSLE     ?C0051
                                                ; SOURCE LINE # 478
000A09 9E240800       SUB      WR4,#0800H
                                                ; SOURCE LINE # 479
               ?C0051:
                                                ; SOURCE LINE # 481
000A0D 7CB4           MOV      R11,R4           ; A=R11
000A0F 9A000000    E  ECALL    ?C?FCASTI?
000A13 6D11           XRL      WR2,WR2
000A15 7E043E00       MOV      WR0,#03E00H
000A19 9A000000    E  ECALL    ?C?FPMUL?
000A1D 6D11           XRL      WR2,WR2
000A1F 7E0441B8       MOV      WR0,#041B8H
000A23 8A000000    E  EJMP     ?C?FPADD?
;---- Variable 'temperate' assigned to Register 'DR4' ----
                                                ; SOURCE LINE # 483
                                                ; SOURCE LINE # 484
;       FUNCTION get_BMI088_temperate? (END)

;       FUNCTION get_BMI088_gyro? (BEGIN)
                                                ; SOURCE LINE # 486
000A27 CA3B           PUSH     DR12
000A29 7F30           MOV      DR12,DR0
;---- Variable 'gyro' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 487
                                                ; SOURCE LINE # 488
000A2B 7E540000    R  MOV      WR10,#WORD0 ?tpl?0003
000A2F 7E440000    R  MOV      WR8,#WORD2 ?tpl?0003
000A33 69320004       MOV      WR6,@DR8+0x4
000A37 69220002       MOV      WR4,@DR8+0x2
000A3B 0B2A10         MOV      WR2,@DR8
000A3E 7A1F0000    R  MOV      buf+2,DR4
000A42 7A170000    R  MOV      buf,WR2
                                                ; SOURCE LINE # 491
000A46 9A000000    E  ECALL    BMI088_GYRO_NS_L?
000A4A 7402           MOV      A,#02H           ; A=R11
000A4C 7E000000    R  MOV      DR0,#WORD0 buf
000A50 7E7006         MOV      R7,#06H
000A53 120000      R  LCALL    BMI088_read_muli_reg
000A56 9A000000    E  ECALL    BMI088_GYRO_NS_H?
                                                ; SOURCE LINE # 493
000A5A 7E730000    R  MOV      R7,buf+1
000A5E 7C47           MOV      R4,R7
000A60 6C55           XRL      R5,R5
000A62 7E730000    R  MOV      R7,buf
000A66 7C64           MOV      R6,R4
;---- Variable 'gyro_raw_temp' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 494
000A68 1B3A30         MOV      @DR12,WR6
                                                ; SOURCE LINE # 495
000A6B 7E730000    R  MOV      R7,buf+3
000A6F 7C47           MOV      R4,R7
000A71 7E730000    R  MOV      R7,buf+2
000A75 7C64           MOV      R6,R4
                                                ; SOURCE LINE # 496
000A77 79330002       MOV      @DR12+0x2,WR6
                                                ; SOURCE LINE # 497
000A7B 7E730000    R  MOV      R7,buf+5
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 28  

000A7F 7C47           MOV      R4,R7
000A81 7E730000    R  MOV      R7,buf+4
000A85 7C64           MOV      R6,R4
                                                ; SOURCE LINE # 498
000A87 79330004       MOV      @DR12+0x4,WR6
                                                ; SOURCE LINE # 499
000A8B DA3B           POP      DR12
000A8D AA             ERET     
;       FUNCTION get_BMI088_gyro? (END)

;       FUNCTION get_BMI088_accel? (BEGIN)
                                                ; SOURCE LINE # 501
000A8E CA3B           PUSH     DR12
000A90 7F30           MOV      DR12,DR0
;---- Variable 'accel' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 502
                                                ; SOURCE LINE # 503
000A92 7E540000    R  MOV      WR10,#WORD0 ?tpl?0004
000A96 7E440000    R  MOV      WR8,#WORD2 ?tpl?0004
000A9A 69320004       MOV      WR6,@DR8+0x4
000A9E 69220002       MOV      WR4,@DR8+0x2
000AA2 0B2A10         MOV      WR2,@DR8
000AA5 7A1F0000    R  MOV      buf+2,DR4
000AA9 7A170000    R  MOV      buf,WR2
                                                ; SOURCE LINE # 506
000AAD 9A000000    E  ECALL    BMI088_ACCEL_NS_L?
000AB1 7492           MOV      A,#092H          ; A=R11
000AB3 9A000000    E  ECALL    BMI088_read_write_byte?
000AB7 7412           MOV      A,#012H          ; A=R11
000AB9 7E000000    R  MOV      DR0,#WORD0 buf
000ABD 7E7006         MOV      R7,#06H
000AC0 120000      R  LCALL    BMI088_read_muli_reg
000AC3 9A000000    E  ECALL    BMI088_ACCEL_NS_H?
                                                ; SOURCE LINE # 508
000AC7 7E630000    R  MOV      R6,buf+1
000ACB 7E530000    R  MOV      R5,buf
000ACF 7C46           MOV      R4,R6
;---- Variable 'accel_raw_temp' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 509
000AD1 7CB6           MOV      R11,R6           ; A=R11
000AD3 9A000000    E  ECALL    ?C?FCASTI?
000AD7 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000ADB 9A000000    E  ECALL    ?C?FPMUL?
000ADF 79330002       MOV      @DR12+0x2,WR6
000AE3 1B3A20         MOV      @DR12,WR4
                                                ; SOURCE LINE # 510
000AE6 7E630000    R  MOV      R6,buf+3
000AEA 7E530000    R  MOV      R5,buf+2
000AEE 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 511
000AF0 7CB6           MOV      R11,R6           ; A=R11
000AF2 9A000000    E  ECALL    ?C?FCASTI?
000AF6 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000AFA 9A000000    E  ECALL    ?C?FPMUL?
000AFE 79330006       MOV      @DR12+0x6,WR6
000B02 79230004       MOV      @DR12+0x4,WR4
                                                ; SOURCE LINE # 512
000B06 7E630000    R  MOV      R6,buf+5
000B0A 7E530000    R  MOV      R5,buf+4
000B0E 7C46           MOV      R4,R6
                                                ; SOURCE LINE # 513
000B10 7CB6           MOV      R11,R6           ; A=R11
000B12 9A000000    E  ECALL    ?C?FCASTI?
000B16 7E0F0000    R  MOV      DR0,BMI088_ACCEL_SEN
000B1A 9A000000    E  ECALL    ?C?FPMUL?
000B1E 7933000A       MOV      @DR12+0xA,WR6
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 29  

000B22 79230008       MOV      @DR12+0x8,WR4
                                                ; SOURCE LINE # 514
000B26 DA3B           POP      DR12
000B28 AA             ERET     
;       FUNCTION get_BMI088_accel? (END)

;       FUNCTION BMI088_write_single_reg (BEGIN)
                                                ; SOURCE LINE # 518
000B29 CAF8           PUSH     R15
000B2B 7CF7           MOV      R15,R7
;---- Variable 'data_t' assigned to Register 'R15' ----
;---- Variable 'reg' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 520
000B2D 9A000000    E  ECALL    BMI088_read_write_byte?
                                                ; SOURCE LINE # 521
000B31 7CBF           MOV      R11,R15          ; A=R11
000B33 9A000000    E  ECALL    BMI088_read_write_byte?
                                                ; SOURCE LINE # 522
000B37 DAF8           POP      R15
000B39 22             RET      
;       FUNCTION BMI088_write_single_reg (END)

;       FUNCTION BMI088_read_single_reg (BEGIN)
                                                ; SOURCE LINE # 524
000B3A CA3B           PUSH     DR12
000B3C 7F30           MOV      DR12,DR0
;---- Variable 'return_data' assigned to Register 'DR12' ----
;---- Variable 'reg' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 526
000B3E 4480           ORL      A,#080H          ; A=R11
000B40 9A000000    E  ECALL    BMI088_read_write_byte?
                                                ; SOURCE LINE # 527
000B44 7455           MOV      A,#055H          ; A=R11
000B46 9A000000    E  ECALL    BMI088_read_write_byte?
000B4A 7A3BB0         MOV      @DR12,R11        ; A=R11
                                                ; SOURCE LINE # 528
000B4D DA3B           POP      DR12
000B4F 22             RET      
;       FUNCTION BMI088_read_single_reg (END)

;       FUNCTION BMI088_read_muli_reg (BEGIN)
                                                ; SOURCE LINE # 543
000B50 CA3B           PUSH     DR12
000B52 7A730000    R  MOV      len,R7
000B56 7F30           MOV      DR12,DR0
;---- Variable 'buf' assigned to Register 'DR12' ----
;---- Variable 'reg' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 545
000B58 4480           ORL      A,#080H          ; A=R11
000B5A 9A000000    E  ECALL    BMI088_read_write_byte?
                                                ; SOURCE LINE # 547
000B5E 8014           SJMP     ?C0053
               ?C0055:
                                                ; SOURCE LINE # 550
000B60 7455           MOV      A,#055H          ; A=R11
000B62 9A000000    E  ECALL    BMI088_read_write_byte?
000B66 7A3BB0         MOV      @DR12,R11        ; A=R11
                                                ; SOURCE LINE # 551
000B69 0B74           INC      WR14,#01H
                                                ; SOURCE LINE # 552
000B6B 7EB30000    R  MOV      R11,len          ; A=R11
000B6F 14             DEC      A                ; A=R11
000B70 7AB30000    R  MOV      len,R11          ; A=R11
                                                ; SOURCE LINE # 553
               ?C0053:
000B74 7EB30000    R  MOV      R11,len          ; A=R11
C251 COMPILER V5.60.0,  BMI088driver                                                       24/08/26  10:23:43  PAGE 30  

000B78 70E6           JNZ      ?C0055
                                                ; SOURCE LINE # 554
000B7A DA3B           POP      DR12
000B7C 22             RET      
;       FUNCTION BMI088_read_muli_reg (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      2941     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =        44         62
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =       104     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)
