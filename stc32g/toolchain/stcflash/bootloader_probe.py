#!/usr/bin/env python3
"""与 PIE_BOOTLOADER 通信的最小客户端，用于验证 bootloader 是否活着。

官方帧协议（见 PIE_BOOTLOADER/USER/src/uart.c）：
  主机 -> 芯片:  '#' | len | cmd | payload... | '$' | 累加和
  芯片 -> 主机:  '@' | status | size | payload... | '$' | 累加和

  len   = cmd 加 payload 的字节数（不含帧头帧尾与校验）
  累加和 = 使前面所有字节之和的低 8 位为 0 的那个字节

用法：
  python bootloader_probe.py COM11 connect
  python bootloader_probe.py COM11 erase
  python bootloader_probe.py COM11 read 0x11000 16
"""
import argparse
import sys
import time

try:
    import serial
except ImportError:
    print("需要 pyserial：pip install pyserial", file=sys.stderr)
    sys.exit(1)

CMD_CONNECT = 0xA0
CMD_READ = 0xA1
CMD_PROGRAM = 0xA2
CMD_ERASE = 0xA3
CMD_REBOOT = 0xA4

STATUS_NAMES = {
    0x00: "OK",
    0x01: "ERRORCMD (命令不支持)",
    0x02: "OUTOFRANGE (地址越界)",
    0x03: "PROGRAMERR (写入失败)",
    0xFF: "ERRORWRAP (帧错误)",
}


def build_frame(cmd, payload=b""):
    """组帧。累加和取负，使整帧字节之和的低 8 位为 0。"""
    body = bytes([0x23, len(payload) + 1, cmd]) + payload + b"\x24"
    checksum = (-sum(body)) & 0xFF
    return body + bytes([checksum])


def parse_response(raw):
    """解析芯片回应，返回 (status, payload) 或抛 ValueError。"""
    start = raw.find(b"@")
    if start < 0:
        raise ValueError(f"没找到帧头 '@'，收到 {raw.hex(' ') or '(空)'}")
    frame = raw[start:]
    if len(frame) < 5:
        raise ValueError(f"帧太短: {frame.hex(' ')}")
    status, size = frame[1], frame[2]
    need = 3 + size + 2
    if len(frame) < need:
        raise ValueError(f"帧不完整，需要 {need} 字节只有 {len(frame)}: {frame.hex(' ')}")
    frame = frame[:need]
    if frame[3 + size] != 0x24:
        raise ValueError(f"帧尾不是 '$': {frame.hex(' ')}")
    if (sum(frame) & 0xFF) != 0:
        raise ValueError(f"校验和错误（和={sum(frame) & 0xFF:#04x}）: {frame.hex(' ')}")
    return status, frame[3:3 + size]


def request(port, baud, cmd, payload=b"", timeout=1.5, retries=3):
    """发一帧并等回应。bootloader 无缓冲，失败时重试。"""
    frame = build_frame(cmd, payload)
    with serial.Serial(port, baud, timeout=timeout) as ser:
        for attempt in range(1, retries + 1):
            ser.reset_input_buffer()
            ser.write(frame)
            ser.flush()
            print(f"  [{attempt}] 发送 {frame.hex(' ')}")
            time.sleep(0.05)
            raw = ser.read(64)
            if not raw:
                print("      无回应")
                continue
            print(f"      收到 {raw.hex(' ')}")
            try:
                return parse_response(raw)
            except ValueError as exc:
                print(f"      解析失败: {exc}")
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("port", help="串口，例如 COM11")
    ap.add_argument("action", choices=["connect", "erase", "read", "reboot"])
    ap.add_argument("addr", nargs="?", help="read 的 IAP 起始地址，如 0x11000")
    ap.add_argument("size", nargs="?", type=int, help="read 的字节数")
    ap.add_argument("--baud", type=int, default=230400)
    args = ap.parse_args(argv)

    print(f"串口 {args.port} @ {args.baud}")

    if args.action == "connect":
        print("CONNECT: 期望回 status=OK, payload=02 00 (LDR_VERSION 0x0200)")
        got = request(args.port, args.baud, CMD_CONNECT)
    elif args.action == "erase":
        print("ERASE: 擦除 App 区（bootloader 自身受 iap_check_addr 保护）")
        got = request(args.port, args.baud, CMD_ERASE, timeout=8.0)
    elif args.action == "reboot":
        print("REBOOT: 芯片软复位，不会有回应")
        got = request(args.port, args.baud, CMD_REBOOT, retries=1)
    else:
        if args.addr is None or args.size is None:
            ap.error("read 需要 addr 与 size")
        addr = int(args.addr, 0)
        payload = bytes([addr & 0xFF, (addr >> 8) & 0xFF, (addr >> 16) & 0xFF,
                         0x00, args.size])
        print(f"READ: IAP 0x{addr:05X} 起 {args.size} 字节")
        print("  注意：官方 bootloader 的 READ 只在 #define DEBUG 时启用，")
        print("        未启用会回 ERRORCMD，这是正常的")
        got = request(args.port, args.baud, CMD_READ, payload)

    print()
    if got is None:
        print("结果: 没有拿到有效回应")
        print("排查方向：")
        print("  1. STC-ISP 里 IRC 频率是否设成 33.1776MHz（错了波特率就不对）")
        print("  2. 烧录后是否断电重新上电（EEPROM 设置需重新上电才生效）")
        print("  3. 串口号是否正确、是否被其他程序占用")
        return 1

    status, payload = got
    print(f"结果: status={status:#04x} ({STATUS_NAMES.get(status, '未知')})")
    if payload:
        print(f"      payload={payload.hex(' ')}")
    if args.action == "connect" and status == 0 and len(payload) == 2:
        ver = (payload[0] << 8) | payload[1]
        print(f"      bootloader 版本 {ver:#06x} "
              f"({'与 LDR_VERSION 一致' if ver == 0x0200 else '与预期 0x0200 不符'})")
    return 0 if status == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
