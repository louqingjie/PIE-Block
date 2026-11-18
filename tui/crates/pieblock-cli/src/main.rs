//! `pieblock-cli`：PIE-Block 工程命令行工具（M1 移植中）。
//!
//! 契约与 Flutter 版保持一致：stdout 只放机器可读数据，stderr 放人类可读信息；
//! 退出码 0 成功 / 1 参数错误 / 2 校验失败 / 3 IO 或格式错误 / 4 生成失败 /
//! 5 内部错误 / 6 已有待处理提案（propose 尚未移植）。
//!
//! 已移植：`validate`、`codegen`（调试/步兵工程）；工程/音乐代码生成与
//! `propose` 在后续提交补齐。

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use pieblock_core::codegen::{GenerationError, generate};
use pieblock_core::validation::{IssueSeverity, ValidationIssue};
use pieblock_core::{ProjectDocument, validate};
use serde_json::{Map, Value, json};

const EXIT_USAGE: u8 = 1;
const EXIT_INVALID: u8 = 2;
const EXIT_IO: u8 = 3;
const EXIT_GENERATE: u8 = 4;
const EXIT_INTERNAL: u8 = 5;

const TOOL_NAME: &str = "pieblock-cli";
const CLI_VERSION: &str = "1.0.0";

#[derive(Debug, Parser)]
#[command(
    name = "pieblock-cli",
    version,
    about = "PIE-Block 工程命令行工具（只写提案，不编译不烧录）",
    disable_help_subcommand = true
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// 校验 `.pieproj` 并输出 JSON。
    Validate {
        /// 工程文件路径。
        path: PathBuf,
    },
    /// 生成 `main.c`；`--out` 省略时写到 stdout。
    Codegen {
        /// 工程文件路径。
        path: PathBuf,
        /// 输出文件；省略时写到 stdout。
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// 输出机器可读的命令契约（JSON）。
    Describe,
}

fn main() -> ExitCode {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            // clap 默认把参数错误落成 2；本工具契约里 1 才是参数错误。
            let _ = error.print();
            return ExitCode::from(EXIT_USAGE);
        }
    };
    match run(cli) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("内部错误：{error}");
            eprintln!("设置 PIEBLOCK_DEBUG=1 可查看调用栈。");
            ExitCode::from(EXIT_INTERNAL)
        }
    }
}

fn run(cli: Cli) -> Result<u8, String> {
    match cli.command {
        Command::Describe => {
            describe();
            Ok(0)
        }
        Command::Validate { path } => validate_command(&path),
        Command::Codegen { path, out } => codegen_command(&path, out.as_deref()),
    }
}

fn describe() {
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "name": TOOL_NAME,
            "version": CLI_VERSION,
            "description": "PIE-Block 工程命令行工具：校验配置、生成代码、提交改动提案。",
            "stdoutPolicy": "机器可读数据（validate/propose/describe=JSON, codegen=纯 C 源码）",
            "stderrPolicy": "人类可读的进度与错误",
            "exitCodes": {
                "0": "成功",
                "1": "参数错误",
                "2": "校验失败（存在 error 级问题）",
                "3": "IO 或格式错误（文件不存在/JSON 非法/内容结构错误/版本不兼容）",
                "4": "代码生成失败",
                "5": "内部错误（兜底；设置 PIEBLOCK_DEBUG=1 可查看调用栈）",
                "6": "已有待处理提案（未加 --force）",
            },
            "commands": [
                {"name": "validate", "usage": "pieblock-cli validate <工程.pieproj>", "stdout": "JSON: {ok, valid, project:{kind,format,sourceFormat}, counts:{errors,warnings}, issues:[{severity,kind,fieldPath,message,stepId}]}", "note": "无论是否有问题都以 JSON 返回；valid=false 表示存在 error。"},
                {"name": "codegen", "usage": "pieblock-cli codegen <工程.pieproj> [--out <main.c>]", "stdout": "纯 C 源码（可直接在 shell 里重定向到文件）", "stderr": "人类可读的生成摘要；失败时给出错误清单", "note": "配置有 error 级问题时拒绝生成（与 GUI 行为一致）。"},
                {"name": "describe", "usage": "pieblock-cli describe", "stdout": "本命令契约（JSON）"},
            ],
        }))
        .expect("describe JSON")
    );
}

fn validate_command(path: &Path) -> Result<u8, String> {
    let document = match load_document(path) {
        Ok(document) => document,
        Err(error) => {
            eprintln!("{error}");
            return Ok(EXIT_IO);
        }
    };
    let issues = validate(&document.config);
    let errors: Vec<&ValidationIssue> = issues
        .iter()
        .filter(|issue| issue.severity == IssueSeverity::Error)
        .collect();
    let warnings: Vec<&ValidationIssue> = issues
        .iter()
        .filter(|issue| issue.severity == IssueSeverity::Warning)
        .collect();
    let payload = json!({
        "ok": true,
        "valid": errors.is_empty(),
        "project": {
            "kind": document.kind.as_str(),
            "format": pieblock_core::FORMAT_VERSION,
            "sourceFormat": document.source_format_version,
        },
        "counts": {
            "errors": errors.len(),
            "warnings": warnings.len(),
        },
        "issues": issues.iter().map(issue_json).collect::<Vec<_>>(),
    });
    println!(
        "{}",
        serde_json::to_string(&payload).map_err(|error| error.to_string())?
    );
    eprintln!(
        "校验完成：{} 工程，{} 个错误，{} 个提醒。",
        document.kind.as_str(),
        errors.len(),
        warnings.len()
    );
    Ok(if errors.is_empty() { 0 } else { EXIT_INVALID })
}

fn codegen_command(path: &Path, out: Option<&Path>) -> Result<u8, String> {
    let document = match load_document(path) {
        Ok(document) => document,
        Err(error) => {
            eprintln!("{error}");
            return Ok(EXIT_IO);
        }
    };
    let issues = validate(&document.config);
    let errors: Vec<&ValidationIssue> = issues
        .iter()
        .filter(|issue| issue.severity == IssueSeverity::Error)
        .collect();
    if !errors.is_empty() {
        eprintln!(
            "配置有 {} 个错误，不能生成代码（与 GUI 行为一致）：",
            errors.len()
        );
        for issue in errors {
            eprintln!("  · [{}] {}", issue.field_path, issue.message);
        }
        return Ok(EXIT_INVALID);
    }
    let code = match generate(&document.config) {
        Ok(code) => code,
        Err(GenerationError::InvalidConfig { message }) => {
            eprintln!("生成失败：配置尚未完成，不能生成代码：{message}");
            return Ok(EXIT_GENERATE);
        }
        Err(GenerationError::NotPorted { kind }) => {
            eprintln!("生成失败：{kind}代码生成尚未移植");
            return Ok(EXIT_GENERATE);
        }
    };
    let line_count = code.split('\n').count();
    if let Some(out_path) = out {
        if let Some(parent) = out_path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
        }
        let mut file = match std::fs::File::create(out_path) {
            Ok(file) => file,
            Err(error) => {
                eprintln!("写出失败：{}\n{error}", out_path.display());
                return Ok(EXIT_IO);
            }
        };
        if let Err(error) = file.write_all(code.as_bytes()) {
            eprintln!("写出失败：{}\n{error}", out_path.display());
            return Ok(EXIT_IO);
        }
        eprintln!("已生成 {line_count} 行代码 → {}", out_path.display());
    } else {
        print!("{code}");
        eprintln!(
            "已生成 {line_count} 行代码（{} 工程）。",
            document.kind.as_str()
        );
    }
    Ok(0)
}

fn load_document(path: &Path) -> Result<ProjectDocument, String> {
    if !path.exists() {
        return Err(format!("工程文件不存在：{}", path.display()));
    }
    let text = std::fs::read_to_string(path)
        .map_err(|error| format!("读取工程失败：{}\n{error}", path.display()))?;
    let decoded: Value = match serde_json::from_str(&text) {
        Ok(value) => value,
        Err(_) => {
            return Err(format!("工程文件不是合法 JSON：{}", path.display()));
        }
    };
    let Some(map) = decoded.as_object() else {
        return Err(format!("工程文件内容不是 JSON 对象：{}", path.display()));
    };
    ProjectDocument::from_json(&Value::Object(map.clone()))
        .map_err(|error| format!("工程格式错误：{error}"))
}

fn issue_json(issue: &ValidationIssue) -> Value {
    let mut map = Map::new();
    map.insert(
        "severity".to_owned(),
        Value::String(issue.severity.as_str().to_owned()),
    );
    map.insert(
        "kind".to_owned(),
        Value::String(issue.kind.as_str().to_owned()),
    );
    map.insert(
        "fieldPath".to_owned(),
        Value::String(issue.field_path.clone()),
    );
    map.insert("message".to_owned(), Value::String(issue.message.clone()));
    map.insert("stepId".to_owned(), Value::String(issue.step_id.clone()));
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use super::*;
    use pieblock_core::ProjectKind;

    #[test]
    fn describe_keeps_exit_codes() {
        assert!(run(Cli::parse_from(["pieblock-cli", "describe"])).is_ok());
    }

    #[test]
    fn missing_file_is_io_error() {
        let cli = Cli::parse_from(["pieblock-cli", "validate", "no-such-file.pieproj"]);
        assert_eq!(run(cli).unwrap(), EXIT_IO);
    }

    #[test]
    fn kind_labels_match_dart_contract() {
        for (kind, label) in [
            (ProjectKind::Infantry, "infantry"),
            (ProjectKind::Engineer, "engineer"),
            (ProjectKind::Debug, "debug"),
            (ProjectKind::Music, "music"),
        ] {
            assert_eq!(kind.as_str(), label);
        }
    }
}
