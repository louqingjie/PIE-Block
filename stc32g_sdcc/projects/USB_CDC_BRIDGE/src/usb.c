/*---------------------------------------------------------------------*/
/* --- STC MCU Limited ------------------------------------------------*/
/* --- STC 1T Series MCU Demo Programme -------------------------------*/
/* --- Mobile: (86)13922805190 ----------------------------------------*/
/* --- Fax: 86-0513-55012956,55012947,55012969 ------------------------*/
/* --- Tel: 86-0513-55012928,55012929,55012966 ------------------------*/
/* --- Web: www.STCAI.com ---------------------------------------------*/
/* --- BBS: www.STCAIMCU.com  -----------------------------------------*/
/* --- QQ:  800003751 -------------------------------------------------*/
/* 如果要在程序中使用此代码,请在程序中注明使用了STC的资料及程序        */
/*---------------------------------------------------------------------*/

#include "main.h"
#include "usb.h"
#include "usb_req_std.h"
#include "usb_req_class.h"
#include "usb_req_vendor.h"
#include "util.h"

volatile BYTE DeviceState;
volatile __xdata SETUP Setup;
/* IE2 的 EUSB(bit7) 是只写位，读回永远为 0；绝不能对 IE2 做 |= / &=。
   Ie2Shadow 保存除 EUSB 外的 IE2 位，写 IE2 时始终用 Ie2Shadow|0x80。 */
volatile BYTE Ie2Shadow;
volatile BYTE UsbIrqEnabled;
volatile BYTE UsbIrqCount;
volatile BYTE UsbResetCount;
volatile BYTE UsbSetupCount;
volatile BYTE UsbLastIntrusb;
volatile BYTE UsbLastIntrin;
volatile BYTE UsbLastIntrout;
volatile __xdata EPSTATE Ep0State;
volatile BYTE InEpState;
volatile BYTE OutEpState;

volatile BOOL UsbInBusy;
volatile BOOL UsbOutBusy;

volatile BYTE RxRptr;
volatile BYTE RxWptr;
volatile BYTE TxRptr;
volatile BYTE TxWptr;
__xdata BYTE RxBuffer[256];
__xdata BYTE TxBuffer[256];

/* USB 线上结构不能有 padding。 */
typedef char usb_setup_size_check[(sizeof(SETUP) == 8) ? 1 : -1];
typedef char usb_linecoding_size_check[(sizeof(LINECODING) == 7) ? 1 : -1];

void usb_init(void)
{
    /*
     * 冷启动时 ROM ISP 可能已经用 HID Writer 枚举过一次。先显式断开
     * USB 20ms，让主机丢掉旧的 HID 设备，再按 CDC 重新枚举，避免
     * 插拔后设备管理器里残留 HID Writer。
     */
    USBCON = 0x00;
    P3M0 &= ~0x03;
    P3M1 |= 0x03;
    printf("[USB] disconnect 20ms\r\n");
    Ms_Delay(20);

    /* Register_Set() 会把 IRCBAND 的 SEL 位写成 27M 频段，并把
       USBCKS/USBCKS2 清成 0（PLL/2）。这里显式选择 USB 专用 IRC48M。 */
    P_SW2 |= 0x80;
    IRCBAND = (IRCBAND & 0x03) | 0x80;
    printf("[USB] IRCBAND=%02X\r\n", (unsigned int)IRCBAND);

    printf("[USB] wait IRC48M...\r\n");
    IRC48MCR = 0x80;
    while (!(IRC48MCR & 0x01));
    printf("[USB] IRC48MCR=%02X\r\n", (unsigned int)IRC48MCR);

    USBCLK = 0x00;
    USBCON = 0x90;
    printf("[USB] USBCLK=%02X USBCON=%02X\r\n",
           (unsigned int)USBCLK, (unsigned int)USBCON);

    usb_write_reg(FADDR, 0x00);
    usb_write_reg(POWER, 0x08);
    usb_write_reg(INTRIN1E, 0x3f);
    usb_write_reg(INTROUT1E, 0x3f);
    usb_write_reg(INTRUSBE, 0x07);
    usb_write_reg(POWER, 0x00);

    DeviceState = DEVSTATE_DEFAULT;
    Ep0State.bState = EPSTATE_IDLE;
    InEpState = 0x00;
    OutEpState = 0x00;

    UsbInBusy = 0;
    UsbOutBusy = 0;
    RxRptr = 0;
    RxWptr = 0;
    TxRptr = 0;
    TxWptr = 0;

    /* EUSB(bit7) 是只写位，读回为 0；这里整字节写入 Ie2Shadow|0x80。 */
    IE2 = Ie2Shadow | 0x80;
    UsbIrqEnabled = 1;
    printf("[USB] init done IE2=%02X shadow=%02X\r\n",
           (unsigned int)IE2, (unsigned int)Ie2Shadow);
}

BYTE usb_read_reg(BYTE addr)
{
	BYTE dat;

	while (USBADR & 0x80);
	USBADR = addr | 0x80;
	while (USBADR & 0x80);
	dat = USBDAT;

	return dat;
}

void usb_write_reg(BYTE addr, BYTE dat)
{
	while (USBADR & 0x80);
	USBADR = addr & 0x7f;
	USBDAT = dat;
}

BYTE usb_read_fifo(BYTE fifo, BYTE *pdat)
{
    BYTE cnt;
    BYTE ret;

    ret = cnt = usb_read_reg(COUNT0);
    while (cnt--)
    {
    	*pdat++ = usb_read_reg(fifo);
    }

    return ret;
}

void usb_write_fifo(BYTE fifo, BYTE *pdat, BYTE cnt)
{
	while (cnt--)
	{
        usb_write_reg(fifo, *pdat++);
    }
}

void usb_isr(void) __interrupt (25)
{
    BYTE intrusb;
    BYTE intrin;
    BYTE introut;
    BYTE adrTemp;

    adrTemp = USBADR;     //USBADR 现场保存，避免主循环里写完 USBADR 后产生中断，在中断里修改了 USBADR 内容

    intrusb = usb_read_reg(INTRUSB);
    intrin = usb_read_reg(INTRIN1);
    introut = usb_read_reg(INTROUT1);

    UsbIrqCount++;
    UsbLastIntrusb = intrusb;
    UsbLastIntrin = intrin;
    UsbLastIntrout = introut;

    if (intrusb & RSUIF) usb_resume();
    if (intrusb & RSTIF) usb_reset();

    if (intrin & EP0IF) usb_setup();

#ifdef EN_EP1IN
    if (intrin & EP1INIF) usb_in_ep1();
#endif
#ifdef EN_EP2IN
    if (intrin & EP2INIF) usb_in_ep2();
#endif
#ifdef EN_EP3IN
    if (intrin & EP3INIF) usb_in_ep3();
#endif
#ifdef EN_EP4IN
    if (intrin & EP4INIF) usb_in_ep4();
#endif
#ifdef EN_EP5IN
    if (intrin & EP5INIF) usb_in_ep5();
#endif

#ifdef EN_EP1OUT
    if (introut & EP1OUTIF) usb_out_ep1();
#endif
#ifdef EN_EP2OUT
    if (introut & EP2OUTIF) usb_out_ep2();
#endif
#ifdef EN_EP3OUT
    if (introut & EP3OUTIF) usb_out_ep3();
#endif
#ifdef EN_EP4OUT
    if (introut & EP4OUTIF) usb_out_ep4();
#endif
#ifdef EN_EP5OUT
    if (introut & EP5OUTIF) usb_out_ep5();
#endif

    if (intrusb & SUSIF) usb_suspend();

    USBADR = adrTemp;    //USBADR 现场恢复
}

void usb_resume()
{
}

void usb_reset(void)
{
    UsbResetCount++;
    usb_write_reg(FADDR, 0x00);
    DeviceState = DEVSTATE_DEFAULT;
    Ep0State.bState = EPSTATE_IDLE;

#ifdef EN_EP1IN
    usb_write_reg(INDEX, 1);
    usb_write_reg(INCSR1, INCLRDT | INFLUSH);
#endif
#ifdef EN_EP2IN
    usb_write_reg(INDEX, 2);
    usb_write_reg(INCSR1, INCLRDT | INFLUSH);
#endif
#ifdef EN_EP3IN
    usb_write_reg(INDEX, 3);
    usb_write_reg(INCSR1, INCLRDT | INFLUSH);
#endif
#ifdef EN_EP4IN
    usb_write_reg(INDEX, 4);
    usb_write_reg(INCSR1, INCLRDT | INFLUSH);
#endif
#ifdef EN_EP5IN
    usb_write_reg(INDEX, 5);
    usb_write_reg(INCSR1, INCLRDT | INFLUSH);
#endif
#ifdef EN_EP1OUT
    usb_write_reg(INDEX, 1);
    usb_write_reg(OUTCSR1, OUTCLRDT | OUTFLUSH);
#endif
#ifdef EN_EP2OUT
    usb_write_reg(INDEX, 2);
    usb_write_reg(OUTCSR1, OUTCLRDT | OUTFLUSH);
#endif
#ifdef EN_EP3OUT
    usb_write_reg(INDEX, 3);
    usb_write_reg(OUTCSR1, OUTCLRDT | OUTFLUSH);
#endif
#ifdef EN_EP4OUT
    usb_write_reg(INDEX, 4);
    usb_write_reg(OUTCSR1, OUTCLRDT | OUTFLUSH);
#endif
#ifdef EN_EP5OUT
    usb_write_reg(INDEX, 5);
    usb_write_reg(OUTCSR1, OUTCLRDT | OUTFLUSH);
#endif
    usb_write_reg(INDEX, 0);
}

void usb_suspend()
{
}

void usb_setup()
{
    BYTE csr;

    usb_write_reg(INDEX, 0);
    csr = usb_read_reg(CSR0);

    if (csr & OPRDY)
        UsbSetupCount++;

    if (csr & STSTL)
    {
        usb_write_reg(CSR0, csr & ~STSTL);  //对自己写 0 清除标志位
        Ep0State.bState = EPSTATE_IDLE;
    }
    if (csr & SUEND)
    {
        usb_write_reg(CSR0, csr | SSUEND);  //对 SSUEND 写 1 清除 SUEND 标志位
    }

    switch (Ep0State.bState)
    {
    case EPSTATE_IDLE:
        if (csr & OPRDY)
        {
            usb_read_fifo(FIFO0, (BYTE *)&Setup);
            Setup.wLength = reverse2(Setup.wLength);
            switch (Setup.bmRequestType & REQUEST_MASK)
            {
            case STANDARD_REQUEST:
                usb_req_std();
                break;
            case CLASS_REQUEST:
                usb_req_class();
                break;
            case VENDOR_REQUEST:
                usb_req_vendor();
                break;
            default:
                usb_setup_stall();
                return;
            }
        }
        break;
    case EPSTATE_DATAIN:
        usb_ctrl_in();
        break;
    case EPSTATE_DATAOUT:
        usb_ctrl_out();
        break;
    }
}

void usb_setup_stall()
{
    Ep0State.bState = EPSTATE_STALL;
    usb_write_reg(CSR0, SOPRDY | SDSTL);
}

void usb_setup_in()
{
    Ep0State.bState = EPSTATE_DATAIN;
    usb_write_reg(CSR0, SOPRDY);
    usb_ctrl_in();
}

void usb_setup_out()
{
    Ep0State.bState = EPSTATE_DATAOUT;
    usb_write_reg(CSR0, SOPRDY);
}

void usb_setup_status()
{
    Ep0State.bState = EPSTATE_IDLE;
    usb_write_reg(CSR0, SOPRDY | DATEND);
}

void usb_ctrl_in()
{
    BYTE csr;
    BYTE cnt;

    usb_write_reg(INDEX, 0);
    csr = usb_read_reg(CSR0);
    if (csr & IPRDY) return;

    cnt = Ep0State.wSize > EP0_SIZE ? EP0_SIZE : Ep0State.wSize;
    usb_write_fifo(FIFO0, Ep0State.pData, cnt);
    Ep0State.wSize -= cnt;
    Ep0State.pData += cnt;
    if (Ep0State.wSize == 0)
    {
        usb_write_reg(CSR0, IPRDY | DATEND);
        Ep0State.bState = EPSTATE_IDLE;
    }
    else
    {
        usb_write_reg(CSR0, IPRDY);
    }
}

void usb_ctrl_out()
{
    BYTE csr;
    BYTE cnt;

    usb_write_reg(INDEX, 0);
    csr = usb_read_reg(CSR0);
    if (!(csr & OPRDY)) return;

    cnt = usb_read_fifo(FIFO0, Ep0State.pData);
    Ep0State.wSize -= cnt;
    Ep0State.pData += cnt;
    if (Ep0State.wSize == 0)
    {
        usb_write_reg(CSR0, SOPRDY | DATEND);
        Ep0State.bState = EPSTATE_IDLE;
    }
    else
    {
        usb_write_reg(CSR0, SOPRDY);
    }

    usb_uart_settings();
}

#ifdef EN_EP1IN
void usb_in_ep1()
{
    BYTE csr;

    usb_write_reg(INDEX, 1);
    csr = usb_read_reg(INCSR1);
    if (csr & INSTSTL)
    {
        usb_write_reg(INCSR1, INCLRDT);
    }
    if (csr & INUNDRUN)
    {
        usb_write_reg(INCSR1, 0);
    }

    UsbInBusy = 0;
}
#endif

#ifdef EN_EP2IN
void usb_in_ep2()
{
    BYTE csr;

    usb_write_reg(INDEX, 2);
    csr = usb_read_reg(INCSR1);
    if (csr & INSTSTL)
    {
        usb_write_reg(INCSR1, INCLRDT);
    }
    if (csr & INUNDRUN)
    {
        usb_write_reg(INCSR1, 0);
    }
}
#endif

#ifdef EN_EP3IN
void usb_in_ep3()
{
    BYTE csr;

    usb_write_reg(INDEX, 3);
    csr = usb_read_reg(INCSR1);
    if (csr & INSTSTL)
    {
        usb_write_reg(INCSR1, INCLRDT);
    }
    if (csr & INUNDRUN)
    {
        usb_write_reg(INCSR1, 0);
    }
}
#endif

#ifdef EN_EP4IN
void usb_in_ep4()
{
    BYTE csr;

    usb_write_reg(INDEX, 4);
    csr = usb_read_reg(INCSR1);
    if (csr & INSTSTL)
    {
        usb_write_reg(INCSR1, INCLRDT);
    }
    if (csr & INUNDRUN)
    {
        usb_write_reg(INCSR1, 0);
    }
}
#endif

#ifdef EN_EP5IN
void usb_in_ep5()
{
    BYTE csr;

    usb_write_reg(INDEX, 5);
    csr = usb_read_reg(INCSR1);
    if (csr & INSTSTL)
    {
        usb_write_reg(INCSR1, INCLRDT);
    }
    if (csr & INUNDRUN)
    {
        usb_write_reg(INCSR1, 0);
    }
}
#endif

#ifdef EN_EP1OUT
void usb_out_ep1(void)
{
    BYTE csr;
    BYTE cnt;

    if (UsbOutBusy)
        return;

    usb_write_reg(INDEX, 1);
    csr = usb_read_reg(OUTCSR1);
    if (csr & OUTSTSTL)
    {
        usb_write_reg(OUTCSR1, OUTCLRDT);
    }
    if (csr & OUTOPRDY)
    {
        /* 先检查空间，再读 FIFO；否则 64 字节包可能把 256 字节环写爆。 */
        if ((BYTE)(RxWptr - RxRptr) > (256 - EP1OUT_SIZE))
        {
            UsbOutBusy = 1;
            return;
        }

        cnt = usb_read_reg(OUTCOUNT1);
        while (cnt--)
        {
            RxBuffer[RxWptr++] = usb_read_reg(FIFO1);
        }

        if ((BYTE)(RxWptr - RxRptr) >= (256 - EP1OUT_SIZE))
        {
            UsbOutBusy = 1;
        }
        else
        {
            usb_write_reg(OUTCSR1, 0);
        }
    }
}
#endif

#ifdef EN_EP2OUT
void usb_out_ep2()
{
    BYTE csr;

    usb_write_reg(INDEX, 2);
    csr = usb_read_reg(OUTCSR1);
    if (csr & OUTSTSTL)
    {
        usb_write_reg(OUTCSR1, OUTCLRDT);
    }
    if (csr & OUTOPRDY)
    {
        usb_bulk_intr_out(Ep2OutBuffer, 2);
    }
}
#endif

#ifdef EN_EP3OUT
void usb_out_ep3()
{
    BYTE csr;

    usb_write_reg(INDEX, 3);
    csr = usb_read_reg(OUTCSR1);
    if (csr & OUTSTSTL)
    {
        usb_write_reg(OUTCSR1, OUTCLRDT);
    }
    if (csr & OUTOPRDY)
    {
        usb_bulk_intr_out(Ep3OutBuffer, 3);
    }
}
#endif

#ifdef EN_EP4OUT
void usb_out_ep4()
{
    BYTE csr;

    usb_write_reg(INDEX, 4);
    csr = usb_read_reg(OUTCSR1);
    if (csr & OUTSTSTL)
    {
        usb_write_reg(OUTCSR1, OUTCLRDT);
    }
    if (csr & OUTOPRDY)
    {
        usb_bulk_intr_out(Ep4OutBuffer, 4);
    }
}
#endif

#ifdef EN_EP5OUT
void usb_out_ep5()
{
    BYTE csr;

    usb_write_reg(INDEX, 5);
    csr = usb_read_reg(OUTCSR1);
    if (csr & OUTSTSTL)
    {
        usb_write_reg(OUTCSR1, OUTCLRDT);
    }
    if (csr & OUTOPRDY)
    {
        usb_bulk_intr_out(Ep5OutBuffer, 5);
    }
}
#endif
