#!/usr/bin/env python3
"""
pie_block_iap.py - STC32G 自定义 bootloader 串口下载工具

与 pie_block_flash.py（走 ROM ISP + stcgal）的区别：
  这个脚本对话的是我们自己写的 bootloader，协议自定，
  不依赖 ROM ISP、不依赖 IRC trim、不需要 2400 波特率握手。

流程：
  1. 以 App 波特率打开串口，发 @PIEIAP#
     App 的 UART1 ISR 收到后写下载标志、IAP_CONTR=0x20 软复位到用户程序
  2. 芯片复位后跑的是 0xFF0000 的 bootloader，切到 bootloader 波特率
  3. PING 确认 bootloader 在线
  4. ERASE → 分块 WRITE → VERIFY 比对 CRC → RUN

帧格式（PC ⇄ bootloader 双向同构）：
    AA 55 | ver | cmd | addr(3, 小端) | len(2, 小端) | payload... | crc16(2, 小端)
    crc16 覆盖从 ver 到 payload 末字节（不含 AA 55 帧头本身）

协议层（build_frame / parse_frame / crc16 / hex_to_app_image）不碰串口，
可以脱离硬件自测，见 --selftest。
"""

from __future__ import annotations

import sys
import time

# ------------------------------------------------------------------ 协议常量

FRAME_MAGIC = b"\xAA\x55"
PROTO_VER = 0x01

CMD_PING = 0x01
CMD_ERASE = 0x02
CMD_WRITE = 0x03
CMD_VERIFY = 0x04
CMD_RUN = 0x05

# bootloader 的应答码。ACK/NAK 走 cmd 字段高位，便于一眼区分方向。
RESP_ACK = 0x80
RESP_NAK = 0x81

CMD_NAMES = {
    CMD_PING: "PING",
    CMD_ERASE: "ERASE",
    CMD_WRITE: "WRITE",
    CMD_VERIFY: "VERIFY",
    CMD_RUN: "RUN",
    RESP_ACK: "ACK",
    RESP_NAK: "NAK",
}

# 触发命令字。App 的 UART1 ISR 匹配这 8 字节。
TRIGGER = b"@PIEIAP#"

# 地址布局（EEPROM=128K 模式，实测确认）：
#
#   物理 0xFF0000  = IAP 地址 0x010000  Bootloader 8K
#   物理 0xFF2000  = IAP 地址 0x012000  App 代码区
#   物理 0xFFFE00  = IAP 地址 0x01FE00  元数据扇区
#   物理 0xFE0000  = IAP 地址 0x000000  EEPROM 数据区（不可取指）
#
# 为何 App 不放 0xFE0000：实测证明该区不能取指执行（调用后芯片复位）。
# EEPROM=128K 时整片 flash 都是 IAP 可写区，所以 App 可以留在代码区。

# Bootloader 占用的 IAP 地址范围
BOOT_IAP_BASE = 0x010000
BOOT_IAP_SIZE = 0x2000  # 8K

# App 区在 IAP 线性地址空间的起点
APP_IAP_BASE = 0x012000
# 元数据扇区地址（App 区最后一个扇区，不得写入 App 代码）
META_IAP_ADDR = 0x01FE00
# App 区可用大小
APP_REGION_SIZE = META_IAP_ADDR - APP_IAP_BASE  # 0xDE00 = 56832
# hex 里 App 代码的链接基址
APP_LINK_BASE = 0xFF2000

SECTOR_SIZE = 512
# 单帧 payload 上限。bootloader 侧收帧缓冲区要能装下。
MAX_PAYLOAD = 256

DEFAULT_APP_BAUD = 230400
DEFAULT_BOOT_BAUD = 115200


class ProtocolError(Exception):
    pass


# ------------------------------------------------------------------ CRC16

def crc16(data: bytes) -> int:
    """CRC-16/MODBUS（多项式 0xA001 反向）。

    选它的理由：查表版在 8051 上只要几十字节代码，
    bootloader 空间紧张，不用 CRC32。
    """
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF


# ------------------------------------------------------------------ 帧编解码

def build_frame(cmd: int, addr: int = 0, payload: bytes = b"") -> bytes:
    """组一个帧。addr 与 len 都是小端，方便 8051 侧直接按字节取。"""
    if len(payload) > 0xFFFF:
        raise ValueError("payload too long: %d" % len(payload))
    if not (0 <= addr <= 0xFFFFFF):
        raise ValueError("addr out of 24-bit range: 0x%X" % addr)

    body = bytes([
        PROTO_VER,
        cmd & 0xFF,
        addr & 0xFF,
        (addr >> 8) & 0xFF,
        (addr >> 16) & 0xFF,
        len(payload) & 0xFF,
        (len(payload) >> 8) & 0xFF,
    ]) + payload

    c = crc16(body)
    return FRAME_MAGIC + body + bytes([c & 0xFF, (c >> 8) & 0xFF])


def parse_frame(buf: bytes):
    """从 buf 头部解一个帧。

    返回 (cmd, addr, payload, consumed)。
    数据不足返回 None —— 调用方继续读串口再试，而不是当成错误。
    CRC 或帧头不对则抛 ProtocolError。
    """
    if len(buf) < 2:
        return None
    if buf[0:2] != FRAME_MAGIC:
        raise ProtocolError("bad frame magic: %s" % buf[0:2].hex())
    # 帧头 2 + body 头 7 + crc 2
    if len(buf) < 11:
        return None

    length = buf[7] | (buf[8] << 8)
    total = 2 + 7 + length + 2
    if len(buf) < total:
        return None

    body = buf[2:2 + 7 + length]
    got = buf[2 + 7 + length] | (buf[2 + 7 + length + 1] << 8)
    want = crc16(body)
    if got != want:
        raise ProtocolError("crc mismatch: got %04X want %04X" % (got, want))

    cmd = body[1]
    addr = body[2] | (body[3] << 8) | (body[4] << 16)
    payload = bytes(body[7:])
    return cmd, addr, payload, total


# ------------------------------------------------------------------ hex 处理

def hex_to_app_image(path: str) -> bytes:
    """读 Intel HEX，抽出 App 区那段，按扇区补齐。

    App 链接在 0xFF2000（bootloader 之后），hex 里会有一条
    type 04 记录把 linear base 设成 0x00FF。
    返回的 bytes 下标 0 对应 IAP 地址 APP_IAP_BASE。

    链接到 0xFF0000 的 hex 会被拒绝——那是 bootloader 自己的地盘。
    """
    segments = parse_ihex(path)
    if not segments:
        raise ProtocolError("hex 里没有任何数据记录: %s" % path)

    lo = min(segments)
    hi = max(a for a in segments)

    # 落在 App 区之外的地址一律是配置错误，早报比晚报好
    for addr in (lo, hi):
        if not (APP_LINK_BASE <= addr < APP_LINK_BASE + APP_REGION_SIZE):
            raise ProtocolError(
                "hex 地址 0x%06X 不在 App 区 [0x%06X, 0x%06X) 内。\n"
                "  App 必须链接到 0x%06X。检查 uvproj 的 IROM 设置。"
                % (addr, APP_LINK_BASE, APP_LINK_BASE + APP_REGION_SIZE, APP_LINK_BASE)
            )

    size = hi - APP_LINK_BASE + 1
    if size % SECTOR_SIZE:
        size += SECTOR_SIZE - (size % SECTOR_SIZE)

    img = bytearray(b"\xFF" * size)
    for addr, val in segments.items():
        img[addr - APP_LINK_BASE] = val
    return bytes(img)


def parse_ihex(path: str) -> dict:
    """最小 Intel HEX 解析，支持 type 00/01/04。

    返回 {绝对地址: 字节值}。不自己拼段，交给调用方决定布局。
    """
    out = {}
    base = 0
    with open(path, "r", encoding="ascii", errors="strict") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line:
                continue
            if not line.startswith(":"):
                raise ProtocolError("%s:%d 不是以 ':' 开头" % (path, lineno))
            try:
                rec = bytes.fromhex(line[1:])
            except ValueError as e:
                raise ProtocolError("%s:%d 十六进制解析失败: %s" % (path, lineno, e))
            if len(rec) < 5:
                raise ProtocolError("%s:%d 记录过短" % (path, lineno))

            count, hi, lo, rtype = rec[0], rec[1], rec[2], rec[3]
            data = rec[4:4 + count]
            if len(data) != count:
                raise ProtocolError("%s:%d 长度字段与实际不符" % (path, lineno))
            if (sum(rec) & 0xFF) != 0:
                raise ProtocolError("%s:%d 校验和错误" % (path, lineno))

            if rtype == 0x00:
                off = (hi << 8) | lo
                for i, b in enumerate(data):
                    out[base + off + i] = b
            elif rtype == 0x01:
                break
            elif rtype == 0x04:
                if count != 2:
                    raise ProtocolError("%s:%d type 04 长度应为 2" % (path, lineno))
                base = ((data[0] << 8) | data[1]) << 16
            # 其余记录类型（02/03/05）对本用途无意义，忽略
    return out


# ------------------------------------------------------------------ 串口会话

class IapSession:
    def __init__(self, port: str, app_baud: int, boot_baud: int, verbose: bool = True):
        self.port = port
        self.app_baud = app_baud
        self.boot_baud = boot_baud
        self.verbose = verbose
        self.ser = None
        self._rx = bytearray()

    def log(self, msg: str) -> None:
        if self.verbose:
            print(msg, flush=True)

    def open(self) -> None:
        import serial
        self.ser = serial.Serial(
            self.port, self.app_baud, timeout=0.2,
            parity=serial.PARITY_NONE, stopbits=1, bytesize=8,
        )

    def close(self) -> None:
        if self.ser is not None:
            try:
                self.ser.close()
            finally:
                self.ser = None

    def set_baud(self, baud: int) -> None:
        self.ser.baudrate = baud

    def trigger(self) -> None:
        """发触发命令让 App 软复位到 bootloader。

        若芯片本来就停在 bootloader（上次下载失败），这一步收不到回应也无妨，
        后面 PING 会兜住。
        """
        self.log("发送触发命令 %s @ %d baud" % (TRIGGER.decode(), self.app_baud))
        self.set_baud(self.app_baud)
        self.ser.reset_input_buffer()
        self.ser.write(TRIGGER)
        self.ser.flush()

    def send(self, cmd: int, addr: int = 0, payload: bytes = b"") -> None:
        frame = build_frame(cmd, addr, payload)
        self.ser.write(frame)
        self.ser.flush()

    def recv(self, timeout: float = 1.0):
        """读一个完整帧。超时返回 None。

        串口是字节流，可能一次读到半个帧或多个帧，所以维护一个累积缓冲区。
        帧头之前的垃圾字节（App 复位时的乱码）要跳过而不是报错。
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            chunk = self.ser.read(256)
            if chunk:
                self._rx.extend(chunk)

            # 丢弃帧头之前的噪声
            while len(self._rx) >= 2 and self._rx[0:2] != FRAME_MAGIC:
                # 只有第一个字节可能是 AA 而第二个不是 55，这种情况也要前移
                del self._rx[0]

            if len(self._rx) >= 11:
                try:
                    got = parse_frame(bytes(self._rx))
                except ProtocolError as e:
                    # 坏帧：丢掉这个帧头继续找，别让一次误码毁掉整次下载
                    self.log("  [warn] %s，丢弃并重新同步" % e)
                    del self._rx[0:2]
                    continue
                if got is not None:
                    cmd, addr, payload, consumed = got
                    del self._rx[0:consumed]
                    return cmd, addr, payload
        return None

    def request(self, cmd: int, addr: int = 0, payload: bytes = b"",
                timeout: float = 1.0, retries: int = 3):
        """发一帧并等 ACK。返回 ACK 的 payload。"""
        name = CMD_NAMES.get(cmd, "0x%02X" % cmd)
        for attempt in range(1, retries + 1):
            self.send(cmd, addr, payload)
            got = self.recv(timeout=timeout)
            if got is None:
                self.log("  %s 第 %d 次无应答" % (name, attempt))
                continue
            rcmd, raddr, rpayload = got
            if rcmd == RESP_ACK:
                return rpayload
            if rcmd == RESP_NAK:
                self.log("  %s 被拒绝（NAK），第 %d 次" % (name, attempt))
                continue
            self.log("  %s 收到意外应答 0x%02X，第 %d 次" % (name, rcmd, attempt))
        raise ProtocolError("%s 连续 %d 次失败" % (name, retries))

    def wait_bootloader(self, total_timeout: float = 5.0) -> None:
        """切到 bootloader 波特率，反复 PING 直到有回应。"""
        self.log("等待 bootloader（%d baud）…" % self.boot_baud)
        self.set_baud(self.boot_baud)
        self._rx.clear()
        self.ser.reset_input_buffer()

        deadline = time.time() + total_timeout
        while time.time() < deadline:
            self.send(CMD_PING)
            got = self.recv(timeout=0.3)
            if got is not None and got[0] == RESP_ACK:
                ver = got[2]
                self.log("bootloader 已就绪%s" % (
                    "（版本 %s）" % ver.hex() if ver else ""))
                return
        raise ProtocolError(
            "bootloader 没有响应。可能原因：\n"
            "  - 芯片上还没烧过 bootloader（需要先用 stcgal 刷底一次）\n"
            "  - App 里没有 %s 监听代码\n"
            "  - 串口选错了" % TRIGGER.decode()
        )

    def download(self, image: bytes) -> None:
        n_sectors = (len(image) + SECTOR_SIZE - 1) // SECTOR_SIZE
        self.log("固件 %d 字节，%d 个扇区" % (len(image), n_sectors))

        self.log("擦除 App 区…")
        self.request(CMD_ERASE, APP_IAP_BASE,
                     bytes([len(image) & 0xFF, (len(image) >> 8) & 0xFF]),
                     timeout=5.0)

        self.log("写入…")
        written = 0
        while written < len(image):
            chunk = image[written:written + MAX_PAYLOAD]
            self.request(CMD_WRITE, APP_IAP_BASE + written, chunk, timeout=2.0)
            written += len(chunk)
            pct = written * 100 // len(image)
            self.log("  %d/%d 字节 (%d%%)" % (written, len(image), pct))

        self.log("校验…")
        want = crc16(image)
        resp = self.request(
            CMD_VERIFY, APP_IAP_BASE,
            bytes([len(image) & 0xFF, (len(image) >> 8) & 0xFF,
                   (len(image) >> 16) & 0xFF]),
            timeout=5.0)
        if len(resp) < 2:
            raise ProtocolError("VERIFY 应答没带 CRC")
        got = resp[0] | (resp[1] << 8)
        if got != want:
            raise ProtocolError(
                "校验失败：芯片算出 %04X，本地算出 %04X。固件未生效，"
                "bootloader 会保持等待状态，可以重新下载。" % (got, want))
        self.log("校验通过（CRC %04X）" % got)

        self.log("启动新固件…")
        self.send(CMD_RUN)
        self.ser.flush()


# ------------------------------------------------------------------ 自测

def selftest() -> int:
    """协议层自测，不需要串口也不需要板子。"""
    fails = []

    def check(name, cond, detail=""):
        if cond:
            print("  [ok] %s" % name)
        else:
            print("  [FAIL] %s %s" % (name, detail))
            fails.append(name)

    print("crc16")
    # CRC-16/MODBUS 的标准测试向量
    check("空输入", crc16(b"") == 0xFFFF, "got %04X" % crc16(b""))
    check('"123456789"', crc16(b"123456789") == 0x4B37,
          "got %04X" % crc16(b"123456789"))
    check("单字节差异会改变结果", crc16(b"\x00") != crc16(b"\x01"))

    print("build_frame / parse_frame 往返")
    for cmd, addr, payload in [
        (CMD_PING, 0, b""),
        (CMD_WRITE, 0x000200, bytes(range(256))),
        (CMD_ERASE, 0xFFFFFF, b"\x00\xFE"),
        (RESP_ACK, 0, b"\x01\x00"),
    ]:
        frame = build_frame(cmd, addr, payload)
        got = parse_frame(frame)
        ok = (got is not None and got[0] == cmd and got[1] == addr
              and got[2] == payload and got[3] == len(frame))
        check("往返 %s addr=0x%06X len=%d"
              % (CMD_NAMES.get(cmd, cmd), addr, len(payload)), ok, repr(got))

    print("parse_frame 的健壮性")
    frame = build_frame(CMD_WRITE, 0x1234, b"hello")
    for cut in range(2, len(frame)):
        got = parse_frame(frame[:cut])
        if got is not None:
            check("截断到 %d 字节应返回 None" % cut, False, repr(got))
            break
    else:
        check("任意截断都返回 None（等更多数据）", True)

    bad = bytearray(frame)
    bad[-1] ^= 0xFF
    try:
        parse_frame(bytes(bad))
        check("CRC 被破坏应抛异常", False)
    except ProtocolError:
        check("CRC 被破坏应抛异常", True)

    try:
        parse_frame(b"\x00\x11" + frame[2:])
        check("帧头错误应抛异常", False)
    except ProtocolError:
        check("帧头错误应抛异常", True)

    got = parse_frame(frame + build_frame(CMD_PING))
    check("多帧粘连时只消费第一帧",
          got is not None and got[3] == len(frame), repr(got))

    print("parse_ihex")
    import os
    import tempfile

    def rec(rtype, addr, data):
        body = bytes([len(data), (addr >> 8) & 0xFF, addr & 0xFF, rtype]) + data
        return ":" + (body + bytes([(-sum(body)) & 0xFF])).hex().upper() + "\n"

    tmpdir = tempfile.mkdtemp(prefix="iap_selftest_")
    try:
        p = os.path.join(tmpdir, "t.hex")
        with open(p, "w", encoding="ascii") as f:
            # type 04 给的是高 16 位地址，0x00FF << 16 == 0xFF0000
            # App 从 0xFF2000 开始，所以数据记录偏移是 0x2000
            f.write(rec(0x04, 0, bytes([0x00, 0xFF])))
            f.write(rec(0x00, 0x2000, b"\x01\x02\x03\x04"))
            f.write(rec(0x00, 0x2010, b"\xAA"))
            f.write(rec(0x01, 0, b""))

        segs = parse_ihex(p)
        check("解析出 5 个字节", len(segs) == 5, "got %d" % len(segs))
        check("基址生效：0xFF2000 处是 0x01",
              segs.get(0xFF2000) == 0x01, repr(segs.get(0xFF2000)))
        check("0xFF2010 处是 0xAA",
              segs.get(0xFF2010) == 0xAA, repr(segs.get(0xFF2010)))

        img = hex_to_app_image(p)
        check("补齐到扇区边界", len(img) == SECTOR_SIZE, "got %d" % len(img))
        check("镜像下标 0 是 0x01", img[0] == 0x01, repr(img[0]))
        check("镜像下标 16 是 0xAA", img[16] == 0xAA, repr(img[16]))
        check("空隙填 0xFF", img[5] == 0xFF, repr(img[5]))

        # 校验和错误要被抓住
        bad_p = os.path.join(tmpdir, "bad.hex")
        with open(bad_p, "w", encoding="ascii") as f:
            f.write(":0400000001020304FF\n")
        try:
            parse_ihex(bad_p)
            check("坏校验和应抛异常", False)
        except ProtocolError:
            check("坏校验和应抛异常", True)

        # 链接到 bootloader 区（0xFF0000）要被拦
        # 否则会把 bootloader 当成 App 烧，把自己覆盖掉
        wrong_p = os.path.join(tmpdir, "wrong.hex")
        with open(wrong_p, "w", encoding="ascii") as f:
            f.write(rec(0x04, 0, bytes([0x00, 0xFF])))
            f.write(rec(0x00, 0x0000, b"\x01"))  # 0xFF0000 = bootloader 起始
            f.write(rec(0x01, 0, b""))
        try:
            hex_to_app_image(wrong_p)
            check("链接到 bootloader 区的 hex 应被拒绍", False)
        except ProtocolError:
            check("链接到 bootloader 区的 hex 应被拒绍", True)

        # 链接到 EEPROM 区（0xFE0000）也要被拦
        # 实测证明那个区不能取指执行
        ee_p = os.path.join(tmpdir, "ee.hex")
        with open(ee_p, "w", encoding="ascii") as f:
            f.write(rec(0x04, 0, bytes([0x00, 0xFE])))
            f.write(rec(0x00, 0x0000, b"\x01"))
            f.write(rec(0x01, 0, b""))
        try:
            hex_to_app_image(ee_p)
            check("链接到 EEPROM 区的 hex 应被拒绍", False)
        except ProtocolError:
            check("链接到 EEPROM 区的 hex 应被拒绍", True)
    finally:
        import shutil
        shutil.rmtree(tmpdir, ignore_errors=True)

    print()
    if fails:
        print("自测失败 %d 项: %s" % (len(fails), ", ".join(fails)))
        return 1
    print("自测全部通过")
    return 0


# ------------------------------------------------------------------ 入口

def usage() -> None:
    print(__doc__)
    print("用法:")
    print("  pie_block_iap.py --selftest")
    print("  pie_block_iap.py <hex> <COM口> [app_baud] [boot_baud]")


def main(argv) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    if len(argv) >= 2 and argv[1] == "--selftest":
        return selftest()

    if len(argv) < 3:
        usage()
        return 2

    hex_path = argv[1]
    port = argv[2]
    app_baud = int(argv[3]) if len(argv) > 3 else DEFAULT_APP_BAUD
    boot_baud = int(argv[4]) if len(argv) > 4 else DEFAULT_BOOT_BAUD

    try:
        image = hex_to_app_image(hex_path)
    except (ProtocolError, OSError) as e:
        print("读取固件失败: %s" % e)
        return 1

    sess = IapSession(port, app_baud, boot_baud)
    try:
        sess.open()
    except Exception as e:
        print("打开串口 %s 失败: %s" % (port, e))
        return 1

    try:
        sess.trigger()
        sess.wait_bootloader()
        sess.download(image)
        print("烧录成功")
        return 0
    except ProtocolError as e:
        print("烧录失败: %s" % e)
        return 1
    except Exception as e:
        print("烧录失败（未预期的错误）: %r" % e)
        return 1
    finally:
        sess.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
