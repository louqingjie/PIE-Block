//! 模型 golden 对拍：读取 Dart 侧生成的 `tui/parity/golden/model/*.json`，
//! 验证 Rust 读取/迁移/保存与 Flutter 实现逐字节一致。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::ProjectDocument;
use pieblock_core::document::golden_wrapper;
use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden_dir() -> PathBuf {
    repo_root().join("tui/parity/golden/model")
}

#[test]
fn model_goldens_match_byte_for_byte() {
    let dir = golden_dir();
    let mut files: Vec<PathBuf> = fs::read_dir(&dir)
        .unwrap_or_else(|error| panic!("read golden dir {}: {error}", dir.display()))
        .map(|entry| entry.expect("dir entry").path())
        .filter(|path| path.extension().and_then(|ext| ext.to_str()) == Some("json"))
        .collect();
    files.sort();
    assert!(!files.is_empty(), "no golden files in {}", dir.display());

    for path in &files {
        let expected = fs::read_to_string(path)
            .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
        let wrapper: Value = serde_json::from_str(&expected).expect("golden is valid json");
        let source = wrapper["source"].as_str().expect("source");
        let source_path = repo_root().join(source);
        let raw = fs::read_to_string(&source_path)
            .unwrap_or_else(|error| panic!("read {}: {error}", source_path.display()));
        let value: Value = serde_json::from_str(&raw).expect("project is valid json");

        let document =
            ProjectDocument::from_json(&value).unwrap_or_else(|error| panic!("{source}: {error}"));
        assert_eq!(
            document.kind.as_str(),
            wrapper["kind"].as_str().expect("kind"),
            "{source}: kind"
        );
        assert_eq!(
            document.source_format_version,
            wrapper["sourceFormatVersion"]
                .as_i64()
                .expect("sourceFormatVersion"),
            "{source}: source format version"
        );
        assert_eq!(
            document.to_json(),
            wrapper["document"],
            "{source}: document semantics"
        );

        let actual = serde_json::to_string_pretty(&golden_wrapper(source, &document))
            .expect("serialize")
            + "\n";
        assert_eq!(actual, expected, "{}: byte mismatch", path.display());
    }

    assert_eq!(files.len(), 13, "expected 9 fixtures + 4 templates");
}

#[test]
fn golden_document_payload_roundtrips() {
    let dir = golden_dir();
    let path = dir.join("format18_engineer.json");
    let wrapper: Value =
        serde_json::from_str(&fs::read_to_string(&path).expect("golden")).expect("json");
    let document =
        ProjectDocument::from_json(&wrapper["document"]).expect("golden document is readable");
    assert_eq!(document.kind.as_str(), "engineer");
    assert_eq!(document.source_format_version, 23);
    assert_eq!(document.to_json(), wrapper["document"]);
}

#[test]
fn old_versions_are_migrated_to_current_shape() {
    let dir = golden_dir();
    for name in [
        "format17_engineer.json",
        "format18_engineer.json",
        "format19_engineer.json",
        "format20_engineer.json",
        "format21_engineer.json",
        "format22_engineer.json",
    ] {
        let wrapper: Value =
            serde_json::from_str(&fs::read_to_string(dir.join(name)).expect("golden"))
                .expect("json");
        assert_eq!(wrapper["document"]["format_version"], 23, "{name}");
    }
}
