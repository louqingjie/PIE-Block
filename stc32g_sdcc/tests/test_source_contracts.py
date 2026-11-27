from __future__ import annotations

import hashlib
import unittest
import re
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FirmwareSafetyContractTests(unittest.TestCase):
    def test_spi_probe_has_finite_timeout_api(self) -> None:
        header = (ROOT / "libraries" / "drivers" / "inc" / "CNU_PIE_SPI.h").read_text(
            encoding="utf-8"
        )
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_SPI.c").read_text(
            encoding="utf-8"
        )
        self.assertIn("SPI_TRANSFER_TIMEOUT 2000U", header)
        self.assertIn("SPI_ReadWriteByte_Timeout", header)
        self.assertIn("if (timeout == 0)", source)
        self.assertNotIn("while (!(SPSTAT & 0x80));", source)

    def test_sdcc_never_bit_addresses_non_addressable_spi_sfrs(self) -> None:
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_SPI.c").read_text(
            encoding="utf-8"
        )
        for bit_name in ("SSIG", "SPEN", "DORD", "MSTR", "CPOL", "CPHA", "SPIF", "WCOL"):
            self.assertIsNone(
                re.search(rf"\b{bit_name}\b\s*=", source),
                f"{bit_name} must be accessed through its containing SFR byte under SDCC",
            )
        self.assertIn("SPCTL = control;", source)
        self.assertIn("SPSTAT & 0x80", source)
        self.assertIn("SPSTAT = 0xC0", source)

    def test_other_non_addressable_sfr_bits_use_byte_masks(self) -> None:
        common = (ROOT / "startup" / "common.c").read_text(encoding="utf-8")
        uart = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_UART.c").read_text(
            encoding="utf-8"
        )
        watchdog = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_WDog.c").read_text(
            encoding="utf-8"
        )
        self.assertNotRegex(common, r"\bEAXFR\b\s*=")
        self.assertNotRegex(uart, r"\bES[234]\b\s*=")
        self.assertNotRegex(watchdog, r"\b(?:EN_WDT|CLR_WDT|IDL_WDT)\b\s*=")
        self.assertIn("P_SW2 |= 0x80", common)
        self.assertIn("IE2 |= 0x01", uart)
        self.assertIn("WDT_CONTR |= 0x20", watchdog)

    def test_packaged_sources_do_not_use_unsupported_extended_sbits(self) -> None:
        """SDCC 会把这些别名误编码到经典 8051 位地址，常见结果是破坏 PSW。"""
        header = (ROOT / "include" / "STC32Gxx.h").read_text(encoding="utf-8")
        current_sfr_address: int | None = None
        unsafe_names: set[str] = set()
        for line in header.splitlines():
            sfr_match = re.match(r"__sfr __at \(0x([0-9a-fA-F]+)\) (\w+);", line)
            if sfr_match:
                current_sfr_address = int(sfr_match.group(1), 16)
                continue
            sbit_match = re.match(r"__sbit __at \(0x[0-9a-fA-F]+\) (\w+);", line)
            if sbit_match and current_sfr_address is not None and current_sfr_address & 0x07:
                unsafe_names.add(sbit_match.group(1))

        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        relative_sources: set[str] = set()
        for sources in manifest["source_groups"].values():
            relative_sources.update(sources)
        relative_sources.update(manifest["source_groups"]["common"])
        relative_sources.update(
            path.relative_to(ROOT).as_posix() for path in (ROOT / "projects").rglob("*.c")
        )

        violations: list[str] = []
        for relative_source in sorted(relative_sources):
            source_path = ROOT / relative_source
            text = source_path.read_text(encoding="utf-8")
            text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.DOTALL)
            used_names = set(re.findall(r"\b[A-Za-z_]\w*\b", text)) & unsafe_names
            if used_names:
                violations.append(f"{relative_source}: {', '.join(sorted(used_names))}")
        self.assertEqual([], violations, "unsupported extended __sbit use:\n" + "\n".join(violations))

    def test_infantry_keeps_radio_initialization_bounded(self) -> None:
        source = (
            ROOT / "projects" / "ROBOMASTER_INFANTRY" / "src" / "main.c"
        ).read_text(encoding="utf-8")
        self.assertIn("for (retry = 0; retry < 20; retry++)", source)
        self.assertIn("SPI_ReadWriteByte", (ROOT / "libraries" / "boards" / "src" / "nrf24l01.c").read_text(encoding="utf-8"))

    def test_remote_status_send_contract(self) -> None:
        """十路 IO 状态回传：两端固件实现一致，payload 为 10 个 int16 小端。

        协议（与手柄端约定）：payload[20] 依次是
        P60/P62/P64/P66/P74/P75/P76/P77/MP03/MP74 的 int16 小端值，
        nrf_tx_packet 再加帧头长度与校验，最终无线帧 22 字节。
        """
        sources = [
            ROOT / "libraries" / "boards" / "src" / "nrf24l01.c",
            ROOT.parent / "stc32g" / "Libraries" / "boards" / "src" / "nrf24l01.c",
        ]
        headers = [
            ROOT / "libraries" / "boards" / "inc" / "nrf24l01.h",
            ROOT.parent / "stc32g" / "Libraries" / "boards" / "inc" / "nrf24l01.h",
        ]
        declaration = (
            "void RemoteStatusSend(int v0, int v1, int v2, int v3, int v4, "
            "int v5, int v6, int v7, int v8, int v9);"
        )
        for path in headers:
            # stc32g 的 Keil 头是 GBK；声明本身是纯 ASCII，按字节比对。
            self.assertIn(
                declaration.encode("ascii"), path.read_bytes(), str(path)
            )
        for path in sources:
            source = path.read_text(encoding="utf-8")
            self.assertIn(
                "void RemoteStatusSend(int v0, int v1, int v2, int v3, int v4,\n",
                source,
                str(path),
            )
            self.assertIn("uint8_t payload[20];", source, str(path))
            for slot in range(10):
                self.assertIn(
                    f"payload[{slot * 2}] = (uint8_t)((uint16_t)v{slot} & 0xFF);",
                    source,
                    str(path),
                )
                self.assertIn(
                    f"payload[{slot * 2 + 1}] = (uint8_t)(((uint16_t)v{slot} >> 8) & 0xFF);",
                    source,
                    str(path),
                )
            # 5 次分频：divider 初值 4，首次调用立即发送，之后每 5 次一包。
            self.assertIn("static uint8_t divider = 4;", source, str(path))
            self.assertIn(
                "if (++divider < 5)\n    return;\n  divider = 0;",
                source,
                str(path),
            )
            self.assertIn("nrf_tx_packet(payload, 20);", source, str(path))
            self.assertIn("Ms_Delay(3);\n  nrf_handler();", source, str(path))
            # 落帧不能写成「数组 + 变址循环」：SDCC 对这类写法取字节有误。
            self.assertIsNone(
                re.search(r"payload\[[A-Za-z_]\w*\]\s*=", source),
                f"{path}: payload 必须逐元素展开赋值",
            )

    def test_nrf_tx_mode_settle_delay_shortened(self) -> None:
        """状态回传每 5 圈进一次 TX，切模式等待从 25ms 缩到 1ms 以保持主循环节奏。"""
        for path in (
            ROOT / "libraries" / "boards" / "src" / "nrf24l01.c",
            ROOT.parent / "stc32g" / "Libraries" / "boards" / "src" / "nrf24l01.c",
        ):
            source = path.read_text(encoding="utf-8")
            match = re.search(
                r"void nrf_tx_mode\(void\)\n\{(.*?)\n\}", source, re.DOTALL
            )
            self.assertIsNotNone(match, f"{path}: 找不到 nrf_tx_mode 定义")
            self.assertIn("Ms_Delay(1);", match.group(1), str(path))
            self.assertNotIn("Ms_Delay(25);", match.group(1), str(path))

    def test_robot_projects_use_known_good_bytewise_uart_query(self) -> None:
        projects = (
            "0000.培训模板",
            "FRICTION_CALIBRATION",
            "ROBOMASTER_ENGINEER",
            "ROBOMASTER_INFANTRY",
            "TEST",
        )
        for project in projects:
            source = (ROOT / "projects" / project / "src" / "main.c").read_text(
                encoding="utf-8"
            )
            self.assertIn("static void Uart1TxQuery(uint8_t dat)", source, project)
            self.assertIn("Uart1TxQuery(control_frame_pack[i])", source, project)
            self.assertNotIn("Uart1SendFrameQuery", source, project)
            self.assertNotIn("uint8_t globalInterruptEnabled = EA", source, project)
            self.assertNotIn(
                "UART_PutChar(UART_1, control_frame_pack[i])", source, project
            )

    def test_infantry_uses_requested_remote_channel(self) -> None:
        source = (
            ROOT / "projects" / "ROBOMASTER_INFANTRY" / "src" / "main.c"
        ).read_text(encoding="utf-8")
        self.assertIn("uint8_t Channal = 3;", source)

    def test_keil_robot_projects_use_known_good_bytewise_uart_query(self) -> None:
        projects = (
            "0000.培训模板",
            "FRICTION_CALIBRATION",
            "ROBOMASTER_ENGINEER",
            "ROBOMASTER_INFANTRY",
            "TEST",
        )
        for project in projects:
            source = (
                ROOT.parent / "stc32g" / "Projects" / project / "USER" / "src" / "main.c"
            ).read_text(encoding="utf-8")
            self.assertIn("static void Uart1TxQuery(uint8_t dat)", source, project)
            self.assertIn("Uart1TxQuery(control_frame_pack[i])", source, project)
            self.assertNotIn("Uart1SendFrameQuery", source, project)

    def test_diagnostics_and_guide_use_bytewise_uart_query(self) -> None:
        paths = (
            ROOT.parent / "tools" / "diagnostics" / "friction_wheel_diagnostic.c",
            # 指南已按 docs/README.md 的分类目录整理到 docs/guides/。
            ROOT.parent / "docs" / "guides" / "RM电控指南.md",
        )
        for path in paths:
            source = path.read_text(encoding="utf-8")
            self.assertIn("static void Uart1TxQuery(uint8_t dat)", source, str(path))
            self.assertIn("Uart1TxQuery(control_frame_pack[i])", source, str(path))
            self.assertNotIn("Uart1SendFrameQuery", source, str(path))

    def test_robot_chassis_scaling_avoids_float_sign_conversion(self) -> None:
        projects = (
            "0000.培训模板",
            "ROBOMASTER_ENGINEER",
            "ROBOMASTER_INFANTRY",
            "TEST",
        )
        for project in projects:
            source = (ROOT / "projects" / project / "src" / "main.c").read_text(
                encoding="utf-8"
            )
            self.assertNotRegex(source, r"(?:baseSpeed|turnSpeed|_base_spd|_turn_spd)\s*=.*\(float\)", project)
            self.assertIn("int32_t", source, project)
            self.assertIn("2047L", source, project)

    def test_hspwm_prescaler_uses_async_window(self) -> None:
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_PWM.c").read_text(
            encoding="utf-8"
        )
        for timer in ("A", "B"):
            for byte in ("H", "L"):
                register = f"PWM{timer}_PSCR{byte}"
                self.assertGreaterEqual(
                    source.count(f"PWM_Write{timer}((uint32_t)&{register}"),
                    2,
                    f"{register} must use the HSPWM async window in init and update",
                )
                self.assertIsNone(
                    re.search(rf"\b{register}\s*=", source),
                    f"direct writes to {register} leave the prescaler at reset value",
                )

    def test_servo_50hz_register_model(self) -> None:
        system_clock = 33_177_600
        requested_frequency = 50
        timer_ticks = system_clock // requested_frequency
        prescaler = timer_ticks >> 16
        period = timer_ticks // (prescaler + 1) - 1
        actual_frequency = system_clock / ((prescaler + 1) * (period + 1))
        self.assertEqual(prescaler, 10)
        self.assertEqual(period, 60_321)
        self.assertAlmostEqual(actual_frequency, requested_frequency, delta=0.001)


class StaffDisplayContractTests(unittest.TestCase):
    """OLED 五线谱显示的构建清单/源码契约。

    显示链路只允许新增 OLED_Staff.c / StaffRender.c / LCD_Frame.c /
    MusicClock.c；厂商文件 LCD.c / LCD.h（以及 OLED.c / OLED.h）保持原样，
    避免固件升级时和上游 CNU_PIE 库产生冲突。若确实需要改厂商文件，请同步
    更新下面的 SHA-256 并在改动说明里写清原因。
    """

    VENDOR_FILE_SHA256 = {
        "libraries/boards/src/LCD.c": "e1290f55bc18a64ca2846de301307ec50eedc6601b42e3dfd5449de606fd1d8e",
        "libraries/boards/inc/LCD.h": "e9abb88537524d9cca37f9c5ce1573075c784104ea7c8bc0f92300f245b262c5",
        "libraries/boards/src/OLED.c": "c1c53164b7e595ef919deb29a2a824688aacb6306add876c34286e8e4df1347d",
        "libraries/boards/inc/OLED.h": "d75e5eebac4b79272ff5cd1b491555f97d112d8bb107612336caeb6eee3bd5cb",
    }

    def test_music_projects_link_lcd_and_staff_groups(self) -> None:
        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        for project in (
            "BUZZER_MUSIC_GENERATED",
            "BUZZER_MUSIC_SMOKE",
            "BUZZER_MUSIC_SONG_SMOKE",
        ):
            groups = list(manifest["projects"][project]["library_groups"])
            self.assertIn("pwm", groups, project)
            self.assertIn("lcd", groups, project)
            self.assertIn("staff", groups, project)
            # 顺序固定：PWM 发声 + LCD 驱动 + 五线谱渲染，便于 diff 时保持稳定。
            self.assertEqual(["pwm", "lcd", "staff"], groups, project)

    def test_staff_source_group_lists_existing_sources(self) -> None:
        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        expected = {
            "libraries/boards/src/OLED_Staff.c",
            "libraries/boards/src/StaffRender.c",
            "libraries/boards/src/LCD_Frame.c",
            "libraries/boards/src/MusicClock.c",
        }
        self.assertEqual(expected, set(manifest["source_groups"]["staff"]))
        for relative_source in expected:
            self.assertTrue(
                (ROOT / relative_source).is_file(),
                f"staff 源组里的文件不存在: {relative_source}",
            )

    def test_music_clock_polls_free_running_timer0(self) -> None:
        """播放节奏补偿用无中断的 Timer0 轮询，避免 ISR 破坏 DPXL/DPTR。"""
        header = (
            ROOT / "libraries" / "boards" / "inc" / "MusicClock.h"
        ).read_text(encoding="utf-8")
        source = (
            ROOT / "libraries" / "boards" / "src" / "MusicClock.c"
        ).read_text(encoding="utf-8")
        oled_staff = (
            ROOT / "libraries" / "boards" / "src" / "OLED_Staff.c"
        ).read_text(encoding="utf-8")
        for symbol in (
            "MusicClock_Init",
            "MusicClock_Poll",
            "MusicClock_Reset",
            "MusicClock_WaitDeadline",
            "MusicClock_Advance",
        ):
            self.assertIn(symbol, header)
        # 不允许再出现定时器中断：SDCC 的 ISR 不保存 DPXL，会打断 MOVC/@DPX。
        self.assertNotIn("__interrupt", source)
        self.assertNotIn("TMR0_VECTOR", source)
        self.assertNotIn("ET0 = 1", source)
        # 自由计数 + 差值累加 + 上电校准 + 计时器失效时回退 Ms_Delay。
        self.assertIn("musicClockTicks += (uint32_t)delta;", source)
        self.assertIn("MUSIC_CLOCK_CALIBRATION_SAMPLES", source)
        self.assertIn("musicClockTicksPerMs", source)
        self.assertIn("MusicClock_DelayMs", source)
        # 渲染/刷屏之间必须补采样，保证采样间隔 < 23.7ms 的 16-bit 溢出周期。
        self.assertIn("MusicClock_Poll();", oled_staff)
        self.assertGreaterEqual(oled_staff.count("MusicClock_Poll();"), 2)

    def test_music_project_sources_all_exist(self) -> None:
        """按 build.ps1 的解析规则展开 music 工程源码，确认没有缺失文件。"""
        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        for project in (
            "BUZZER_MUSIC_GENERATED",
            "BUZZER_MUSIC_SMOKE",
            "BUZZER_MUSIC_SONG_SMOKE",
        ):
            resolved = list(manifest["source_groups"]["common"])
            resolved.append(f"projects/{project}/src/isr.c")
            resolved.append(f"projects/{project}/src/main.c")
            for group in manifest["projects"][project]["library_groups"]:
                resolved.extend(manifest["source_groups"][group])
            for relative_source in dict.fromkeys(resolved):
                self.assertTrue(
                    (ROOT / relative_source).is_file(),
                    f"{project}: 构建清单展开后缺少源文件 {relative_source}",
                )

    def test_staff_renderer_uses_page_format_frame_buffer(self) -> None:
        header = (
            ROOT / "libraries" / "boards" / "inc" / "StaffRender.h"
        ).read_text(encoding="utf-8")
        renderer = (
            ROOT / "libraries" / "boards" / "src" / "StaffRender.c"
        ).read_text(encoding="utf-8")
        oled_staff = (
            ROOT / "libraries" / "boards" / "src" / "OLED_Staff.c"
        ).read_text(encoding="utf-8")
        lcd_frame = (
            ROOT / "libraries" / "boards" / "src" / "LCD_Frame.c"
        ).read_text(encoding="utf-8")
        for symbol in (
            "STAFF_FRAME_BYTES",
            "StaffRender_DrawFrame",
            "StaffRender_PanelWidth",
            "StaffRender_NoteAreaStart",
            "StaffRender_CursorX",
            "StaffSong",
        ):
            self.assertIn(symbol, header)
        # 帧缓冲 1024B 必须是 static 数组（大模型下进 XSEG），不能放栈上。
        self.assertIn("static uint8_t staffFrame[STAFF_FRAME_BYTES];", oled_staff)
        self.assertIn("OLEDStaff_Init", oled_staff)
        self.assertIn("LCD_WriteFrame", oled_staff)
        # 整屏写命令序列与 LCD.c 的 LCD_Fill 一致。
        self.assertIn("0xB0u + page", lcd_frame)
        self.assertIn("LCD_FrameWriteByte(0x01u, 0u)", lcd_frame)
        self.assertIn("LCD_FrameWriteByte(0x10u, 0u)", lcd_frame)
        # 渲染器先清零再绘制。
        self.assertIn("memset(frame1024, 0, STAFF_FRAME_BYTES)", renderer)

    def test_vendor_lcd_and_oled_sources_are_unmodified(self) -> None:
        for relative_path, expected_hash in self.VENDOR_FILE_SHA256.items():
            with self.subTest(path=relative_path):
                path = ROOT / relative_path
                self.assertTrue(path.is_file(), f"厂商文件缺失: {relative_path}")
                actual = hashlib.sha256(path.read_bytes()).hexdigest()
                self.assertEqual(
                    expected_hash,
                    actual,
                    f"{relative_path} 被修改了；五线谱写屏请用新增的 "
                    "LCD_Frame.c/OLED_Staff.c 实现，不要改厂商文件。",
                )


class UsbCdcBridgeContractTests(unittest.TestCase):
    """USB_CDC_BRIDGE 的 SDCC 移植契约。

    固件来自 STC 官方 70-CDC 例程，但必须按 SDCC MCS-251 的规则改写：
    - 不允许把 Keil 的 code/xdata/bit/interrupt 关键字带回来；
    - IE2/P_SW2/IRCBAND/S2CON/AUXR 不是可位寻址 SFR，必须整字节操作；
    - EP0 描述符必须先拷到 XDATA，不能把 __code 数组直接赋给 generic 指针；
    - ISR 共享变量必须 volatile，环形缓冲回绕判断必须用 (BYTE)(w - r)。
    """

    PROJECT = ROOT / "projects" / "USB_CDC_BRIDGE"

    @staticmethod
    def _strip_comments(text: str) -> str:
        return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.DOTALL)

    def _source(self, name: str) -> str:
        return (self.PROJECT / "src" / name).read_text(encoding="utf-8")

    def test_no_keil_storage_or_interrupt_keywords(self) -> None:
        for path in sorted((self.PROJECT / "src").glob("*.c")):
            text = self._strip_comments(path.read_text(encoding="utf-8"))
            self.assertIsNone(
                re.search(r"\b(?:code|xdata|bit|interrupt)\b", text),
                f"{path.name}: 仍含 Keil 关键字",
            )

    def test_non_addressable_sfr_bits_use_byte_masks(self) -> None:
        usb = self._strip_comments(self._source("usb.c"))
        uart = self._strip_comments(self._source("uart_cdc.c"))

        self.assertNotRegex(usb, r"\bEUSB\b\s*=")
        self.assertNotRegex(usb, r"\b(?:EAXFR|USBCKS|USBCKS2)\b\s*=")
        self.assertIn("IE2 |= 0x80", usb)
        self.assertIn("IRCBAND = (IRCBAND & 0x03) | 0x80", usb)

        self.assertNotRegex(uart, r"\b(?:ES2|S2_S|S2TI|S2RI|S2TB8|T2x12|T2R)\b\s*=")
        self.assertIn("IE2 |= 0x01", uart)
        self.assertIn("AUXR |= 0x14", uart)
        self.assertIn("S2CON", uart)

    def test_usb_and_uart_isr_signatures(self) -> None:
        usb = self._source("usb.c")
        uart = self._source("uart_cdc.c")
        isr = self._source("isr.c")

        self.assertIn("void usb_isr(void) __interrupt (25)", usb)
        self.assertIn(
            "void uart2_isr(void) __interrupt (UART2_VECTOR)", uart
        )
        self.assertIn(
            "void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)", isr
        )

    def test_ep0_descriptors_are_staged_in_xdata(self) -> None:
        std = self._strip_comments(self._source("usb_req_std.c"))
        self.assertIn("__xdata BYTE Ep0Stage[EP0_STAGE_SIZE];", std)
        self.assertIn("Ep0LoadDescriptor", std)
        self.assertNotRegex(
            std,
            r"Ep0State\.pData\s*=\s*(?:DEVICEDESC|CONFIGDESC|LANGIDDESC|"
            r"MANUFACTDESC|PRODUCTDESC)",
        )

    def test_shared_isr_state_is_volatile(self) -> None:
        usb = self._source("usb.c")
        uart = self._source("uart_cdc.c")
        for declaration in (
            "volatile BYTE DeviceState;",
            "volatile BOOL UsbInBusy;",
            "volatile BOOL UsbOutBusy;",
            "volatile BYTE RxWptr;",
            "volatile BYTE TxWptr;",
        ):
            self.assertIn(declaration, usb)
        self.assertIn("volatile BOOL UartBusy", uart)

    def test_ring_buffers_use_byte_difference(self) -> None:
        usb = self._strip_comments(self._source("usb.c"))
        uart = self._strip_comments(self._source("uart_cdc.c"))
        self.assertIn("(BYTE)(RxWptr - RxRptr)", usb)
        self.assertIn("(BYTE)(TxWptr - TxRptr)", uart)

    def test_wire_struct_sizes_are_checked(self) -> None:
        usb = self._source("usb.c")
        self.assertIn("sizeof(SETUP) == 8", usb)
        self.assertIn("sizeof(LINECODING) == 7", usb)

    def test_manifest_lists_bridge_sources(self) -> None:
        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        self.assertIn("USB_CDC_BRIDGE", manifest["projects"])
        self.assertEqual(
            ["usb_cdc"],
            list(manifest["projects"]["USB_CDC_BRIDGE"]["library_groups"]),
        )
        relative_sources = manifest["source_groups"]["usb_cdc"]
        self.assertEqual(len(relative_sources), len(set(relative_sources)))
        for relative_source in relative_sources:
            self.assertTrue(
                (ROOT / relative_source).is_file(),
                f"usb_cdc 源组里的文件不存在: {relative_source}",
            )


if __name__ == "__main__":
    unittest.main()

