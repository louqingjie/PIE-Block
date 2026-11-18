//! 固件构建器：SDCC 编译/链接、增量对象缓存、HEX/MAP 校验、产物入库。
//!
//! 与 `builder.dart` 的 SDCC 路径对齐；Keil 路径与 Android 编译器后端后续移植。
//! 进程执行通过 [`ProcessRunner`] 注入，测试可用脚本化假编译器。

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use pieblock_core::ProjectKind;

use crate::artifact_repository::BuildArtifactRepository;
use crate::file_ops::copy_directory;
use crate::hex::IntelHexValidator;
use crate::models::{
    BuildArtifact, BuildEvent, BuildEventLevel, BuildFingerprint, BuildRequest, BuildResult,
    BuildStage, CompilerKind,
};
use crate::sdcc_object_cache::SdccObjectCache;
use crate::sdcc_runtime_deployer::{SdccRuntimeDeployer, SdccRuntimeDeployment};

/// 构建清单 schema 版本（与 Flutter 版一致）。
pub const BUILD_SCHEMA_VERSION: &str = "flutter_build_v5";
const TARGET_MCU: &str = "STC32G12K128";

/// 工程类型对应的固件工程名。
#[must_use]
pub fn firmware_project_for(kind: ProjectKind, compiler: CompilerKind) -> &'static str {
    match compiler {
        CompilerKind::Sdcc => match kind {
            ProjectKind::Infantry => "ROBOMASTER_INFANTRY",
            ProjectKind::Engineer => "ROBOMASTER_ENGINEER",
            ProjectKind::Debug => "ROBOMASTER_INFANTRY",
            ProjectKind::Music => "BUZZER_MUSIC_GENERATED",
        },
        CompilerKind::Keil => match kind {
            ProjectKind::Engineer => "ROBOMASTER_ENGINEER",
            _ => "ROBOMASTER_INFANTRY",
        },
    }
}

/// 一次工具进程执行结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessOutput {
    pub exit_code: i32,
    pub output: String,
}

/// 可注入的进程执行器。
pub trait ProcessRunner {
    fn run(
        &mut self,
        executable: &Path,
        arguments: &[String],
        working_directory: Option<&Path>,
        on_line: &mut dyn FnMut(&str),
    ) -> std::io::Result<ProcessOutput>;

    fn cancel(&mut self);
}

/// 真实系统进程执行器（合并 stdout/stderr，逐行回调）。
pub struct SystemProcessRunner {
    cancelled: Arc<AtomicBool>,
}

impl Default for SystemProcessRunner {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemProcessRunner {
    #[must_use]
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    /// 外部取消句柄（设置标志并终止子进程）。
    #[must_use]
    pub fn cancel_handle(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.cancelled)
    }
}

impl ProcessRunner for SystemProcessRunner {
    fn run(
        &mut self,
        executable: &Path,
        arguments: &[String],
        working_directory: Option<&Path>,
        on_line: &mut dyn FnMut(&str),
    ) -> std::io::Result<ProcessOutput> {
        self.cancelled.store(false, Ordering::SeqCst);
        let mut command = std::process::Command::new(executable);
        command
            .args(arguments)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        if let Some(directory) = working_directory {
            command.current_dir(directory);
        }
        let mut child = command.spawn()?;
        let (sender, receiver) = mpsc::channel::<String>();
        let mut handles = Vec::new();
        if let Some(stdout) = child.stdout.take() {
            let sender = sender.clone();
            handles.push(std::thread::spawn(move || {
                for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                    let _ = sender.send(line);
                }
            }));
        }
        if let Some(stderr) = child.stderr.take() {
            let sender = sender.clone();
            handles.push(std::thread::spawn(move || {
                for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                    let _ = sender.send(line);
                }
            }));
        }
        drop(sender);
        let mut output = String::new();
        loop {
            while let Ok(line) = receiver.try_recv() {
                output.push_str(&line);
                output.push('\n');
                on_line(&line);
            }
            if self.cancelled.load(Ordering::SeqCst) {
                let _ = child.kill();
                let _ = child.wait();
                for handle in handles {
                    let _ = handle.join();
                }
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "构建已取消",
                ));
            }
            match child.try_wait() {
                Ok(Some(status)) => {
                    while let Ok(line) = receiver.try_recv() {
                        output.push_str(&line);
                        output.push('\n');
                        on_line(&line);
                    }
                    for handle in handles {
                        let _ = handle.join();
                    }
                    return Ok(ProcessOutput {
                        exit_code: status.code().unwrap_or(-1),
                        output,
                    });
                }
                Ok(None) => std::thread::sleep(Duration::from_millis(10)),
                Err(error) => return Err(error),
            }
        }
    }

    fn cancel(&mut self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }
}

/// 固件构建器。
pub struct FirmwareBuilder {
    pub runtime_root: PathBuf,
    pub work_root: PathBuf,
    pub artifacts: BuildArtifactRepository,
    pub assets_root: Option<PathBuf>,
    runner: Box<dyn ProcessRunner>,
    cancelled: Arc<AtomicBool>,
}

impl FirmwareBuilder {
    #[must_use]
    pub fn new(
        runtime_root: impl Into<PathBuf>,
        work_root: impl Into<PathBuf>,
        artifacts: BuildArtifactRepository,
        runner: Box<dyn ProcessRunner>,
    ) -> Self {
        Self {
            runtime_root: runtime_root.into(),
            work_root: work_root.into(),
            artifacts,
            assets_root: None,
            runner,
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    #[must_use]
    pub fn with_assets_root(mut self, root: impl Into<PathBuf>) -> Self {
        self.assets_root = Some(root.into());
        self
    }

    /// 请求取消当前构建。
    pub fn cancel(&mut self) {
        self.cancelled.store(true, Ordering::SeqCst);
        self.runner.cancel();
    }

    /// 构建指纹（schema/MCU/工程/编译器/编译器指纹/源码哈希）。
    #[must_use]
    pub fn fingerprint(request: &BuildRequest) -> BuildFingerprint {
        let source_hash = pieblock_core::sha256_hex(request.source_code.as_bytes());
        let value = pieblock_core::sha256_hex(
            [
                BUILD_SCHEMA_VERSION,
                TARGET_MCU,
                request.project_kind.as_str(),
                request.compiler.as_str(),
                &request.compiler_fingerprint,
                &source_hash,
            ]
            .join("|")
            .as_bytes(),
        );
        BuildFingerprint { value, source_hash }
    }

    /// 解析编译器指纹；SDCC 使用内置资源清单与固件源码内容哈希。
    pub fn resolve_compiler_fingerprint(
        &self,
        compiler: CompilerKind,
        keil_root: Option<&str>,
    ) -> Result<String, String> {
        match compiler {
            CompilerKind::Keil => {
                let installation = resolve_keil(keil_root)?;
                keil_fingerprint(&installation)
            }
            CompilerKind::Sdcc => {
                let assets = self.locate_assets()?;
                let bundle =
                    std::fs::read_to_string(assets.sdcc_toolchain.join("bundle_manifest.json"))
                        .map_err(|error| format!("读取 SDCC 工具链清单失败：{error}"))?;
                let firmware =
                    std::fs::read_to_string(assets.sdcc_firmware.join("build_manifest.json"))
                        .map_err(|error| format!("读取 SDCC 固件清单失败：{error}"))?;
                let sources = firmware_content_hash(&assets.sdcc_firmware);
                Ok(pieblock_core::sha256_hex(
                    format!("{bundle}\n{firmware}\n{sources}").as_bytes(),
                ))
            }
        }
    }

    /// 执行一次构建（阻塞；事件通过 `emit` 回调）。
    pub fn build(
        &mut self,
        request: &BuildRequest,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
    ) -> BuildResult {
        self.cancelled.store(false, Ordering::SeqCst);
        let fingerprint = Self::fingerprint(request);
        let mut logs: Vec<String> = Vec::new();
        macro_rules! event {
            ($stage:expr, $level:expr, $msg:expr $(,)?) => {{
                let message: String = $msg;
                logs.push(message.clone());
                emit(BuildEvent {
                    stage: $stage,
                    level: $level,
                    message,
                    current: None,
                    total: None,
                });
            }};
        }
        if let Some(fresh) = self.artifacts.find_fresh(&fingerprint) {
            event!(
                BuildStage::Done,
                BuildEventLevel::Info,
                "复用已有构建产物".to_owned(),
            );
            return BuildResult {
                success: true,
                artifact: Some(fresh),
                log: logs.join("\n"),
                exit_code: Some(0),
                canceled: false,
                license_failure: false,
                listing: None,
            };
        }
        if request.compiler == CompilerKind::Keil {
            return self.build_keil_flow(request, &fingerprint, emit, sleep, &mut logs);
        }
        let work = self.work_root.join(format!(
            "{}.{}",
            &fingerprint.value[..16.min(fingerprint.value.len())],
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |duration| duration.as_micros())
        ));
        if let Err(error) = std::fs::create_dir_all(&work) {
            event!(
                BuildStage::Done,
                BuildEventLevel::Error,
                format!("编译失败：{error}"),
            );
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: None,
                canceled: false,
                license_failure: false,
                listing: None,
            };
        }
        let raw = self.build_sdcc(request, &fingerprint, &work, emit, sleep, &mut logs);
        let hex_path = raw.hex_path.clone();
        if self.cancelled.load(Ordering::SeqCst) {
            let _ = std::fs::remove_dir_all(&work);
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: None,
                canceled: true,
                license_failure: false,
                listing: None,
            };
        }
        if !raw.success {
            let _ = std::fs::remove_dir_all(&work);
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: raw.license_failure,
                listing: None,
            };
        }
        let Some(hex_path) = hex_path else {
            let _ = std::fs::remove_dir_all(&work);
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: false,
                listing: None,
            };
        };
        let validation = IntelHexValidator::validate_application(&hex_path);
        let level = if validation.ok {
            BuildEventLevel::Info
        } else {
            BuildEventLevel::Error
        };
        let message = validation.message.clone();
        logs.push(message.clone());
        emit(BuildEvent {
            stage: BuildStage::Validating,
            level,
            message,
            current: None,
            total: None,
        });
        if !validation.ok {
            let _ = std::fs::remove_dir_all(&work);
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: raw.license_failure,
                listing: None,
            };
        }
        let byte_count = i64::try_from(
            validation
                .image
                .as_ref()
                .map_or(0, |image| image.bytes.len()),
        )
        .unwrap_or(0);
        let artifact = BuildArtifact {
            hex_path: hex_path.display().to_string(),
            hex_sha256: String::new(),
            fingerprint: fingerprint.value.clone(),
            source_sha256: fingerprint.source_hash.clone(),
            compiler: request.compiler,
            compiler_fingerprint: request.compiler_fingerprint.clone(),
            template_version: BUILD_SCHEMA_VERSION.to_owned(),
            built_at: pieblock_core::now_iso8601(),
            byte_count,
            warning_count: raw.warning_count,
            last_flashed_at: None,
        };
        let stored = match self.artifacts.store(&hex_path, &artifact, &logs.join("\n")) {
            Ok(stored) => stored,
            Err(error) => {
                logs.push(format!("保存构建产物失败：{error}"));
                let _ = std::fs::remove_dir_all(&work);
                return BuildResult {
                    success: false,
                    artifact: None,
                    log: logs.join("\n"),
                    exit_code: None,
                    canceled: false,
                    license_failure: false,
                    listing: None,
                };
            }
        };
        let _ = std::fs::remove_dir_all(&work);
        let done = format!("编译完成：{} 字节", stored.byte_count);
        logs.push(done.clone());
        emit(BuildEvent {
            stage: BuildStage::Done,
            level: BuildEventLevel::Info,
            message: done,
            current: None,
            total: None,
        });
        BuildResult {
            success: true,
            artifact: Some(stored),
            log: logs.join("\n"),
            exit_code: Some(0),
            canceled: false,
            license_failure: false,
            listing: raw.listing,
        }
    }

    fn build_keil_flow(
        &mut self,
        request: &BuildRequest,
        fingerprint: &BuildFingerprint,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
        logs: &mut Vec<String>,
    ) -> BuildResult {
        let work = self.work_root.join(format!(
            "{}.{}",
            &fingerprint.value[..16.min(fingerprint.value.len())],
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |duration| duration.as_micros())
        ));
        if let Err(error) = std::fs::create_dir_all(&work) {
            logs.push(format!("编译失败：{error}"));
            emit(BuildEvent {
                stage: BuildStage::Done,
                level: BuildEventLevel::Error,
                message: format!("编译失败：{error}"),
                current: None,
                total: None,
            });
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: None,
                canceled: false,
                license_failure: false,
                listing: None,
            };
        }
        let raw = self.build_keil(request, &work, emit, sleep, logs);
        let _ = std::fs::remove_dir_all(&work);
        if self.cancelled.load(Ordering::SeqCst) {
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: true,
                license_failure: false,
                listing: None,
            };
        }
        if !raw.success {
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: raw.license_failure,
                listing: None,
            };
        }
        let Some(hex_path) = raw.hex_path else {
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: raw.license_failure,
                listing: None,
            };
        };
        let validation = IntelHexValidator::validate_application(&hex_path);
        let level = if validation.ok {
            BuildEventLevel::Info
        } else {
            BuildEventLevel::Error
        };
        let message = validation.message.clone();
        logs.push(message.clone());
        emit(BuildEvent {
            stage: BuildStage::Validating,
            level,
            message,
            current: None,
            total: None,
        });
        if !validation.ok {
            return BuildResult {
                success: false,
                artifact: None,
                log: logs.join("\n"),
                exit_code: raw.exit_code.map(i64::from),
                canceled: false,
                license_failure: raw.license_failure,
                listing: raw.listing,
            };
        }
        let byte_count = i64::try_from(
            validation
                .image
                .as_ref()
                .map_or(0, |image| image.bytes.len()),
        )
        .unwrap_or(0);
        let artifact = BuildArtifact {
            hex_path: hex_path.display().to_string(),
            hex_sha256: String::new(),
            fingerprint: fingerprint.value.clone(),
            source_sha256: fingerprint.source_hash.clone(),
            compiler: request.compiler,
            compiler_fingerprint: request.compiler_fingerprint.clone(),
            template_version: BUILD_SCHEMA_VERSION.to_owned(),
            built_at: pieblock_core::now_iso8601(),
            byte_count,
            warning_count: raw.warning_count,
            last_flashed_at: None,
        };
        let stored = match self.artifacts.store(&hex_path, &artifact, &logs.join("\n")) {
            Ok(stored) => stored,
            Err(error) => {
                logs.push(format!("保存构建产物失败：{error}"));
                return BuildResult {
                    success: false,
                    artifact: None,
                    log: logs.join("\n"),
                    exit_code: None,
                    canceled: false,
                    license_failure: false,
                    listing: None,
                };
            }
        };
        let done = format!("编译完成：{} 字节", stored.byte_count);
        logs.push(done.clone());
        emit(BuildEvent {
            stage: BuildStage::Done,
            level: BuildEventLevel::Info,
            message: done,
            current: None,
            total: None,
        });
        BuildResult {
            success: true,
            artifact: Some(stored),
            log: logs.join("\n"),
            exit_code: Some(0),
            canceled: false,
            license_failure: false,
            listing: raw.listing,
        }
    }

    fn build_keil(
        &mut self,
        request: &BuildRequest,
        work: &Path,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
        logs: &mut Vec<String>,
    ) -> RawBuildResult {
        macro_rules! emit_stage {
            ($stage:expr, $level:expr, $msg:expr $(,)?) => {{
                let message: String = $msg;
                logs.push(message.clone());
                emit(BuildEvent {
                    stage: $stage,
                    level: $level,
                    message,
                    current: None,
                    total: None,
                });
            }};
        }
        let keil_root = std::env::var("PIEBLOCK_KEIL").ok();
        let installation = match resolve_keil(request.keil_root.as_deref().or(keil_root.as_deref()))
        {
            Ok(installation) => installation,
            Err(error) => {
                emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error,);
                return RawBuildResult::failure();
            }
        };
        let assets = match self.locate_assets() {
            Ok(assets) => assets,
            Err(error) => {
                emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error);
                return RawBuildResult::failure();
            }
        };
        let project = firmware_project_for(request.project_kind, CompilerKind::Keil);
        let workspace = work.join("stc32g");
        if let Err(error) = crate::file_ops::copy_directory(
            &assets.keil.join("Libraries"),
            &workspace.join("Libraries"),
            sleep,
        ) {
            emit_stage!(
                BuildStage::Preparing,
                BuildEventLevel::Error,
                format!("复制 Keil Libraries 失败：{error}"),
            );
            return RawBuildResult::failure();
        }
        let project_dir = workspace.join("Projects").join(project);
        if let Err(error) = crate::file_ops::copy_directory(
            &assets.keil.join("Projects").join(project),
            &project_dir,
            sleep,
        ) {
            emit_stage!(
                BuildStage::Preparing,
                BuildEventLevel::Error,
                format!("复制 Keil 工程失败：{error}"),
            );
            return RawBuildResult::failure();
        }
        let mdk = project_dir.join("MDK");
        for generated in [mdk.join("Objects"), mdk.join("Listings")] {
            let _ = std::fs::remove_dir_all(&generated);
        }
        let main_c = project_dir.join("USER").join("src").join("main.c");
        if let Some(parent) = main_c.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Err(error) = std::fs::write(&main_c, &request.source_code) {
            emit_stage!(
                BuildStage::Preparing,
                BuildEventLevel::Error,
                format!("写入 main.c 失败：{error}"),
            );
            return RawBuildResult::failure();
        }
        let project_file = mdk.join("Project_Template.uvproj");
        let log_path = mdk.join("pie_block_build.log");
        let _ = std::fs::remove_file(&log_path);
        emit_stage!(
            BuildStage::Compiling,
            BuildEventLevel::Info,
            "正在调用 Keil C251 全量重建…".to_owned(),
        );
        let arguments = vec![
            "-r".to_owned(),
            project_file.display().to_string(),
            "-o".to_owned(),
            log_path.display().to_string(),
        ];
        let mut streamed: Vec<String> = Vec::new();
        let run = self
            .runner
            .run(&installation.uv4, &arguments, Some(&mdk), &mut |line| {
                streamed.push(line.to_owned())
            });
        let log = std::fs::read_to_string(&log_path).unwrap_or_else(|_| streamed.join("\n"));
        let mut warning_count = 0_i64;
        for line in log.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let lower = line.to_lowercase();
            let level = if lower.contains("error") {
                BuildEventLevel::Error
            } else if lower.contains("warning") {
                warning_count += 1;
                BuildEventLevel::Warning
            } else {
                BuildEventLevel::Info
            };
            emit_stage!(BuildStage::Compiling, level, line.to_owned());
        }
        let hex_path = mdk.join("Objects").join("Project_Template.hex");
        let success = log.contains("0 Error(s)") && hex_path.is_file();
        RawBuildResult {
            success,
            exit_code: run.as_ref().map(|output| output.exit_code).ok(),
            hex_path: Some(hex_path),
            warning_count,
            license_failure: is_keil_license_failure(&log),
            listing: None,
        }
    }

    fn build_sdcc(
        &mut self,
        request: &BuildRequest,
        _fingerprint: &BuildFingerprint,
        work: &Path,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
        logs: &mut Vec<String>,
    ) -> RawBuildResult {
        macro_rules! emit_stage {
            ($stage:expr, $level:expr, $msg:expr $(,)?) => {{
                let message: String = $msg;
                logs.push(message.clone());
                emit(BuildEvent {
                    stage: $stage,
                    level: $level,
                    message,
                    current: None,
                    total: None,
                });
            }};
        }
        let assets = match self.locate_assets() {
            Ok(assets) => assets,
            Err(error) => {
                emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error);
                return RawBuildResult::failure();
            }
        };
        let deployer = SdccRuntimeDeployer::new(&self.runtime_root);
        let deployment = match deployer.ensure(
            &assets.sdcc_toolchain,
            &assets.sdcc_firmware,
            &self
                .resolve_compiler_fingerprint(CompilerKind::Sdcc, None)
                .unwrap_or_default(),
            &mut |event| emit(event),
            sleep,
        ) {
            Ok(deployment) => deployment,
            Err(error) => {
                emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error.message);
                if let Some(hint) = error.hint {
                    emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, hint);
                }
                return RawBuildResult::failure();
            }
        };
        let manifest_text =
            match std::fs::read_to_string(deployment.firmware.join("build_manifest.json")) {
                Ok(text) => text,
                Err(error) => {
                    emit_stage!(
                        BuildStage::Preparing,
                        BuildEventLevel::Error,
                        format!("读取 SDCC 构建清单失败：{error}"),
                    );
                    return RawBuildResult::failure();
                }
            };
        let manifest: serde_json::Value = match serde_json::from_str(&manifest_text) {
            Ok(value) => value,
            Err(error) => {
                emit_stage!(
                    BuildStage::Preparing,
                    BuildEventLevel::Error,
                    format!("SDCC 构建清单非法：{error}"),
                );
                return RawBuildResult::failure();
            }
        };
        let project = firmware_project_for(request.project_kind, CompilerKind::Sdcc).to_owned();
        let (sources, libraries) = match sources_for(&manifest, &project) {
            Ok(value) => value,
            Err(error) => {
                emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error);
                return RawBuildResult::failure();
            }
        };
        let output = work.join("output");
        let _ = std::fs::create_dir_all(&output);
        let main_path = work.join("main.c");
        if let Err(error) = std::fs::write(&main_path, &request.source_code) {
            emit_stage!(
                BuildStage::Preparing,
                BuildEventLevel::Error,
                format!("写入 main.c 失败：{error}"),
            );
            return RawBuildResult::failure();
        }
        let interrupt_header = output.join("generated_interrupt_declarations.h");
        if let Err(error) = write_interrupt_header(
            &deployment.firmware,
            &sources,
            &main_path,
            &interrupt_header,
        ) {
            emit_stage!(BuildStage::Preparing, BuildEventLevel::Error, error);
            return RawBuildResult::failure();
        }
        let include_args = include_args(&deployment, &manifest, &project);
        let mut direct_objects: Vec<String> = Vec::new();
        let mut library_objects: Vec<String> = Vec::new();
        let library_sources: Vec<String> = libraries.clone();
        let object_cache =
            SdccObjectCache::new(&self.runtime_root, &request.compiler_fingerprint, &project);
        object_cache.prune_other_fingerprints();
        let mut warning_count = 0_i64;
        let mut reused = 0_usize;
        let mut compiled = 0_usize;
        let mut cache_warning_emitted = false;
        let sdcc =
            deployment
                .toolchain
                .join("bin")
                .join(if cfg!(windows) { "sdcc.exe" } else { "sdcc" });
        let total = sources.len();
        for (index, relative) in sources.iter().enumerate() {
            let is_main = relative.ends_with("/src/main.c");
            let source = if is_main {
                main_path.clone()
            } else {
                deployment
                    .firmware
                    .join(relative.replace('/', std::path::MAIN_SEPARATOR_STR))
            };
            let object = output.join(format!(
                "{}_{}.rel",
                source
                    .file_stem()
                    .and_then(|name| name.to_str())
                    .unwrap_or("object"),
                index
            ));
            if !is_main {
                if let Some(cached) = object_cache.lookup(relative, &object) {
                    reused += 1;
                    warning_count += cached.warning_count;
                    emit_stage!(
                        BuildStage::Compiling,
                        BuildEventLevel::Info,
                        format!("[{}/{}] 复用缓存 {relative}", index + 1, total),
                    );
                    let list = if library_sources.contains(relative) {
                        &mut library_objects
                    } else {
                        &mut direct_objects
                    };
                    list.push(object.display().to_string());
                    continue;
                }
            }
            emit_stage!(
                BuildStage::Compiling,
                BuildEventLevel::Info,
                format!("[{}/{}] 编译 {relative}", index + 1, total),
            );
            let mut arguments: Vec<String> = manifest
                .get("compile_flags")
                .and_then(serde_json::Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|value| value.as_str().map(str::to_owned))
                .collect();
            arguments.extend(include_args.iter().cloned());
            if is_main {
                arguments.push("--include".to_owned());
                arguments.push(interrupt_header.display().to_string());
            }
            arguments.push("-o".to_owned());
            arguments.push(object.display().to_string());
            arguments.push(source.display().to_string());
            let mut line_emit = |line: &str| {
                if is_internal_noise(line) {
                    return;
                }
                let level = if line.to_lowercase().contains("error") {
                    BuildEventLevel::Error
                } else if line.to_lowercase().contains("warning") {
                    BuildEventLevel::Warning
                } else {
                    BuildEventLevel::Info
                };
                emit_stage!(BuildStage::Compiling, level, line.to_owned());
            };
            let run = match self.runner.run(&sdcc, &arguments, None, &mut line_emit) {
                Ok(run) => run,
                Err(error) => {
                    emit_stage!(
                        BuildStage::Compiling,
                        BuildEventLevel::Error,
                        format!("启动 SDCC 失败：{error}"),
                    );
                    return RawBuildResult::failure();
                }
            };
            let compile_warnings = visible_warning_count(&run.output);
            warning_count += compile_warnings;
            compiled += 1;
            if run.exit_code != 0 || self.cancelled.load(Ordering::SeqCst) {
                return RawBuildResult {
                    exit_code: Some(run.exit_code),
                    warning_count,
                    ..RawBuildResult::failure()
                };
            }
            if !is_main {
                if let Err(error) = object_cache.store(relative, &object, compile_warnings) {
                    if !cache_warning_emitted {
                        emit_stage!(
                            BuildStage::Compiling,
                            BuildEventLevel::Warning,
                            format!("目标文件缓存写入失败，本次构建继续：{error}"),
                        );
                        cache_warning_emitted = true;
                    }
                }
            }
            let list = if library_sources.contains(relative) {
                &mut library_objects
            } else {
                &mut direct_objects
            };
            list.push(object.display().to_string());
        }
        if reused > 0 {
            emit_stage!(
                BuildStage::Compiling,
                BuildEventLevel::Info,
                format!("增量编译：复用 {reused} 个模块，重新编译 {compiled} 个模块"),
            );
        }
        let shared_library = output.join("stc32g_shared.lib");
        let shared_content = format!(
            "{}\n",
            library_objects
                .iter()
                .filter_map(|object| Path::new(object).file_stem().and_then(|name| name.to_str()))
                .collect::<Vec<_>>()
                .join("\n")
        );
        if let Err(error) = std::fs::write(&shared_library, shared_content) {
            emit_stage!(
                BuildStage::Linking,
                BuildEventLevel::Error,
                format!("写入共享库清单失败：{error}"),
            );
            return RawBuildResult::failure();
        }
        let hex_path = output.join(format!("{project}.hex"));
        emit_stage!(
            BuildStage::Linking,
            BuildEventLevel::Info,
            format!("正在链接 {project}.hex…"),
        );
        let mut link_args: Vec<String> = manifest
            .get("link_flags")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|value| value.as_str().map(str::to_owned))
            .collect();
        link_args.push(format!("-L{}", output.display()));
        link_args.push(format!(
            "-L{}",
            deployment
                .toolchain
                .join("lib")
                .join("mcs251-large-stack-auto")
                .display()
        ));
        link_args.extend(include_args);
        link_args.extend(direct_objects.iter().cloned());
        link_args.push(
            shared_library
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("stc32g_shared.lib")
                .to_owned(),
        );
        for library in manifest
            .get("runtime_libraries")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|value| value.as_str())
        {
            link_args.push(library.to_owned());
        }
        link_args.push("-o".to_owned());
        link_args.push(hex_path.display().to_string());
        let mut link_line_emit = |line: &str| {
            if is_internal_noise(line) {
                return;
            }
            let level = if line.to_lowercase().contains("error") {
                BuildEventLevel::Error
            } else if line.to_lowercase().contains("warning") {
                BuildEventLevel::Warning
            } else {
                BuildEventLevel::Info
            };
            emit_stage!(BuildStage::Linking, level, line.to_owned());
        };
        let link = match self
            .runner
            .run(&sdcc, &link_args, Some(&output), &mut link_line_emit)
        {
            Ok(link) => link,
            Err(error) => {
                emit_stage!(
                    BuildStage::Linking,
                    BuildEventLevel::Error,
                    format!("启动链接器失败：{error}"),
                );
                return RawBuildResult::failure();
            }
        };
        warning_count += visible_warning_count(&link.output);
        if link.exit_code == 0 && !self.cancelled.load(Ordering::SeqCst) {
            let layout =
                IntelHexValidator::validate_sdcc_layout(&hex_path, &hex_path.with_extension("map"));
            let level = if layout.ok {
                BuildEventLevel::Info
            } else {
                BuildEventLevel::Error
            };
            emit_stage!(BuildStage::Validating, level, layout.message);
            if !layout.ok {
                return RawBuildResult {
                    exit_code: Some(link.exit_code),
                    warning_count,
                    ..RawBuildResult::failure()
                };
            }
        }
        let success = link.exit_code == 0 && hex_path.exists();
        let listing = if success { read_listing(&output) } else { None };
        if success && listing.is_none() {
            emit_stage!(
                BuildStage::Validating,
                BuildEventLevel::Warning,
                "SDCC 未产出列表文件（main_*.rst）".to_owned(),
            );
        }
        RawBuildResult {
            success,
            exit_code: Some(link.exit_code),
            hex_path: Some(hex_path),
            warning_count,
            license_failure: false,
            listing,
        }
    }

    fn locate_assets(&self) -> Result<ToolchainAssets, String> {
        let mut candidates: Vec<PathBuf> = Vec::new();
        if let Ok(root) = std::env::var("PIEBLOCK_RUNTIME_ROOT") {
            if !root.is_empty() {
                candidates.push(PathBuf::from(root));
            }
        }
        if let Ok(exe) = std::env::current_exe() {
            if let Some(parent) = exe.parent() {
                candidates.push(parent.join("data").join("pieblock_runtime"));
            }
        }
        if let Some(root) = &self.assets_root {
            candidates.push(root.clone());
        }
        if let Ok(cwd) = std::env::current_dir() {
            let mut cursor = Some(cwd);
            for _ in 0..8 {
                let Some(directory) = cursor else {
                    break;
                };
                candidates.push(directory.clone());
                cursor = directory.parent().map(Path::to_path_buf);
            }
        }
        for root in candidates {
            let direct = root.join("sdcc-toolchain");
            let vendored = root.join("vendor").join("sdcc-toolchain");
            let firmware = root.join("stc32g_sdcc");
            let keil = root.join("stc32g");
            let toolchain = if direct.exists() { direct } else { vendored };
            if toolchain.exists() && firmware.exists() && keil.exists() {
                return Ok(ToolchainAssets {
                    sdcc_toolchain: toolchain,
                    sdcc_firmware: firmware,
                    keil,
                });
            }
        }
        Err("发布包缺少 C251 工具链资源".to_owned())
    }
}

#[derive(Debug, Clone)]
struct ToolchainAssets {
    sdcc_toolchain: PathBuf,
    sdcc_firmware: PathBuf,
    #[allow(dead_code)]
    keil: PathBuf,
}

#[derive(Debug, Clone, Default)]
struct RawBuildResult {
    success: bool,
    exit_code: Option<i32>,
    hex_path: Option<PathBuf>,
    warning_count: i64,
    license_failure: bool,
    listing: Option<String>,
}

impl RawBuildResult {
    fn failure() -> Self {
        Self::default()
    }
}

fn sources_for(
    manifest: &serde_json::Value,
    project: &str,
) -> Result<(Vec<String>, Vec<String>), String> {
    let groups = manifest
        .get("source_groups")
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| "SDCC 构建清单缺少 source_groups".to_owned())?;
    let projects = manifest
        .get("projects")
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| "SDCC 构建清单缺少 projects".to_owned())?;
    let spec = projects
        .get(project)
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| format!("SDCC 构建清单缺少项目：{project}"))?;
    let mut sources: Vec<String> = Vec::new();
    let mut libraries: Vec<String> = Vec::new();
    let mut add = |value: &str| {
        if !sources.iter().any(|item| item == value) {
            sources.push(value.to_owned());
        }
    };
    for value in groups
        .get("common")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "SDCC 构建清单缺少 common 源码组".to_owned())?
    {
        add(value.as_str().unwrap_or(""));
    }
    add(&format!("projects/{project}/src/isr.c"));
    add(&format!("projects/{project}/src/main.c"));
    for group_name in spec
        .get("library_groups")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "SDCC 构建清单缺少 library_groups".to_owned())?
    {
        let group_name = group_name.as_str().unwrap_or("");
        let group = groups
            .get(group_name)
            .and_then(serde_json::Value::as_array)
            .ok_or_else(|| format!("SDCC 构建清单缺少源码组：{group_name}"))?;
        for value in group {
            let relative = value.as_str().unwrap_or("");
            add(relative);
            if !libraries.iter().any(|item| item == relative) {
                libraries.push(relative.to_owned());
            }
        }
    }
    Ok((sources, libraries))
}

fn include_args(
    deployment: &SdccRuntimeDeployment,
    manifest: &serde_json::Value,
    project: &str,
) -> Vec<String> {
    let mut args = vec![
        format!("-I{}", deployment.toolchain.join("include").display()),
        format!(
            "-I{}",
            deployment.toolchain.join("include").join("mcs51").display()
        ),
    ];
    for directory in manifest
        .get("include_dirs")
        .and_then(serde_json::Value::as_array)
        .into_iter()
        .flatten()
    {
        args.push(format!(
            "-I{}",
            deployment
                .firmware
                .join(directory.as_str().unwrap_or(""))
                .display()
        ));
    }
    args.push(format!(
        "-I{}",
        deployment
            .firmware
            .join("projects")
            .join(project)
            .join("inc")
            .display()
    ));
    args
}

fn write_interrupt_header(
    firmware: &Path,
    sources: &[String],
    main_path: &Path,
    destination: &Path,
) -> Result<(), String> {
    let mut declarations: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for relative in sources {
        let source = if relative.ends_with("/src/main.c") {
            main_path.to_path_buf()
        } else {
            firmware.join(relative.replace('/', std::path::MAIN_SEPARATOR_STR))
        };
        let text = std::fs::read_to_string(&source)
            .map_err(|error| format!("读取固件源码失败：{}：{error}", source.display()))?;
        for line in text.lines() {
            if let Some(declaration) = parse_interrupt_declaration(line) {
                declarations.insert(declaration);
            }
        }
    }
    let body = format!(
        "#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n\
         #define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n\
         #include \"STC32Gxx.h\"\n\
         #include <stdlib.h>\n\
         {}\n\
         #endif\n",
        declarations.into_iter().collect::<Vec<_>>().join("\n")
    );
    std::fs::write(destination, body)
        .map_err(|error| format!("写入中断声明头失败：{}：{error}", destination.display()))
}

fn parse_interrupt_declaration(line: &str) -> Option<String> {
    let text = line.trim_start();
    let text = text
        .strip_prefix("static")
        .map_or(text, |rest| rest.trim_start());
    let text = text.strip_prefix("void")?;
    if !text.starts_with(|ch: char| ch.is_whitespace()) {
        return None;
    }
    let rest = text.trim_start();
    let name_end = rest
        .find(|ch: char| !(ch.is_alphanumeric() || ch == '_'))
        .unwrap_or(rest.len());
    let name = &rest[..name_end];
    if name.is_empty() {
        return None;
    }
    let rest = rest[name_end..].trim_start();
    let rest = rest.strip_prefix("(void)")?.trim_start();
    let rest = rest.strip_prefix("__interrupt")?.trim_start();
    let rest = rest.strip_prefix('(')?;
    let end = rest.find(')')?;
    Some(format!(
        "void {name}(void) __interrupt ({});",
        rest[..end].trim()
    ))
}

fn read_listing(directory: &Path) -> Option<String> {
    let mut candidates: Vec<PathBuf> = std::fs::read_dir(directory)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("main_") && name.ends_with(".rst"))
        })
        .collect();
    candidates.sort();
    let first = candidates.first()?;
    let bytes = std::fs::read(first).ok()?;
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

fn is_internal_noise(line: &str) -> bool {
    line.contains("__has_builtin")
        || line.contains("__STDC_HOSTED__")
        || line.contains("<built-in>: note:")
        || line.starts_with("DPTR no-match:")
        || line.contains("warning 110:")
        || line.contains("warning 126:")
}

fn visible_warning_count(output: &str) -> i64 {
    i64::try_from(
        output
            .lines()
            .filter(|line| line.to_lowercase().contains("warning") && !is_internal_noise(line))
            .count(),
    )
    .unwrap_or(0)
}

/// 固件源码树内容哈希（排除 build/ 等生成目录）。
#[must_use]
pub fn firmware_content_hash(root: &Path) -> String {
    let mut files: Vec<(String, PathBuf)> = Vec::new();
    collect_files(root, root, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    let mut bytes: Vec<u8> = Vec::new();
    for (name, path) in files {
        bytes.extend_from_slice(name.as_bytes());
        bytes.push(0);
        bytes.extend_from_slice(&std::fs::read(path).unwrap_or_default());
        bytes.push(0);
    }
    pieblock_core::sha256_hex(&bytes)
}

fn collect_files(root: &Path, current: &Path, out: &mut Vec<(String, PathBuf)>) {
    let Ok(entries) = std::fs::read_dir(current) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("");
            if matches!(
                name,
                "build" | "__pycache__" | ".git" | ".dart_tool" | ".tooling" | "tmp"
            ) {
                continue;
            }
            collect_files(root, &path, out);
        } else if path.is_file() {
            let relative = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            if firmware_hash_excluded(&relative) {
                continue;
            }
            out.push((relative, path));
        }
    }
}

fn firmware_hash_excluded(relative: &str) -> bool {
    relative.split('/').any(|segment| {
        matches!(
            segment,
            "build" | "__pycache__" | ".git" | ".dart_tool" | ".tooling" | "tmp"
        )
    })
}

/// 便捷：复制发布包资源到临时目录（测试/部署复用）。
pub fn copy_assets(source: &Path, destination: &Path) -> std::io::Result<()> {
    copy_directory(source, destination, &|_| {})
}

#[derive(Debug, Clone)]
struct KeilInstallation {
    uv4: PathBuf,
    c251: PathBuf,
}

fn find_first(root: &Path, preferred: &[&str], names: &[&str]) -> Option<PathBuf> {
    for relative in preferred {
        let candidate = root.join(relative);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    let lower: Vec<String> = names.iter().map(|name| name.to_lowercase()).collect();
    fn walk(directory: &Path, lower: &[String], depth: u32) -> Option<PathBuf> {
        if depth > 8 {
            return None;
        }
        let entries = std::fs::read_dir(directory).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_lowercase();
            if path.is_file() && lower.contains(&name) {
                return Some(path);
            }
            if path.is_dir() {
                if let Some(found) = walk(&path, lower, depth + 1) {
                    return Some(found);
                }
            }
        }
        None
    }
    walk(root, &lower, 0)
}

fn validate_keil(root: &str) -> Option<KeilInstallation> {
    let root = PathBuf::from(root.trim());
    if !root.is_dir() {
        return None;
    }
    let root = root.canonicalize().unwrap_or(root);
    let uv4 = find_first(
        &root,
        &["UV4/uVision.com", "UV4/UV4.exe"],
        &["uVision.com", "UV4.exe"],
    )?;
    let c251 = find_first(&root, &["C251/BIN/C251.EXE"], &["C251.EXE"])?;
    Some(KeilInstallation { uv4, c251 })
}

fn resolve_keil(configured: Option<&str>) -> Result<KeilInstallation, String> {
    let mut candidates: Vec<String> = Vec::new();
    if let Ok(value) = std::env::var("PIEBLOCK_KEIL") {
        if !value.trim().is_empty() {
            candidates.push(value.trim().to_owned());
        }
    }
    if let Some(value) = configured {
        if !value.trim().is_empty() {
            candidates.push(value.trim().to_owned());
        }
    }
    candidates.push("C:\\Keil_v5".to_owned());
    candidates.push("C:\\Keil".to_owned());
    for candidate in candidates {
        if let Some(installation) = validate_keil(&candidate) {
            return Ok(installation);
        }
    }
    Err("Keil 目录无效或缺少 C251（可在设置中填写 Keil 安装目录）".to_owned())
}

fn keil_fingerprint(installation: &KeilInstallation) -> Result<String, String> {
    let mut bytes: Vec<u8> = Vec::new();
    for path in [&installation.uv4, &installation.c251] {
        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        bytes.extend_from_slice(name.as_bytes());
        let content =
            std::fs::read(path).map_err(|error| format!("读取 Keil 工具文件失败：{error}"))?;
        bytes.extend_from_slice(&content);
    }
    Ok(pieblock_core::sha256_hex(&bytes))
}

fn is_keil_license_failure(log: &str) -> bool {
    log.contains("RESTRICTED VERSION")
        || log.contains("LICENSE ERROR")
        || log.contains("ERROR L250")
}
