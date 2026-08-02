"""原始帧测试：直接向仿真固件发 HELLO/PING，打印响应的原始 payload 字节。

绕过 GDScript 解析层，用于诊断固件返回的 position/angles 数据。
用法：python tools/raw_ping_test.py COM3
"""
import serial
import struct
import sys
import time

DELIMITER = 0x7E
ESCAPE = 0x7D
RESERVED = {0x7E, 0x7D, 0xAB, 0xBC, 0x40, 0x50, 0x49, 0x45, 0x41, 0x23}
VERSION = 1
CMD_HELLO = 0x01
CMD_STEP_POSE = 0x02
CMD_PING = 0x05
RESP_HELLO = 0x81
RESP_STATE = 0x82


def pack_float32_big(value: float) -> bytes:
    return struct.pack(">f", value)


def pack_pose(position, rpy=(0.0, 0.0, 0.0)) -> bytes:
    # wire order: X,Y,Z,Yaw,Pitch,Roll
    return b"".join(pack_float32_big(v) for v in
                    [position[0], position[1], position[2], rpy[2], rpy[1], rpy[0]])


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for v in data:
        crc ^= v << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def pack_frame(kind: int, seq: int, payload: bytes = b"") -> bytes:
    body = bytes([VERSION, kind, seq & 0xFF, (seq >> 8) & 0xFF, len(payload)]) + payload
    body += struct.pack("<H", crc16(body))
    out = bytearray([DELIMITER])
    for v in body:
        if v in RESERVED:
            out += bytes([ESCAPE, v ^ 0x20])
        else:
            out.append(v)
    out.append(DELIMITER)
    return bytes(out)


def unescape(data: bytes) -> bytes:
    raw = bytearray()
    esc = False
    for v in data:
        if esc:
            raw.append(v ^ 0x20)
            esc = False
        elif v == ESCAPE:
            esc = True
        else:
            raw.append(v)
    return bytes(raw)


def read_frame(ser, timeout=2.0):
    buf = bytearray()
    deadline = time.time() + timeout
    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            chunk = ser.read(waiting)
            buf.extend(chunk)
            while True:
                s = buf.find(bytes([DELIMITER]))
                if s < 0:
                    break
                e = buf.find(bytes([DELIMITER]), s + 1)
                if e < 0:
                    break
                frame = bytes(buf[s + 1:e])
                del buf[:e + 1]
                return frame
        else:
            time.sleep(0.01)
    return None


def parse_body(frame: bytes):
    body = unescape(frame)
    if len(body) < 5:
        return None, None
    ver, typ = body[0], body[1]
    seq = body[2] | (body[3] << 8)
    n = body[4]
    payload = body[5:5 + n]
    crc = struct.unpack("<H", body[5 + n:7 + n])[0]
    ok = crc == crc16(body[:5 + n])
    return (ver, typ, seq, ok), payload


def main() -> int:
    port = sys.argv[1] if len(sys.argv) > 1 else "COM3"
    ser = serial.Serial(port, 230400, timeout=0.5)
    ser.reset_input_buffer()
    try:
        ser.write(pack_frame(CMD_HELLO, 1))
        fr = read_frame(ser)
        hdr, payload = parse_body(fr) if fr else (None, None)
        print("HELLO resp: hdr=%s payload_len=%d" % (hdr, len(payload) if payload else -1))
        if payload:
            print("  hello payload: %s" % payload.hex(" "))

        ser.write(pack_frame(CMD_PING, 2))
        fr = read_frame(ser)
        hdr, payload = parse_body(fr) if fr else (None, None)
        print("PING resp: hdr=%s payload_len=%d" % (hdr, len(payload) if payload else -1))
        if payload and len(payload) >= 77:
            print("  raw payload[0..76]:")
            print("  " + payload[:77].hex(" "))
            # 布局：0 status,1 jc,2 posdof,3 oridof,4 mask,5-12 fp,13-36 angles,37-48 pos,49-60 rpy
            print("  status=%d jc=%d posdof=%d oridof=%d mask=%d" % (
                payload[0], payload[1], payload[2], payload[3], payload[4]))
            print("  angles[13:37] = %s" % payload[13:37].hex(" "))
            print("  pos[37:49]    = %s" % payload[37:49].hex(" "))
            print("  rpy[49:61]    = %s" % payload[49:61].hex(" "))
            print("  pe[61:65]     = %s" % payload[61:65].hex(" "))

        # STEP_POSE: target (330,0,0)，从当前状态收敛
        print("\n发送 STEP_POSE target=(330,0,0) 并观察 IK 收敛...")
        ser.write(pack_frame(CMD_STEP_POSE, 10, pack_pose((330.0, 0.0, 0.0))))
        for step in range(10):
            fr = read_frame(ser)
            hdr, payload = parse_body(fr) if fr else (None, None)
            if not payload or len(payload) < 65:
                print("  step %d: 无有效响应" % (step + 1))
                break
            pos = struct.unpack(">3f", payload[37:49])
            ang = struct.unpack(">6f", payload[13:37])
            pe = struct.unpack(">f", payload[61:65])[0]
            print("  step %d: pos=%.1f,%.1f,%.1f err=%.1fmm angles=%s" % (
                step + 1, pos[0], pos[1], pos[2], pe,
                ",".join("%.1f" % a for a in ang)))
            # 持续重发同目标推进收敛
            ser.write(pack_frame(CMD_STEP_POSE, 11, pack_pose((330.0, 0.0, 0.0))))
    finally:
        ser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
