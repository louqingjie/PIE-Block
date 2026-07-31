$NOMOD51
$MODSRC

        NAME    STARTUP_UART_SMOKE

        EXTRN   CODE (main)
        SP      DATA 081H

        CSEG    AT 0
START:
        MOV     SP,#07H
        LCALL   main
STOP_LOOP:
        SJMP    STOP_LOOP

        END