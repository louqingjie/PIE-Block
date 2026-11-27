/*---------------------------------------------------------------------*/
/* --- STC MCU Limited ------------------------------------------------*/
/* --- STC 1T Series MCU Demo Programme ------------------------------- */
/* 如果要在程序中使用此代码,请在程序中注明使用了STC的资料及程序        */
/*---------------------------------------------------------------------*/

/*
 * UART2 <-> USB CDC 桥。
 *
 * 相对 STC 官方 70-CDC 例程的改动：
 * - S2_S / S2TI / S2RI / S2TB8 / ES2 / T2x12 / T2R 全部改成字节掩码；
 * - UART2 固定 P1.0/P1.1、115200 8N1，不跟随电脑端 line coding；
 * - 环形缓冲增加满检查，回绕判断统一用 (BYTE)(w - r)；
 * - ISR 共享变量加 volatile。
 */

#include "main.h"
#include "usb.h"
#include "usb_req_class.h"

volatile BOOL UartBusy = 0;
volatile BYTE TxOverflow = 0;
volatile BYTE RxOverflow = 0;

void uart_init(void)
{
#if (CDC_UART_PIN_GROUP == 0)
    /* UART2: P1.0 = RX, P1.1 = TX。 */
    P_SW2 &= ~0x01;
    P1M0 &= ~0x03;
    P1M1 &= ~0x03;
#else
    /* UART2: P4.6 = RX, P4.7 = TX。 */
    P_SW2 |= 0x01;
    P4M0 &= ~0xc0;
    P4M1 &= ~0xc0;
#endif

    S2CON = 0x50;
    T2L = (BYTE)BR(CDC_UART_BAUD);
    T2H = BR(CDC_UART_BAUD) >> 8;
    AUXR |= 0x14;   /* T2x12 = 1, T2R = 1；AUXR 不是可位寻址 SFR。 */
    IE2 |= 0x01;    /* ES2 */

    /* CDC line coding 的 GET_LINE_CODING 回读值；不应用到 UART。 */
    LineCoding.dwDTERate = 0x00c20100;  /* 115200，USB 小端字节序 */
    LineCoding.bCharFormat = 0;
    LineCoding.bParityType = 0;
    LineCoding.bDataBits = 8;
}

void uart2_isr(void) __interrupt (UART2_VECTOR)
{
    BYTE dat;

    if (S2CON & 0x02)   /* S2TI */
    {
        S2CON &= ~0x02;
        UartBusy = 0;
    }

    if (S2CON & 0x01)   /* S2RI */
    {
        dat = S2BUF;
        S2CON &= ~0x01;

        if ((BYTE)(TxWptr - TxRptr) < 255)
            TxBuffer[TxWptr++] = dat;
        else
            TxOverflow++;
    }
}

void uart_set_parity(BYTE parity)
{
    switch (parity)
    {
    case NONE_PARITY:
        S2CON = 0x50;
        break;
    case ODD_PARITY:
    case EVEN_PARITY:
    case MARK_PARITY:
        S2CON = 0xda;
        break;
    case SPACE_PARITY:
        S2CON = 0xd2;
        break;
    }
}

void uart_set_baud(DWORD baud)
{
    WORD temp;

    switch (baud)
    {
    case 300:
        T2L = (BYTE)BR(300);
        T2H = BR(300) >> 8;
        break;
    case 600:
        T2L = (BYTE)BR(600);
        T2H = BR(600) >> 8;
        break;
    case 1200:
        T2L = (BYTE)BR(1200);
        T2H = BR(1200) >> 8;
        break;
    case 2400:
        T2L = (BYTE)BR(2400);
        T2H = BR(2400) >> 8;
        break;
    case 4800:
        T2L = (BYTE)BR(4800);
        T2H = BR(4800) >> 8;
        break;
    case 9600:
        T2L = (BYTE)BR(9600);
        T2H = BR(9600) >> 8;
        break;
    case 14400:
        T2L = (BYTE)BR(14400);
        T2H = BR(14400) >> 8;
        break;
    case 19200:
        T2L = (BYTE)BR(19200);
        T2H = BR(19200) >> 8;
        break;
    case 28800:
        T2L = (BYTE)BR(28800);
        T2H = BR(28800) >> 8;
        break;
    case 38400:
        T2L = (BYTE)BR(38400);
        T2H = BR(38400) >> 8;
        break;
    case 57600:
        T2L = (BYTE)BR(57600);
        T2H = BR(57600) >> 8;
        break;
    case 115200:
        T2L = (BYTE)BR(115200);
        T2H = BR(115200) >> 8;
        break;
    case 230400:
        T2L = (BYTE)BR(230400);
        T2H = BR(230400) >> 8;
        break;
    case 460800:
        T2L = (BYTE)BR(460800);
        T2H = BR(460800) >> 8;
        break;
    default:
        temp = (WORD)BR(baud);
        T2L = (BYTE)temp;
        T2H = (BYTE)(temp >> 8);
        break;
    }
}

void uart_polling(void)
{
    BYTE dat;
    BYTE cnt;

    if (DeviceState != DEVSTATE_CONFIGURED)
        return;

    /* UART2 RX -> USB CDC IN。 */
    if (!UsbInBusy && (TxRptr != TxWptr))
    {
        IE2 &= ~0x80;   /* EUSB = 0 */
        UsbInBusy = 1;
        usb_write_reg(INDEX, 1);
        cnt = 0;

        while (TxRptr != TxWptr)
        {
            usb_write_reg(FIFO1, TxBuffer[TxRptr++]);
            cnt++;
            if (cnt == EP1IN_SIZE)
                break;
        }

        usb_write_reg(INCSR1, INIPRDY);
        IE2 |= 0x80;
    }

    /* USB CDC OUT -> UART2 TX。 */
    if (!UartBusy && (RxRptr != RxWptr))
    {
        dat = RxBuffer[RxRptr++];
        UartBusy = 1;

        /* 固定 8N1：TB8 始终为 0，不读取电脑端 line coding。 */
        S2CON &= ~0x08;
        S2BUF = dat;

        while (UartBusy)
        {
        }
    }

    /* USB OUT 缓冲满时，等主循环腾出空间后重新放行 OUT 端点。 */
    if (UsbOutBusy)
    {
        IE2 &= ~0x80;
        if ((BYTE)(RxWptr - RxRptr) <= (256 - EP1OUT_SIZE))
        {
            UsbOutBusy = 0;
            usb_write_reg(INDEX, 1);
            usb_write_reg(OUTCSR1, 0);
        }
        IE2 |= 0x80;
    }
}
