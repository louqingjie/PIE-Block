/*
 * SDCC MCS-251 startup hook for STC32G12K128.
 *
 * 链接进来的 mcs251.lib 提供原生 crtstart/crtxinit/crtxclear。本文件只做
 * 目标相关的最小前置初始化：它在数据初始化之前运行，不能使用全局量或标准库。
 * 板级初始化仍由 main() -> vSystemInit() 显式完成。
 */
unsigned char __sdcc_external_startup(void)
{
    return 0;
}
