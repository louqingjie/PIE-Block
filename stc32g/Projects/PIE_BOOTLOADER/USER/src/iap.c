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

    return (iap_read_byte(addr) == dat);
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

