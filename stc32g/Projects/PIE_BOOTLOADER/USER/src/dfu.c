#include "stc.h"
#include "uart.h"
#include "iap.h"
#include "dfu.h"

DWORD xdata DfuFlag _at_ 0x1ffc;

static void delay()
{
    int i;

    for (i = 0; i < 5000; i++)
        ;
}

void dfu_check()
{
    /* 强制下载引脚配成带上拉的准双向口，延时等电平稳定。
       掩码来自 dfu.h，原例程这里硬编码 0x08(P33)，我们换到了 P32。 */
    P3M1 &= ~DFU_FORCEPIN_MASK;
    P3PU |= DFU_FORCEPIN_MASK;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
    delay();

    /* 四重校验都通过才跳 App：
         引脚未被拉低 / 无 DFU 标志 / App 首字节是 LJMP(0x02) / 跳转目标跨过本区 */
    if ((DFU_FORCEPIN != 0) &&
        (DfuFlag != DFU_TAG) &&
        (*(BYTE code *)(LDR_SIZE) == 0x02) &&
        (*(WORD code *)(LDR_SIZE + 1) >= LDR_SIZE + 3))
    {
        P3M1 |= DFU_FORCEPIN_MASK;
        P3PU = 0x00;
        ((void(far *)())(0xff0000 + LDR_SIZE))();
    }

    P3M1 |= DFU_FORCEPIN_MASK;
    P3PU = 0x00;
    DfuFlag = 0;
}

void dfu_events()
{
    BYTE cmd;
    DWORD addr;
    BYTE size;
    BYTE ret;
    BYTE edata *ptr;
    BYTE status;

    if (!bUartRxReady)
        return;

    cmd = UartRxBuffer[1];
    /* 逐字节拼地址，不用 *(DWORD *)&UartRxBuffer[2]。
       原例程那种写法是从 edata 数组做未对齐 32 位读，实测地址会取错
       （现象：READ 总是读到同一处，PROGRAM 按 payload 长度奇偶交替失败）。 */
    addr = ((DWORD)UartRxBuffer[2]) | ((DWORD)UartRxBuffer[3] << 8) | ((DWORD)UartRxBuffer[4] << 16) | ((DWORD)UartRxBuffer[5] << 24);
    addr &= 0x1ffff;
    size = UartRxBuffer[6];
    /* ptr 必须显式声明成 edata 指针：UartRxBuffer/UartTxBuffer 都在 edata，
       通用指针在大内存模型下会被截断。 */
    ptr = &UartRxBuffer[7];
    status = STATUS_OK;
    ret = 0;

    switch (cmd)
    {
    case DFU_CMD_CONNECT:
        UartTxBuffer[0] = LDR_VERSION >> 8;
        UartTxBuffer[1] = LDR_VERSION;
        ret = 2;
        break;
    case DFU_CMD_READ:
#ifdef DEBUG
        /* 原例程这里写的是 UartInBuffer，那个变量并不存在 —— 官方笔误，
           因为 DEBUG 分支从未被编译过。回应数据要放发送缓冲区。 */
        ret = size;
        ptr = &UartTxBuffer[0];
        while (size--)
        {
            *ptr++ = iap_read_byte(addr++);
        }
#else
        status = STATUS_ERRORCMD;
#endif
        break;
    case DFU_CMD_PROGRAM:
        while (size--)
        {
            if (!iap_write_byte(addr, *ptr))
            {
                status = STATUS_PROGRAMERR;
                break;
            }
            addr++;
            ptr++;
        }
        break;
    case DFU_CMD_ERASE:
        addr = 0;
        while (addr < 0x20000)
        {
            iap_erase_page(addr);
            addr += 0x200;
        }
        break;
    case DFU_CMD_REBOOT:
        IAP_CONTR = 0x20;
        while (1)
            ;
        break;
    default:
        status = STATUS_ERRORCMD;
        break;
    }

    uart_send(status, ret);
    uart_recv_done();
}
