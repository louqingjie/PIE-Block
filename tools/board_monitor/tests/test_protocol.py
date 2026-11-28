"""协议层单元测试：组帧、解码、流式分帧与内容诊断。"""
from __future__ import annotations

import pytest

from board_monitor.protocol import (
    CMD_DIR,
    CMD_DUTY,
    CMD_FREQ,
    CMD_INIT,
    CMD_ZERO,
    CHANNELS,
    FRAME_LEN,
    HEADER,
    TAIL,
    Frame,
    FrameParser,
    ProtocolError,
    RawBytes,
    build_frame,
    command_label,
    format_hex,
    parse_frame,
    validate_frame,
)

VALUES_ZERO = (0, 0, 0, 0, 0, 0, 0, 0)
VALUES_DUTY = (0, 0, 700, 700, 0, 0, 6000, 6000)
VALUES_INIT = (50, 50, 50, 50, 10000, 10000, 10000, 10000)


def make_frame(command: int, values=VALUES_ZERO, *, wall=1.0, mono=2.0) -> Frame:
    raw = build_frame(command, values)
    return validate_frame(raw, at_wall=wall, at_mono=mono)


def parse(command: int, values=VALUES_ZERO):
    return parse_frame(make_frame(command, values))


def frames_only(events):
    return [event for event in events if isinstance(event, Frame)]


def raw_only(events):
    return [event for event in events if isinstance(event, RawBytes)]


# ---------------------------------------------------------------------------
# 组帧 / 结构校验
# ---------------------------------------------------------------------------


def test_build_frame_exact_layout():
    raw = build_frame(CMD_DUTY, VALUES_DUTY)
    assert len(raw) == FRAME_LEN == 21
    assert raw[:2] == HEADER == b"\xAB\xBC"
    assert raw[-2:] == TAIL == b"\xCD\xDE"
    assert raw[2] == CMD_DUTY
    # P64=700=0x02BC，P76=6000=0x1770，大端落帧。
    assert raw[7:11] == b"\x02\xBC\x02\xBC"
    assert raw[15:19] == b"\x17\x70\x17\x70"
    assert format_hex(raw) == (
        "AB BC BB 00 00 00 00 02 BC 02 BC 00 00 00 00 17 70 17 70 CD DE"
    )


@pytest.mark.parametrize("command", [CMD_INIT, CMD_DUTY, CMD_FREQ, CMD_DIR, CMD_ZERO])
def test_build_frame_roundtrip(command):
    frame = make_frame(command, VALUES_DUTY)
    assert frame.command == command
    assert frame.values == VALUES_DUTY


def test_build_frame_rejects_bad_input():
    with pytest.raises(ValueError):
        build_frame(0x100, VALUES_ZERO)
    with pytest.raises(ValueError):
        build_frame(CMD_INIT, (0, 0, 0))
    with pytest.raises(ValueError):
        build_frame(CMD_INIT, (0, 0, 0, 0, 0, 0, 0, 65536))
    with pytest.raises(ValueError):
        build_frame(CMD_INIT, (0, 0, 0, 0, 0, 0, 0, -1))


def test_validate_frame_rejects_bad_structure():
    good = build_frame(CMD_INIT, VALUES_INIT)
    with pytest.raises(ProtocolError):
        validate_frame(good[:-1])
    with pytest.raises(ProtocolError):
        validate_frame(b"\x00\x00" + good[2:])
    with pytest.raises(ProtocolError):
        validate_frame(good[:-2] + b"\x00\x00")


def test_validate_frame_keeps_timestamps_and_raw():
    raw = build_frame(CMD_INIT, VALUES_INIT)
    frame = validate_frame(raw, at_wall=12.5, at_mono=3.25)
    assert frame.raw == raw
    assert frame.at_wall == 12.5
    assert frame.at_mono == 3.25


# ---------------------------------------------------------------------------
# 内容解析
# ---------------------------------------------------------------------------


def test_parse_init_summary_and_fields():
    parsed = parse(CMD_INIT, VALUES_INIT)
    assert parsed.command_name == "初始化"
    assert parsed.summary == "初始化：PWMA=50 Hz · PWMB=10000 Hz"
    assert [field.text for field in parsed.fields] == ["50 Hz"] * 4 + ["10000 Hz"] * 4
    assert parsed.issues == ()


def test_parse_duty_is_percent_of_10000():
    parsed = parse(CMD_DUTY, VALUES_DUTY)
    assert parsed.command_name == "占空比"
    assert parsed.summary == (
        "占空比：P64=700(7.00%) · P66=700(7.00%) · "
        "P76=6000(60.00%) · P77=6000(60.00%)"
    )
    assert parsed.fields[2].text == "700 (7.00%)"
    assert parsed.fields[3].text == "700 (7.00%)"
    assert parsed.issues == ()


def test_parse_duty_all_zero_summary():
    parsed = parse(CMD_DUTY, VALUES_ZERO)
    assert parsed.summary == "占空比：全部 0%"


def test_parse_freq_summary():
    parsed = parse(CMD_FREQ, (100, 100, 100, 100, 200, 200, 200, 200))
    assert parsed.command_name == "频率变更"
    assert parsed.summary == "频率变更：PWMA=100 Hz · PWMB=200 Hz"


def test_parse_dir_summary_and_fields():
    parsed = parse(CMD_DIR, (1, 0, 1, 0, 1, 0, 1, 0))
    assert parsed.command_name == "方向"
    assert parsed.fields[0].text == "正"
    assert parsed.fields[1].text == "负"
    assert parsed.summary.startswith("方向：P60=正 P62=负 P64=正")
    assert parsed.issues == ()


def test_parse_zero_summary():
    parsed = parse(CMD_ZERO, (1, 2, 3, 4, 5, 6, 7, 8))
    assert parsed.command_name == "归零"
    assert parsed.summary == "归零：P60–P77 输出清零"
    assert parsed.fields[0].text == "?(1)"


def test_parse_unknown_command():
    parsed = parse(0x12, (0, 1, 2, 3, 4, 5, 6, 7))
    assert parsed.command_name == "未知命令"
    assert parsed.summary == "未知命令 0x12"
    assert parsed.fields[0].text == "0x0000"
    assert parsed.fields[7].text == "0x0007"
    assert [issue.key for issue in parsed.issues] == ["unknown_command:0x12"]


def test_duty_out_of_range_warning():
    parsed = parse(CMD_DUTY, (10001, 0, 0, 0, 0, 0, 0, 0))
    keys = {issue.key for issue in parsed.issues}
    assert "duty_range:P60" in keys
    assert "占空比 P60=10001" in " ".join(issue.message for issue in parsed.issues)


def test_dir_invalid_value_warning():
    parsed = parse(CMD_DIR, (2, 0, 0, 0, 0, 0, 0, 0))
    keys = {issue.key for issue in parsed.issues}
    assert keys == {"dir_range:P60"}
    assert parsed.fields[0].text == "?(2)"


def test_init_unexpected_frequency_warning():
    parsed = parse(CMD_INIT, (10023, 10023, 10023, 10023, 10023, 10023, 10023, 10023))
    keys = {issue.key for issue in parsed.issues}
    assert "init_freq:P60" in keys
    assert "byte_dup:P60" in keys


def test_group_frequency_mismatch_warning():
    parsed = parse(CMD_INIT, (50, 50, 50, 60, 10000, 10000, 10000, 10000))
    keys = {issue.key for issue in parsed.issues}
    assert "freq_group:PWMA" in keys
    assert "freq_group:PWMB" not in keys
    assert parsed.summary == "初始化：PWMA=50 Hz / 50 Hz / 50 Hz / 60 Hz · PWMB=10000 Hz"


def test_byte_duplication_heuristic():
    parsed = parse(CMD_DUTY, (0, 0, 0x2727, 0, 0, 0, 0, 0))
    keys = {issue.key for issue in parsed.issues}
    # 0x2727=10023 同时命中超范围与高低字节重复。
    assert keys == {"duty_range:P64", "byte_dup:P64"}


def test_zero_value_not_flagged_as_byte_duplication():
    parsed = parse(CMD_DUTY, VALUES_ZERO)
    assert parsed.issues == ()


def test_command_label():
    assert command_label(CMD_INIT) == "0xAA 初始化"
    assert command_label(0x12) == "0x12 未知命令"


def test_channel_order_is_protocol_order():
    assert CHANNELS == ("P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77")


# ---------------------------------------------------------------------------
# 流式分帧
# ---------------------------------------------------------------------------


def test_parser_single_frame():
    raw = build_frame(CMD_DUTY, VALUES_DUTY)
    events = FrameParser().feed(raw, at_wall=5.0, at_mono=1.0)
    frames = frames_only(events)
    assert len(frames) == 1
    assert frames[0].values == VALUES_DUTY
    assert frames[0].at_wall == 5.0
    assert frames[0].at_mono == 1.0


def test_parser_frame_split_at_every_position():
    raw = build_frame(CMD_INIT, VALUES_INIT)
    for split in range(len(raw) + 1):
        parser = FrameParser()
        events = parser.feed(raw[:split]) + parser.feed(raw[split:])
        frames = frames_only(events)
        assert len(frames) == 1, f"split={split}"
        assert frames[0].raw == raw
        assert not raw_only(events), f"split={split} 不应产生原始字节事件"


def test_parser_byte_by_byte():
    raw = build_frame(CMD_DIR, (1, 0, 1, 0, 1, 0, 1, 0))
    parser = FrameParser()
    events = []
    for index in range(len(raw)):
        events.extend(parser.feed(raw[index : index + 1]))
    assert len(frames_only(events)) == 1
    assert parser.pending_bytes == 0


def test_parser_two_frames_with_garbage():
    first = build_frame(CMD_INIT, VALUES_INIT)
    second = build_frame(CMD_DUTY, VALUES_DUTY)
    parser = FrameParser()
    events = parser.feed(b"\x01\x02" + first + b"\xEE" + second)
    kinds = [type(event).__name__ for event in events]
    assert kinds == ["RawBytes", "Frame", "RawBytes", "Frame"]
    raw_events = raw_only(events)
    assert raw_events[0].data == b"\x01\x02"
    assert raw_events[0].reason == "garbage"
    assert raw_events[1].data == b"\xEE"
    assert raw_events[1].reason == "garbage"


def test_parser_bad_tail_resyncs_at_next_header():
    valid = build_frame(CMD_DUTY, VALUES_DUTY)
    broken = b"\xAB\xBC" + b"\x00" * 8 + valid
    parser = FrameParser()
    events = parser.feed(broken)
    raw_events = raw_only(events)
    frames = frames_only(events)
    assert len(frames) == 1 and frames[0].raw == valid
    assert raw_events[0].reason == "bad_tail"
    assert raw_events[0].data == b"\xAB\xBC" + b"\x00" * 8


def test_parser_does_not_swallow_nested_valid_frame():
    valid = build_frame(CMD_INIT, VALUES_INIT)
    # 在坏候选帧的第 10 字节之后就是合法帧；解析器必须只丢掉前 10 字节。
    broken = b"\xAB\xBC" + b"\x00" * 8 + valid + valid
    events = FrameParser().feed(broken)
    frames = frames_only(events)
    assert [frame.raw for frame in frames] == [valid, valid]
    assert raw_only(events)[0].data == b"\xAB\xBC" + b"\x00" * 8


def test_parser_false_header_in_noise_is_flushed():
    parser = FrameParser()
    # 先喂一段含伪帧头、后面没有合法帧的噪声，再 flush。
    events = parser.feed(b"\x11\x22\xAB\xBC\x33\x44", at_wall=1.0, at_mono=1.0)
    assert frames_only(events) == []
    assert raw_only(events)[0].data == b"\x11\x22"
    flushed = parser.flush(at_wall=2.0, at_mono=2.0)
    assert len(flushed) == 1
    assert flushed[0].reason == "bad_tail"
    assert flushed[0].data == b"\xAB\xBC\x33\x44"
    assert parser.pending_bytes == 0


def test_parser_flush_single_header_byte_is_partial():
    parser = FrameParser()
    assert parser.feed(b"\xAB") == []
    flushed = parser.flush()
    assert len(flushed) == 1
    assert flushed[0].reason == "partial"
    assert flushed[0].data == b"\xAB"


def test_parser_split_header_kept_for_next_feed():
    raw = build_frame(CMD_INIT, VALUES_INIT)
    parser = FrameParser()
    first = parser.feed(raw[:1])
    assert first == []
    events = parser.feed(raw[1:])
    assert len(frames_only(events)) == 1


def test_parser_garbage_keeps_possible_split_header():
    parser = FrameParser()
    events = parser.feed(b"\x00\xAB")
    assert raw_only(events)[0].data == b"\x00"
    assert parser.pending_bytes == 1
    events = parser.feed(b"\xBC" + build_frame(CMD_ZERO, VALUES_ZERO))
    assert len(frames_only(events)) == 1


def test_parser_flush_bad_tail_candidate():
    parser = FrameParser()
    events = parser.feed(b"\xAB\xBC" + b"\x00" * 30)
    assert frames_only(events) == []
    flushed = parser.flush()
    assert flushed[0].reason == "bad_tail"


def test_parser_overflow_protects_memory():
    parser = FrameParser(max_buffer=64)
    events = parser.feed(b"\xAB\xBC" + b"\x00" * 100)
    raw_events = raw_only(events)
    assert raw_events[0].reason == "overflow"
    assert len(raw_events[0].data) == 102
    assert parser.pending_bytes == 0


def test_parser_empty_feed_is_noop():
    parser = FrameParser()
    assert parser.feed(b"") == []
    assert parser.flush() == []


def test_parser_frame_timestamps():
    raw = build_frame(CMD_DUTY, VALUES_ZERO)
    events = FrameParser().feed(raw, at_wall=99.5, at_mono=4.5)
    frame = frames_only(events)[0]
    assert frame.at_wall == 99.5
    assert frame.at_mono == 4.5
