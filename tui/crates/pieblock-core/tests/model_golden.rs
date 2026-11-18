//! 模型 golden 基线：由开发期 Dart 工具生成，Rust 侧只读快照。
//!
//! golden 覆盖 `packages/pieblock_core/test/fixtures/*.pieproj`（格式 17–22）
//! 与 `assets/templates/*.pieproj`（格式 23），用来锁定读取/迁移后的文档形态。

use std::fs;
use std::path::PathBuf;

#[test]
fn golden_models_are_readable_and_current_format() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../parity/golden/model");
    let entries = fs::read_dir(&dir).unwrap_or_else(|error| {
        panic!("读取 golden 目录失败 {}：{error}", dir.display());
    });

    let mut count = 0_usize;
    for entry in entries {
        let path = entry.expect("golden entry").path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path).expect("read golden");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("parse golden");

        let source_format = value["sourceFormatVersion"]
            .as_u64()
            .unwrap_or_else(|| panic!("{} 缺少 sourceFormatVersion", path.display()));
        assert!(
            (17..=23).contains(&source_format),
            "{} sourceFormatVersion={source_format}",
            path.display()
        );

        let document = &value["document"];
        assert_eq!(
            document["format_version"].as_u64(),
            Some(23),
            "{} 未迁移到格式 23",
            path.display()
        );
        let kind = document["project_kind"]
            .as_str()
            .unwrap_or_else(|| panic!("{} 缺少 project_kind", path.display()));
        assert!(
            matches!(kind, "infantry" | "engineer" | "debug" | "music"),
            "{} project_kind={kind}",
            path.display()
        );
        assert!(
            document["guide_progress"]["current_step_id"].is_string(),
            "{} 缺少 guide_progress.current_step_id",
            path.display()
        );
        assert!(
            document["config"].is_object(),
            "{} 缺少 config 对象",
            path.display()
        );
        count += 1;
    }

    assert!(count >= 13, "golden 文件数量不足：{count}");
}
