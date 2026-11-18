//! STC32G ROM USB-HID ISP 烧录协议（M2 里程碑）。
//!
//! M0 仅冻结设备标识与帧常量；真实实现将移植
//! `packages/pieblock_hid/lib/src/{protocol,flasher,transport}.dart` 与
//! `packages/pieblock_hid/src/pieblock_hid*.cpp` 的协议/时序/重试语义。

/// STC32G 主控板 USB ISP 的厂商 ID。
pub const VID: u16 = 0x34BF;
/// STC32G 主控板 USB ISP 的产品 ID。
pub const PID: u16 = 0x1001;
/// 固件分块大小（字节）。
pub const BLOCK_SIZE: usize = 128;
/// 单份 HID 报告的载荷长度；每份报告另带 1 字节 report ID 槽。
pub const REPORT_PAYLOAD: usize = 64;
/// 线上每份报告的长度（含 report ID 槽）。
pub const REPORT_SIZE: usize = REPORT_PAYLOAD + 1;
/// 代码区基址。
pub const CODE_BASE: u32 = 0x00FE_0000;
/// 向量区基址。
pub const VECTOR_BASE: u32 = 0x00FF_0000;
/// 整体硬超时（秒）。
pub const FLASH_TIMEOUT_SECS: u64 = 90;

/// M0 阶段能力描述。
#[must_use]
pub const fn stage() -> &'static str {
    "M0 占位：HID 帧/传输/烧录状态机将在 M2 移植"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_identity_matches_flutter_implementation() {
        assert_eq!(VID, 0x34BF);
        assert_eq!(PID, 0x1001);
        assert_eq!(BLOCK_SIZE, 128);
        assert_eq!(REPORT_PAYLOAD, 64);
        assert_eq!(REPORT_SIZE, REPORT_PAYLOAD + 1);
        assert_eq!(BLOCK_SIZE, REPORT_PAYLOAD * 2);
        assert_eq!(VECTOR_BASE, CODE_BASE + 0x1_0000);
        assert_eq!(FLASH_TIMEOUT_SECS, 90);
    }
}
