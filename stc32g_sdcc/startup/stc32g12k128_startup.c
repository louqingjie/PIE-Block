/*
 * SDCC MCS-251 startup hook for STC32G12K128.
 *
 * The linked mcs251.lib supplies the native crtstart/crtxinit/crtxclear
 * objects.  This hook is intentionally limited to target pre-initialisation:
 * it runs before the normal data initialisation and must not use globals or
 * the standard library.  Board_Init() remains an explicit application step.
 */
unsigned char __sdcc_external_startup(void)
{
    return 0;
}


