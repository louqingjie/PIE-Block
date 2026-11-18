//! `pieblock-cli`：PIE-Block 只读命令行入口（M0 骨架）。
//!
//! 契约与 Flutter 版保持一致：stdout 只放机器可读数据，stderr 放人类可读信息；
//! 退出码 0 成功 / 1 参数错误 / 2 校验失败 / 3 IO 或格式错误 / 4 生成失败 / 5 内部错误。
//! M0 阶段 validate/codegen 尚未移植领域内核，统一返回 5 并在 stderr 说明。

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde_json::json;

#[derive(Debug, Parser)]
#[command(
    name = "pieblock-cli",
    version,
    about = "PIE-Block TUI 的只读命令行工具（M0 骨架）",
    disable_help_subcommand = true
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// 输出机器可读的命令契约（JSON）。
    Describe,
    /// 校验 `.pieproj` 并输出 JSON（M1 实现）。
    Validate {
        /// 工程文件路径。
        path: PathBuf,
    },
    /// 生成 `main.c`（M1 实现）。
    Codegen {
        /// 工程文件路径。
        path: PathBuf,
        /// 输出文件；省略时写到 stdout。
        #[arg(long)]
        out: Option<PathBuf>,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("pieblock-cli: {error}");
            ExitCode::from(5)
        }
    }
}

fn run(cli: Cli) -> Result<(), CliError> {
    match cli.command {
        Command::Describe => {
            let contract = json!({
                "name": "pieblock-cli",
                "version": "1.0.0",
                "status": "M0 scaffold",
                "stdout": "validate/describe 输出 JSON，codegen 输出纯 C 源码",
                "stderr": "人类可读的进度与错误",
                "projectFormatVersion": pieblock_core::FORMAT_VERSION,
                "oldestSupportedFormatVersion": pieblock_core::OLDEST_SUPPORTED_FORMAT_VERSION,
                "exitCodes": {
                    "0": "成功",
                    "1": "参数错误",
                    "2": "校验失败（stdout 仍有 JSON）",
                    "3": "IO 或格式错误",
                    "4": "代码生成失败",
                    "5": "内部错误"
                },
                "commands": ["describe", "validate <path>", "codegen <path> [--out <file>]"]
            });
            println!("{}", serde_json::to_string_pretty(&contract)?);
            Ok(())
        }
        Command::Validate { path } => Err(CliError::NotPorted(format!(
            "validate 需要 M1 领域内核，当前 M0 骨架尚未移植（输入：{}）",
            path.display()
        ))),
        Command::Codegen { path, out } => Err(CliError::NotPorted(format!(
            "codegen 需要 M1 领域内核，当前 M0 骨架尚未移植（输入：{}，输出：{}）",
            path.display(),
            out.as_ref()
                .map_or_else(|| "stdout".to_owned(), |p| p.display().to_string())
        ))),
    }
}

#[derive(Debug, thiserror::Error)]
enum CliError {
    #[error("JSON 序列化失败：{0}")]
    Json(#[from] serde_json::Error),
    #[error("{0}")]
    NotPorted(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn describe_contract_keeps_exit_codes() {
        let cli = Cli::parse_from(["pieblock-cli", "describe"]);
        assert!(run(cli).is_ok());
    }

    #[test]
    fn validate_reports_not_ported_in_m0() {
        let cli = Cli::parse_from(["pieblock-cli", "validate", "demo.pieproj"]);
        assert!(matches!(run(cli), Err(CliError::NotPorted(_))));
    }
}
