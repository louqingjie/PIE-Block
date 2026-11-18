//! Linux hidraw udev 授权规则：检测、通过 pkexec 安装（与 Flutter 版一致）。
//!
//! 规则内容内嵌在二进制里（发布包无需单独资产）；非 Linux 平台
//! [`is_installed`] 恒为 true，安装返回「仅支持 Linux 桌面版」。

use std::time::{Duration, Instant};

/// 目标规则文件（与 `tools/install_udev_rules.sh` 一致）。
pub const UDEV_RULE_TARGET_PATH: &str = "/etc/udev/rules.d/70-pieblock-hid.rules";
/// 规则内容（与 `linux/udev/70-pieblock-hid.rules` 同一份）。
pub const UDEV_RULE_CONTENT: &str = include_str!("../../../../linux/udev/70-pieblock-hid.rules");
/// root shell 安装脚本：规则内容 base64 后作为 `$1` 传入，写规则 + reload + trigger。
pub const UDEV_INSTALL_SCRIPT: &str = r#"
set -eu
target=/etc/udev/rules.d/70-pieblock-hid.rules
mkdir -p /etc/udev/rules.d
printf %s "$1" | base64 -d > "$target"
chmod 0644 "$target"
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload
  udevadm trigger --subsystem-match=hidraw
else
  exit 10
fi
"#;

/// 规则是否已安装；非 Linux 恒为 true（对应 UI 不显示）。
#[must_use]
pub fn is_installed(path: &str) -> bool {
    if !cfg!(target_os = "linux") {
        return true;
    }
    std::path::Path::new(path).exists()
}

/// 安装结果分类。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UdevInstallOutcome {
    Success,
    InstalledNoUdevadm,
    Canceled,
    NotAuthorized,
    PkexecMissing,
    TimedOut,
    Failed,
}

/// 安装结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UdevInstallResult {
    pub outcome: UdevInstallOutcome,
    pub exit_code: Option<i32>,
    pub stderr_text: String,
}

impl UdevInstallResult {
    #[must_use]
    pub fn ok(&self) -> bool {
        matches!(
            self.outcome,
            UdevInstallOutcome::Success | UdevInstallOutcome::InstalledNoUdevadm
        )
    }
}

/// 命令执行结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandOutput {
    pub exit_code: i32,
    pub stderr_text: String,
}

/// 命令执行错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandError {
    /// 可执行文件不存在（例如未安装 polkit 的 pkexec）。
    NotFound(String),
    TimedOut,
    Other(String),
}

/// 可注入的命令执行器。
pub trait UdevCommandRunner {
    fn run(
        &mut self,
        program: &str,
        arguments: &[String],
        timeout: Duration,
    ) -> Result<CommandOutput, CommandError>;
}

/// 真实系统命令执行器。
pub struct SystemCommandRunner;

impl UdevCommandRunner for SystemCommandRunner {
    fn run(
        &mut self,
        program: &str,
        arguments: &[String],
        timeout: Duration,
    ) -> Result<CommandOutput, CommandError> {
        let started = Instant::now();
        let mut child = std::process::Command::new(program)
            .args(arguments)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|error| {
                if error.kind() == std::io::ErrorKind::NotFound {
                    CommandError::NotFound(error.to_string())
                } else {
                    CommandError::Other(error.to_string())
                }
            })?;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let output = child
                        .wait_with_output()
                        .map_err(|error| CommandError::Other(error.to_string()))?;
                    return Ok(CommandOutput {
                        exit_code: status.code().unwrap_or(-1),
                        stderr_text: String::from_utf8_lossy(&output.stderr).trim().to_owned(),
                    });
                }
                Ok(None) => {
                    if started.elapsed() >= timeout {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(CommandError::TimedOut);
                    }
                    std::thread::sleep(Duration::from_millis(20));
                }
                Err(error) => return Err(CommandError::Other(error.to_string())),
            }
        }
    }
}

/// 安装 udev 规则（同步）。
pub fn install(
    rule_content: &str,
    runner: &mut dyn UdevCommandRunner,
    timeout: Duration,
) -> UdevInstallResult {
    if !cfg!(target_os = "linux") {
        return UdevInstallResult {
            outcome: UdevInstallOutcome::Failed,
            exit_code: None,
            stderr_text: "仅支持 Linux 桌面版".to_owned(),
        };
    }
    let encoded = base64_encode(rule_content.as_bytes());
    let arguments = vec![
        "/bin/sh".to_owned(),
        "-c".to_owned(),
        UDEV_INSTALL_SCRIPT.trim_start_matches('\n').to_owned(),
        "pieblock-udev".to_owned(),
        encoded,
    ];
    match runner.run("pkexec", &arguments, timeout) {
        Ok(output) => {
            let outcome = match output.exit_code {
                0 => UdevInstallOutcome::Success,
                10 => UdevInstallOutcome::InstalledNoUdevadm,
                126 => UdevInstallOutcome::Canceled,
                127 => UdevInstallOutcome::NotAuthorized,
                _ => UdevInstallOutcome::Failed,
            };
            UdevInstallResult {
                outcome,
                exit_code: Some(output.exit_code),
                stderr_text: output.stderr_text,
            }
        }
        Err(CommandError::TimedOut) => UdevInstallResult {
            outcome: UdevInstallOutcome::TimedOut,
            exit_code: None,
            stderr_text: String::new(),
        },
        Err(CommandError::NotFound(message)) => UdevInstallResult {
            outcome: UdevInstallOutcome::PkexecMissing,
            exit_code: None,
            stderr_text: message,
        },
        Err(CommandError::Other(message)) => UdevInstallResult {
            outcome: UdevInstallOutcome::Failed,
            exit_code: None,
            stderr_text: message,
        },
    }
}

/// 用内嵌规则与系统执行器安装。
pub fn install_default(timeout: Duration) -> UdevInstallResult {
    install(UDEV_RULE_CONTENT, &mut SystemCommandRunner, timeout)
}

fn base64_encode(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::new();
    for chunk in bytes.chunks(3) {
        let buffer = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let indexes = [
            buffer[0] >> 2,
            ((buffer[0] & 0x03) << 4) | (buffer[1] >> 4),
            ((buffer[1] & 0x0f) << 2) | (buffer[2] >> 6),
            buffer[2] & 0x3f,
        ];
        for (index, value) in indexes.iter().enumerate() {
            if index <= chunk.len() {
                output.push(ALPHABET[*value as usize] as char);
            } else {
                output.push('=');
            }
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeRunner {
        result: Result<CommandOutput, CommandError>,
        captured: Option<(String, Vec<String>)>,
    }

    impl UdevCommandRunner for FakeRunner {
        fn run(
            &mut self,
            program: &str,
            arguments: &[String],
            _timeout: Duration,
        ) -> Result<CommandOutput, CommandError> {
            self.captured = Some((program.to_owned(), arguments.to_vec()));
            self.result.clone()
        }
    }

    #[test]
    fn base64_matches_rfc4648() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn install_maps_exit_codes() {
        for (code, expected) in [
            (0, UdevInstallOutcome::Success),
            (10, UdevInstallOutcome::InstalledNoUdevadm),
            (126, UdevInstallOutcome::Canceled),
            (127, UdevInstallOutcome::NotAuthorized),
            (1, UdevInstallOutcome::Failed),
        ] {
            let mut runner = FakeRunner {
                result: Ok(CommandOutput {
                    exit_code: code,
                    stderr_text: "err".to_owned(),
                }),
                captured: None,
            };
            let result = install("rule\n", &mut runner, Duration::from_secs(1));
            if cfg!(target_os = "linux") {
                assert_eq!(result.outcome, expected, "exit code {code}");
                let (program, arguments) = runner.captured.expect("captured");
                assert_eq!(program, "pkexec");
                assert_eq!(arguments[1], "-c");
                assert_eq!(arguments[3], "pieblock-udev");
            } else {
                assert_eq!(result.outcome, UdevInstallOutcome::Failed);
                assert!(result.stderr_text.contains("Linux"));
            }
        }
    }

    #[test]
    fn install_maps_runner_errors() {
        let mut runner = FakeRunner {
            result: Err(CommandError::NotFound("pkexec".to_owned())),
            captured: None,
        };
        let result = install("rule\n", &mut runner, Duration::from_secs(1));
        assert_eq!(
            result.outcome,
            if cfg!(target_os = "linux") {
                UdevInstallOutcome::PkexecMissing
            } else {
                UdevInstallOutcome::Failed
            }
        );
    }
}
