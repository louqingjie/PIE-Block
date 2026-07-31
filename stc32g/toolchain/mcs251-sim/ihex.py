"""Strict Intel HEX parsing for MCS-251 tooling."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


class HexParseError(ValueError):
    """Raised when an Intel HEX stream is malformed or ambiguous."""


@dataclass(frozen=True)
class HexImage:
    """Sparse memory image decoded from Intel HEX records."""

    memory: dict[int, int]
    entry_point: int | None = None

    @property
    def address_range(self) -> tuple[int, int]:
        if not self.memory:
            raise HexParseError("HEX image contains no data records")
        return min(self.memory), max(self.memory)

    def regions(self) -> list[tuple[int, int]]:
        """Return inclusive contiguous address ranges."""
        if not self.memory:
            return []
        addresses = sorted(self.memory)
        result: list[tuple[int, int]] = []
        start = previous = addresses[0]
        for address in addresses[1:]:
            if address != previous + 1:
                result.append((start, previous))
                start = address
            previous = address
        result.append((start, previous))
        return result


def parse_ihex_file(path: str | Path) -> HexImage:
    source = Path(path)
    try:
        lines = source.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError) as exc:
        raise HexParseError(f"cannot read {source}: {exc}") from exc
    return parse_ihex(lines, source=str(source))


def parse_ihex(lines: Iterable[str], *, source: str = "<input>") -> HexImage:
    memory: dict[int, int] = {}
    linear_base = 0
    segment_base = 0
    entry_point: int | None = None
    ended = False

    for line_number, original_line in enumerate(lines, 1):
        line = original_line.strip()
        if not line:
            continue
        if ended:
            raise HexParseError(f"{source}:{line_number}: record after EOF")
        if not line.startswith(":"):
            raise HexParseError(f"{source}:{line_number}: missing ':' prefix")
        try:
            raw = bytes.fromhex(line[1:])
        except ValueError as exc:
            raise HexParseError(
                f"{source}:{line_number}: invalid hexadecimal record"
            ) from exc
        if len(raw) < 5:
            raise HexParseError(f"{source}:{line_number}: record is too short")

        count = raw[0]
        expected_length = count + 5
        if len(raw) != expected_length:
            raise HexParseError(
                f"{source}:{line_number}: byte count is {count}, "
                f"record contains {len(raw) - 5} data bytes"
            )
        if sum(raw) & 0xFF:
            raise HexParseError(f"{source}:{line_number}: checksum mismatch")

        offset = (raw[1] << 8) | raw[2]
        record_type = raw[3]
        data = raw[4:-1]

        if record_type == 0x00:
            base = linear_base + segment_base
            for index, value in enumerate(data):
                address = base + offset + index
                if address in memory:
                    raise HexParseError(
                        f"{source}:{line_number}: overlapping data at 0x{address:08X}"
                    )
                memory[address] = value
        elif record_type == 0x01:
            if count != 0 or offset != 0:
                raise HexParseError(f"{source}:{line_number}: malformed EOF record")
            ended = True
        elif record_type == 0x02:
            _require_shape(source, line_number, count, offset, expected_count=2)
            segment_base = int.from_bytes(data, "big") << 4
            linear_base = 0
        elif record_type == 0x03:
            _require_shape(source, line_number, count, offset, expected_count=4)
            cs = int.from_bytes(data[:2], "big")
            ip = int.from_bytes(data[2:], "big")
            entry_point = (cs << 4) + ip
        elif record_type == 0x04:
            _require_shape(source, line_number, count, offset, expected_count=2)
            linear_base = int.from_bytes(data, "big") << 16
            segment_base = 0
        elif record_type == 0x05:
            _require_shape(source, line_number, count, offset, expected_count=4)
            entry_point = int.from_bytes(data, "big")
        else:
            raise HexParseError(
                f"{source}:{line_number}: unsupported record type 0x{record_type:02X}"
            )

    if not ended:
        raise HexParseError(f"{source}: missing EOF record")
    if not memory:
        raise HexParseError(f"{source}: HEX image contains no data records")
    return HexImage(memory=memory, entry_point=entry_point)


def _require_shape(
    source: str,
    line_number: int,
    count: int,
    offset: int,
    *,
    expected_count: int,
) -> None:
    if count != expected_count or offset != 0:
        raise HexParseError(
            f"{source}:{line_number}: malformed extended address/start record"
        )