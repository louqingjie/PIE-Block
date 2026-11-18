//! STC32G ROM USB-HID ISP 烧录协议（M2 里程碑）。
//!
//! 已移植：帧编码、报告拆分、HEX→块映射、ACK 交互、烧录状态机（含重试与
//! 已移植：帧编码、报告拆分、HEX→块映射、ACK 交互、烧录状态机（含重试与
//! 探活/操作指引），以及 Windows/Linux 原生 hidapi 传输（真机验证待硬件）。

pub mod flasher;
#[cfg(any(windows, target_os = "linux"))]
pub mod native;
pub mod protocol;
pub mod transport;

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
pub const CODE_BASE: i64 = 0x00FE_0000;
/// 向量区基址。
pub const VECTOR_BASE: i64 = 0x00FF_0000;
/// 整体硬超时（秒）。
pub const FLASH_TIMEOUT_SECS: u64 = 90;

pub use flasher::{FlashEvent, FlashOptions, FlashResult, FlashStage, HidFlasher};
#[cfg(any(windows, target_os = "linux"))]
pub use native::NativeHidTransport;
pub use protocol::{FlashBlock, HidProtocol, HidProtocolError};
pub use transport::{HidTransport, TransportError};

/// M2 阶段能力描述。
#[must_use]
pub const fn stage() -> &'static str {
    "M2 进行中：协议/烧录状态机与原生 hidapi 已移植，真机验证待完成"
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
