//! HID 烧录状态机：连接→擦除→分块写入（含重试）→复位，以及中断探活指引。
//!
//! 与 `flasher.dart` 对齐（Dart 侧还有 isolate/超时/取消的外层封装；TUI 由
//! worker 线程负责超时与取消，这里只保留协议主流程，便于脚本化对拍）。

use pieblock_toolchain::HexImage;

use crate::protocol::{HidNoResponse, HidProtocol, HidProtocolError};
use crate::transport::HidTransport;

/// 烧录阶段。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlashStage {
    Preparing,
    Connecting,
    Erasing,
    Programming,
    Resetting,
    Done,
    Canceled,
}

impl FlashStage {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Connecting => "connecting",
            Self::Erasing => "erasing",
            Self::Programming => "programming",
            Self::Resetting => "resetting",
            Self::Done => "done",
            Self::Canceled => "canceled",
        }
    }

    fn stage_text(self) -> &'static str {
        match self {
            Self::Connecting => "连接引导程序",
            Self::Erasing => "擦除程序区",
            Self::Programming => "写入固件",
            Self::Resetting => "复位主控板",
            Self::Preparing => "校验固件",
            Self::Done | Self::Canceled => "烧录",
        }
    }
}

/// 一条烧录进度事件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashEvent {
    pub stage: FlashStage,
    pub message: String,
    pub current: Option<i64>,
    pub total: Option<i64>,
}

/// 烧录结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashResult {
    pub success: bool,
    pub stage: FlashStage,
    pub message: String,
    pub canceled: bool,
}

impl FlashResult {
    fn failure(stage: FlashStage, message: impl Into<String>) -> Self {
        Self {
            success: false,
            stage,
            message: message.into(),
            canceled: false,
        }
    }
}

/// 烧录节奏与重试参数。
#[derive(Debug, Clone, Copy)]
pub struct FlashOptions {
    pub report_gap_ms: i64,
    pub write_attempts: i64,
    pub retry_backoff_ms: i64,
    pub probe_timeout_ms: i64,
}

impl Default for FlashOptions {
    fn default() -> Self {
        Self {
            report_gap_ms: crate::protocol::HID_REPORT_GAP_MS,
            write_attempts: 3,
            retry_backoff_ms: 50,
            probe_timeout_ms: 800,
        }
    }
}

/// 烧录器（无状态；传输层由调用方注入）。
pub struct HidFlasher;

impl HidFlasher {
    /// 枚举设备数量；枚举失败按 Dart `detectDeviceCount` 返回 0。
    pub fn detect_device_count<T: HidTransport + ?Sized>(transport: &mut T) -> i64 {
        transport.count_devices().unwrap_or(0)
    }

    /// 在给定传输层上执行完整烧录流程。
    pub fn flash_with_transport<T: HidTransport + ?Sized>(
        image: &HexImage,
        transport: &mut T,
        on_event: &mut dyn FnMut(FlashEvent),
        options: &FlashOptions,
        sleep_ms: &dyn Fn(i64),
    ) -> FlashResult {
        let device_count = match transport.count_devices() {
            Ok(count) => count,
            Err(error) => {
                return FlashResult::failure(FlashStage::Connecting, error.message);
            }
        };
        if device_count != 1 {
            return FlashResult::failure(
                FlashStage::Connecting,
                if device_count == 0 {
                    "未找到处于 ISP 模式的主控板"
                } else {
                    "检测到多块主控板，请只连接一块"
                },
            );
        }
        if !transport.open() {
            let result = FlashResult::failure(FlashStage::Connecting, "无法打开 USB-HID 设备");
            transport.close();
            return result;
        }
        let mut active_stage = FlashStage::Connecting;
        let mut block_index: i64 = -1;
        let mut block_total: i64 = 0;
        let result = (|| {
            emit(
                on_event,
                FlashStage::Connecting,
                "正在连接主控板引导程序…",
                None,
                None,
            );
            emit(
                on_event,
                FlashStage::Connecting,
                format!("帧内报告间隔 {}ms", options.report_gap_ms),
                None,
                None,
            );
            let expect = |transport: &mut T,
                          payload: &[u8],
                          label: &str,
                          command_offset: usize,
                          command: u8,
                          timeout: i64| {
                HidProtocol::expect_ack(
                    transport,
                    payload,
                    label,
                    command_offset,
                    command,
                    timeout,
                    options.report_gap_ms,
                    sleep_ms,
                )
            };
            expect(
                transport,
                &[0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
                "info",
                0,
                0x01,
                3000,
            )?;
            expect(
                transport,
                &[0x05, 0, 0, 0x5a, 0xa5],
                "unlock",
                0,
                0x05,
                3000,
            )?;
            active_stage = FlashStage::Erasing;
            emit(on_event, active_stage, "正在擦除主控板程序区…", None, None);
            expect(transport, &[0x03, 0, 0, 0x5a, 0xa5], "erase", 0, 0x03, 3000)?;
            let blocks = HidProtocol::build_write_blocks(image)
                .map_err(|error| HidProtocolError::state(error.to_string()))?;
            block_total = i64::try_from(blocks.len()).unwrap_or(0);
            active_stage = FlashStage::Programming;
            for (index, block) in blocks.iter().enumerate() {
                block_index = i64::try_from(index).unwrap_or(0);
                let label = format!("写入 0x{:04x}", block.address);
                let mut payload = vec![
                    block.command as u8,
                    ((block.address >> 8) & 0xff) as u8,
                    (block.address & 0xff) as u8,
                    0x5a,
                    0xa5,
                ];
                payload.extend_from_slice(&block.data);
                let mut attempt = 1_i64;
                let response = loop {
                    match expect(transport, &payload, &label, 0, 0x02, 3000) {
                        Ok(value) => break value,
                        Err(HidProtocolError::NoResponse(_)) => {
                            if attempt >= options.write_attempts {
                                return Err(HidProtocolError::NoResponse(HidNoResponse { label }));
                            }
                            emit(
                                on_event,
                                active_stage,
                                format!(
                                    "{label} 无响应，正在重发（第 {}/{} 次）",
                                    attempt + 1,
                                    options.write_attempts
                                ),
                                None,
                                None,
                            );
                            sleep_ms(options.retry_backoff_ms);
                            attempt += 1;
                        }
                        Err(error) => return Err(error),
                    }
                };
                if response.len() < 7 || response[6] != 0x54 {
                    return Err(HidProtocolError::state(format!("{label} 未确认成功")));
                }
                emit(
                    on_event,
                    active_stage,
                    format!("正在写入固件 {}/{}", index + 1, blocks.len()),
                    Some(i64::try_from(index + 1).unwrap_or(0)),
                    Some(block_total),
                );
            }
            active_stage = FlashStage::Resetting;
            emit(
                on_event,
                active_stage,
                "写入完成，正在复位主控板…",
                None,
                None,
            );
            for report in HidProtocol::split_reports(&HidProtocol::build_packet(&[0xff])) {
                let _ = transport.write(&report);
            }
            sleep_ms(200);
            emit(
                on_event,
                FlashStage::Done,
                "烧录完成，主控板已运行新程序",
                None,
                None,
            );
            Ok::<(), HidProtocolError>(())
        })();
        match result {
            Ok(()) => {
                transport.close();
                FlashResult {
                    success: true,
                    stage: FlashStage::Done,
                    message: "烧录完成".to_owned(),
                    canceled: false,
                }
            }
            Err(error) => {
                let result = if matches!(error, HidProtocolError::NoResponse(_)) || block_index >= 0
                {
                    report_interruption(
                        &error,
                        transport,
                        active_stage,
                        block_index,
                        block_total,
                        options,
                        on_event,
                        sleep_ms,
                    )
                } else {
                    let message = error.to_string();
                    emit(on_event, active_stage, message.clone(), None, None);
                    FlashResult::failure(active_stage, message)
                };
                transport.close();
                result
            }
        }
    }
}

fn emit(
    on_event: &mut dyn FnMut(FlashEvent),
    stage: FlashStage,
    message: impl Into<String>,
    current: Option<i64>,
    total: Option<i64>,
) {
    on_event(FlashEvent {
        stage,
        message: message.into(),
        current,
        total,
    });
}

#[allow(clippy::too_many_arguments)]
fn report_interruption<T: HidTransport + ?Sized>(
    error: &HidProtocolError,
    transport: &mut T,
    stage: FlashStage,
    block_index: i64,
    block_total: i64,
    options: &FlashOptions,
    on_event: &mut dyn FnMut(FlashEvent),
    sleep_ms: &dyn Fn(i64),
) -> FlashResult {
    let no_response = matches!(error, HidProtocolError::NoResponse(_));
    let label = match error {
        HidProtocolError::NoResponse(error) => error.label.clone(),
        HidProtocolError::State(message) => message.clone(),
    };
    let where_text = if block_index < 0 {
        format!("{}（{label}）", stage.stage_text())
    } else {
        format!("第 {}/{} 块（{label}）", block_index + 1, block_total)
    };
    emit(
        on_event,
        stage,
        format!(
            "{where_text}：{}，烧录中断",
            if no_response {
                format!("连续 {} 次无响应", options.write_attempts)
            } else {
                "写入中断".to_owned()
            }
        ),
        None,
        None,
    );
    let alive = probe_alive(transport, options, sleep_ms);
    let reason = if no_response { "无响应" } else { "" };
    if alive {
        emit(
            on_event,
            stage,
            "主控板仍在 ISP 模式：直接点「烧录当前固件」重试即可，无需重新编译。",
            None,
            None,
        );
        return FlashResult::failure(
            stage,
            format!("烧录中断：{where_text}{reason}，设备仍在 ISP 模式，可直接重试"),
        );
    }
    emit(
        on_event,
        stage,
        "主控板已无响应：请关闭四个开关，给主控板断电几秒后重新上电，再点「烧录当前固件」用同一份固件重试，无需重新编译。",
        None,
        None,
    );
    FlashResult::failure(
        stage,
        format!("烧录中断：{where_text}{reason}，请断电重新上电后重试"),
    )
}

fn probe_alive<T: HidTransport + ?Sized>(
    transport: &mut T,
    options: &FlashOptions,
    sleep_ms: &dyn Fn(i64),
) -> bool {
    HidProtocol::expect_ack(
        transport,
        &[0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
        "info",
        0,
        0x01,
        options.probe_timeout_ms,
        options.report_gap_ms,
        sleep_ms,
    )
    .is_ok()
}
