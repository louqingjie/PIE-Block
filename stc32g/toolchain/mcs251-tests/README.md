# MCS-251 differential tests

This directory contains architecture-level tests shared by the Keil C251
baseline, the SDCC `mcs251` port, and the instruction simulator.

The calibration cases currently cover:

- `uart_smoke.c`: reset, near call, direct SFR write, and an infinite loop.
- `integer_control.c`: source-mode registers, function arguments and returns,
  8/16-bit arithmetic, a counted loop, comparisons, and conditional branches.
- `direct_ram.c`: linked DATA addresses, direct load/store/copy/increment, UART
  output, and final IRAM state.

Keil and SDCC HEX files may differ in layout and instruction selection. Their
observable UART traces and declared memory end states must match.

Run the simulator tests from the repository root:

```powershell
.venv\Scripts\python.exe -m unittest discover `
  -s stc32g/toolchain/mcs251-tests -p "test_*.py" -v
```

Generated compiler output belongs under `build/` and is not committed.

Build the Keil C251 calibration HEX and execute it in the simulator:

```powershell
.venv\Scripts\python.exe `
  stc32g/toolchain/mcs251-tests/validate_keil_baseline.py
```

## Current simulator boundary

The simulator is intentionally fail-closed. It supports the classic forms used
by these cases (`NOP`, `LJMP`, `LCALL`, `RET`, `INC`, `ADD A,#data`, `JZ`,
`JNZ`, `CJNE A,#data,rel`, direct `MOV`, `SJMP`, and `CLR A`) plus the
Keil C251 source-mode forms calibrated from assembler listings (`MOV`/`MOVZ`
register forms, word `ADD`/`XRL`/`CMP`, `DEC Rn,#1`, `JNE`, and the observed
extended `CJNE R5,#data,rel`). Unknown opcodes, unknown operand modes, and
execution from unmapped code are errors.

Direct writes to `SBUF`, `S2BUF`, `S3BUF`, and `S4BUF` are recorded as UART
events. Timing, interrupts, receive behavior, and other STC32G peripherals are
not implemented yet.
