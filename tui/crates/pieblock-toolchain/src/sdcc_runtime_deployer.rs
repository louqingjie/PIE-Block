//! 内置 SDCC 工具链与固件源码的运行时部署（与 `sdcc_runtime_deployer.dart` 对齐）。
//!
//! 顺序：复制到唯一暂存目录 → 校验 `bundle_manifest.json` → 写 `.ready` 指纹 →
//! rename 晋升；目标不可用时清理重装，绝不删除一份已就绪的部署。

use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::file_ops::copy_directory;
use crate::models::{BuildEvent, BuildEventLevel, BuildStage};

const READY_MARKER: &str = ".ready";
const PROMOTE_ATTEMPTS: u32 = 8;
const INITIAL_RETRY_DELAY: Duration = Duration::from_millis(120);

/// 一份已部署且通过校验的内置 SDCC 运行时。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SdccRuntimeDeployment {
    pub toolchain: PathBuf,
    pub firmware: PathBuf,
}

/// 部署失败，`hint` 给用户可操作的处理建议。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SdccDeploymentException {
    pub message: String,
    pub hint: Option<String>,
}

impl std::fmt::Display for SdccDeploymentException {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.hint {
            Some(hint) => write!(formatter, "{}\n{hint}", self.message),
            None => formatter.write_str(&self.message),
        }
    }
}

impl std::error::Error for SdccDeploymentException {}

/// 运行时部署器。
pub struct SdccRuntimeDeployer {
    pub runtime_root: PathBuf,
    pub stale_staging_age: Duration,
}

impl SdccRuntimeDeployer {
    #[must_use]
    pub fn new(runtime_root: impl Into<PathBuf>) -> Self {
        Self {
            runtime_root: runtime_root.into(),
            stale_staging_age: Duration::from_secs(3600),
        }
    }

    /// 确保 `fingerprint` 对应的运行时已就绪。
    pub fn ensure(
        &self,
        toolchain_assets: &Path,
        firmware_assets: &Path,
        fingerprint: &str,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
    ) -> Result<SdccRuntimeDeployment, SdccDeploymentException> {
        let root = self.runtime_root.join("sdcc");
        let destination = root.join(fingerprint);
        if is_ready(&destination, fingerprint) {
            return Ok(deployment(&destination));
        }
        emit(BuildEvent {
            stage: BuildStage::Preparing,
            level: BuildEventLevel::Info,
            message: "首次使用，正在部署内置 SDCC 工具链…".to_owned(),
            current: None,
            total: None,
        });
        let staging = root.join(format!(
            "{fingerprint}.staging-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |duration| duration.as_micros())
        ));
        let result = (|| {
            let _ = std::fs::create_dir_all(&root);
            self.prune_stale_staging(&root, &staging);
            copy_directory(toolchain_assets, &staging.join("toolchain"), sleep).map_err(
                |error| SdccDeploymentException {
                    message: format!("内置 SDCC 工具链部署失败：{error}"),
                    hint: Some(self.deployment_hint(&root)),
                },
            )?;
            copy_directory(firmware_assets, &staging.join("firmware"), sleep).map_err(|error| {
                SdccDeploymentException {
                    message: format!("内置 SDCC 工具链部署失败：{error}"),
                    hint: Some(self.deployment_hint(&root)),
                }
            })?;
            validate_bundle(&staging.join("toolchain")).map_err(|message| {
                SdccDeploymentException {
                    message: format!("内置 SDCC 工具链部署失败：{message}"),
                    hint: Some(self.deployment_hint(&root)),
                }
            })?;
            std::fs::write(staging.join(READY_MARKER), fingerprint).map_err(|error| {
                SdccDeploymentException {
                    message: format!("内置 SDCC 工具链部署失败：{error}"),
                    hint: Some(self.deployment_hint(&root)),
                }
            })?;
            self.promote(&staging, &destination, fingerprint, emit, sleep)
        })();
        if result.is_err() {
            best_effort_delete(&staging);
        }
        result.map(|_| deployment(&destination))
    }

    fn deployment_hint(&self, root: &Path) -> String {
        format!(
            "请关闭杀毒软件实时防护，或将 {} 加入白名单后重试；若仍失败，可退出应用后删除该目录再重试。",
            root.display()
        )
    }

    fn prune_stale_staging(&self, root: &Path, current: &Path) {
        let Ok(entries) = std::fs::read_dir(root) else {
            return;
        };
        let now = std::time::SystemTime::now();
        for entry in entries.flatten() {
            let path = entry.path();
            if path == current || !path.is_dir() {
                continue;
            }
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("");
            if !name.ends_with(".pending") && !name.contains(".staging-") {
                continue;
            }
            let stale = entry
                .metadata()
                .and_then(|metadata| metadata.modified())
                .ok()
                .and_then(|modified| now.duration_since(modified).ok())
                .is_some_and(|age| age >= self.stale_staging_age);
            if stale {
                let _ = std::fs::remove_dir_all(&path);
            }
        }
    }

    fn promote(
        &self,
        staging: &Path,
        destination: &Path,
        fingerprint: &str,
        emit: &mut dyn FnMut(BuildEvent),
        sleep: &dyn Fn(Duration),
    ) -> Result<(), SdccDeploymentException> {
        let mut delay = INITIAL_RETRY_DELAY;
        for attempt in 1..=PROMOTE_ATTEMPTS {
            if is_ready(destination, fingerprint) {
                best_effort_delete(staging);
                return Ok(());
            }
            if destination.exists() {
                let _ = std::fs::remove_dir_all(destination);
            }
            match std::fs::rename(staging, destination) {
                Ok(()) => return Ok(()),
                Err(_) => {
                    if attempt == 1 {
                        emit(BuildEvent {
                            stage: BuildStage::Preparing,
                            level: BuildEventLevel::Warning,
                            message: "内置 SDCC 工具链目录暂时被占用，正在重试…".to_owned(),
                            current: None,
                            total: None,
                        });
                    }
                    if attempt < PROMOTE_ATTEMPTS {
                        sleep(delay);
                        delay = Duration::from_millis(
                            (delay.as_millis().saturating_mul(2))
                                .min(u128::from(2000_u64))
                                .try_into()
                                .unwrap_or(2000),
                        );
                    }
                }
            }
        }
        if is_ready(destination, fingerprint) {
            best_effort_delete(staging);
            return Ok(());
        }
        Err(SdccDeploymentException {
            message: format!(
                "内置 SDCC 工具链部署失败：{} 无法替换（文件被其它进程占用）",
                destination.display()
            ),
            hint: Some(self.deployment_hint(&self.runtime_root.join("sdcc"))),
        })
    }
}

fn deployment(destination: &Path) -> SdccRuntimeDeployment {
    SdccRuntimeDeployment {
        toolchain: destination.join("toolchain"),
        firmware: destination.join("firmware"),
    }
}

fn is_ready(destination: &Path, fingerprint: &str) -> bool {
    let marker = destination.join(READY_MARKER);
    let Ok(content) = std::fs::read_to_string(&marker) else {
        return false;
    };
    if content.trim() != fingerprint {
        return false;
    }
    let executable = destination
        .join("toolchain")
        .join("bin")
        .join(if cfg!(windows) { "sdcc.exe" } else { "sdcc" });
    executable.exists()
        && destination
            .join("firmware")
            .join("build_manifest.json")
            .exists()
}

fn validate_bundle(toolchain: &Path) -> Result<(), String> {
    let manifest_path = toolchain.join("bundle_manifest.json");
    let text = std::fs::read_to_string(&manifest_path)
        .map_err(|error| format!("读取 bundle_manifest.json 失败：{error}"))?;
    let manifest: serde_json::Value = serde_json::from_str(&text)
        .map_err(|error| format!("bundle_manifest.json 非法：{error}"))?;
    let files = manifest
        .get("files")
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| "bundle_manifest.json 缺少 files".to_owned())?;
    for (relative, expected) in files {
        let path = toolchain.join(relative.replace('/', std::path::MAIN_SEPARATOR_STR));
        if !path.exists() {
            return Err(format!("内置 SDCC 工具链文件缺失：{relative}"));
        }
        let bytes = std::fs::read(&path)
            .map_err(|error| format!("读取内置 SDCC 工具链文件失败：{relative}：{error}"))?;
        if pieblock_core::sha256_hex(&bytes) != expected.as_str().unwrap_or("") {
            return Err(format!("内置 SDCC 工具链文件校验失败：{relative}"));
        }
    }
    Ok(())
}

fn best_effort_delete(directory: &Path) {
    if directory.exists() {
        let _ = std::fs::remove_dir_all(directory);
    }
}
