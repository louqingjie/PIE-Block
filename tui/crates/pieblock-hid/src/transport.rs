//! HID 传输层抽象。
//!
//! 桌面端原生实现（Windows `windows-native` / Linux `linux-static-hidraw`）在
//! M2 收尾接入；协议与烧录状态机只依赖本 trait，测试使用脚本化假设备。

/// 传输层错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransportError {
    pub message: String,
}

impl TransportError {
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for TransportError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for TransportError {}

/// HID 传输接口（对应 Dart `HidTransport`）。
pub trait HidTransport {
    /// 枚举处于 ISP 模式的设备数量。
    fn count_devices(&mut self) -> Result<i64, TransportError>;
    /// 打开设备。
    fn open(&mut self) -> bool;
    /// 写一份报告（含 report ID 槽）；返回是否成功。
    fn write(&mut self, report: &[u8]) -> bool;
    /// 读取一份响应；超时返回空。
    fn read(&mut self, timeout_milliseconds: i64) -> Vec<u8>;
    /// 请求取消当前阻塞读。
    fn cancel(&mut self);
    /// 关闭设备。
    fn close(&mut self);
}
