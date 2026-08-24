C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE nrf24l01
OBJECT MODULE PLACED IN .\Objects\ASM\nrf24l01.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\nrf24l01.c XSMALL ROM(HUGE) BROWSE INCDI
                    -R(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X1
                    -000) DEBUG CODE PRINT(.\ASM\nrf24l01.asm) TABS(2) OBJECT(.\Objects\ASM\nrf24l01.obj) 

stmt  level    source

    1          #include "nrf24l01.h"
    2          #include "CNU_PIE_SPI.h"
    3          #include "string.h"
    4          #include "remote_control.h"
    5          #include "CNU_PIE_EXTI.h"
    6          #include "isr.h"
    7          #include "main.h"
    8          
    9          // NRF24L01+״̬
   10          typedef enum
   11          {
   12            NOT_INIT = 0,
   13            TX_MODE,
   14            RX_MODE,
   15          } nrf_mode_e;
   16          
   17          int RecFPS = 0;
   18          
   19          #define CHANAL 36 // Ƶ��ѡ��
   20          
   21          uint8_t TX_ADDRESS[5] = {'R', 'C', 'T', 'L', 0}; // ���͵�ַ
   22          uint8_t RX_ADDRESS[5] = {'R', 'C', 'T', 'L', 0}; // ���յ�ַ
   23          
   24          uint8_t TX_Buff[TX_PACKET_LENTH];
   25          uint8_t RX_Buff[RX_PACKET_LENTH];
   26          
   27          /******************************** NRF24L01+ �Ĵ������� �궨��**********************
             -*****************/
   28          
   29          // SPI(nRF24L01) commands , NRF��SPI����궨�壬���NRF����ʹ���ĵ�
   30          #define NRF_READ_REG 0x00  // Define read command to register
   31          #define NRF_WRITE_REG 0x20 // Define write command to register
   32          #define RD_RX_PLOAD 0x61   // Define RX payload register address
   33          #define WR_TX_PLOAD 0xA0   // Define TX payload register address
   34          #define FLUSH_TX 0xE1      // Define flush TX register command
   35          #define FLUSH_RX 0xE2      // Define flush RX register command
   36          #define REUSE_TX_PL 0xE3   // Define reuse TX payload register command
   37          #define _NOP 0xFF          // Define No Operation, might be used to read status register
   38          
   39          // ����Ƶ
   40          #define CE_ON 0x70
   41          #define CE_OFF 0x71
   42          #define FEATURE 0x1D //  Feature Register address
   43          
   44          // SPI(nRF24L01) registers(addresses) ��NRF24L01 ��ؼĴ�����ַ�ĺ궨��
   45          #define CONFIG 0x00      // 'Config' register address
   46          #define EN_AA 0x01       // 'Enable Auto Acknowledgment' register address
   47          #define EN_RXADDR 0x02   // 'Enabled RX addresses' register address
   48          #define SETUP_AW 0x03    // 'Setup address width' register address
   49          #define SETUP_RETR 0x04  // 'Setup Auto. Retrans' register address
   50          #define RF_CH 0x05       // 'RF channel' register address
   51          #define RF_SETUP 0x06    // 'RF setup' register address
   52          #define STATUS 0x07      // 'Status' register address
   53          #define OBSERVE_TX 0x08  // 'Observe TX' register address
   54          #define CD 0x09          // 'Carrier Detect' register address
   55          #define RX_ADDR_P0 0x0A  // 'RX address pipe0' register address
   56          #define RX_ADDR_P1 0x0B  // 'RX address pipe1' register address
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 2   

   57          #define RX_ADDR_P2 0x0C  // 'RX address pipe2' register address
   58          #define RX_ADDR_P3 0x0D  // 'RX address pipe3' register address
   59          #define RX_ADDR_P4 0x0E  // 'RX address pipe4' register address
   60          #define RX_ADDR_P5 0x0F  // 'RX address pipe5' register address
   61          #define TX_ADDR 0x10     // 'TX address' register address
   62          #define RX_PW_P0 0x11    // 'RX payload width, pipe0' register address
   63          #define RX_PW_P1 0x12    // 'RX payload width, pipe1' register address
   64          #define RX_PW_P2 0x13    // 'RX payload width, pipe2' register address
   65          #define RX_PW_P3 0x14    // 'RX payload width, pipe3' register address
   66          #define RX_PW_P4 0x15    // 'RX payload width, pipe4' register address
   67          #define RX_PW_P5 0x16    // 'RX payload width, pipe5' register address
   68          #define FIFO_STATUS 0x17 // 'FIFO Status Register' register address
   69          
   70          // ������Ҫ��״̬���
   71          #define TX_FULL 0x01 // TX FIFO �Ĵ�������־�� 1 Ϊ ����0Ϊ ����
   72          #define MAX_RT 0x10  // �ﵽ����ط������жϱ�־λ
   73          #define TX_DS 0x20   // ��������жϱ�־λ
   74          #define RX_DR 0x40   // ���յ������жϱ�־λ
   75          
   76          // �ڲ��Ĵ���������������
   77          void nrf_writereg(uint8_t reg, uint8_t dat);
   78          uint8_t nrf_readreg(uint8_t reg);
   79          
   80          void nrf_writebuf(uint8_t reg, uint8_t *pBuf, uint16_t len) reentrant;
   81          void nrf_readbuf(uint8_t reg, uint8_t *pBuf, uint16_t len) reentrant;
   82          
   83          void nrf_rx_mode(void);       // �������ģʽ
   84          void nrf_tx_mode(void);       // ���뷢��ģʽ
   85          uint8_t nrf_link_check(void); // ���NRF24L01+�뵥Ƭ���Ƿ�ͨ������
   86          /*!
   87           *  @brief      NRF24L01+ ģʽ���
   88           */
   89          volatile uint8_t nrf_mode = NOT_INIT;
   90          
   91          // RF2G4��ʼ��
   92          //------------------------------------------------------------------------------------------
   93          uint8_t NRF24L01_Init(void)
   94          {
   95   1      
   96   1        GPIO_Init(RF2G4_CE_Port, RF2G4_CE_Pin, GPIO_OUT_PP);
   97   1        GPIO_Init(RF2G4_CSN_Port, RF2G4_CSN_Pin, GPIO_OUT_PP);
   98   1      
   99   1        GPIO_Init(RF2G4_MISO_Port, RF2G4_MISO_Pin, GPIO_HighZ);
  100   1        GPIO_PinPullConfig(RF2G4_MISO_Port, RF2G4_MISO_Pin, GPIO_NO_PULL);
  101   1      
  102   1        GPIO_Init(RF2G4_IRQ_Port, RF2G4_IRQ_Pin, GPIO_HighZ);
  103   1        GPIO_EXTI_Init(RF2G4_IRQ_Port, RF2G4_IRQ_Pin, FALLING_EDGE);
  104   1        GPIO_EXTI_Open(RF2G4_IRQ_Port, RF2G4_IRQ_Pin);
  105   1        GPIO_EXTI_Set_Priority(RF2G4_IRQ_Port, Highest_priority);
  106   1      
  107   1        SPI_Init(SPI_2, 0, SPI_MSB, SPI_CPOL_Low, SPI_CPHA_1Edge, SPI_Speed_4, SPI_Mode_Master, 1);
  108   1      
  109   1        RX_ADDRESS[4] = Channal;
  110   1        TX_ADDRESS[4] = Channal;
  111   1      
  112   1        // 2401�Ĵ�������
  113   1        RF2G4_CE_LOW;
  114   1      
  115   1        nrf_writereg(NRF_WRITE_REG + SETUP_AW, ADR_WIDTH - 2); // ���õ�ַ����Ϊ TX_ADR_WIDTH
  116   1      
  117   1        nrf_writereg(NRF_WRITE_REG + RF_CH, Channal); // ����RFͨ��ΪCHANAL
  118   1      
  119   1        /*            | NRF24L01      | SI24R1        |Ci24R1
  120   1         *     1Mbps   |  0x06   0dBm  |  0x07    7dBm | 0x07  11dBm
  121   1         *     250kbps |  0x26   0dBm  |  0x27    7dBm | 0x27  11dBm
  122   1         */
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 3   

  123   1        nrf_writereg(NRF_WRITE_REG + RF_SETUP, 0x06); // ����TX�������
  124   1      
  125   1        // nrf_writereg(NRF_WRITE_REG + FEATURE, 0x04);                   //ʹ�ܶ�̬���� SI24R1 Ci24R1
  126   1      
  127   1        nrf_writereg(NRF_WRITE_REG + EN_AA, 0x01); // ʹ��ͨ��0���Զ�Ӧ��
  128   1      
  129   1        nrf_writereg(NRF_WRITE_REG + EN_RXADDR, 0x01); // ʹ��ͨ��0�Ľ��յ�ַ
  130   1      
  131   1        // RXģʽ����
  132   1        nrf_writebuf(NRF_WRITE_REG + RX_ADDR_P0, RX_ADDRESS, ADR_WIDTH); // дRX0�ڵ��ַ
  133   1      
  134   1        nrf_writereg(NRF_WRITE_REG + RX_PW_P0, RX_PACKET_LENTH); // ѡ��ͨ��0����Ч���ݿ�
             -����
  135   1      
  136   1        nrf_writereg(FLUSH_RX, _NOP); // ���RX FIFO�Ĵ���
  137   1      
  138   1        // TXģʽ����
  139   1        nrf_writebuf(NRF_WRITE_REG + TX_ADDR, TX_ADDRESS, ADR_WIDTH); // дTX�ڵ��ַ
  140   1      
  141   1        nrf_writereg(NRF_WRITE_REG + SETUP_RETR, 0x05); // �����Զ��ط����ʱ��:250us;
             - ����Զ��ط�����:10��
  142   1      
  143   1        nrf_writereg(FLUSH_TX, _NOP); // ���TX FIFO�Ĵ���
  144   1      
  145   1        nrf_rx_mode(); // Ĭ�Ͻ������ģʽ
  146   1      
  147   1        RF2G4_CE_HIGH;
  148   1      
  149   1        return nrf_link_check();
  150   1      }
  151          
  152          // ���NRF24L01+��MCU�Ƿ���������
  153          // return = 0:�ɹ�, 1:ʧ��
  154          //---------------------------------------------------------------------------------------------------
  155          uint8_t nrf_link_check(void)
  156          {
  157   1      #define NRF_CHECH_DATA 0x06 // ��ֵΪУ������ʱʹ�ã����޸�Ϊ����ֵ
  158   1      
  159   1        uint8_t reg;
  160   1      
  161   1        uint8_t buff[5] = {NRF_CHECH_DATA, NRF_CHECH_DATA, NRF_CHECH_DATA, NRF_CHECH_DATA, NRF_CHECH_DATA};
  162   1        uint8_t i;
  163   1        // д��У������
  164   1        reg = NRF_WRITE_REG + TX_ADDR;
  165   1      
  166   1        RF2G4_CE_LOW;
  167   1      
  168   1        nrf_writebuf(reg, buff, 5); // д��У������
  169   1      
  170   1        // ��ȡУ������
  171   1        reg = TX_ADDR;
  172   1        nrf_readbuf(reg, buff, 5); // ��ȡУ������
  173   1      
  174   1        RF2G4_CE_HIGH;
  175   1        /*�Ƚ�*/
  176   1        for (i = 0; i < 5; i++)
  177   1        {
  178   2          if (buff[i] != NRF_CHECH_DATA)
  179   2          {
  180   3            return 0; // MCU��NRF����������
  181   3          }
  182   2        }
  183   1        return 1; // MCU��NRF�ɹ�����
  184   1      }
  185          
  186          /*!
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 4   

  187           *  @brief      NRF24L01+�������ģʽ
  188           *  @since      v5.0
  189           */
  190          void nrf_rx_mode(void)
  191          {
  192   1        RF2G4_CE_LOW;
  193   1      
  194   1        nrf_writereg(NRF_WRITE_REG + EN_AA, 0x01); // ʹ��ͨ��0���Զ�Ӧ��
  195   1      
  196   1        nrf_writereg(NRF_WRITE_REG + EN_RXADDR, 0x01); // ʹ��ͨ��0�Ľ��յ�ַ
  197   1      
  198   1        nrf_writebuf(NRF_WRITE_REG + RX_ADDR_P0, RX_ADDRESS, ADR_WIDTH); // дRX�ڵ��ַ
  199   1      
  200   1        nrf_writereg(NRF_WRITE_REG + CONFIG, 0x0B | (IS_CRC16 << 2)); // ���û�������ģʽ�
             -�Ĳ���;PWR_UP,EN_CRC,16BIT_CRC,����ģʽ
  201   1      
  202   1        /* ����жϱ�־*/
  203   1        nrf_writereg(NRF_WRITE_REG + STATUS, _NOP);
  204   1      
  205   1        nrf_writereg(FLUSH_RX, _NOP); // ���RX FIFO�Ĵ���
  206   1      
  207   1        RF2G4_CE_HIGH;
  208   1      
  209   1        nrf_mode = RX_MODE;
  210   1      }
  211          
  212          /*!
  213           *  @brief      NRF24L01+���뷢��ģʽ
  214           *  @since      v5.0
  215           */
  216          void nrf_tx_mode(void)
  217          {
  218   1        RF2G4_CE_LOW;
  219   1      
  220   1        nrf_writebuf(NRF_WRITE_REG + TX_ADDR, TX_ADDRESS, ADR_WIDTH); // дTX�ڵ��ַ
  221   1      
  222   1        nrf_writebuf(NRF_WRITE_REG + RX_ADDR_P0, RX_ADDRESS, ADR_WIDTH); // ����RX�ڵ��ַ ,��
             -ҪΪ��ʹ��ACK
  223   1      
  224   1        nrf_writereg(NRF_WRITE_REG + CONFIG, 0x0A | (IS_CRC16 << 2)); // ���û�������ģʽ�
             -�Ĳ���;PWR_UP,EN_CRC,16BIT_CRC,����ģʽ,���������ж�
  225   1      
  226   1        RF2G4_CE_HIGH;
  227   1      
  228   1        nrf_mode = TX_MODE;
  229   1      
  230   1        Ms_Delay(25);
  231   1      }
  232          
  233          // ���Ͳ���̫��
  234          void nrf_tx_packet(uint8_t *txbuf, uint8_t len)
  235          {
  236   1        uint8_t crc = 0;
  237   1        int i;
  238   1        if ((txbuf == 0) || len <= 0)
  239   1          return;
  240   1        TX_Buff[0] = len + 1;            // ֡ͷ �ֽڳ���
  241   1        memcpy(TX_Buff + 1, txbuf, len); // ��ȡ����
  242   1        for (i = 0; i < len; i++)
  243   1          crc += *(txbuf + i);
  244   1        TX_Buff[len + 1] = crc; // ֡βУ��
  245   1        // ����
  246   1        if (nrf_mode != TX_MODE)
  247   1        {
  248   2          nrf_tx_mode();
  249   2        }
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 5   

  250   1        RF2G4_CE_LOW;
  251   1        nrf_writebuf(WR_TX_PLOAD, (uint8_t *)TX_Buff, len + 2);
  252   1        RF2G4_CE_HIGH;
  253   1      }
  254          
  255          void nrf_handler(void)
  256          {
  257   1        uint8_t state;
  258   1        /*��ȡstatus�Ĵ�����ֵ  */
  259   1        // RF2G4_CE_LOW;
  260   1        state = nrf_readreg(STATUS);
  261   1      
  262   1        /* ����жϱ�־*/
  263   1        nrf_writereg(NRF_WRITE_REG + STATUS, state);
  264   1        // RF2G4_CE_HIGH;
  265   1        if (state & RX_DR) // ���յ�����
  266   1        {
  267   2          // ��ȡ���ݲ����
  268   2          RF2G4_CE_LOW;
  269   2          nrf_readbuf(RD_RX_PLOAD, RX_Buff, RX_PACKET_LENTH);
  270   2          Rc_unpack_data(RX_Buff);
  271   2          RF2G4_CE_HIGH;
  272   2        }
  273   1      
  274   1        if (state & TX_DS) // ����������
  275   1        {
  276   2          // RF2G4_CE_LOW;
  277   2          nrf_writereg(FLUSH_TX, _NOP); // ���TX FIFO
  278   2          // RF2G4_CE_HIGH;
  279   2          if (nrf_mode != RX_MODE)
  280   2          {
  281   3            nrf_rx_mode();
  282   3          }
  283   2        }
  284   1      
  285   1        if (state & MAX_RT) // ���ͳ�ʱ
  286   1        {
  287   2          // RF2G4_CE_LOW;
  288   2          nrf_writereg(FLUSH_TX, _NOP); // ���TX FIFO�Ĵ���
  289   2          // RF2G4_CE_HIGH;
  290   2          if (nrf_mode != RX_MODE) // ���� ����״̬
  291   2          {
  292   3            nrf_rx_mode();
  293   3          }
  294   2        }
  295   1      
  296   1        if (state & TX_FULL) // TX FIFO ��
  297   1        {
  298   2        }
  299   1      }
  300          
  301          // ���ݰ�ѹ������
  302          uint8_t label = 0;
  303          void RCPacket_Send(void)
  304          {
  305   1        int i;
  306   1        uint8_t crc = 0;
  307   1        SendPack_t *pack_t = get_sendpack_point();
  308   1        int number = 0;
  309   1        for (i = label; i < 3 + label; i++) // ��ѹ��
  310   1        {
  311   2          int pot = number * 10 + 1;
  312   2          if (pack_t->Mode[i] == 1) // �ַ���+����
  313   2          {
  314   3            TX_Buff[pot] = 0;
  315   3            TX_Buff[pot] |= (pack_t->line[i].Namelenth << 4) | (pack_t->line[i].Row << 1) | (pack_t->line[i].Si
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 6   

             -ze);
  316   3            memcpy(TX_Buff + pot + 1, pack_t->line[i].Name, pack_t->line[i].Namelenth);
  317   3            memcpy(TX_Buff + pot + 6, pack_t->line[i].Number, sizeof(float));
  318   3            number++;
  319   3          }
  320   2          else if (pack_t->Mode[i] == 2) // ����+����
  321   2          {
  322   3            TX_Buff[pot] = 1 << 7;
  323   3            TX_Buff[pot] |= (pack_t->line[i].Row << 1) | (pack_t->line[i].Size);
  324   3            memcpy(TX_Buff + pot + 1, pack_t->line[i].Number, 2 * sizeof(float));
  325   3            number++;
  326   3          }
  327   2          else if (pack_t->Mode[i] == 3) // ����
  328   2          {
  329   3            TX_Buff[pot] = 0x70;
  330   3            TX_Buff[pot] |= (pack_t->line[i].Row << 1) | (pack_t->line[i].Size);
  331   3            number++;
  332   3          }
  333   2      
  334   2          pack_t->Mode[i] = 0; // ��ȡ���ݺ�������
  335   2        }
  336   1        if (number != 0) // ������
  337   1        {
  338   2          TX_Buff[0] = number * 10 + 1; // ֡ͷ
  339   2          crc = 0;
  340   2          for (i = 1; i < TX_Buff[0]; i++)
  341   2            crc += TX_Buff[i];
  342   2          TX_Buff[TX_Buff[0]] = crc; // ֡β
  343   2          if (nrf_mode != TX_MODE)
  344   2          {
  345   3            nrf_tx_mode();
  346   3          }
  347   2          // ����
  348   2          RF2G4_CE_LOW;
  349   2          nrf_writebuf(WR_TX_PLOAD, TX_Buff, TX_PACKET_LENTH);
  350   2          RF2G4_CE_HIGH;
  351   2        }
  352   1        if (label)
  353   1          label = 0;
  354   1        else
  355   1          label = 3;
  356   1      }
  357          
  358          //----------------------SPIд����----------------------------//
  359          void nrf_writereg(uint8_t reg, uint8_t dat)
  360          {
  361   1        RF2G4_CSN_LOW; // ʹ��SPI����
  362   1      
  363   1        SPI_ReadWriteByte(reg); // ���ͼĴ�����
  364   1        SPI_ReadWriteByte(dat); // д��Ĵ�����ֵ
  365   1      
  366   1        RF2G4_CSN_HIGH; // ��ֹSPI����
  367   1      }
  368          
  369          void nrf_writebuf(uint8_t reg, uint8_t *pBuf, uint16_t len) reentrant
  370          {
  371   1        uint16_t i;
  372   1        RF2G4_CSN_LOW; // ʹ��SPI����
  373   1      
  374   1        SPI_ReadWriteByte(reg); // ���ͼĴ�����
  375   1        for (i = 0; i < len; i++)
  376   1          SPI_ReadWriteByte(*(pBuf + i));
  377   1      
  378   1        RF2G4_CSN_HIGH; // ��ֹSPI����
  379   1      }
  380          
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 7   

  381          //----------------------SPI������----------------------------//
  382          uint8_t nrf_readreg(uint8_t reg)
  383          {
  384   1        uint8_t value;
  385   1        RF2G4_CSN_LOW; // ʹ��SPI����
  386   1      
  387   1        SPI_ReadWriteByte(reg);          // ���ͼĴ�����
  388   1        value = SPI_ReadWriteByte(0xFF); // ��ȡ�Ĵ�������
  389   1      
  390   1        RF2G4_CSN_HIGH; // ��ֹSPI����
  391   1      
  392   1        return value;
  393   1      }
  394          
  395          void nrf_readbuf(uint8_t reg, uint8_t *pBuf, uint16_t len) reentrant
  396          {
  397   1        uint16_t i;
  398   1        RF2G4_CSN_LOW; // ʹ��SPI����
  399   1      
  400   1        SPI_ReadWriteByte(reg); // ���ͼĴ���ֵ(λ��),����ȡ״ֵ̬
  401   1      
  402   1        for (i = 0; i < len; i++)
  403   1          *(pBuf + i) = SPI_ReadWriteByte(0xFF); // ��������
  404   1      
  405   1        RF2G4_CSN_HIGH; // �ر�SPI����
  406   1      }
  407          
  408          void P2_INT_ISR_Handler(void) interrupt P2INT_VECTOR
  409          {
  410   1        GPIO_EXTI_Flag_Read(GPIO_P2); // ��־λ��ֵ+��ձ�־λ
  411   1        if (Port_Exti_Flag[2])
  412   1        {
  413   2          GPIO_EXTI_Flag_Clear(GPIO_P2);
  414   2          if (Port_Exti_Flag[2] & Port_Pin_0)
  415   2          {
  416   3            // P2.0�ж�
  417   3          }
  418   2          if (Port_Exti_Flag[2] & Port_Pin_1)
  419   2          {
  420   3            // P2.1�ж�
  421   3          }
  422   2          if (Port_Exti_Flag[2] & Port_Pin_2)
  423   2          {
  424   3            // P2.2�ж�
  425   3          }
  426   2          if (Port_Exti_Flag[2] & Port_Pin_3)
  427   2          {
  428   3            // P2.3�ж�
  429   3          }
  430   2          if (Port_Exti_Flag[2] & Port_Pin_4)
  431   2          {
  432   3            // P2.4�ж�
  433   3          }
  434   2          if (Port_Exti_Flag[2] & Port_Pin_5)
  435   2          {
  436   3            // P2.5�ж�
  437   3          }
  438   2          if (Port_Exti_Flag[2] & Port_Pin_6)
  439   2          {
  440   3            // P2.6�ж�
  441   3            nrf_handler();
  442   3          }
  443   2          if (Port_Exti_Flag[2] & Port_Pin_7)
  444   2          {
  445   3            // P2.7�ж�
  446   3          }
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 8   

  447   2        }
  448   1      }
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 9   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION NRF24L01_Init? (BEGIN)
                                                ; SOURCE LINE # 93
                                                ; SOURCE LINE # 96
000000 7E140003       MOV      WR2,#03H
000004 7D31           MOV      WR6,WR2
000006 7E240010       MOV      WR4,#010H
00000A 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 97
00000E 7E340002       MOV      WR6,#02H
000012 7E240004       MOV      WR4,#04H
000016 7E140003       MOV      WR2,#03H
00001A 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 99
00001E 7E340002       MOV      WR6,#02H
000022 7E240010       MOV      WR4,#010H
000026 7E140001       MOV      WR2,#01H
00002A 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 100
00002E 7E340002       MOV      WR6,#02H
000032 7E240010       MOV      WR4,#010H
000036 6D11           XRL      WR2,WR2
000038 9A000000    E  ECALL    GPIO_PinPullConfig?
                                                ; SOURCE LINE # 102
00003C 7E340002       MOV      WR6,#02H
000040 7E240040       MOV      WR4,#040H
000044 7E140001       MOV      WR2,#01H
000048 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 103
00004C 7E340002       MOV      WR6,#02H
000050 7E240040       MOV      WR4,#040H
000054 6D11           XRL      WR2,WR2
000056 9A000000    E  ECALL    GPIO_EXTI_Init?
                                                ; SOURCE LINE # 104
00005A 7E340002       MOV      WR6,#02H
00005E 7E240040       MOV      WR4,#040H
000062 9A000000    E  ECALL    GPIO_EXTI_Open?
                                                ; SOURCE LINE # 105
000066 7E340002       MOV      WR6,#02H
00006A 6D22           XRL      WR4,WR4
00006C 9A000000    E  ECALL    GPIO_EXTI_Set_Priority?
                                                ; SOURCE LINE # 107
000070 7E340001       MOV      WR6,#01H
000074 E4             CLR      A                ; A=R11
000075 6C55           XRL      R5,R5
000077 6C44           XRL      R4,R4
000079 6C33           XRL      R3,R3
00007B 6C22           XRL      R2,R2
00007D 7E1001         MOV      R1,#01H
000080 7E0001         MOV      R0,#01H
000083 9A000000    E  ECALL    SPI_Init?
                                                ; SOURCE LINE # 109
000087 7E730000    E  MOV      R7,Channal
00008B 7A730000    R  MOV      RX_ADDRESS+4,R7
                                                ; SOURCE LINE # 110
00008F 7A730000    R  MOV      TX_ADDRESS+4,R7
                                                ; SOURCE LINE # 113
000093 7E340003       MOV      WR6,#03H
000097 7E240010       MOV      WR4,#010H
00009B E4             CLR      A                ; A=R11
00009C 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 115
0000A0 7423           MOV      A,#023H          ; A=R11
0000A2 7E7003         MOV      R7,#03H
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 10  

0000A5 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 117
0000A9 7425           MOV      A,#025H          ; A=R11
0000AB 7E730000    E  MOV      R7,Channal
0000AF 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 123
0000B3 7426           MOV      A,#026H          ; A=R11
0000B5 7E7006         MOV      R7,#06H
0000B8 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 127
0000BC 7421           MOV      A,#021H          ; A=R11
0000BE 7E7001         MOV      R7,#01H
0000C1 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 129
0000C5 7422           MOV      A,#022H          ; A=R11
0000C7 7E7001         MOV      R7,#01H
0000CA 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 132
0000CE 7E000000    R  MOV      DR0,#WORD0 RX_ADDRESS
0000D2 7E340005       MOV      WR6,#05H
0000D6 742A           MOV      A,#02AH          ; A=R11
0000D8 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 134
0000DC 7431           MOV      A,#031H          ; A=R11
0000DE 7E700C         MOV      R7,#0CH
0000E1 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 136
0000E5 74E2           MOV      A,#0E2H          ; A=R11
0000E7 7E70FF         MOV      R7,#0FFH
0000EA 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 139
0000EE 7E000000    R  MOV      DR0,#WORD0 TX_ADDRESS
0000F2 7E340005       MOV      WR6,#05H
0000F6 7430           MOV      A,#030H          ; A=R11
0000F8 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 141
0000FC 7424           MOV      A,#024H          ; A=R11
0000FE 7E7005         MOV      R7,#05H
000101 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 143
000105 74E1           MOV      A,#0E1H          ; A=R11
000107 7E70FF         MOV      R7,#0FFH
00010A 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 145
00010E 9A000000    R  ECALL    nrf_rx_mode?
                                                ; SOURCE LINE # 147
000112 7E340003       MOV      WR6,#03H
000116 7E240010       MOV      WR4,#010H
00011A 7401           MOV      A,#01H           ; A=R11
00011C 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 149
000120 8A000000    R  EJMP     nrf_link_check?
;       FUNCTION NRF24L01_Init? (END)

;       FUNCTION nrf_link_check? (BEGIN)
                                                ; SOURCE LINE # 155
                                                ; SOURCE LINE # 156
                                                ; SOURCE LINE # 161
000124 7E540000    R  MOV      WR10,#WORD0 ?tpl?0001
000128 7E440000    R  MOV      WR8,#WORD2 ?tpl?0001
00012C 69320003       MOV      WR6,@DR8+0x3
000130 69220001       MOV      WR4,@DR8+0x1
000134 7E2B30         MOV      R3,@DR8
000137 7A1F0000    R  MOV      buff+1,DR4
00013B 7A330000    R  MOV      buff,R3
                                                ; SOURCE LINE # 164
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 11  

                                                ; SOURCE LINE # 166
00013F 7E340003       MOV      WR6,#03H
000143 7E240010       MOV      WR4,#010H
000147 E4             CLR      A                ; A=R11
000148 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 168
00014C 7E000000    R  MOV      DR0,#WORD0 buff
000150 7430           MOV      A,#030H          ; A=R11
000152 7E340005       MOV      WR6,#05H
000156 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 171
                                                ; SOURCE LINE # 172
00015A 7E000000    R  MOV      DR0,#WORD0 buff
00015E 7410           MOV      A,#010H          ; A=R11
000160 7E340005       MOV      WR6,#05H
000164 9A000000    R  ECALL    nrf_readbuf??
                                                ; SOURCE LINE # 174
000168 7E340003       MOV      WR6,#03H
00016C 7E240010       MOV      WR4,#010H
000170 7401           MOV      A,#01H           ; A=R11
000172 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 176
000176 6CAA           XRL      R10,R10
;---- Variable 'i' assigned to Register 'R10' ----
               ?C0005:
                                                ; SOURCE LINE # 178
000178 0A3A           MOVZ     WR6,R10
00017A 09B30000    R  MOV      R11,@WR6+buff    ; A=R11
00017E BEB006         CMP      R11,#06H         ; A=R11
000181 6802           JE       ?C0002
                                                ; SOURCE LINE # 180
000183 E4             CLR      A                ; A=R11
000184 AA             ERET     
                                                ; SOURCE LINE # 181
               ?C0002:
000185 0BA0           INC      R10,#01H
000187 BEA005         CMP      R10,#05H
00018A 40EC           JC       ?C0005
                                                ; SOURCE LINE # 183
00018C 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 184
00018E AA             ERET     
;       FUNCTION nrf_link_check? (END)

;       FUNCTION nrf_rx_mode? (BEGIN)
                                                ; SOURCE LINE # 190
                                                ; SOURCE LINE # 192
00018F 7E340003       MOV      WR6,#03H
000193 7E240010       MOV      WR4,#010H
000197 E4             CLR      A                ; A=R11
000198 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 194
00019C 7421           MOV      A,#021H          ; A=R11
00019E 7E7001         MOV      R7,#01H
0001A1 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 196
0001A5 7422           MOV      A,#022H          ; A=R11
0001A7 7E7001         MOV      R7,#01H
0001AA 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 198
0001AE 7E000000    R  MOV      DR0,#WORD0 RX_ADDRESS
0001B2 7E340005       MOV      WR6,#05H
0001B6 742A           MOV      A,#02AH          ; A=R11
0001B8 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 200
0001BC 7420           MOV      A,#020H          ; A=R11
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 12  

0001BE 7E700F         MOV      R7,#0FH
0001C1 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 203
0001C5 7427           MOV      A,#027H          ; A=R11
0001C7 7E70FF         MOV      R7,#0FFH
0001CA 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 205
0001CE 74E2           MOV      A,#0E2H          ; A=R11
0001D0 7E70FF         MOV      R7,#0FFH
0001D3 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 207
0001D7 7E340003       MOV      WR6,#03H
0001DB 7E240010       MOV      WR4,#010H
0001DF 7401           MOV      A,#01H           ; A=R11
0001E1 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 209
0001E5 7402           MOV      A,#02H           ; A=R11
0001E7 7AB30000    R  MOV      nrf_mode,R11     ; A=R11
                                                ; SOURCE LINE # 210
0001EB AA             ERET     
;       FUNCTION nrf_rx_mode? (END)

;       FUNCTION nrf_tx_mode? (BEGIN)
                                                ; SOURCE LINE # 216
                                                ; SOURCE LINE # 218
0001EC 7E340003       MOV      WR6,#03H
0001F0 7E240010       MOV      WR4,#010H
0001F4 E4             CLR      A                ; A=R11
0001F5 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 220
0001F9 7E000000    R  MOV      DR0,#WORD0 TX_ADDRESS
0001FD 7E340005       MOV      WR6,#05H
000201 7430           MOV      A,#030H          ; A=R11
000203 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 222
000207 7E000000    R  MOV      DR0,#WORD0 RX_ADDRESS
00020B 7E340005       MOV      WR6,#05H
00020F 742A           MOV      A,#02AH          ; A=R11
000211 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 224
000215 7420           MOV      A,#020H          ; A=R11
000217 7E700E         MOV      R7,#0EH
00021A 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 226
00021E 7E340003       MOV      WR6,#03H
000222 7E240010       MOV      WR4,#010H
000226 7401           MOV      A,#01H           ; A=R11
000228 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 228
00022C 7401           MOV      A,#01H           ; A=R11
00022E 7AB30000    R  MOV      nrf_mode,R11     ; A=R11
                                                ; SOURCE LINE # 230
000232 7E340019       MOV      WR6,#019H
000236 8A000000    E  EJMP     Ms_Delay?
;       FUNCTION nrf_tx_mode? (END)

;       FUNCTION nrf_tx_packet? (BEGIN)
                                                ; SOURCE LINE # 234
00023A CA3B           PUSH     DR12
00023C 7AB30000    R  MOV      len,R11          ; A=R11
000240 7F30           MOV      DR12,DR0
;---- Variable 'txbuf' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 235
                                                ; SOURCE LINE # 236
000242 E4             CLR      A                ; A=R11
000243 7AB30000    R  MOV      crc,R11          ; A=R11
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 13  

                                                ; SOURCE LINE # 238
000247 BE380000       CMP      DR12,#00H
00024B 7803        R  JNE      $ + 5H
00024D 020000      R  LJMP     ?C0011
000250 7E730000    R  MOV      R7,len
000254 BE7000         CMP      R7,#00H
000257 2879           JLE      ?C0011
                                                ; SOURCE LINE # 239
                                                ; SOURCE LINE # 240
000259 0A37           MOVZ     WR6,R7
00025B 7D23           MOV      WR4,WR6
00025D 0B24           INC      WR4,#01H
00025F 7A530000    R  MOV      TX_Buff,R5
                                                ; SOURCE LINE # 241
000263 CA39           PUSH     WR6
000265 7F13           MOV      DR4,DR12
000267 7E000000    R  MOV      DR0,#WORD0 TX_Buff+1
00026B 9A000000    E  ECALL    memcpy??
00026F 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 242
000271 6D33           XRL      WR6,WR6
;---- Variable 'i' assigned to Register 'WR6' ----
000273 8011           SJMP     ?C0014
               ?C0015:
                                                ; SOURCE LINE # 243
000275 7F03           MOV      DR0,DR12
000277 2D13           ADD      WR2,WR6
000279 7E0B50         MOV      R5,@DR0
00027C 2E530000    R  ADD      R5,crc
000280 7A530000    R  MOV      crc,R5
000284 0B34           INC      WR6,#01H
               ?C0014:
000286 7E530000    R  MOV      R5,len
00028A 0A25           MOVZ     WR4,R5
00028C BD23           CMP      WR4,WR6
00028E 18E5           JSG      ?C0015
                                                ; SOURCE LINE # 244
000290 7E730000    R  MOV      R7,crc
000294 19720000    R  MOV      @WR4+TX_Buff+0x1,R7
                                                ; SOURCE LINE # 246
000298 7EB30000    R  MOV      R11,nrf_mode     ; A=R11
00029C BEB001         CMP      R11,#01H         ; A=R11
00029F 6804           JE       ?C0017
                                                ; SOURCE LINE # 248
0002A1 9A000000    R  ECALL    nrf_tx_mode?
                                                ; SOURCE LINE # 249
               ?C0017:
                                                ; SOURCE LINE # 250
0002A5 7E340003       MOV      WR6,#03H
0002A9 7E240010       MOV      WR4,#010H
0002AD E4             CLR      A                ; A=R11
0002AE 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 251
0002B2 7E730000    R  MOV      R7,len
0002B6 0A37           MOVZ     WR6,R7
0002B8 0B35           INC      WR6,#02H
0002BA 7E000000    R  MOV      DR0,#WORD0 TX_Buff
0002BE 74A0           MOV      A,#0A0H          ; A=R11
0002C0 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 252
0002C4 7E340003       MOV      WR6,#03H
0002C8 7E240010       MOV      WR4,#010H
0002CC 7401           MOV      A,#01H           ; A=R11
0002CE 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 253
               ?C0011:
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 14  

0002D2 DA3B           POP      DR12
0002D4 AA             ERET     
;       FUNCTION nrf_tx_packet? (END)

;       FUNCTION nrf_handler? (BEGIN)
                                                ; SOURCE LINE # 255
0002D5 CAF8           PUSH     R15
                                                ; SOURCE LINE # 256
                                                ; SOURCE LINE # 260
0002D7 7407           MOV      A,#07H           ; A=R11
0002D9 9A000000    R  ECALL    nrf_readreg?
0002DD 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'state' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 263
0002DF 7427           MOV      A,#027H          ; A=R11
0002E1 7C7F           MOV      R7,R15
0002E3 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 265
0002E7 7CBF           MOV      R11,R15          ; A=R11
0002E9 30E631         JNB      ACC.6,?C0018
                                                ; SOURCE LINE # 268
0002EC 7E340003       MOV      WR6,#03H
0002F0 7E240010       MOV      WR4,#010H
0002F4 E4             CLR      A                ; A=R11
0002F5 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 269
0002F9 7E000000    R  MOV      DR0,#WORD0 RX_Buff
0002FD 7E34000C       MOV      WR6,#0CH
000301 7461           MOV      A,#061H          ; A=R11
000303 9A000000    R  ECALL    nrf_readbuf??
                                                ; SOURCE LINE # 270
000307 7E000000    R  MOV      DR0,#WORD0 RX_Buff
00030B 9A000000    E  ECALL    Rc_unpack_data?
                                                ; SOURCE LINE # 271
00030F 7E340003       MOV      WR6,#03H
000313 7E240010       MOV      WR4,#010H
000317 7401           MOV      A,#01H           ; A=R11
000319 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 272
               ?C0018:
                                                ; SOURCE LINE # 274
00031D 7CBF           MOV      R11,R15          ; A=R11
00031F 30E516         JNB      ACC.5,?C0019
                                                ; SOURCE LINE # 277
000322 74E1           MOV      A,#0E1H          ; A=R11
000324 7E70FF         MOV      R7,#0FFH
000327 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 279
00032B 7EB30000    R  MOV      R11,nrf_mode     ; A=R11
00032F BEB002         CMP      R11,#02H         ; A=R11
000332 6804           JE       ?C0019
                                                ; SOURCE LINE # 281
000334 9A000000    R  ECALL    nrf_rx_mode?
                                                ; SOURCE LINE # 282
               ?C0019:
                                                ; SOURCE LINE # 285
000338 7CBF           MOV      R11,R15          ; A=R11
00033A 30E416         JNB      ACC.4,?C0021
                                                ; SOURCE LINE # 288
00033D 74E1           MOV      A,#0E1H          ; A=R11
00033F 7E70FF         MOV      R7,#0FFH
000342 9A000000    R  ECALL    nrf_writereg?
                                                ; SOURCE LINE # 290
000346 7EB30000    R  MOV      R11,nrf_mode     ; A=R11
00034A BEB002         CMP      R11,#02H         ; A=R11
00034D 6804           JE       ?C0021
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 15  

                                                ; SOURCE LINE # 292
00034F 9A000000    R  ECALL    nrf_rx_mode?
                                                ; SOURCE LINE # 293
               ?C0021:
                                                ; SOURCE LINE # 296
                                                ; SOURCE LINE # 298
000353 DAF8           POP      R15
000355 AA             ERET     
;       FUNCTION nrf_handler? (END)

;       FUNCTION RCPacket_Send? (BEGIN)
                                                ; SOURCE LINE # 303
000356 CA3B           PUSH     DR12
                                                ; SOURCE LINE # 304
                                                ; SOURCE LINE # 306
000358 E4             CLR      A                ; A=R11
000359 7AB30000    R  MOV      crc,R11          ; A=R11
                                                ; SOURCE LINE # 307
00035D 9A000000    E  ECALL    get_sendpack_point?
000361 7F31           MOV      DR12,DR4
;---- Variable 'pack_t' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 308
000363 6D33           XRL      WR6,WR6
000365 7A370000    R  MOV      number,WR6
                                                ; SOURCE LINE # 309
000369 7E730000    R  MOV      R7,label
00036D 020000      R  LJMP     ?C0064
               ?C0027:
                                                ; SOURCE LINE # 310
                                                ; SOURCE LINE # 311
000370 7E270000    R  MOV      WR4,number
000374 7E34000A       MOV      WR6,#0AH
000378 AD32           MUL      WR6,WR4
00037A 0B34           INC      WR6,#01H
00037C 7A370000    R  MOV      pot,WR6
                                                ; SOURCE LINE # 312
000380 7F13           MOV      DR4,DR12
000382 2E370000    R  ADD      WR6,i
000386 29B10060       MOV      R11,@DR4+0x60    ; A=R11
00038A B40172         CJNE     A,#01H,?C0029    ; A=R11
                                                ; SOURCE LINE # 314
00038D E4             CLR      A                ; A=R11
00038E 7E170000    R  MOV      WR2,pot
000392 19B10000    R  MOV      @WR2+TX_Buff,R11 ; A=R11
                                                ; SOURCE LINE # 315
000396 7E070000    R  MOV      WR0,i
00039A 3E04           SLL      WR0
00039C 3E04           SLL      WR0
00039E 3E04           SLL      WR0
0003A0 3E04           SLL      WR0
0003A2 7F13           MOV      DR4,DR12
0003A4 2D30           ADD      WR6,WR0
0003A6 2911000E       MOV      R1,@DR4+0xE
0003AA 3E10           SLL      R1
0003AC 29A10005       MOV      R10,@DR4+0x5
0003B0 7CBA           MOV      R11,R10          ; A=R11
0003B2 C4             SWAP     A                ; A=R11
0003B3 54F0           ANL      A,#0F0H          ; A=R11
0003B5 4CB1           ORL      R11,R1           ; A=R11
0003B7 2991000F       MOV      R9,@DR4+0xF
0003BB 4C9B           ORL      R9,R11           ; A=R11
0003BD 7D01           MOV      WR0,WR2
0003BF 2E040000    R  ADD      WR0,#WORD0 TX_Buff
0003C3 7E09B0         MOV      R11,@WR0         ; A=R11
0003C6 4CB9           ORL      R11,R9           ; A=R11
0003C8 7A09B0         MOV      @WR0,R11         ; A=R11
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 16  

                                                ; SOURCE LINE # 316
0003CB 0A0A           MOVZ     WR0,R10
0003CD CA09           PUSH     WR0
0003CF 2E140000    R  ADD      WR2,#WORD0 TX_Buff+1
0003D3 6D00           XRL      WR0,WR0
0003D5 9A000000    E  ECALL    memcpy??
0003D9 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 317
0003DB 7E340004       MOV      WR6,#04H
0003DF CA39           PUSH     WR6
0003E1 7E370000    R  MOV      WR6,i
0003E5 3E34           SLL      WR6
0003E7 3E34           SLL      WR6
0003E9 3E34           SLL      WR6
0003EB 3E34           SLL      WR6
0003ED 2D37           ADD      WR6,WR14
0003EF 7D26           MOV      WR4,WR12
0003F1 2E340006       ADD      WR6,#06H
0003F5 7E170000    R  MOV      WR2,pot
0003F9 2E140000    R  ADD      WR2,#WORD0 TX_Buff+6
                                                ; SOURCE LINE # 318
                                                ; SOURCE LINE # 319
0003FD 804F           SJMP     ?C0065
               ?C0029:
                                                ; SOURCE LINE # 320
0003FF 7F13           MOV      DR4,DR12
000401 2E370000    R  ADD      WR6,i
000405 29B10060       MOV      R11,@DR4+0x60    ; A=R11
000409 B4024C         CJNE     A,#02H,?C0031    ; A=R11
                                                ; SOURCE LINE # 322
00040C 7480           MOV      A,#080H          ; A=R11
00040E 7E170000    R  MOV      WR2,pot
000412 19B10000    R  MOV      @WR2+TX_Buff,R11 ; A=R11
                                                ; SOURCE LINE # 323
000416 7E070000    R  MOV      WR0,i
00041A 3E04           SLL      WR0
00041C 3E04           SLL      WR0
00041E 3E04           SLL      WR0
000420 3E04           SLL      WR0
000422 7F13           MOV      DR4,DR12
000424 2D30           ADD      WR6,WR0
000426 2911000E       MOV      R1,@DR4+0xE
00042A 3E10           SLL      R1
00042C 2901000F       MOV      R0,@DR4+0xF
000430 4C01           ORL      R0,R1
000432 7D51           MOV      WR10,WR2
000434 2E540000    R  ADD      WR10,#WORD0 TX_Buff
000438 7E5910         MOV      R1,@WR10
00043B 4C10           ORL      R1,R0
00043D 7A5910         MOV      @WR10,R1
                                                ; SOURCE LINE # 324
000440 7E040008       MOV      WR0,#08H
000444 CA09           PUSH     WR0
000446 2E340006       ADD      WR6,#06H
00044A 2E140000    R  ADD      WR2,#WORD0 TX_Buff+1
               ?C0065:
00044E 6D00           XRL      WR0,WR0
000450 9A000000    E  ECALL    memcpy??
000454 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 325
                                                ; SOURCE LINE # 326
000456 803F           SJMP     ?C0066
               ?C0031:
                                                ; SOURCE LINE # 327
000458 7F13           MOV      DR4,DR12
00045A 2E370000    R  ADD      WR6,i
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 17  

00045E 29B10060       MOV      R11,@DR4+0x60    ; A=R11
000462 B4033C         CJNE     A,#03H,?C0030    ; A=R11
                                                ; SOURCE LINE # 329
000465 7470           MOV      A,#070H          ; A=R11
000467 7E270000    R  MOV      WR4,pot
00046B 19B20000    R  MOV      @WR4+TX_Buff,R11 ; A=R11
                                                ; SOURCE LINE # 330
00046F 7E370000    R  MOV      WR6,i
000473 3E34           SLL      WR6
000475 3E34           SLL      WR6
000477 3E34           SLL      WR6
000479 3E34           SLL      WR6
00047B 7F03           MOV      DR0,DR12
00047D 2D13           ADD      WR2,WR6
00047F 2970000E       MOV      R7,@DR0+0xE
000483 3E70           SLL      R7
000485 2960000F       MOV      R6,@DR0+0xF
000489 4C67           ORL      R6,R7
00048B 2E240000    R  ADD      WR4,#WORD0 TX_Buff
00048F 7E2970         MOV      R7,@WR4
000492 4C76           ORL      R7,R6
000494 7A2970         MOV      @WR4,R7
                                                ; SOURCE LINE # 331
               ?C0066:
000497 7E370000    R  MOV      WR6,number
00049B 0B34           INC      WR6,#01H
00049D 7A370000    R  MOV      number,WR6
                                                ; SOURCE LINE # 332
               ?C0030:
                                                ; SOURCE LINE # 334
0004A1 E4             CLR      A                ; A=R11
0004A2 7F13           MOV      DR4,DR12
0004A4 2E370000    R  ADD      WR6,i
0004A8 39B10060       MOV      @DR4+0x60,R11    ; A=R11
                                                ; SOURCE LINE # 335
0004AC 7E370000    R  MOV      WR6,i
0004B0 0B34           INC      WR6,#01H
               ?C0064:
0004B2 7A370000    R  MOV      i,WR6
               ?C0026:
0004B6 7E730000    R  MOV      R7,label
0004BA 0A37           MOVZ     WR6,R7
0004BC 2E340003       ADD      WR6,#03H
0004C0 BE370000    R  CMP      WR6,i
0004C4 0803        R  JSLE     $ + 5H
0004C6 020000      R  LJMP     ?C0027
                                                ; SOURCE LINE # 336
0004C9 7E270000    R  MOV      WR4,number
0004CD 4D22           ORL      WR4,WR4
0004CF 6877           JE       ?C0034
                                                ; SOURCE LINE # 338
0004D1 7E34000A       MOV      WR6,#0AH
0004D5 AD32           MUL      WR6,WR4
0004D7 0B34           INC      WR6,#01H
0004D9 7A730000    R  MOV      TX_Buff,R7
                                                ; SOURCE LINE # 339
0004DD E4             CLR      A                ; A=R11
0004DE 7AB30000    R  MOV      crc,R11          ; A=R11
                                                ; SOURCE LINE # 340
0004E2 7E340001       MOV      WR6,#01H
0004E6 8012           SJMP     ?C0067
               ?C0038:
                                                ; SOURCE LINE # 341
0004E8 7E370000    R  MOV      WR6,i
0004EC 09530000    R  MOV      R5,@WR6+TX_Buff
0004F0 2E530000    R  ADD      R5,crc
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 18  

0004F4 7A530000    R  MOV      crc,R5
0004F8 0B34           INC      WR6,#01H
               ?C0067:
0004FA 7A370000    R  MOV      i,WR6
               ?C0037:
0004FE 7E730000    R  MOV      R7,TX_Buff
000502 0A27           MOVZ     WR4,R7
000504 BE270000    R  CMP      WR4,i
000508 18DE           JSG      ?C0038
                                                ; SOURCE LINE # 342
00050A 7E730000    R  MOV      R7,crc
00050E 19720000    R  MOV      @WR4+TX_Buff,R7
                                                ; SOURCE LINE # 343
000512 7EB30000    R  MOV      R11,nrf_mode     ; A=R11
000516 BEB001         CMP      R11,#01H         ; A=R11
000519 6804           JE       ?C0040
                                                ; SOURCE LINE # 345
00051B 9A000000    R  ECALL    nrf_tx_mode?
                                                ; SOURCE LINE # 346
               ?C0040:
                                                ; SOURCE LINE # 348
00051F 7E340003       MOV      WR6,#03H
000523 7E240010       MOV      WR4,#010H
000527 E4             CLR      A                ; A=R11
000528 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 349
00052C 7E000000    R  MOV      DR0,#WORD0 TX_Buff
000530 7E340020       MOV      WR6,#020H
000534 74A0           MOV      A,#0A0H          ; A=R11
000536 9A000000    R  ECALL    nrf_writebuf??
                                                ; SOURCE LINE # 350
00053A 7E340003       MOV      WR6,#03H
00053E 7E240010       MOV      WR4,#010H
000542 7401           MOV      A,#01H           ; A=R11
000544 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 351
               ?C0034:
                                                ; SOURCE LINE # 352
000548 7EB30000    R  MOV      R11,label        ; A=R11
00054C 6003           JZ       ?C0041
                                                ; SOURCE LINE # 353
00054E E4             CLR      A                ; A=R11
00054F 8002           SJMP     ?C0063
               ?C0041:
                                                ; SOURCE LINE # 355
000551 7403           MOV      A,#03H           ; A=R11
               ?C0063:
000553 7AB30000    R  MOV      label,R11        ; A=R11
                                                ; SOURCE LINE # 356
000557 DA3B           POP      DR12
000559 AA             ERET     
;       FUNCTION RCPacket_Send? (END)

;       FUNCTION nrf_writereg? (BEGIN)
                                                ; SOURCE LINE # 359
00055A CA79           PUSH     WR14
00055C 7CF7           MOV      R15,R7
;---- Variable 'dat' assigned to Register 'R15' ----
00055E 7CEB           MOV      R14,R11          ; A=R11
;---- Variable 'reg' assigned to Register 'R14' ----
                                                ; SOURCE LINE # 361
000560 7E340002       MOV      WR6,#02H
000564 7E240004       MOV      WR4,#04H
000568 E4             CLR      A                ; A=R11
000569 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 363
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 19  

00056D 7CBE           MOV      R11,R14          ; A=R11
00056F 9A000000    E  ECALL    SPI_ReadWriteByte?
                                                ; SOURCE LINE # 364
000573 7CBF           MOV      R11,R15          ; A=R11
000575 9A000000    E  ECALL    SPI_ReadWriteByte?
                                                ; SOURCE LINE # 366
000579 7E340002       MOV      WR6,#02H
00057D 7E240004       MOV      WR4,#04H
000581 7401           MOV      A,#01H           ; A=R11
000583 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 367
000587 DA79           POP      WR14
000589 AA             ERET     
;       FUNCTION nrf_writereg? (END)

;       FUNCTION nrf_writebuf?? (BEGIN)
                                                ; SOURCE LINE # 369
00058A CA3B           PUSH     DR12
00058C CA39           PUSH     WR6
00058E 7F30           MOV      DR12,DR0
;---- Variable 'pBuf' assigned to Register 'DR12' ----
000590 CAB8           PUSH     R11              ; A=R11
000592 0BFD           INC      DR60,#02H
                                                ; SOURCE LINE # 370
                                                ; SOURCE LINE # 372
000594 7E340002       MOV      WR6,#02H
000598 7E240004       MOV      WR4,#04H
00059C E4             CLR      A                ; A=R11
00059D 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 374
0005A1 29BFFFFE       MOV      R11,@DR60-0x2    ; reg
0005A5 9A000000    E  ECALL    SPI_ReadWriteByte?
                                                ; SOURCE LINE # 375
0005A9 6D33           XRL      WR6,WR6
0005AB 8015           SJMP     ?C0068
               ?C0046:
                                                ; SOURCE LINE # 376
0005AD 693FFFFF       MOV      WR6,@DR60-0x1    ; i
0005B1 2D37           ADD      WR6,WR14
0005B3 7D26           MOV      WR4,WR12
0005B5 7E1BB0         MOV      R11,@DR4         ; A=R11
0005B8 9A000000    E  ECALL    SPI_ReadWriteByte?
0005BC 693FFFFF       MOV      WR6,@DR60-0x1    ; i
0005C0 0B34           INC      WR6,#01H
               ?C0068:
0005C2 793FFFFF       MOV      @DR60-0x1,WR6    ; i
               ?C0045:
0005C6 692FFFFC       MOV      WR4,@DR60-0x4    ; len
0005CA 693FFFFF       MOV      WR6,@DR60-0x1    ; i
0005CE BD32           CMP      WR6,WR4
0005D0 40DB           JC       ?C0046
                                                ; SOURCE LINE # 378
0005D2 7E340002       MOV      WR6,#02H
0005D6 7E240004       MOV      WR4,#04H
0005DA 7401           MOV      A,#01H           ; A=R11
0005DC 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 379
0005E0 9EF80005       SUB      DR60,#05H
0005E4 DA3B           POP      DR12
0005E6 AA             ERET     
;       FUNCTION nrf_writebuf?? (END)

;       FUNCTION nrf_readreg? (BEGIN)
                                                ; SOURCE LINE # 382
0005E7 CAF8           PUSH     R15
0005E9 7CFB           MOV      R15,R11          ; A=R11
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 20  

;---- Variable 'reg' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 383
                                                ; SOURCE LINE # 385
0005EB 7E340002       MOV      WR6,#02H
0005EF 7E240004       MOV      WR4,#04H
0005F3 E4             CLR      A                ; A=R11
0005F4 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 387
0005F8 7CBF           MOV      R11,R15          ; A=R11
0005FA 9A000000    E  ECALL    SPI_ReadWriteByte?
                                                ; SOURCE LINE # 388
0005FE 74FF           MOV      A,#0FFH          ; A=R11
000600 9A000000    E  ECALL    SPI_ReadWriteByte?
000604 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'value' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 390
000606 7E340002       MOV      WR6,#02H
00060A 7E240004       MOV      WR4,#04H
00060E 7401           MOV      A,#01H           ; A=R11
000610 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 392
000614 7CBF           MOV      R11,R15          ; A=R11
                                                ; SOURCE LINE # 393
000616 DAF8           POP      R15
000618 AA             ERET     
;       FUNCTION nrf_readreg? (END)

;       FUNCTION nrf_readbuf?? (BEGIN)
                                                ; SOURCE LINE # 395
000619 CA3B           PUSH     DR12
00061B CA39           PUSH     WR6
00061D 7F30           MOV      DR12,DR0
;---- Variable 'pBuf' assigned to Register 'DR12' ----
00061F CAB8           PUSH     R11              ; A=R11
000621 0BFD           INC      DR60,#02H
                                                ; SOURCE LINE # 396
                                                ; SOURCE LINE # 398
000623 7E340002       MOV      WR6,#02H
000627 7E240004       MOV      WR4,#04H
00062B E4             CLR      A                ; A=R11
00062C 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 400
000630 29BFFFFE       MOV      R11,@DR60-0x2    ; reg
000634 9A000000    E  ECALL    SPI_ReadWriteByte?
                                                ; SOURCE LINE # 402
000638 6D33           XRL      WR6,WR6
00063A 8017           SJMP     ?C0069
               ?C0052:
                                                ; SOURCE LINE # 403
00063C 74FF           MOV      A,#0FFH          ; A=R11
00063E 9A000000    E  ECALL    SPI_ReadWriteByte?
000642 693FFFFF       MOV      WR6,@DR60-0x1    ; i
000646 2D37           ADD      WR6,WR14
000648 7D26           MOV      WR4,WR12
00064A 7A1BB0         MOV      @DR4,R11         ; A=R11
00064D 693FFFFF       MOV      WR6,@DR60-0x1    ; i
000651 0B34           INC      WR6,#01H
               ?C0069:
000653 793FFFFF       MOV      @DR60-0x1,WR6    ; i
               ?C0051:
000657 692FFFFC       MOV      WR4,@DR60-0x4    ; len
00065B 693FFFFF       MOV      WR6,@DR60-0x1    ; i
00065F BD32           CMP      WR6,WR4
000661 40D9           JC       ?C0052
                                                ; SOURCE LINE # 405
000663 7E340002       MOV      WR6,#02H
C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 21  

000667 7E240004       MOV      WR4,#04H
00066B 7401           MOV      A,#01H           ; A=R11
00066D 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 406
000671 9EF80005       SUB      DR60,#05H
000675 DA3B           POP      DR12
000677 AA             ERET     
;       FUNCTION nrf_readbuf?? (END)

;       FUNCTION P2_INT_ISR_Handler? (BEGIN)
                                                ; SOURCE LINE # 408
000678 CA7B           PUSH     DR28
00067A CA6B           PUSH     DR24
00067C CA5B           PUSH     DR20
00067E CA4B           PUSH     DR16
000680 CA2B           PUSH     DR8
000682 CA1B           PUSH     DR4
000684 CA0B           PUSH     DR0
000686 C0D0           PUSH     PSW
000688 C083           PUSH     DPH              ; WORD0(DR56)=DPTR
00068A C082           PUSH     DPL              ; WORD0(DR56)=DPTR
                                                ; SOURCE LINE # 410
00068C 7E340002       MOV      WR6,#02H
000690 9A000000    E  ECALL    GPIO_EXTI_Flag_Read?
                                                ; SOURCE LINE # 411
000694 7EB30000    E  MOV      R11,Port_Exti_Flag+2
000698 6013           JZ       ?C0054
                                                ; SOURCE LINE # 413
00069A 7E340002       MOV      WR6,#02H
00069E 9A000000    E  ECALL    GPIO_EXTI_Flag_Clear?
                                                ; SOURCE LINE # 414
                                                ; SOURCE LINE # 417
                                                ; SOURCE LINE # 418
                                                ; SOURCE LINE # 421
                                                ; SOURCE LINE # 422
                                                ; SOURCE LINE # 425
                                                ; SOURCE LINE # 426
                                                ; SOURCE LINE # 429
                                                ; SOURCE LINE # 430
                                                ; SOURCE LINE # 433
                                                ; SOURCE LINE # 434
                                                ; SOURCE LINE # 437
                                                ; SOURCE LINE # 438
0006A2 7EB30000    E  MOV      R11,Port_Exti_Flag+2
0006A6 30E604         JNB      ACC.6,?C0054
                                                ; SOURCE LINE # 441
0006A9 9A000000    R  ECALL    nrf_handler?
                                                ; SOURCE LINE # 442
                                                ; SOURCE LINE # 443
                                                ; SOURCE LINE # 446
               ?C0054:
                                                ; SOURCE LINE # 448
0006AD D082           POP      DPL              ; WORD0(DR56)=DPTR
0006AF D083           POP      DPH              ; WORD0(DR56)=DPTR
0006B1 D0D0           POP      PSW
0006B3 DA0B           POP      DR0
0006B5 DA1B           POP      DR4
0006B7 DA2B           POP      DR8
0006B9 DA4B           POP      DR16
0006BB DA5B           POP      DR20
0006BD DA6B           POP      DR24
0006BF DA7B           POP      DR28
0006C1 32             RETI     
;       FUNCTION P2_INT_ISR_Handler? (END)


C251 COMPILER V5.60.0,  nrf24l01                                                           24/08/26  10:23:43  PAGE 22  


Module Information          Static   Overlayable
------------------------------------------------
  code size            =         4     ------
  ecode size           =      1730     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =        58         14
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        39     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)
