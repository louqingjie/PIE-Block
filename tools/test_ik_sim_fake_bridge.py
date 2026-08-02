"""Byte-only fake bridge used by the Godot end-to-end link test."""

from __future__ import annotations

import base64
import argparse
import json
import socket
import struct


DELIMITER = 0x7E
ESCAPE = 0x7D
RESERVED = {0x7E, 0x7D, 0xAB, 0xBC, 0x40, 0x50, 0x49, 0x45, 0x41, 0x23}


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def unescape(frame: bytes) -> bytes:
    raw = bytearray()
    escaped = False
    for value in frame[1:-1]:
        if escaped:
            raw.append(value ^ 0x20)
            escaped = False
        elif value == ESCAPE:
            escaped = True
        else:
            raw.append(value)
    return bytes(raw)


def frame(kind: int, sequence: int, payload: bytes) -> bytes:
    body = bytearray([1, kind, sequence & 0xFF, sequence >> 8, len(payload)])
    body.extend(payload)
    body.extend(struct.pack("<H", crc16(body)))
    encoded = bytearray([DELIMITER])
    for value in body:
        if value in RESERVED:
            encoded.extend((ESCAPE, value ^ 0x20))
        else:
            encoded.append(value)
    encoded.append(DELIMITER)
    return bytes(encoded)


def state_payload() -> bytes:
    payload = bytearray([1, 4, 3, 1, 1])
    payload.extend(bytes(range(8)))
    payload.extend(struct.pack(">6f", 10.0, 20.0, 30.0, 40.0, 0.0, 0.0))
    payload.extend(struct.pack(">6f", 100.0, 200.0, 300.0, 60.0, 50.0, 40.0))
    payload.extend(struct.pack(">4f", 1.5, 4.0, 5.0, 6.0))
    return bytes(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipc-port", type=int, required=True)
    args = parser.parse_args()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", args.ipc_port))
    server.listen(1)
    server.settimeout(5.0)
    try:
        ipc, _address = server.accept()
    except TimeoutError:
        return 3
    finally:
        server.close()
    reader = ipc.makefile("r", encoding="utf-8", newline="\n")

    def emit(value: dict) -> None:
        data = (json.dumps(value, separators=(",", ":")) + "\n").encode("utf-8")
        ipc.sendall(data)

    for line in reader:
        command = json.loads(line)
        operation = command.get("op")
        if operation == "open":
            emit({"event": "opened", "port": command.get("port"), "baud": command.get("baud")})
        elif operation == "write":
            request = unescape(base64.b64decode(command["data"]))
            sequence = request[2] | request[3] << 8
            if request[1] == 1:
                payload = bytes([1, 2, 1, 4, 1, 3, 1, 0]) + bytes(range(8))
                response = frame(0x81, sequence, payload)
            else:
                response = frame(0x82, sequence, state_payload())
            emit({"event": "data", "data": base64.b64encode(response).decode("ascii")})
        elif operation == "close":
            emit({"event": "closed"})
            ipc.close()
            return 0
    ipc.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
