//! HID 帧协议：帧编码、报告拆分、HEX→块映射与 ACK 交互。
//!
//! 与 `packages/pieblock_hid/lib/src/protocol.dart` 对齐；帧内报告之间保留
//! 1ms 间隔（参考实现验证过，Dart 移植曾漏掉导致写块无响应）。

use crate::transport::HidTransport;
use crate::{BLOCK_SIZE, CODE_BASE, REPORT_PAYLOAD, VECTOR_BASE};
use pieblock_toolchain::HexImage;

/// 帧内相邻 HID 报告之间的间隔（毫秒）。
pub const HID_REPORT_GAP_MS: i64 = 1;

/// 设备在超时时间内没有返回任何报告。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HidNoResponse {
    pub label: String,
}

impl std::fmt::Display for HidNoResponse {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}：设备无响应", self.label)
    }
}

/// 协议交互错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HidProtocolError {
    /// 设备无响应（可原样重发同一块）。
    NoResponse(HidNoResponse),
    /// 帧头/命令异常、写入失败等其它状态错误。
    State(String),
}

impl HidProtocolError {
    #[must_use]
    pub fn state(message: impl Into<String>) -> Self {
        Self::State(message.into())
    }

    #[must_use]
    pub fn message(&self) -> &str {
        match self {
            Self::NoResponse(error) => &error.label,
            Self::State(message) => message,
        }
    }
}

impl std::fmt::Display for HidProtocolError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoResponse(error) => write!(formatter, "{error}"),
            Self::State(message) => formatter.write_str(message),
        }
    }
}

impl std::error::Error for HidProtocolError {}

/// 一个待写入的 flash 块。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashBlock {
    pub address: i64,
    pub command: i64,
    pub data: [u8; BLOCK_SIZE],
}

/// HID 帧协议。
pub struct HidProtocol;

impl HidProtocol {
    /// 构造完整帧：`46 B9 6A` + 长度 + payload + 校验和 + `16`。
    #[must_use]
    pub fn build_packet(payload: &[u8]) -> Vec<u8> {
        let mut packet = vec![0x46, 0xb9, 0x6a];
        let total_length = i64::try_from(payload.len()).unwrap_or(0) + 6;
        packet.push(((total_length >> 8) & 0xff) as u8);
        packet.push((total_length & 0xff) as u8);
        packet.extend_from_slice(payload);
        let mut checksum: i64 = 0;
        for value in &packet[2..] {
            checksum = (checksum + i64::from(*value)) & 0xffff;
        }
        packet.push(((checksum >> 8) & 0xff) as u8);
        packet.push((checksum & 0xff) as u8);
        packet.push(0x16);
        packet
    }

    /// 把帧拆成每份 65 字节的 HID 报告（首字节为 report ID 0）。
    #[must_use]
    pub fn split_reports(packet: &[u8]) -> Vec<Vec<u8>> {
        let mut reports = Vec::new();
        let mut offset = 0;
        while offset < packet.len() {
            let end = (offset + REPORT_PAYLOAD).min(packet.len());
            let mut wire = vec![0_u8];
            wire.extend_from_slice(&packet[offset..end]);
            while wire.len() < REPORT_PAYLOAD {
                wire.push(0);
            }
            reports.push(wire);
            offset += REPORT_PAYLOAD;
        }
        reports
    }

    /// 把 HEX 镜像映射为 ISP 写块：用户区首块命令 `0x32`、后续 `0x12`，
    /// 向量区 `0x02`；同块空白补零。
    pub fn build_write_blocks(image: &HexImage) -> Result<Vec<FlashBlock>, HidProtocolError> {
        let mut user: std::collections::BTreeMap<i64, [u8; BLOCK_SIZE]> =
            std::collections::BTreeMap::new();
        let mut high: std::collections::BTreeMap<i64, [u8; BLOCK_SIZE]> =
            std::collections::BTreeMap::new();
        for (address, value) in &image.bytes {
            let (base, target) = if *address < VECTOR_BASE {
                (CODE_BASE, &mut user)
            } else {
                (VECTOR_BASE, &mut high)
            };
            let relative = address - base;
            if !(0..0x1_0000).contains(&relative) {
                return Err(HidProtocolError::state(format!(
                    "HEX 地址 0x{:x} 无法映射到 ISP",
                    address
                )));
            }
            let block = relative / i64::try_from(BLOCK_SIZE).unwrap_or(128);
            let offset =
                usize::try_from(relative % i64::try_from(BLOCK_SIZE).unwrap_or(128)).unwrap_or(0);
            target.entry(block).or_insert([0_u8; BLOCK_SIZE])[offset] = *value;
        }
        let mut blocks = Vec::new();
        for (index, (key, data)) in user.iter().enumerate() {
            blocks.push(FlashBlock {
                address: key * i64::try_from(BLOCK_SIZE).unwrap_or(128),
                command: if index == 0 { 0x32 } else { 0x12 },
                data: *data,
            });
        }
        for (key, data) in &high {
            blocks.push(FlashBlock {
                address: key * i64::try_from(BLOCK_SIZE).unwrap_or(128),
                command: 0x02,
                data: *data,
            });
        }
        Ok(blocks)
    }

    /// 发送 payload 并等待命令 ACK；无响应返回 [`HidProtocolError::NoResponse`]。
    #[allow(clippy::too_many_arguments)]
    pub fn expect_ack<T: HidTransport + ?Sized>(
        transport: &mut T,
        payload: &[u8],
        label: &str,
        command_offset: usize,
        command: u8,
        timeout_milliseconds: i64,
        report_gap_ms: i64,
        sleep: &dyn Fn(i64),
    ) -> Result<Vec<u8>, HidProtocolError> {
        let packet = Self::build_packet(payload);
        let mut first = true;
        for report in Self::split_reports(&packet) {
            if !first && report_gap_ms > 0 {
                sleep(report_gap_ms);
            }
            first = false;
            if !transport.write(&report) {
                return Err(HidProtocolError::state(format!("{label}：写入报告失败")));
            }
        }
        let response = transport.read(timeout_milliseconds);
        if response.is_empty() {
            return Err(HidProtocolError::NoResponse(HidNoResponse {
                label: label.to_owned(),
            }));
        }
        if response.len() < 6 || response[0] != 0x46 || response[1] != 0xb9 || response[2] != 0x68 {
            return Err(HidProtocolError::state(format!("{label}：响应帧头异常")));
        }
        if response.get(5 + command_offset).copied() != Some(command) {
            return Err(HidProtocolError::state(format!("{label}：响应命令异常")));
        }
        Ok(response)
    }
}
