;--------------------------------------------------------------------------
; portheap.asm - FreeRTOS 堆在 STC32G12K128 片内 EDATA (region 00:) 的存储
;
; SDCC MCS-251 没有可用的 edata 存储类：__data / __near 是 8 位页零指针，
; 超过 0xFF 会被截断。但硬件栈指针 SPX 只能指向 region 00:，因此任务栈必须
; 落在片内 edata。这里把 FreeRTOS 堆放进一个独立的 XDATA 类型区域，并用
; 链接参数 -Wl-b FRHEAP=0x0400 把它钉在 edata 0x0400 起：
;
;   - C 侧把 ucHeap 当 xdata 访问，走 DPX（0x000400），物理地址正是 00:0400；
;   - heap_4.c 分配出的 TCB/任务栈因此天然位于 region 00:，SPX 合法。
;
; 本区域大小必须与 FreeRTOSConfig.h 的 configTOTAL_HEAP_SIZE 一致。
;--------------------------------------------------------------------------

	.module portheap

	.area FRHEAP	(XDATA)
	.globl _ucHeap
_ucHeap::
	.ds 0x0C00
