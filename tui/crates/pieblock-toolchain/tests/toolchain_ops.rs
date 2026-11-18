//! 工具链运行时部署、目标文件缓存、SDCC 构建计划的行为测试。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_toolchain::{
    BuildArtifact, BuildEvent, CompilerKind, SdccBuildPlan, SdccObjectCache, SdccRuntimeDeployer,
};

fn unique_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!("toolchain-ops-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn write_bundle(toolchain: &Path, files: &[(&str, &[u8])]) {
    let mut manifest = serde_json::Map::new();
    for (relative, content) in files {
        let path = toolchain.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("parent");
        }
        fs::write(&path, content).expect("write bundle file");
        manifest.insert(
            (*relative).to_owned(),
            serde_json::Value::String(pieblock_core::sha256_hex(content)),
        );
    }
    let mut root = serde_json::Map::new();
    root.insert("files".to_owned(), serde_json::Value::Object(manifest));
    fs::write(
        toolchain.join("bundle_manifest.json"),
        serde_json::to_string(&serde_json::Value::Object(root)).expect("manifest"),
    )
    .expect("write manifest");
}

#[test]
fn deployer_copies_validates_and_reuses() {
    let dir = unique_dir("deploy");
    let assets = dir.join("assets");
    let toolchain_assets = assets.join("toolchain");
    fs::create_dir_all(toolchain_assets.join("bin")).expect("toolchain");
    fs::write(toolchain_assets.join("bin").join("sdcc.exe"), b"sdcc").expect("sdcc");
    write_bundle(
        &toolchain_assets,
        &[("bin/sdcc.exe", b"sdcc"), ("include/stdint.h", b"header")],
    );
    let firmware_assets = assets.join("firmware");
    fs::create_dir_all(&firmware_assets).expect("firmware");
    fs::write(firmware_assets.join("build_manifest.json"), b"{}").expect("build manifest");

    let deployer = SdccRuntimeDeployer::new(dir.join("runtime"));
    let mut events: Vec<BuildEvent> = Vec::new();
    let deployment = deployer
        .ensure(
            &toolchain_assets,
            &firmware_assets,
            "fp-1",
            &mut |event| events.push(event),
            &|_| {},
        )
        .expect("deploy");
    assert!(deployment.toolchain.join("bin").join("sdcc.exe").exists());
    assert_eq!(
        fs::read_to_string(deployment.toolchain.parent().expect("root").join(".ready"))
            .expect("marker"),
        "fp-1"
    );
    assert!(!events.is_empty());
    let staging: Vec<_> = fs::read_dir(dir.join("runtime").join("sdcc"))
        .expect("root")
        .flatten()
        .filter(|entry| entry.file_name().to_string_lossy().contains(".staging-"))
        .collect();
    assert!(staging.is_empty(), "staging should be cleaned");

    events.clear();
    deployer
        .ensure(
            &toolchain_assets,
            &firmware_assets,
            "fp-1",
            &mut |event| events.push(event),
            &|_| {},
        )
        .expect("reuse");
    assert!(
        events.is_empty(),
        "ready deployment should be reused silently"
    );
}

#[test]
fn deployer_rejects_corrupted_bundle() {
    let dir = unique_dir("deploy-corrupt");
    let toolchain_assets = dir.join("assets").join("toolchain");
    fs::create_dir_all(toolchain_assets.join("bin")).expect("toolchain");
    write_bundle(
        &toolchain_assets,
        &[("bin/sdcc.exe", b"sdcc"), ("include/stdint.h", b"header")],
    );
    fs::write(
        toolchain_assets.join("include").join("stdint.h"),
        b"tampered",
    )
    .expect("tamper");
    let firmware_assets = dir.join("assets").join("firmware");
    fs::create_dir_all(&firmware_assets).expect("firmware");
    fs::write(firmware_assets.join("build_manifest.json"), b"{}").expect("manifest");
    let deployer = SdccRuntimeDeployer::new(dir.join("runtime"));
    let error = deployer
        .ensure(
            &toolchain_assets,
            &firmware_assets,
            "fp-1",
            &mut |_| {},
            &|_| {},
        )
        .expect_err("corrupt bundle");
    assert!(
        error.message.contains("校验失败"),
        "unexpected message: {}",
        error.message
    );
    assert!(error.hint.is_some());
}

#[test]
fn object_cache_roundtrip_and_corruption() {
    let dir = unique_dir("object-cache");
    let cache = SdccObjectCache::new(&dir.join("runtime"), "fp-1", "infantry");
    let object = dir.join("build").join("isr.rel");
    fs::create_dir_all(object.parent().expect("parent")).expect("build");
    fs::write(&object, b"object-bytes").expect("object");
    fs::write(object.with_extension("lst"), b"listing").expect("listing");
    cache
        .store("projects/infantry/src/isr.c", &object, 2)
        .expect("store");
    let destination = dir.join("out").join("isr.rel");
    let hit = cache
        .lookup("projects/infantry/src/isr.c", &destination)
        .expect("hit");
    assert_eq!(hit.warning_count, 2);
    assert_eq!(fs::read(&destination).expect("copied"), b"object-bytes");
    assert_eq!(
        fs::read(destination.with_extension("lst")).expect("listing"),
        b"listing"
    );

    let cached = cache.cache_path("projects/infantry/src/isr.c");
    fs::write(&cached, b"corrupted").expect("corrupt");
    assert!(
        cache
            .lookup("projects/infantry/src/isr.c", &destination)
            .is_none()
    );
}

#[test]
fn build_plan_parses_manifest_and_writes_interrupt_header() {
    let dir = unique_dir("build-plan");
    let resource = dir.join("resource");
    let firmware = resource.join("firmware");
    fs::create_dir_all(firmware.join("projects").join("infantry").join("src")).expect("src");
    fs::create_dir_all(firmware.join("projects").join("infantry").join("inc")).expect("inc");
    fs::create_dir_all(firmware.join("common")).expect("common");
    fs::create_dir_all(resource.join("toolchain").join("include")).expect("include");
    fs::write(
        firmware.join("common").join("board.c"),
        b"void board_init(void) {}\n",
    )
    .expect("board");
    fs::write(
        firmware
            .join("projects")
            .join("infantry")
            .join("src")
            .join("isr.c"),
        b"static void timer_isr(void) __interrupt (1) {}\nvoid outer(void) __interrupt (3)\n{\n}\n",
    )
    .expect("isr");
    let main_source = dir.join("generated").join("main.c");
    fs::create_dir_all(main_source.parent().expect("parent")).expect("generated");
    fs::write(&main_source, b"int main(void) { return 0; }\n").expect("main");
    let manifest = serde_json::json!({
        "source_groups": {
            "common": ["common/board.c"],
            "runtime": ["common/board.c"]
        },
        "projects": {
            "infantry": {"library_groups": ["runtime"]}
        },
        "kind_projects": {"infantry": "infantry"},
        "include_dirs": ["common"],
        "compile_flags": ["--model-large", "-c"],
        "link_flags": ["--model-large"],
        "runtime_libraries": ["libc251.lib"]
    });
    fs::write(
        firmware.join("build_manifest.json"),
        serde_json::to_string(&manifest).expect("manifest"),
    )
    .expect("write manifest");

    let output = dir.join("out");
    let plan = SdccBuildPlan::prepare(
        &resource,
        "infantry",
        &main_source.display().to_string(),
        &output,
    )
    .expect("plan");
    assert_eq!(plan.project_name, "infantry");
    assert_eq!(plan.source_paths.len(), 3);
    assert_eq!(plan.library_source_paths.len(), 1);
    assert!(plan.source_paths[2].ends_with("main.c"));
    let header = fs::read_to_string(&plan.interrupt_header_path).expect("header");
    assert!(header.contains("#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H"));
    assert!(header.contains("void outer(void) __interrupt (3);"));
    assert!(header.contains("void timer_isr(void) __interrupt (1);"));
    assert!(header.find("outer").expect("outer") < header.find("timer_isr").expect("timer"));
    assert!(plan.compile_arguments.contains(&"--model-large".to_owned()));
    assert!(plan.link_arguments.contains(&"libc251.lib".to_owned()));
}

#[test]
fn build_artifact_json_roundtrip() {
    let artifact = BuildArtifact {
        hex_path: "C:/build/main.hex".to_owned(),
        hex_sha256: "a".repeat(64),
        fingerprint: "flutter_build_v5|x".to_owned(),
        source_sha256: "b".repeat(64),
        compiler: CompilerKind::Sdcc,
        compiler_fingerprint: "c".repeat(64),
        template_version: "1.8.0".to_owned(),
        built_at: "2026-01-01T00:00:00.000Z".to_owned(),
        byte_count: 128,
        warning_count: 0,
        last_flashed_at: Some("2026-01-02T00:00:00.000Z".to_owned()),
    };
    let json = artifact.to_json();
    let text = serde_json::to_string(&json).expect("json");
    let parsed: serde_json::Value = serde_json::from_str(&text).expect("parse");
    let back = BuildArtifact::from_json(&parsed).expect("from json");
    assert_eq!(back, artifact);
    assert!(text.starts_with("{\"hex_path\""));
    assert!(text.contains("\"compiler\":\"sdcc\""));
}
