#ifndef __IAP_H__
#define __IAP_H__

void iap_init();
BOOL iap_check_addr(DWORD addr);
BYTE iap_read_byte(DWORD addr);
BOOL iap_write_byte(DWORD addr, BYTE dat);
void iap_erase_page(DWORD addr);

#endif
