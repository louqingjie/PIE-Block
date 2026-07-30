#!/usr/bin/env python3
"""pie_block_iap.py - STC32G 固件自升级下载工具（对话我们自己的 bootloader）

与 pie_block_flash.py（走 ROM ISP + stcgal）的区别：
  这个脚本对话的是常驻在 0xFF0000 的 PIE_BOOTLOADER，
  不依赖 ROM ISP、不依赖 IRC trim、不需要 2400 波特率握手。

协议与地址布局照 STC 官方例程，不要自创。改动前先读
`/memories/repo/keil-c251.md` 的「STC32G 用户自建 ISP / IAP 固件自升级」节。

流程：
  1. 以 App 波特率发 @PIEIAP#
     App 的 UART1 ISR 收到后置 iapDownloadReq，主循环写 XRAM 的 DfuFlag
     再 IAP_CONTR=0x20 软复位。XRAM 软复位不清零，bootloader 据此停在下载模式。
  2. 芯片复位后跑 0xFF0000 的 bootloader，切到 bootloader 波特率
  3. CONNECT 确认在线 -> ERASE -> 分块 PROGRAM -> REBOOT

帧格式（官方，见 PIE_BOOTLOADER/USER/src/uart.c）：
    主机 -> 芯片:  '#' | len | cmd | payload... | '$' | 累加和
    芯片 -> 主机:  '@' | status | size | payload... | '$' | 累加和
    len   = cmd 加 payload 的字节数
    累加和 = 使整帧字节之和的低 8 位为 0 的那个字节

协议层（build_frame / parse_response / hex_to_iap_chunks）不碰串口，
可以脱离硬件自测，见 --selftest。
"""

from __future__ import annotations

import sys
import time

# ------------------------------------------------------------------ 协议常量

REQ_HEAD = 0x23    # '#'  主机发出的帧头
RESP_HEAD = 0x40   # '@'  芯片回应的帧头
FRAME_TAIL = 0x24  # '$'

CMD_CONNECT = 0xA0
CMD_READ = 0xA1
CMD_PROGRAM = 0xA2
CMD_ERASE = 0xA3
CMD_REBOOT = 0xA4

CMD_NAMES = {
    CMD_CONNECT: "CONNECT",
    CMD_READ: "READ",
    CMD_PROGRAM: "PROGRAM",
    CMD_ERASE: "ERASE",
    CMD_REBOOT: "REBOOT",
}

STATUS_OK = 0x00
STATUS_ERRORCMD = 0x01
STATUS_OUTOFRANGE = 0x02
STATUS_PROGRAMERR = 0x03
STATUS_ERRORWRAP = 0xFF

STATUS_NAMES = {
    STATUS_OK: "OK",
    STATUS_ERRORCMD: "命令不支持",
    STATUS_OUTOFRANGE: "地址越界",
    STATUS_PROGRAMERR: "写入失败",
    STATUS_ERRORWRAP: "帧错误",
}

# 触发命令字。App 的 UART1 ISR 匹配这 8 字节。
TRIGGER = b"@PIEIAP#"

# ------------------------------------------------------------------ 地址布局
#
# 照 STC 官方 PDF 第 2 页的 flash 规划。
# IAP 地址 = 物理地址 & 0x1FFFF（IAP_ADDRE 只取 bit16，寻址空间 17 位）：
#
#   物理 0xFE0000-0xFEFFFF = IAP 0x00000-0x0FFFF  低 64K，用户代码放这里
#   物理 0xFF0000-0xFF0FFF = IAP 0x10000-0x10FFF  Bootloader 4K（拒绝写）
#   物理 0xFF1000-0xFFFFFF = IAP 0x11000-0x1FFFF  App 入口/向量表/启动代码
#
# 0xFE0000 区不能取指执行（探针 Q6 实测复位），所以那里只放通过 far 调用
# 进入的代码（ECODE 类）；入口与中断向量必须落在 0xFF1000 之后。

IAP_ADDR_MASK = 0x1FFFF
"""IAP 地址位宽掩码。物理地址与它相与即得 IAP 地址。"""

LDR_SIZE = 0x1000
"""bootloader 占用大小，必须与 PIE_BOOTLOADER/USER/inc/config.h 一致。"""

PHYS_LOW_BASE = 0xFE0000
PHYS_HIGH_BASE = 0xFF0000

BOOT_IAP_BASE = 0x10000
"""bootloader 自身的 IAP 起始地址（= 物理 0xFF0000）。"""
BOOT_IAP_END = BOOT_IAP_BASE + LDR_SIZE
"""bootloader 保护区上界（不含）。芯片侧 iap_check_addr 会拒绝写这个区间。"""

RESET_VECTOR_PHYS = PHYS_HIGH_BASE
"""App hex 里复位跳转所在的物理地址，共 3 字节。"""
RESET_VECTOR_TARGET = PHYS_HIGH_BASE + LDR_SIZE
"""复位跳转要搬到的物理地址。搬完 App 首字节才是 0x02，能过 bootloader 校验。"""

FLASH_SIZE = 0x20000
"""IAP 可寻址的 flash 总量 128K。"""

SECTOR_SIZE = 512

MAX_PAYLOAD = 128
"""单帧数据字节上限。

芯片侧 dfu_events 的 size 字段是 BYTE，收缓冲区 UartRxBuffer 为 256 字节，
帧开销 head+len+cmd+addr(4)+size(1)+tail+sum = 10 字节，理论上限 245。
取 128 留足余量，也让进度显示更平滑。
"""

DEFAULT_APP_BAUD = 230400
"""App 的 UART1 波特率，用于发 @PIEIAP# 触发命令。

必须与三处保持一致：本常量、scripts/toolchain.gd 的 DEFAULT_APP_BAUD、
scripts/codegen/codegen_base.gd 的 APP_BAUD（它写进生成的 C 代码）。
不一致时 App 的 UART1 中断收不到触发字，现象却是"bootloader 没有响应"，
错误信息离真因很远（踩过两次：先在 GDScript 侧写成 115200，改回后又漏了这里）。
"""

DEFAULT_BOOT_BAUD = 115200
"""bootloader 的波特率，由 PIE_BOOTLOADER/USER/inc/config.h 编译期写死。

与 App 波特率不同，所以下载过程有一次切换：
230400 发触发字 → 115200 与 bootloader 通信。
蓝牙链路做不到这个切换（模块波特率配对时固定），走蓝牙需把两端统一。
"""


class ProtocolError(Exception):
    pass


# ------------------------------------------------------------------ 帧编解码

def checksum(data: bytes) -> int:
    """官方校验：使整帧字节之和的低 8 位归零的那个字节。"""
    return (-sum(data)) & 0xFF


def build_frame(cmd: int, payload: bytes = b"") -> bytes:
    """组一个主机 -> 芯片的帧。

    len 字段算的是 cmd 加 payload 的长度，所以是 len(payload) + 1。
    """
    if not 0 <= cmd <= 0xFF:
        raise ValueError("cmd 超出字节范围: %r" % cmd)
    if len(payload) + 1 > 0xFF:
        raise ValueError("payload 过长: %d" % len(payload))
    body = bytes([REQ_HEAD, len(payload) + 1, cmd]) + payload + bytes([FRAME_TAIL])
    return body + bytes([checksum(body)])


def build_program_payload(iap_addr: int, data: bytes) -> bytes:
    """PROGRAM 的 payload：addr(4, 小端) | size(1) | data...

    下标必须与芯片侧 dfu_events() 对齐：
      addr = *(DWORD *)&UartRxBuffer[2] & 0x1ffff
      size = UartRxBuffer[6]
      ptr  = &UartRxBuffer[7]
    """
    if not 0 <= iap_addr <= 0xFFFFFFFF:
        raise ValueError("iap_addr 超出 32 位: 0x%X" % iap_addr)
    if not 1 <= len(data) <= 0xFF:
        raise ValueError("data 长度必须在 1..255，实际 %d" % len(data))
    return bytes([
        iap_addr & 0xFF,
        (iap_addr >> 8) & 0xFF,
        (iap_addr >> 16) & 0xFF,
        (iap_addr >> 24) & 0xFF,
        len(data),
    ]) + data


def parse_response(buf: bytes):
    """从 buf 头部解一个芯片回应帧。

    返回 (status, payload, consumed)。
    数据不足返回 None —— 调用方继续读串口再试，而不是当成错误。
    帧头/帧尾/校验和不对则抛 ProtocolError。
    """
    if len(buf) < 1:
        return None
    if buf[0] != RESP_HEAD:
        raise ProtocolError("帧头不是 '@': 0x%02X" % buf[0])
    # head + status + size + tail + sum = 5
    if len(buf) < 5:
        return None
    status, size = buf[1], buf[2]
    total = 3 + size + 2
    if len(buf) < total:
        return None
    frame = bytes(buf[:total])
    if frame[3 + size] != FRAME_TAIL:
        raise ProtocolError("帧尾不是 '$': %s" % frame.hex(" "))
    if (sum(frame) & 0xFF) != 0:
        raise ProtocolError("校验和错误: %s" % frame.hex(" "))
    return status, frame[3:3 + size], total


# ------------------------------------------------------------------ hex 处理

def parse_ihex(path: str) -> dict:
    """最小 Intel HEX 解析，支持 type 00/01/04。

    返回 {绝对物理地址: 字节值}。不自己拼段，交给调用方决定布局。
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


def relocate_reset_vector(segs: dict) -> dict:
    """把 0xFF0000-0xFF0002 的复位跳转搬到 0xFF1000-0xFF1002。

    这一步是必须的，不是可选优化：
      - bootloader 自己占着 0xFF0000-0xFF0FFF，IAP 会拒绝写那里
      - bootloader 跳 App 前要检查 *(BYTE code *)(LDR_SIZE) == 0x02，
        也就是物理 0xFF1000 处必须是 LJMP 指令
    官方 PDF 原话："重映射的工作上位机应用程序会自动处理，
    用户在编写 AP 代码时无需关心"。

    返回搬运后的新字典，不改动入参。
    """
    out = dict(segs)
    moved = 0
    for i in range(3):
        src = RESET_VECTOR_PHYS + i
        if src not in out:
            continue
        dst = RESET_VECTOR_TARGET + i
        if dst in out:
            raise ProtocolError(
                "复位向量搬运目标 0x%06X 已被占用（值 0x%02X）。\n"
                "  App 的链接器 MiscControls 应设 "
                "CLASSES (CODE (0xFF1003-0xFFFFFF))，\n"
                "  把 CODE 起点抬到 0xFF1003 给这 3 字节让位。" % (dst, out[dst])
            )
        out[dst] = out.pop(src)
        moved += 1

    if moved == 0:
        raise ProtocolError(
            "hex 里 0x%06X 处没有复位跳转指令。\n"
            "  正常的 App hex 应该在那里有 3 字节 LJMP。检查 uvproj 配置。"
            % RESET_VECTOR_PHYS
        )
    if moved != 3:
        raise ProtocolError(
            "复位跳转不完整，只找到 %d 字节（应为 3）。hex 可能损坏。" % moved)

    first = out[RESET_VECTOR_TARGET]
    if first != 0x02:
        raise ProtocolError(
            "搬运后 App 首字节是 0x%02X，不是 LJMP(0x02)。\n"
            "  bootloader 会因此判定 App 无效而拒绝跳转。" % first
        )
    target = (out[RESET_VECTOR_TARGET + 1] << 8) | out[RESET_VECTOR_TARGET + 2]
    if target < LDR_SIZE + 3:
        raise ProtocolError(
            "复位跳转目标 0x%04X 落在 bootloader 区内（应 >= 0x%04X）。\n"
            "  bootloader 的第四重校验会拒绝它。" % (target, LDR_SIZE + 3)
        )
    return out


VECTOR_STRIDE = 8
"""相邻中断入口的间距（字节）。MCS-251 固定 8。"""

VECTOR_AREA_END = 0xFF11FF
"""中断向量区上界（含）。

bootloader 的 isr.asm 最后一条 MAPISR 是 01FBH，转发目标 0xFF11FB，占 4 字节。
App 的链接器 CODE 起点必须落在这之后，当前约定取 0xFF1300。
"""


def check_vector_area(segs: dict) -> None:
    """检查中断向量区里放的是跳转指令，而不是被普通代码或数据挤占。

    bootloader 的蹦床把硬件中断入口 0x0003+n*8 转发到 0xFF1003+n*8，
    所以那些地址必须是 App 的中断向量。若链接器把别的段填了进去，
    对应中断触发时会跳进数据里执行。

    这个检查是踩坑后加的：曾把链接器 CODE 起点设成 0xFF1003，
    链接器于是把 ?CO?MAIN（内含 "@PIEIAP#" 命令字）放在那里，
    正好占掉 interrupt 0 的入口。现象是 App 完全不启动，
    而写入、读回校验、bootloader 的四重校验判据全部正常 —— 极难定位。
    """
    bad = []
    addr = RESET_VECTOR_TARGET + 3
    while addr <= VECTOR_AREA_END:
        if addr in segs:
            op = segs[addr]
            # LJMP=0x02，EJMP(far)=0x8A（ECODE 区的 ISR 用它）
            if op not in (0x02, 0x8A):
                bad.append((addr, op))
        addr += VECTOR_STRIDE

    if bad:
        lines = ["中断向量区里有非跳转数据，App 的中断会跳进错误位置："]
        for phys, op in bad[:5]:
            idx = (phys - RESET_VECTOR_TARGET - 3) // VECTOR_STRIDE
            lines.append("  0x%06X (interrupt %d) 首字节 0x%02X，"
                         "应为 0x02(LJMP) 或 0x8A(EJMP)" % (phys, idx, op))
        lines.append("原因通常是链接器 CODE 起点设得太低，把普通段挤进了向量区。")
        lines.append("App 的 Lx51 MiscControls 应设 "
                     "CLASSES (CODE (0xFF1300-0xFFFFFF))。")
        raise ProtocolError("\n".join(lines))


def hex_to_iap_chunks(path: str, chunk_size: int = MAX_PAYLOAD):
    """读 App hex，搬好复位向量，转成按 IAP 地址排列的连续块列表。

    返回 [(iap_addr, bytes), ...]，块内地址连续，块长不超过 chunk_size。

    按块发而不是补齐成一大片：App hex 是稀疏的（中断向量之间有大量空洞），
    30KB 的 App 若补齐到 0xFF113E 会多写将近 4K 的空洞。
    """
    segs = parse_ihex(path)
    if not segs:
        raise ProtocolError("hex 里没有任何数据记录: %s" % path)

    segs = relocate_reset_vector(segs)
    check_vector_area(segs)

    # 搬运后不应再有任何字节落在 bootloader 保护区
    for phys in sorted(segs):
        iap = phys & IAP_ADDR_MASK
        if BOOT_IAP_BASE <= iap < BOOT_IAP_END:
            raise ProtocolError(
                "物理地址 0x%06X (IAP 0x%05X) 落在 bootloader 保护区 "
                "[0x%05X, 0x%05X)。\n"
                "  芯片会拒绝写入。检查 App 的链接器 CLASSES 设置。"
                % (phys, iap, BOOT_IAP_BASE, BOOT_IAP_END)
            )
        if iap >= FLASH_SIZE:
            raise ProtocolError("IAP 地址 0x%05X 超出 128K flash" % iap)

    # 按 IAP 地址切成连续块
    items = sorted((phys & IAP_ADDR_MASK, val) for phys, val in segs.items())
    chunks = []
    cur_addr = None
    cur = bytearray()
    for addr, val in items:
        if (cur_addr is not None and addr == cur_addr + len(cur)
                and len(cur) < chunk_size):
            cur.append(val)
            continue
        if cur:
            chunks.append((cur_addr, bytes(cur)))
        cur_addr = addr
        cur = bytearray([val])
    if cur:
        chunks.append((cur_addr, bytes(cur)))
    return chunks


# ------------------------------------------------------------------ 串口会话

class IapSession:
    def __init__(self, port: str, app_baud: int = DEFAULT_APP_BAUD,
                 boot_baud: int = DEFAULT_BOOT_BAUD, verbose: bool = True):
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

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def set_baud(self, baud: int) -> None:
        self.ser.baudrate = baud

    def trigger(self) -> None:
        """发触发命令让 App 软复位到 bootloader。

        若芯片本来就停在 bootloader（上次下载失败或 P32 被拉低），
        这一步没有回应也无妨，后面 CONNECT 会兜住。
        """
        self.log("发送触发命令 %s @ %d baud" % (TRIGGER.decode(), self.app_baud))
        self.set_baud(self.app_baud)
        self.ser.reset_input_buffer()
        self.ser.write(TRIGGER)
        self.ser.flush()

    def send(self, cmd: int, payload: bytes = b"") -> None:
        self.ser.write(build_frame(cmd, payload))
        self.ser.flush()

    def recv(self, timeout: float = 1.0):
        """读一个完整回应帧。超时返回 None。

        串口是字节流，可能一次读到半个帧或多个帧，所以维护累积缓冲区。
        帧头之前的垃圾字节（App 复位时的乱码）要跳过而不是报错。
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            chunk = self.ser.read(256)
            if chunk:
                self._rx.extend(chunk)

            while self._rx and self._rx[0] != RESP_HEAD:
                del self._rx[0]

            if len(self._rx) >= 5:
                try:
                    got = parse_response(bytes(self._rx))
                except ProtocolError as e:
                    # 坏帧：丢掉这个帧头继续找，别让一次误码毁掉整次下载
                    self.log("  [warn] %s，丢弃并重新同步" % e)
                    del self._rx[0]
                    continue
                if got is not None:
                    status, payload, consumed = got
                    del self._rx[0:consumed]
                    return status, payload
        return None

    def request(self, cmd: int, payload: bytes = b"",
                timeout: float = 1.0, retries: int = 3) -> bytes:
        """发一帧并等 OK 应答，返回 payload。非 OK 或超时则重试。"""
        name = CMD_NAMES.get(cmd, "0x%02X" % cmd)
        last = None
        for attempt in range(1, retries + 1):
            self.send(cmd, payload)
            got = self.recv(timeout=timeout)
            if got is None:
                last = "无应答"
                self.log("  %s 第 %d 次无应答" % (name, attempt))
                continue
            status, rpayload = got
            if status == STATUS_OK:
                return rpayload
            last = STATUS_NAMES.get(status, "未知状态 0x%02X" % status)
            self.log("  %s 第 %d 次被拒绝：%s" % (name, attempt, last))
        raise ProtocolError("%s 连续 %d 次失败（%s）" % (name, retries, last))

    def connect(self, total_timeout: float = 5.0) -> int:
        """切到 bootloader 波特率反复 CONNECT，返回 bootloader 版本号。"""
        self.log("等待 bootloader（%d baud）…" % self.boot_baud)
        self.set_baud(self.boot_baud)
        self._rx.clear()
        self.ser.reset_input_buffer()

        deadline = time.time() + total_timeout
        while time.time() < deadline:
            self.send(CMD_CONNECT)
            got = self.recv(timeout=0.3)
            if got is not None and got[0] == STATUS_OK and len(got[1]) >= 2:
                ver = (got[1][0] << 8) | got[1][1]
                self.log("bootloader 就绪，版本 0x%04X" % ver)
                return ver
        raise ProtocolError(
            "bootloader 没有响应。可能原因：\n"
            "  - 芯片上还没烧过 bootloader（用官方 STC-ISP 刷 PIE_BOOTLOADER，\n"
            "    工作频率 33.1776MHz，EEPROM 设 128K，烧完必须重新上电）\n"
            "  - App 里没有 %s 监听代码\n"
            "  - 串口选错了或被别的程序占用" % TRIGGER.decode()
        )

    def erase(self) -> None:
        """擦除 App 区。bootloader 自身受芯片侧 iap_check_addr 保护。"""
        self.log("擦除 App 区…")
        self.request(CMD_ERASE, timeout=10.0)

    def read(self, iap_addr: int, size: int) -> bytes:
        """读回 flash。需要 bootloader 编译时开了 DEBUG，否则回 ERRORCMD。

        payload 布局与 PROGRAM 相同：addr(4, 小端) | size(1)。
        """
        if not 1 <= size <= 0xFF:
            raise ValueError("size 必须在 1..255，实际 %d" % size)
        payload = bytes([
            iap_addr & 0xFF,
            (iap_addr >> 8) & 0xFF,
            (iap_addr >> 16) & 0xFF,
            (iap_addr >> 24) & 0xFF,
            size,
        ])
        return self.request(CMD_READ, payload, timeout=3.0)

    def verify(self, chunks, sample: int = 0) -> None:
        """把写进去的内容读回来比对。

        sample=0 全量校验；sample=N 只抽查前 N 个块（快速自查用）。
        这一步不能省：PROGRAM 只报 CMD_FAIL，不保证内容真的对，
        而 bootloader 侧的逐字节回读被证明不可靠（见 iap.c 注释）。
        """
        todo = chunks if sample <= 0 else chunks[:sample]
        self.log("读回校验 %d 个块…" % len(todo))
        bad = 0
        for iap_addr, want in todo:
            got = self.read(iap_addr, len(want))
            if got != want:
                bad += 1
                self.log("  [差异] 0x%05X 期望 %s 实际 %s"
                         % (iap_addr, want[:8].hex(" "), got[:8].hex(" ")))
                if bad >= 5:
                    self.log("  差异过多，停止比对")
                    break
        if bad:
            raise ProtocolError(
                "读回校验失败：%d 个块内容不符。固件未生效，"
                "bootloader 会保持等待状态，可以重新下载。" % bad)
        self.log("读回校验通过")

    def program(self, chunks) -> None:
        total = sum(len(d) for _, d in chunks)
        done = 0
        last_pct = -1
        self.log("写入 %d 字节，分 %d 个块…" % (total, len(chunks)))
        for iap_addr, data in chunks:
            self.request(CMD_PROGRAM, build_program_payload(iap_addr, data),
                         timeout=3.0)
            done += len(data)
            pct = done * 100 // total
            if pct != last_pct:
                self.log("  %d/%d 字节 (%d%%)" % (done, total, pct))
                last_pct = pct

    def reboot(self) -> None:
        """让芯片软复位去跑新 App。这个命令没有回应。"""
        self.log("重启到新固件…")
        self.send(CMD_REBOOT)
        self.ser.flush()

    def download(self, chunks, verify: bool = True) -> None:
        self.erase()
        self.program(chunks)
        if verify:
            self.verify(chunks)
        self.reboot()


# ------------------------------------------------------------------ 自测

def _mk_ihex(records) -> str:
    """把 [(type, addr, data)] 组成 Intel HEX 文本，供自测用。"""
    lines = []
    for rtype, addr, data in records:
        rec = bytes([len(data), (addr >> 8) & 0xFF, addr & 0xFF, rtype]) + data
        lines.append(":" + (rec + bytes([checksum(rec)])).hex().upper())
    lines.append(":00000001FF")
    return "\n".join(lines) + "\n"


def selftest() -> int:
    """协议层自测，不需要串口也不需要板子。"""
    import os
    import tempfile

    fails = []

    def check(name, got, want):
        if got != want:
            fails.append("%s: got %r want %r" % (name, got, want))

    def expect_raises(name, fn):
        try:
            fn()
        except (ProtocolError, ValueError):
            return
        fails.append("%s: 应该抛异常但没抛" % name)

    # --- 校验和
    check("checksum 空", checksum(b""), 0)
    check("checksum 0x01", checksum(b"\x01"), 0xFF)
    body = b"\x23\x01\xa0\x24"
    check("checksum 归零", (sum(body) + checksum(body)) & 0xFF, 0)

    # --- 组帧：与 2026-07-29 真机实测抓到的字节序列比对。
    #     改协议时这三行必须仍然相等，否则芯片侧对不上。
    check("CONNECT 帧", build_frame(CMD_CONNECT).hex(), "2301a02418")
    check("ERASE 帧", build_frame(CMD_ERASE).hex(), "2301a32415")
    check("REBOOT 帧", build_frame(CMD_REBOOT).hex(), "2301a42414")
    for name, cmd in (("CONNECT", CMD_CONNECT), ("ERASE", CMD_ERASE)):
        frame = build_frame(cmd)
        check("%s 整帧和归零" % name, sum(frame) & 0xFF, 0)
        check("%s len 字段" % name, frame[1], 1)
        check("%s 帧头" % name, frame[0], REQ_HEAD)
        check("%s 帧尾" % name, frame[-2], FRAME_TAIL)

    # --- 组帧：带 payload
    f = build_frame(CMD_PROGRAM, b"\x01\x02\x03")
    check("PROGRAM len 含 cmd", f[1], 4)
    check("PROGRAM 整帧和归零", sum(f) & 0xFF, 0)
    check("PROGRAM 帧尾", f[-2], FRAME_TAIL)
    expect_raises("payload 过长", lambda: build_frame(CMD_PROGRAM, b"\x00" * 255))

    # --- PROGRAM payload 布局必须与芯片侧 UartRxBuffer 下标对齐
    p = build_program_payload(0x11234, b"\xAA\xBB")
    check("program payload 长度", len(p), 7)
    check("program addr 小端", p[0:4].hex(), "34120100")
    check("program size 字段", p[4], 2)
    check("program data", p[5:].hex(), "aabb")
    expect_raises("program data 空", lambda: build_program_payload(0, b""))
    expect_raises("program data 过长",
                  lambda: build_program_payload(0, b"\x00" * 256))
    # 整帧下标复核：帧内 addr 应落在 buffer[2:6]，size 在 [6]，data 从 [7]
    full = build_frame(CMD_PROGRAM, p)
    check("帧内 addr 位置", full[3:7].hex(), "34120100")
    check("帧内 size 位置", full[7], 2)
    check("帧内 data 位置", full[8:10].hex(), "aabb")

    # --- 解析回应：真机抓到的两个回应
    got = parse_response(bytes.fromhex("4000020100" + "24" + "99"))
    check("CONNECT 回应 status", got[0], STATUS_OK)
    check("CONNECT 回应 payload", got[1].hex(), "0100")
    check("CONNECT 回应 consumed", got[2], 7)
    got = parse_response(bytes.fromhex("400000249c"))
    check("ERASE 回应 status", got[0], STATUS_OK)
    check("ERASE 回应 payload 空", got[1], b"")

    # 数据不足应返回 None 而不是抛异常
    check("回应空", parse_response(b""), None)
    check("回应不足 5 字节", parse_response(b"\x40\x00\x02"), None)
    check("回应缺 payload", parse_response(bytes.fromhex("40000201")), None)
    expect_raises("回应帧头错", lambda: parse_response(b"\x41\x00\x00\x24\x9b"))
    expect_raises("回应校验错", lambda: parse_response(bytes.fromhex("400000249d")))
    expect_raises("回应帧尾错", lambda: parse_response(bytes.fromhex("400000259b")))

    # --- 地址换算
    check("IAP 低块基址", PHYS_LOW_BASE & IAP_ADDR_MASK, 0x00000)
    check("IAP 高块基址", PHYS_HIGH_BASE & IAP_ADDR_MASK, 0x10000)
    check("IAP App 入口", (PHYS_HIGH_BASE + LDR_SIZE) & IAP_ADDR_MASK, 0x11000)
    check("IAP 顶端", 0xFFFFFF & IAP_ADDR_MASK, 0x1FFFF)
    check("boot 保护区上界", BOOT_IAP_END, 0x11000)

    # --- hex 解析与复位向量搬运
    tmp = tempfile.mkdtemp(prefix="pieiap_")
    try:
        def write_hex(name, records):
            path = os.path.join(tmp, name)
            with open(path, "w", encoding="ascii") as fp:
                fp.write(_mk_ihex(records))
            return path

        # 正常的 App hex：低块代码 + 0xFF0000 复位跳转 + 0xFF1300 起的启动代码。
        # 向量区（0xFF1003-0xFF11FF）留空 —— 那是编译器按 INTVECTOR 放 IV?n 的地方，
        # 普通段不能落进去（见 check_vector_area）。
        good = write_hex("good.hex", [
            (0x04, 0, b"\x00\xFE"),
            (0x00, 0x0000, bytes(range(16))),
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x13\x00"),
            (0x00, 0x1300, b"\x75\x84\x01\x7E"),
        ])
        segs = parse_ihex(good)
        check("hex 低块首字节", segs[0xFE0000], 0)
        check("hex 复位向量", segs[0xFF0000], 0x02)
        check("hex 0xFF1000 空", 0xFF1000 in segs, False)

        moved = relocate_reset_vector(segs)
        check("搬运后 0xFF0000 已清", 0xFF0000 in moved, False)
        check("搬运后 0xFF1000", moved[0xFF1000], 0x02)
        check("搬运后 0xFF1001", moved[0xFF1001], 0x13)
        check("搬运后 0xFF1002", moved[0xFF1002], 0x00)
        check("搬运不动低块", moved[0xFE0000], 0)
        check("搬运不影响启动代码", moved[0xFF1300], 0x75)
        check("搬运前后字节总数不变", len(moved), len(segs))
        check("不改动入参", 0xFF0000 in segs, True)

        chunks = hex_to_iap_chunks(good)
        addrs = [a for a, _ in chunks]
        check("块地址已在 IAP 空间", all(a <= IAP_ADDR_MASK for a in addrs), True)
        check("低块映射到 IAP 0", min(addrs), 0x00000)
        check("入口映射到 IAP 0x11000", 0x11000 in addrs, True)
        check("块字节总数", sum(len(d) for _, d in chunks), len(segs))
        for a, d in chunks:
            check("块长不超上限 @0x%05X" % a, len(d) <= MAX_PAYLOAD, True)
            if BOOT_IAP_BASE <= a < BOOT_IAP_END:
                fails.append("块 0x%05X 落在 bootloader 保护区" % a)

        # 目标已被占用：必须报错而不是静默覆盖
        occupied = write_hex("occupied.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x10\xA7"),
            (0x00, 0x1000, b"\x40\x50\x49"),
        ])
        expect_raises("搬运目标被占用",
                      lambda: relocate_reset_vector(parse_ihex(occupied)))

        novec = write_hex("novec.hex", [
            (0x04, 0, b"\x00\xFE"),
            (0x00, 0x0000, b"\x01\x02"),
        ])
        expect_raises("缺复位向量",
                      lambda: relocate_reset_vector(parse_ihex(novec)))

        badop = write_hex("badop.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x12\x10\xA7"),
        ])
        expect_raises("首字节非 LJMP",
                      lambda: relocate_reset_vector(parse_ihex(badop)))

        badtgt = write_hex("badtgt.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x00\x50"),
        ])
        expect_raises("跳转目标在 boot 区",
                      lambda: relocate_reset_vector(parse_ihex(badtgt)))

        overlap = write_hex("overlap.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x10\xA7"),
            (0x00, 0x0500, b"\xAA\xBB"),
        ])
        expect_raises("代码压在 boot 区", lambda: hex_to_iap_chunks(overlap))

        # 中断向量区被普通数据挤占：必须拦住。
        # 这正是 CODE 起点设成 0xFF1003 时发生的事 —— 链接器把命令字
        # "@PIEIAP#"(40 50 49 45...) 放进了 interrupt 0 的入口，
        # 结果 App 完全不启动而所有校验都显示正常。
        vecbad = write_hex("vecbad.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x13\x00"),
            (0x00, 0x1003, b"\x40\x50\x49\x45"),
        ])
        expect_raises("向量区被数据挤占", lambda: hex_to_iap_chunks(vecbad))

        # 合法向量区：LJMP 与 EJMP 都要接受（后者是 ECODE 区 ISR 用的 far 跳转）
        vecok = write_hex("vecok.hex", [
            (0x04, 0, b"\x00\xFF"),
            (0x00, 0x0000, b"\x02\x13\x00"),
            (0x00, 0x1003, b"\x02\x13\x34"),
            (0x00, 0x1023, b"\x8A\xFE\x53\x20"),
            (0x00, 0x1300, b"\x75\x84\x01"),
        ])
        try:
            hex_to_iap_chunks(vecok)
        except ProtocolError as exc:
            fails.append("合法向量区被误拦: %s" % exc)

        badsum = os.path.join(tmp, "badsum.hex")
        with open(badsum, "w", encoding="ascii") as fp:
            fp.write(":0200000400FEFB\n:00000001FF\n")
        expect_raises("hex 校验和错", lambda: parse_ihex(badsum))
    finally:
        for name in os.listdir(tmp):
            os.remove(os.path.join(tmp, name))
        os.rmdir(tmp)

    # --- 分块：长连续区间要被切成不超过上限的多块，且拼回去与原数据一致
    src = {}
    for i in range(MAX_PAYLOAD * 2 + 5):
        src[PHYS_LOW_BASE + i] = i & 0xFF
    src[0xFF0000], src[0xFF0001], src[0xFF0002] = 0x02, 0x10, 0xA7
    moved = relocate_reset_vector(src)
    items = sorted((p & IAP_ADDR_MASK, v) for p, v in moved.items())
    rebuilt = {}
    cur_addr, cur = None, bytearray()
    out_chunks = []
    for addr, val in items:
        if cur_addr is not None and addr == cur_addr + len(cur) and len(cur) < MAX_PAYLOAD:
            cur.append(val)
            continue
        if cur:
            out_chunks.append((cur_addr, bytes(cur)))
        cur_addr, cur = addr, bytearray([val])
    if cur:
        out_chunks.append((cur_addr, bytes(cur)))
    for a, d in out_chunks:
        check("分块长度 @0x%05X" % a, len(d) <= MAX_PAYLOAD, True)
        for i, v in enumerate(d):
            rebuilt[a + i] = v
    check("分块可无损拼回", rebuilt, dict(items))
    check("分块数", len(out_chunks), 4)

    if fails:
        print("自测失败 %d 项:" % len(fails))
        for msg in fails:
            print("  [FAIL] %s" % msg)
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
        chunks = hex_to_iap_chunks(hex_path)
    except (ProtocolError, OSError) as e:
        print("读取固件失败: %s" % e)
        return 1

    total = sum(len(d) for _, d in chunks)
    print("固件 %d 字节，%d 个块" % (total, len(chunks)))

    sess = IapSession(port, app_baud, boot_baud)
    try:
        sess.open()
    except Exception as e:
        print("打开串口 %s 失败: %s" % (port, e))
        return 1

    try:
        sess.trigger()
        sess.connect()
        sess.download(chunks)
        print("烧录成功")
        return 0
    except ProtocolError as e:
        print("烧录失败: %s" % e)
        return 1
    finally:
        sess.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
