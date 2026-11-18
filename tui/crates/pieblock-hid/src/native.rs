//! 原生 hidapi 传输（Windows `windows-native` / Linux `linux-static-hidraw`）。
//!
//! 与 Dart FFI 层同一 ABI 语义：写报告包含 report ID 槽；读超时返回空。
//! 取消通过共享标志位实现：`read` 分片等待并在标志置位后尽快返回。

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use hidapi::{HidApi, HidDevice};

use crate::transport::{HidTransport, TransportError};
use crate::{PID, VID};

/// 原生 HID 传输。
pub struct NativeHidTransport {
    api: Option<HidApi>,
    device: Option<HidDevice>,
    cancelled: Arc<AtomicBool>,
}

impl NativeHidTransport {
    /// 初始化 hidapi；失败时返回带上下文的错误。
    pub fn new() -> Result<Self, TransportError> {
        let api = HidApi::new()
            .map_err(|error| TransportError::new(format!("初始化 hidapi 失败：{error}")))?;
        Ok(Self {
            api: Some(api),
            device: None,
            cancelled: Arc::new(AtomicBool::new(false)),
        })
    }

    /// 供外部线程触发取消的句柄。
    #[must_use]
    pub fn cancel_handle(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.cancelled)
    }
}

impl HidTransport for NativeHidTransport {
    fn count_devices(&mut self) -> Result<i64, TransportError> {
        let api = self
            .api
            .as_ref()
            .ok_or_else(|| TransportError::new("hidapi 未初始化"))?;
        let count = api
            .device_list()
            .filter(|info| info.vendor_id() == VID && info.product_id() == PID)
            .count();
        Ok(i64::try_from(count).unwrap_or(0))
    }

    fn open(&mut self) -> bool {
        let Some(api) = self.api.as_ref() else {
            return false;
        };
        let path = api
            .device_list()
            .find(|info| info.vendor_id() == VID && info.product_id() == PID)
            .map(|info| info.path().to_owned());
        let Some(path) = path else {
            return false;
        };
        match api.open_path(&path) {
            Ok(device) => {
                self.cancelled.store(false, Ordering::SeqCst);
                self.device = Some(device);
                true
            }
            Err(_) => false,
        }
    }

    fn write(&mut self, report: &[u8]) -> bool {
        let Some(device) = self.device.as_mut() else {
            return false;
        };
        device
            .write(report)
            .is_ok_and(|written| written == report.len())
    }

    fn read(&mut self, timeout_milliseconds: i64) -> Vec<u8> {
        let Some(device) = self.device.as_mut() else {
            return Vec::new();
        };
        let mut buffer = [0_u8; 256];
        let mut remaining = timeout_milliseconds.max(0);
        while remaining > 0 {
            if self.cancelled.load(Ordering::SeqCst) {
                return Vec::new();
            }
            let chunk = remaining.min(100);
            match device.read_timeout(&mut buffer, i32::try_from(chunk).unwrap_or(100)) {
                Ok(0) => {
                    remaining -= chunk;
                }
                Ok(length) => {
                    if self.cancelled.load(Ordering::SeqCst) {
                        return Vec::new();
                    }
                    return buffer[..length.min(buffer.len())].to_vec();
                }
                Err(_) => return Vec::new(),
            }
        }
        Vec::new()
    }

    fn cancel(&mut self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    fn close(&mut self) {
        self.device = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hidapi_initializes_or_reports_error() {
        match NativeHidTransport::new() {
            Ok(mut transport) => {
                assert!(transport.count_devices().unwrap_or(0) >= 0);
            }
            Err(error) => assert!(!error.message.is_empty()),
        }
    }
}
