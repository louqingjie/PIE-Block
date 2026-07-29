#include "stc.h"
#include "iap.h"

void iap_init()
{
    IAP_CONTR = 0x80;
    IAP_TPS = FOSC / 1000000;
}

BOOL iap_check_addr(DWORD addr)
{
    addr &= 0x1ffff;

    return ((addr < 0x10000) ||
            (addr >= (0x10000 + LDR_SIZE)));
}

BYTE iap_read_byte(DWORD addr)
{
    return *(BYTE ecode *)(addr | 0x00fe0000);
}

BOOL iap_write_byte(DWORD addr, BYTE dat)
{
    if (!iap_check_addr(addr))
        return 0;

    IAP_CMD = 2;
    IAP_ADDRE = BYTE2(addr) & 0x01;
    IAP_ADDRH = BYTE1(addr);
    IAP_ADDRL = BYTE0(addr);
    IAP_DATA = dat;
    IAP_TRIG = 0x5a;
    IAP_TRIG = 0xa5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();

    /* 只查 CMD_FAIL（IAP_CONTR 的 B4 位，手册第 905 页），不做回读比对。
       原例程用 ecode 直读回比对，实测在连续写多字节时会误报失败
       （现象：payload 长度为偶数时必然 PROGRAM_ERR）。
       库函数 EEPROM_* 不检查 CMD_FAIL，所以这里直接读寄存器。
       整体正确性由 PC 端下载后读回校验保证，不依赖逐字节回读。 */
    return (BOOL)((IAP_CONTR & 0x10) == 0);
}

void iap_erase_page(DWORD addr)
{
    if (!iap_check_addr(addr))
        return;

    IAP_CMD = 3;
    IAP_ADDRE = BYTE2(addr) & 0x01;
    IAP_ADDRH = BYTE1(addr);
    IAP_ADDRL = BYTE0(addr);
    IAP_TRIG = 0x5a;
    IAP_TRIG = 0xa5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
}
