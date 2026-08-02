#!/usr/bin/env python3
"""生成二维码 PNG。

用法:
    python gen_qr.py --text "ws://192.168.0.114:19821" --out "C:/path/qr.png"

被 Godot 的 phone_pose_receiver.gd 调用，把连接地址生成二维码供手机扫码。
"""

import argparse
import sys

import qrcode
from qrcode.constants import ERROR_CORRECT_L


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a QR code PNG")
    parser.add_argument("--text", required=True, help="Text to encode")
    parser.add_argument("--out", required=True, help="Output PNG path")
    args = parser.parse_args()

    qr = qrcode.QRCode(
        version=None,          # auto-size
        error_correction=ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(args.text)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(args.out)
    print("QR OK: %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
