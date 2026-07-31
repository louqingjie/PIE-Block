#!/usr/bin/env python3
"""Execute a supported subset of an MCS-251 Intel HEX image."""

from __future__ import annotations

import argparse
import json
import sys

from cpu import MCS251Cpu, SimulationError
from ihex import HexParseError, parse_ihex_file


def _address(value: str) -> int:
    return int(value, 0)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hexfile")
    parser.add_argument("--reset", type=_address, help="override reset address")
    parser.add_argument("--stop-pc", type=_address, required=True)
    parser.add_argument("--max-steps", type=int, default=100_000)
    args = parser.parse_args(argv)

    try:
        image = parse_ihex_file(args.hexfile)
        cpu = MCS251Cpu.from_hex(image, reset_address=args.reset)
        cpu.run(max_steps=args.max_steps, stop_pc=args.stop_pc)
    except (HexParseError, SimulationError, OSError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1

    result = {
        "ok": True,
        "pc": cpu.pc,
        "steps": cpu.steps,
        "uart": [
            {"step": write.step, "channel": write.channel, "value": write.value}
            for write in cpu.uart_trace
        ],
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())