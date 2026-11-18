//! 主程序命令行选项冒烟测试（不进入 TUI）。

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_pieblock-tui")
}

#[test]
fn version_flag_prints_version() {
    let output = Command::new(bin()).arg("--version").output().expect("run");
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("PIE-Block TUI 0.1.0"), "got {text}");
}

#[test]
fn diagnostics_flag_prints_environment() {
    let output = Command::new(bin())
        .arg("--diagnostics")
        .output()
        .expect("run");
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("平台"));
    assert!(text.contains("数据目录"));
    assert!(text.contains("运行时资源"));
}

#[test]
fn help_flag_lists_options() {
    let output = Command::new(bin()).arg("--help").output().expect("run");
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("--diagnostics"));
    assert!(text.contains("--no-mouse"));
}
