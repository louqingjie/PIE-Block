//! 烧录 worker：HEX 校验、传输层工厂、90 秒硬超时与取消。
//!
//! Dart 侧用 isolate + Timer 封装；Rust 用独立线程 + 共享取消标志达到同样语义：
//! 超时/取消后置位标志（原生传输的阻塞读会尽快返回），并把最终结果改写为
//! 「已自动取消 / 已取消烧录」。

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::time::Duration;

use pieblock_toolchain::IntelHexValidator;

use crate::flasher::{FlashEvent, FlashOptions, FlashResult, FlashStage, HidFlasher};
use crate::transport::{HidTransport, TransportError};

/// 烧录硬超时。
pub const FLASH_TIMEOUT: Duration = Duration::from_secs(90);

/// 起一次烧录任务。
pub struct FlashOperation {
    events: Receiver<FlashEvent>,
    result: Receiver<FlashResult>,
    cancel_flag: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl FlashOperation {
    /// 立即取消烧录。
    pub fn cancel(&self) {
        self.cancel_flag.store(true, Ordering::SeqCst);
    }

    /// 非阻塞读取下一条进度事件。
    #[must_use]
    pub fn try_recv_event(&self) -> Option<FlashEvent> {
        self.events.try_recv().ok()
    }

    /// 阻塞等待结果（会等待 worker 线程退出）。
    pub fn wait(mut self) -> FlashResult {
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
        self.result.recv().unwrap_or(FlashResult {
            success: false,
            stage: FlashStage::Preparing,
            message: "烧录任务异常终止".to_owned(),
            canceled: false,
        })
    }
}

/// 启动烧录线程；`transport_factory` 接收取消标志，供传输层提前结束阻塞读。
pub fn start_flash<T, F>(
    hex_path: PathBuf,
    expected_sha256: String,
    transport_factory: F,
    options: FlashOptions,
) -> FlashOperation
where
    T: HidTransport + 'static,
    F: FnOnce(Arc<AtomicBool>) -> Result<T, TransportError> + Send + 'static,
{
    start_flash_with_timeout(
        hex_path,
        expected_sha256,
        transport_factory,
        options,
        FLASH_TIMEOUT,
    )
}

/// 与 [`start_flash`] 相同，可自定义超时（测试用）。
pub fn start_flash_with_timeout<T, F>(
    hex_path: PathBuf,
    expected_sha256: String,
    transport_factory: F,
    options: FlashOptions,
    timeout: Duration,
) -> FlashOperation
where
    T: HidTransport + 'static,
    F: FnOnce(Arc<AtomicBool>) -> Result<T, TransportError> + Send + 'static,
{
    let (event_sender, events) = mpsc::channel::<FlashEvent>();
    let (result_sender, result) = mpsc::sync_channel::<FlashResult>(1);
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let timed_out = Arc::new(AtomicBool::new(false));
    let done = Arc::new(AtomicBool::new(false));
    {
        let cancel_flag = Arc::clone(&cancel_flag);
        let timed_out = Arc::clone(&timed_out);
        let done = Arc::clone(&done);
        std::thread::spawn(move || {
            let deadline_flag = Arc::clone(&cancel_flag);
            let mut waited = Duration::ZERO;
            while waited < timeout {
                if done.load(Ordering::SeqCst) || deadline_flag.load(Ordering::SeqCst) {
                    return;
                }
                let step = Duration::from_millis(50).min(timeout - waited);
                std::thread::sleep(step);
                waited += step;
            }
            if !done.load(Ordering::SeqCst) {
                timed_out.store(true, Ordering::SeqCst);
                cancel_flag.store(true, Ordering::SeqCst);
            }
        });
    }
    let worker_cancel = Arc::clone(&cancel_flag);
    let handle = std::thread::spawn(move || {
        let sender = event_sender;
        let mut emit =
            |stage: FlashStage, message: &str, current: Option<i64>, total: Option<i64>| {
                let _ = sender.send(FlashEvent {
                    stage,
                    message: message.to_owned(),
                    current,
                    total,
                });
            };
        emit(FlashStage::Preparing, "正在校验待烧录固件…", None, None);
        let Some(image) = read_and_validate(&hex_path, &expected_sha256, &mut emit) else {
            done.store(true, Ordering::SeqCst);
            let _ = result_sender.send(FlashResult {
                success: false,
                stage: FlashStage::Preparing,
                message: "HEX 已丢失或内容发生变化，请重新编译".to_owned(),
                canceled: false,
            });
            return;
        };
        let transport = match transport_factory(Arc::clone(&worker_cancel)) {
            Ok(transport) => transport,
            Err(error) => {
                done.store(true, Ordering::SeqCst);
                let _ = result_sender.send(FlashResult {
                    success: false,
                    stage: FlashStage::Preparing,
                    message: error.message,
                    canceled: false,
                });
                return;
            }
        };
        let mut transport = transport;
        let sleep_flag = Arc::clone(&worker_cancel);
        let sleep = move |milliseconds: i64| {
            let mut remaining = milliseconds.max(0);
            while remaining > 0 {
                if sleep_flag.load(Ordering::SeqCst) {
                    return;
                }
                let step = remaining.min(20);
                std::thread::sleep(Duration::from_millis(u64::try_from(step).unwrap_or(0)));
                remaining -= step;
            }
        };
        let event_sender = sender;
        let mut on_event = |event: FlashEvent| {
            let _ = event_sender.send(event);
        };
        let mut flash_result = HidFlasher::flash_with_transport(
            &image,
            &mut transport,
            &mut on_event,
            &options,
            &sleep,
        );
        if timed_out.load(Ordering::SeqCst) {
            flash_result = FlashResult {
                success: false,
                stage: FlashStage::Canceled,
                message: "烧录超过 90 秒，已自动取消".to_owned(),
                canceled: true,
            };
        } else if worker_cancel.load(Ordering::SeqCst) && !flash_result.success {
            flash_result = FlashResult {
                success: false,
                stage: FlashStage::Canceled,
                message: "已取消烧录".to_owned(),
                canceled: true,
            };
        }
        done.store(true, Ordering::SeqCst);
        let _ = result_sender.send(flash_result);
    });
    FlashOperation {
        events,
        result,
        cancel_flag,
        handle: Some(handle),
    }
}

#[allow(clippy::type_complexity)]
fn read_and_validate(
    hex_path: &std::path::Path,
    expected_sha256: &str,
    emit: &mut dyn FnMut(FlashStage, &str, Option<i64>, Option<i64>),
) -> Option<pieblock_toolchain::HexImage> {
    let bytes = std::fs::read(hex_path).ok()?;
    let text = String::from_utf8_lossy(&bytes);
    let normalized = text.replace("\r\n", "\n");
    let actual = pieblock_core::sha256_hex(normalized.as_bytes());
    if actual != expected_sha256 {
        return None;
    }
    let validation = IntelHexValidator::validate_application(hex_path);
    emit(FlashStage::Preparing, &validation.message, None, None);
    if !validation.ok {
        return None;
    }
    validation.image
}
