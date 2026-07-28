#!/usr/bin/env python3
"""
pie_block_flash.py - STC32G 串口一键烧录（仅 UART，基于 stcgal 协议库）

关键修复：
  1) 同一串口会话完成 @STCISP# → 0x7F 握手（避免 close 后丢 ISP 窗口）
  2) 绕过 stcgal.connect 时必须先 initialize_model()
  3) 强制 trim=33177.6kHz（对齐 FOSC=33177600），避免被写成 ~11MHz
  4) 若芯片已被写成 ~11MHz，按 11/33 比例推算真实波特率再试
"""

from __future__ import annotations

import os
import sys
import time


DEFAULT_TRIM_KHZ = 33177.6
DEFAULT_HANDSHAKE = 2400
DEFAULT_TRANSFER = 115200

# 名义波特率（固件里写的）
NOMINAL_BAUDS = (230400, 115200, 460800, 57600, 38400, 19200, 9600)

# 若 option 频率被 stcgal 默认写成 ~11.0592M，而代码按 33.1776M 配波特率，
# 真实波特率 ≈ nominal * 11.0592/33.1776 ≈ nominal * 1/3
FOSC_CODE = 33177600.0
FOSC_WRONG = 11059200.0  # 常见默认/测量值附近


def _scaled_bauds(nominal: int) -> list[int]:
    out = [int(nominal)]
    # 11M / 33M
    out.append(int(round(nominal * FOSC_WRONG / FOSC_CODE)))
    # 24M / 33M（若被校到 24M）
    out.append(int(round(nominal * 24000000.0 / FOSC_CODE)))
    # 12M / 33M
    out.append(int(round(nominal * 12000000.0 / FOSC_CODE)))
    return out


def _all_app_bauds(preferred: int) -> list[int]:
    seq: list[int] = []
    for n in (preferred,) + NOMINAL_BAUDS:
        for b in _scaled_bauds(int(n)):
            if b >= 1200 and b not in seq:
                seq.append(b)
    # 额外密集点（历史误报/实测附近）
    for b in (128000, 76800, 38400, 25600, 110592, 55296, 36600, 37300, 38000, 39000):
        if b not in seq:
            seq.append(b)
    return seq


def _fix_stdio() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def _p(msg: str) -> None:
    try:
        print(msg, flush=True)
    except UnicodeEncodeError:
        print(msg.encode("gbk", errors="replace").decode("gbk", errors="replace"), flush=True)


def _load_image(path: str) -> bytes:
    from stcgal.ihex import IHex

    with open(path, "rb") as f:
        low = path.lower()
        if low.endswith((".hex", ".ihx", ".ihex")):
            data = IHex.read(f).extract_data()
            _p("Loading flash: %d bytes (Intel HEX)" % len(data))
            return data
        data = f.read()
        _p("Loading flash: %d bytes (Binary)" % len(data))
        return data


def _pad512(data: bytes) -> bytes:
    if len(data) % 512:
        data += b"\xff" * (512 - len(data) % 512)
    return data


def _open_serial(port: str, baud: int):
    import serial

    ser = serial.Serial()
    ser.port = port
    ser.baudrate = baud
    ser.parity = serial.PARITY_NONE
    ser.bytesize = serial.EIGHTBITS
    ser.stopbits = serial.STOPBITS_ONE
    ser.timeout = 0.5
    ser.write_timeout = 1.0
    ser.dsrdtr = False
    ser.rtscts = False
    ser.dtr = False
    ser.rts = False
    ser.open()
    try:
        ser.dtr = False
        ser.rts = False
    except Exception:
        pass
    time.sleep(0.05)
    try:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
    except Exception:
        pass
    return ser


def _send_soft_isp(ser, baud: int) -> None:
    ser.baudrate = int(baud)
    time.sleep(0.02)
    try:
        ser.reset_input_buffer()
    except Exception:
        pass
    # 多轮发送；官方命令 8 字节
    payload = b"@STCISP#"
    for _ in range(6):
        ser.write(payload)
        ser.flush()
        time.sleep(0.025)
    # 软复位进 ROM ISP 需要一点时间
    time.sleep(0.15)


def _line_pulse(ser, pin: str) -> None:
    try:
        if pin == "rts":
            ser.rts = True
            time.sleep(0.2)
            ser.rts = False
        else:
            ser.dtr = True
            time.sleep(0.2)
            ser.dtr = False
        time.sleep(0.05)
    except Exception as exc:
        _p("线控复位失败(%s): %s" % (pin, exc))


def _handshake_like_stcgal(proto, timeout_s: float) -> bool:
    """复刻 stcgal connect 的 pulse + get_status_packet；成功则 status_packet 有效。"""
    import serial
    from stcgal.protocols import StcFramingException, StcProtocolException

    ser = proto.ser
    ser.baudrate = proto.baud_handshake
    ser.timeout = 0.5
    try:
        ser.inter_byte_timeout = 0.5
    except Exception:
        try:
            ser.interCharTimeout = 0.5
        except Exception:
            pass
    try:
        ser.reset_input_buffer()
    except Exception:
        pass

    t0 = time.time()
    proto.status_packet = None
    while time.time() - t0 < timeout_s:
        try:
            ser.write(b"\x7f")
            ser.flush()
            time.sleep(0.030)
            if ser.in_waiting <= 0:
                continue
            packet = proto.get_status_packet()
            # stc8/stc15 状态包 magic 为 0x50，且需足够长以含 model magic
            if packet is not None and len(packet) >= 23 and packet[0] == 0x50:
                proto.status_packet = packet
                # 立刻解析型号，便于日志与后续 program
                proto.initialize_model()
                return True
        except (StcFramingException, StcProtocolException, serial.SerialTimeoutException, OSError):
            try:
                ser.reset_input_buffer()
            except Exception:
                pass
        except Exception:
            try:
                ser.reset_input_buffer()
            except Exception:
                pass
    return False


def _do_program(proto, bindata: bytes, trim_hz: int) -> None:
    if not getattr(proto, "model", None):
        proto.initialize_model()
    _p("Target model: %s (magic %04X)" % (proto.model.name, proto.mcu_magic))
    proto.initialize(None)
    # initialize() 可能改 trim；再强制一次
    proto.trim_frequency = int(trim_hz)
    _p("Forced trim_frequency = %d Hz" % proto.trim_frequency)

    if getattr(proto, "split_code", None) and getattr(proto.model, "iap", False):
        code_size = proto.split_code
        ee_size = proto.split_eeprom or 0
    else:
        code_size = proto.model.code
        ee_size = proto.model.eeprom or 0

    # MCS-251 IAP 芯片：stcgal 对 split 有特殊处理，未 set option 时 split_code 可能仍是 None
    if getattr(proto.model, "mcs251", False) and getattr(proto.model, "iap", False):
        # 与 Stc8dProtocol.set_option(program_eeprom_split) 默认一致：code 用 model.code
        if not code_size:
            code_size = proto.model.code
        if not ee_size:
            ee_size = 0

    if len(bindata) > code_size + ee_size:
        _p("WARNING: image truncated")
        bindata = bindata[: code_size + ee_size]
    bindata = _pad512(bindata)

    proto.handshake()
    proto.erase_flash(len(bindata), code_size)
    proto.program_flash(bindata)
    proto.program_options()
    proto.disconnect()


def flash(hex_path: str, port: str, app_baud: int, transfer: int, mode: str, trim_khz: float) -> int:
    from stcgal.protocols import Stc8dProtocol

    bindata = _load_image(hex_path)
    trim_hz = int(round(float(trim_khz) * 1000.0))

    proto = Stc8dProtocol(port, DEFAULT_HANDSHAKE, transfer, trim_hz)
    proto.debug = False
    ser = _open_serial(port, DEFAULT_HANDSHAKE)
    proto.ser = ser

    entered = False
    try:
        if mode == "uart":
            bauds = _all_app_bauds(app_baud)
            _p("将尝试 %d 种应用波特率（含 11M/33M 比例换算）" % len(bauds))

            for b in bauds:
                _p("软触发 @STCISP# @ %d → 握手 %d" % (b, DEFAULT_HANDSHAKE))
                _send_soft_isp(ser, b)
                # ISP 窗口：给足 2 秒连续 0x7F
                if _handshake_like_stcgal(proto, timeout_s=2.0):
                    _p("软触发成功（baud=%d, model=%s）" % (b, proto.model.name))
                    entered = True
                    break
                _p("  未响应")

            if not entered:
                for pin in ("dtr", "rts"):
                    _p("尝试 %s 线控复位…" % pin.upper())
                    ser.baudrate = DEFAULT_HANDSHAKE
                    _line_pulse(ser, pin)
                    if _handshake_like_stcgal(proto, timeout_s=2.0):
                        _p("线控复位成功（%s, model=%s）" % (pin, proto.model.name))
                        entered = True
                        break

            if not entered:
                _p("================================================")
                _p("自动进 ISP 失败。请现在按一次 Reset / 断电上电（25 秒内）")
                _p("本次将写入 trim=%.1f kHz，之后软触发应可用" % trim_khz)
                _p("================================================")
                if _handshake_like_stcgal(proto, timeout_s=25.0):
                    _p("已捕获 MCU（Reset/上电, model=%s）" % proto.model.name)
                    entered = True
        else:
            _p("请断电再上电或按 Reset（30 秒内）…")
            if _handshake_like_stcgal(proto, timeout_s=30.0):
                entered = True

        if not entered:
            _p("错误：超时未进入 ISP")
            try:
                ser.close()
            except Exception:
                pass
            return 2

        _p("开始编程（stc8d, transfer=%d, trim=%.1f kHz）" % (transfer, trim_khz))
        ser.timeout = 15.0
        try:
            ser.inter_byte_timeout = 1.0
        except Exception:
            try:
                ser.interCharTimeout = 1.0
            except Exception:
                pass

        _do_program(proto, bindata, trim_hz)
        _p("烧录成功")
        return 0
    except KeyboardInterrupt:
        _p("interrupted")
        try:
            ser.close()
        except Exception:
            pass
        return 2
    except Exception as exc:
        _p("烧录失败: %s: %s" % (type(exc).__name__, exc))
        import traceback

        traceback.print_exc()
        try:
            ser.close()
        except Exception:
            pass
        return 3


def main() -> int:
    _fix_stdio()
    if len(sys.argv) < 4:
        _p("用法: python pie_block_flash.py uart|uart-power <hex> <com> [app_baud] [isp_baud]")
        return 1

    mode = sys.argv[1].lower()
    if mode not in ("uart", "uart-power"):
        _p("仅支持 uart / uart-power")
        return 1

    hex_file = sys.argv[2]
    port = sys.argv[3]
    if not os.path.isfile(hex_file):
        _p("错误：hex 不存在: %s" % hex_file)
        return 4

    if mode == "uart":
        app_baud = int(sys.argv[4]) if len(sys.argv) > 4 else 230400
        isp_baud = int(sys.argv[5]) if len(sys.argv) > 5 else DEFAULT_TRANSFER
    else:
        app_baud = 230400
        isp_baud = int(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_TRANSFER

    trim_khz = float(os.environ.get("PIE_STC_TRIM_KHZ", str(DEFAULT_TRIM_KHZ)))
    return flash(hex_file, port, app_baud, isp_baud, mode, trim_khz)


if __name__ == "__main__":
    sys.exit(main())
