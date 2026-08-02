#!/usr/bin/env python3
"""PieBlock 手机传感器模拟客户端。

在没有手机的情况下测试 Godot 侧 WebSocket 接收逻辑。
用法:
    python tools/phone_pose_test.py [host] [port]
默认 host=127.0.0.1 port=19821

交互:
    输入数字回车发送对应位姿
    输入 reset 回车发送重置原点请求
    输入 quit 退出
"""

import json
import sys
import time
import threading
try:
    import websocket  # websocket-client 库
except ImportError:
    print("需要安装 websocket-client: pip install websocket-client")
    sys.exit(1)


def send_loop(ws: websocket.WebSocket):
    """每 33ms 发送一次位姿。"""
    import math
    t = 0.0
    while True:
        try:
            # 圆周运动 position, 固定 rpy
            x = 100.0 * math.cos(t)
            y = 100.0 * math.sin(t)
            z = 50.0 * math.sin(t * 0.5)
            roll = 30.0 * math.sin(t * 0.3)
            pitch = 20.0 * math.sin(t * 0.2)
            yaw = 45.0 * math.cos(t * 0.4)
            msg = {
                "type": "pose",
                "position": {"x": x, "y": y, "z": z},
                "rpy": {"roll": roll, "pitch": pitch, "yaw": yaw},
                "ts": int(time.time() * 1000),
            }
            ws.send(json.dumps(msg))
            t += 0.033
            time.sleep(0.033)
        except Exception:
            break


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 19821
    url = f"ws://{host}:{port}"
    print(f"连接 {url} ...")

    ws = websocket.create_connection(url)
    print("已连接")

    # 发送 hello
    ws.send(json.dumps({"type": "hello", "app": "TestClient", "version": 1}))

    # 接收 welcome
    result = ws.recv()
    print(f"收到: {result}")

    # 启动发送线程
    sender = threading.Thread(target=send_loop, args=(ws,), daemon=True)
    sender.start()

    print("发送中... Ctrl+C 退出")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n退出")
        ws.close()


if __name__ == "__main__":
    main()
