from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "projects" / "DBG_CONSOLE"

SNAPSHOT_KEYS = (
    "t=",
    " loop=",
    " loop_max=",
    " exp_ms=",
    " mode=",
    " st=",
    " fifo=",
    " drain=",
    " drain_max=",
    " rx=",
    " rx_dr=",
    " tx=",
    " tx_ds=",
    " maxrt=",
    " age=",
    " ch=",
    " rf=",
    " retr=",
    " rst=",
    " boot=",
    " dbg_dropped=",
)


class DbgConsoleContractTests(unittest.TestCase):
    """车体串口调试台独立工程的源码契约。

    该工程不参与代码生成器，必须保持：
    - 构建清单能独立展开；
    - UART2 使用 P1.0/P1.1 与已验证的 S2CON=0x50 初始化；
    - 周期行字段顺序与需求文档一致；
    - 调试输出不使用 printf（SDCC 默认 putchar 会写 UART1）。
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.main = (PROJECT / "src" / "main.c").read_text(encoding="utf-8")
        cls.console = (PROJECT / "src" / "dbg_console.c").read_text(encoding="utf-8")
        cls.console_header = (PROJECT / "inc" / "dbg_console.h").read_text(
            encoding="utf-8"
        )
        cls.nrf = (PROJECT / "src" / "nrf_dbg.c").read_text(encoding="utf-8")
        cls.nrf_header = (PROJECT / "inc" / "nrf_dbg.h").read_text(encoding="utf-8")

    def test_manifest_registers_project(self) -> None:
        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        self.assertIn("DBG_CONSOLE", manifest["projects"])
        self.assertEqual(
            ["drivers", "dbg_console"],
            list(manifest["projects"]["DBG_CONSOLE"]["library_groups"]),
        )
        self.assertEqual(
            {
                "projects/DBG_CONSOLE/src/dbg_console.c",
                "projects/DBG_CONSOLE/src/nrf_dbg.c",
            },
            set(manifest["source_groups"]["dbg_console"]),
        )
        self.assertNotIn("DBG_CONSOLE", manifest.get("kind_projects", {}))

    def test_project_sources_exist(self) -> None:
        for name in (
            "inc/main.h",
            "inc/dbg_console.h",
            "inc/nrf_dbg.h",
            "src/main.c",
            "src/isr.c",
            "src/dbg_console.c",
            "src/nrf_dbg.c",
        ):
            self.assertTrue((PROJECT / name).is_file(), name)

    def test_uart2_pins_and_baud(self) -> None:
        code = re.sub(r"/\*.*?\*/|//[^\n]*", "", self.console, flags=re.DOTALL)
        compact = re.sub(r"\s+", " ", code)
        self.assertIn("P_SW2 &= (uint8_t)~0x01", compact)
        self.assertIn("P1M1 &= (uint8_t)~0x03", compact)
        self.assertIn("P1M0 |= 0x02", compact)
        self.assertIn("S2CON = 0x50", compact)
        self.assertIn("AUXR |= 0x14", compact)
        self.assertIn("IE2 |= 0x01", compact)
        self.assertIn("#define DBG_BAUD 115200UL", self.console_header)
        self.assertIn("DBG_BR(DBG_BAUD)", compact)
        # 不调用漏设 UART2 模式位的共享 UART_Init(UART_2, ...)。
        self.assertNotIn("UART_Init(UART_2", compact)

    def test_snapshot_field_order_matches_requirement(self) -> None:
        start = self.console.rindex("static void PrintSnapshot(void)")
        end = self.console.rindex("static void PrintBurstLine(void)")
        body = self.console[start:end]
        positions = [body.index(f'LineStr("{key}")') for key in SNAPSHOT_KEYS]
        self.assertEqual(sorted(positions), positions)

    def test_events_and_commands_present(self) -> None:
        for event in (
            "ev=FIFO_FULL",
            "ev=LOOP_STALL",
            "ev=LINK_LOST",
            "ev=RESET",
        ):
            self.assertIn(event, self.console)
        for command in ("case '?'", "case 's'", "case 'r'", "case 'd'"):
            self.assertIn(command, self.console)
        for command in ("case 'l'", "case 'b'", "case 'm'", "case 'v'"):
            self.assertIn(command, self.console)
        self.assertIn("Nrf_ForceRx", self.console)
        self.assertIn("Nrf_ForceTx", self.console)
        self.assertIn("Nrf_ReadReg", self.console)

    def test_radio_configuration_matches_requirement(self) -> None:
        self.assertIn("#define NRF_CHANNEL 29", self.nrf_header)
        self.assertIn("#define NRF_RF_SETUP_V 0x27", self.nrf_header)
        self.assertIn("#define NRF_SETUP_RETR_V 0x15", self.nrf_header)
        self.assertIn("#define NRF_RX_PAYLOAD 12", self.nrf_header)
        self.assertIn("nrf_writereg(NRF_WRITE_REG + NRF_REG_RX_PW_P0, NRF_RX_PAYLOAD)",
                      self.nrf)
        # RX/TX CONFIG 与需求附录 A.4 一致。
        self.assertIn("NRF_REG_CONFIG, 0x0F", self.nrf)
        self.assertIn("NRF_REG_CONFIG, 0x0E", self.nrf)
        # 遥测 20 字节 payload + 帧头/校验 = 22 字节，5 次分频。
        self.assertIn("static uint8_t divider = 4;", self.nrf)
        self.assertIn("if (++divider < 5)", self.nrf)
        self.assertIn("payload[19] = (uint8_t)(((uint16_t)v9 >> 8) & 0xFF);", self.nrf)
        # 切回 RX 不清 RX FIFO，保证观测不被驱动自身清掉。
        rx_mode = self.nrf[
            self.nrf.index("static void nrf_enter_rx(void)") :
            self.nrf.index("static void nrf_apply_config(void)")
        ]
        self.assertNotIn("FLUSH_RX", rx_mode)

    def test_debug_output_never_uses_printf(self) -> None:
        for path in sorted((PROJECT / "src").glob("*.c")):
            text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(encoding="utf-8"),
                          flags=re.DOTALL)
            self.assertNotIn("printf(", text, path.name)

    def test_isrs_preserve_dpxl(self) -> None:
        """SDCC mcs251 的 ISR 序言不保存 DPXL，ISR 必须手工 push/pop。

        主循环的 switch 跳表（GPIO_Write_Bit）与 __code 字符串读取都依赖 DPXL；
        ISR 里访问 XDATA 会改掉它，返回后可能 ejmp 到非程序区（ROMOVF 复位）。
        """
        isr = (PROJECT / "src" / "isr.c").read_text(encoding="utf-8")
        for name, vector in (("UART1_Isr", 4), ("UART2_Isr", 8), ("TM3_Isr", 19)):
            pattern = re.compile(
                r"void\s+%s\s*\(void\)\s*__interrupt\s*\(\s*%d\s*\)\s*\{(.*?)\n\}"
                % (name, vector),
                re.DOTALL,
            )
            match = pattern.search(isr)
            self.assertIsNotNone(match, f"缺少 {name} 定义")
            body = match.group(1)
            self.assertIn("push dpxl", body, f"{name} 未保存 DPXL")
            self.assertIn("pop dpxl", body, f"{name} 未恢复 DPXL")

    def test_main_loop_calls_debug_hooks(self) -> None:
        for token in (
            "Dbg_Init(PIE_BLOCK_FW_HASH, PIE_BLOCK_BUILD_DATE)",
            "Nrf_Handler();",
            "Dbg_AfterNrfHandler();",
            "Dbg_PollCommands();",
            "Dbg_EndLoop(loop_ms, exp_ms);",
            "Nrf_SendTelemetry(",
        ):
            self.assertIn(token, self.main)
        self.assertIn("Dbg_AgeMs() > DBG_LINK_TIMEOUT_MS", self.main)


    def test_fifo_status_bits_match_datasheet(self) -> None:
        """FIFO_STATUS 位定义必须按 nRF24L01+ 手册 p.61：bit0 RX_EMPTY、bit1 RX_FULL。"""
        self.assertIn("#define NRF_RX_EMPTY 0x01", self.nrf)
        self.assertIn("#define NRF_RX_FULL 0x02", self.nrf)
        self.assertNotIn("#define NRF_RX_EMPTY 0x40", self.nrf)
        self.assertNotIn("#define NRF_RX_FULL 0x10", self.nrf)

    def test_mecanum_mapping_matches_generated_baseline(self) -> None:
        # ROCKER_OFFSET_t: 0=LY, 1=LX, 2=RY, 3=RX；生成代码为 vx=-LY, vy=-LX, turn=-RX。
        for token in (
            "vx = -(int32_t)rocker[0]",
            "vy = -(int32_t)rocker[1]",
            "turn = -(int32_t)rocker[3]",
        ):
            self.assertIn(token, self.main)

    def test_build_script_lists_project(self) -> None:
        script = (ROOT / "build.ps1").read_text(encoding="utf-8")
        self.assertIn("'DBG_CONSOLE'", script)
        self.assertIn("PIE_BLOCK_FW_HASH", script)
        self.assertIn("PIE_BLOCK_BUILD_DATE", script)


if __name__ == "__main__":
    unittest.main()
