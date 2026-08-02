"""Raw serial bridge for the MCU IK simulation link.

The Godot side owns the binary protocol. This process only transports bytes
between JSON-lines stdin/stdout and pyserial, so it cannot introduce a second
kinematics implementation.
"""
from __future__ import annotations

import base64
import argparse
import json
import socket
import sys
import threading
import time


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
    ipc_reader = ipc.makefile("r", encoding="utf-8", newline="\n")
    emit_lock = threading.Lock()

    def emit(value: dict) -> None:
        data = (json.dumps(value, separators=(",", ":")) + "\n").encode("utf-8")
        with emit_lock:
            ipc.sendall(data)

    port = ""
    baud = 230400
    ser = None
    stop = threading.Event()

    def reader() -> None:
        while not stop.is_set() and ser is not None:
            try:
                data = ser.read(256)
                if data:
                    emit({"event": "data", "data": base64.b64encode(data).decode("ascii")})
            except Exception as exc:
                emit({"event": "error", "message": str(exc)})
                stop.set()

    for line in ipc_reader:
        try:
            command = json.loads(line)
        except json.JSONDecodeError as exc:
            emit({"event": "error", "message": f"invalid command: {exc}"})
            continue
        op = command.get("op")
        if op == "open":
            port = str(command.get("port", ""))
            baud = int(command.get("baud", 230400))
            try:
                import serial

                ser = serial.Serial(port, baud, timeout=0.02, parity=serial.PARITY_NONE)
                ser.reset_input_buffer()
                emit({"event": "opened", "port": port, "baud": baud})
                threading.Thread(target=reader, daemon=True).start()
            except ImportError:
                emit({"event": "error", "message": "pyserial not installed"})
                ipc.close()
                return 2
            except Exception as exc:
                emit({"event": "error", "message": str(exc)})
                ser = None
        elif op == "write":
            if ser is None:
                emit({"event": "error", "message": "serial port is not open"})
                continue
            try:
                ser.write(base64.b64decode(str(command.get("data", ""))))
                ser.flush()
            except Exception as exc:
                emit({"event": "error", "message": str(exc)})
                stop.set()
        elif op == "close":
            stop.set()
            if ser is not None:
                ser.close()
            emit({"event": "closed"})
            ipc.close()
            return 0
        elif op == "ping":
            emit({"event": "pong", "time": time.monotonic()})
        else:
            emit({"event": "error", "message": f"unknown operation: {op}"})
    stop.set()
    if ser is not None:
        ser.close()
    ipc.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
