//! 固件构建器（SDCC 路径）行为测试：假编译器 + 真文件系统。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use pieblock_core::ProjectKind;
use pieblock_toolchain::BuildArtifactRepository;
use pieblock_toolchain::builder::{
    FirmwareBuilder, ProcessOutput, ProcessRunner, SystemProcessRunner,
};
use pieblock_toolchain::models::{BuildEvent, BuildRequest, CompilerKind};

fn unique_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!("builder-test-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn record(record_type: u8, address: u16, data: &[u8]) -> String {
    let mut values = vec![
        data.len() as u8,
        (address >> 8) as u8,
        address as u8,
        record_type,
    ];
    values.extend_from_slice(data);
    let sum: u32 = values.iter().map(|value| u32::from(*value)).sum();
    let checksum = ((0x100 - (sum & 0xff)) & 0xff) as u8;
    let mut text = String::from(":");
    for value in values {
        text.push_str(&format!("{value:02X}"));
    }
    text.push_str(&format!("{checksum:02X}"));
    text
}

fn valid_hex() -> String {
    [
        record(4, 0x0000, &[0x00, 0xfe]),
        record(0, 0x0000, &[1, 2, 3, 4]),
        record(4, 0x0000, &[0x00, 0xff]),
        record(0, 0x0000, &[0x02, 0x00, 0x00, 0x10, 0x20]),
        record(1, 0x0000, &[]),
    ]
    .join("\n")
}
/// 组装一个最小 SDCC 资源树。
fn prepare_assets(root: &Path) {
    let toolchain = root.join("sdcc-toolchain");
    std::fs::create_dir_all(toolchain.join("bin")).expect("toolchain");
    std::fs::create_dir_all(toolchain.join("include").join("mcs51")).expect("include");
    std::fs::create_dir_all(toolchain.join("lib").join("mcs251-large-stack-auto")).expect("lib");
    std::fs::write(toolchain.join("bin").join("sdcc.exe"), b"fake-sdcc").expect("sdcc");
    let mut files = serde_json::Map::new();
    files.insert(
        "bin/sdcc.exe".to_owned(),
        serde_json::Value::String(pieblock_core::sha256_hex(b"fake-sdcc")),
    );
    let mut bundle = serde_json::Map::new();
    bundle.insert("files".to_owned(), serde_json::Value::Object(files));
    std::fs::write(
        toolchain.join("bundle_manifest.json"),
        serde_json::to_string(&serde_json::Value::Object(bundle)).expect("bundle"),
    )
    .expect("bundle manifest");

    let firmware = root.join("stc32g_sdcc");
    std::fs::create_dir_all(firmware.join("common")).expect("common");
    std::fs::create_dir_all(
        firmware
            .join("projects")
            .join("ROBOMASTER_INFANTRY")
            .join("src"),
    )
    .expect("project src");
    std::fs::create_dir_all(
        firmware
            .join("projects")
            .join("ROBOMASTER_INFANTRY")
            .join("inc"),
    )
    .expect("project inc");
    std::fs::write(
        firmware.join("common").join("board.c"),
        b"void board_init(void) {}\n",
    )
    .expect("board");
    std::fs::write(
        firmware
            .join("projects")
            .join("ROBOMASTER_INFANTRY")
            .join("src")
            .join("isr.c"),
        b"static void timer_isr(void) __interrupt (1) {}\n",
    )
    .expect("isr");
    let manifest = serde_json::json!({
        "source_groups": {"common": ["common/board.c"], "runtime": ["common/board.c"]},
        "projects": {"ROBOMASTER_INFANTRY": {"library_groups": ["runtime"]}},
        "include_dirs": ["common"],
        "compile_flags": ["--model-large"],
        "link_flags": ["--model-large"],
        "runtime_libraries": ["libc251.lib"]
    });
    std::fs::write(
        firmware.join("build_manifest.json"),
        serde_json::to_string(&manifest).expect("manifest"),
    )
    .expect("build manifest");
    std::fs::create_dir_all(root.join("stc32g")).expect("keil dir");
}

#[derive(Clone, Default)]
struct FakeExecutor {
    invocations: Arc<Mutex<Vec<Vec<String>>>>,
    corrupt_hex: bool,
}

impl FakeExecutor {}

impl ProcessRunner for FakeExecutor {
    fn run(
        &mut self,
        _executable: &Path,
        arguments: &[String],
        working_directory: Option<&Path>,
        on_line: &mut dyn FnMut(&str),
    ) -> std::io::Result<ProcessOutput> {
        self.invocations
            .lock()
            .expect("lock")
            .push(arguments.to_vec());
        on_line("fake compiler line");
        let output_index = arguments
            .iter()
            .position(|argument| argument == "-o")
            .map(|index| index + 1);
        let Some(output) = output_index.and_then(|index| arguments.get(index)) else {
            return Ok(ProcessOutput {
                exit_code: 1,
                output: String::new(),
            });
        };
        if output.ends_with(".hex") {
            let hex = if self.corrupt_hex {
                ":00000001FF\n".to_owned()
            } else {
                valid_hex()
            };
            std::fs::write(output, hex).expect("hex");
            std::fs::write(
                Path::new(output).with_extension("map"),
                "HOME            00FF0000 00000003 =\n\
                 CSEG            00FE0000 00000004 =\n\
                 __sdcc_mcs251_reset_trampoline\n\
                 __sdcc_gsinit_startup\n\
                 _Default_Isr\n",
            )
            .expect("map");
            let directory = working_directory.unwrap_or_else(|| Path::new("."));
            std::fs::write(directory.join("main_0.rst"), "listing from fake").expect("rst");
        } else {
            std::fs::write(output, b"object").expect("object");
            std::fs::write(Path::new(output).with_extension("lst"), b"listing").expect("lst");
        }
        Ok(ProcessOutput {
            exit_code: 0,
            output: "warning: fake visible warning\n".to_owned(),
        })
    }

    fn cancel(&mut self) {}
}

#[test]
fn builds_sdcc_with_fake_compiler_and_reuses_object_cache() {
    let root = unique_dir("sdcc");
    prepare_assets(&root.join("assets"));
    let fake = FakeExecutor::default();
    let calls = fake.invocations.clone();
    let second_fake = fake.clone();
    let mut builder = FirmwareBuilder::new(
        root.join("runtime"),
        root.join("work"),
        BuildArtifactRepository::new(root.join("artifacts")),
        Box::new(fake),
    )
    .with_assets_root(root.join("assets"));
    let fingerprint = builder
        .resolve_compiler_fingerprint(CompilerKind::Sdcc, None)
        .expect("fingerprint");
    assert_eq!(fingerprint.len(), 64);
    let request = BuildRequest {
        project_kind: ProjectKind::Infantry,
        source_code: "int main(void) { return 0; }\n".to_owned(),
        compiler: CompilerKind::Sdcc,
        compiler_fingerprint: fingerprint.clone(),
        keil_root: None,
    };
    let mut events: Vec<BuildEvent> = Vec::new();
    let result = builder.build(&request, &mut |event| events.push(event), &|_| {});
    assert!(result.success, "log: {}", result.log);
    assert!(result.artifact.is_some());
    let artifact = result.artifact.expect("artifact");
    assert_eq!(artifact.compiler, CompilerKind::Sdcc);
    assert!(Path::new(&artifact.hex_path).exists());
    assert_eq!(
        artifact.source_sha256,
        FirmwareBuilder::fingerprint(&request).source_hash
    );
    assert_eq!(result.listing.as_deref(), Some("listing from fake"));
    assert!(events.iter().any(|event| event.message.contains("链接")));
    assert!(
        events
            .iter()
            .any(|event| event.message.contains("HEX 布局有效"))
    );
    let first_calls = calls.lock().expect("lock").len();
    assert!(first_calls >= 4, "calls: {first_calls}");

    // 第二次构建：产物仓库未命中（换一个仓库根），验证对象缓存复用。
    let before = calls.lock().expect("lock").len();
    let mut builder = FirmwareBuilder::new(
        root.join("runtime"),
        root.join("work"),
        BuildArtifactRepository::new(root.join("artifacts2")),
        Box::new(second_fake),
    )
    .with_assets_root(root.join("assets"));
    let result = builder.build(&request, &mut |_| {}, &|_| {});
    assert!(result.success, "log: {}", result.log);
    let after = calls.lock().expect("lock").len();
    assert_eq!(
        after - before,
        2,
        "只应重新编译 main 并链接一次：{}",
        after - before
    );
}

#[test]
fn rejects_invalid_hex_after_link() {
    let root = unique_dir("invalid");
    prepare_assets(&root.join("assets"));
    let fake = FakeExecutor {
        corrupt_hex: true,
        ..FakeExecutor::default()
    };
    let mut builder = FirmwareBuilder::new(
        root.join("runtime"),
        root.join("work"),
        BuildArtifactRepository::new(root.join("artifacts")),
        Box::new(fake),
    )
    .with_assets_root(root.join("assets"));
    let fingerprint = builder
        .resolve_compiler_fingerprint(CompilerKind::Sdcc, None)
        .expect("fingerprint");
    let request = BuildRequest {
        project_kind: ProjectKind::Infantry,
        source_code: "int main(void) { return 0; }\n".to_owned(),
        compiler: CompilerKind::Sdcc,
        compiler_fingerprint: fingerprint,
        keil_root: None,
    };
    let result = builder.build(&request, &mut |_| {}, &|_| {});
    assert!(!result.success);
    assert!(result.artifact.is_none());
    assert!(result.log.contains("HEX"), "log: {}", result.log);
}

#[test]
fn system_runner_reports_missing_executable() {
    let mut runner = SystemProcessRunner::new();
    let error = runner
        .run(
            Path::new("definitely-missing-pieblock-tool"),
            &[],
            None,
            &mut |_| {},
        )
        .expect_err("missing executable");
    assert!(error.kind() == std::io::ErrorKind::NotFound || error.raw_os_error().is_some());
}
