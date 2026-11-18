//! 构建产物仓库：按指纹持久化 HEX、构建日志与产物元数据。
//!
//! 与 `artifact_repository.dart` 对齐；HEX 哈希按 LF 规范化（CRLF→LF），
//! 保证 Windows/Android 两端固件字节级一致。

use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::file_ops::retry_file_system;
use crate::hex::IntelHexValidator;
use crate::models::{BuildArtifact, BuildFingerprint};

/// 产物仓库。
pub struct BuildArtifactRepository {
    pub root: PathBuf,
}

impl BuildArtifactRepository {
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// 命中且校验通过时返回产物；任何异常都按未命中处理。
    pub fn find_fresh(&self, fingerprint: &BuildFingerprint) -> Option<BuildArtifact> {
        let directory = self.root.join(&fingerprint.value);
        let text = std::fs::read_to_string(directory.join("artifact.json")).ok()?;
        let json: Value = serde_json::from_str(&text).ok()?;
        let artifact = BuildArtifact::from_json(&json).ok()?;
        if artifact.fingerprint != fingerprint.value
            || artifact.source_sha256 != fingerprint.source_hash
        {
            return None;
        }
        let hex = Path::new(&artifact.hex_path);
        if !hex.exists() || sha_file(hex) != artifact.hex_sha256 {
            return None;
        }
        if !IntelHexValidator::validate_application(hex).ok {
            return None;
        }
        Some(artifact)
    }

    /// 把构建产物复制进仓库并写元数据/日志。
    pub fn store(
        &self,
        source_hex: &Path,
        artifact: &BuildArtifact,
        log: &str,
    ) -> std::io::Result<BuildArtifact> {
        let directory = self.root.join(&artifact.fingerprint);
        std::fs::create_dir_all(&directory)?;
        let destination = directory.join("firmware.hex");
        atomic_copy(source_hex, &destination)?;
        let mut stored = artifact.clone();
        stored.hex_path = destination.display().to_string();
        stored.hex_sha256 = sha_file(&destination);
        atomic_write(&directory.join("build.log"), log)?;
        let pretty = serde_json::to_string_pretty(&stored.to_json()).expect("artifact json");
        atomic_write(&directory.join("artifact.json"), &pretty)?;
        Ok(stored)
    }

    /// 更新最近烧录时间。
    pub fn mark_flashed(&self, artifact: &BuildArtifact) -> std::io::Result<BuildArtifact> {
        let updated = artifact.with_last_flashed_at(Some(pieblock_core::now_iso8601()));
        let pretty = serde_json::to_string_pretty(&updated.to_json()).expect("artifact json");
        atomic_write(
            &self.root.join(&artifact.fingerprint).join("artifact.json"),
            &pretty,
        )?;
        Ok(updated)
    }

    /// 清理过期/超限产物（保护指定指纹）。
    pub fn prune(
        &self,
        max_age: std::time::Duration,
        max_bytes: u64,
        protected_fingerprints: &[String],
    ) {
        let Ok(entries) = std::fs::read_dir(&self.root) else {
            return;
        };
        let now = std::time::SystemTime::now();
        let mut infos: Vec<(PathBuf, std::time::SystemTime, u64)> = Vec::new();
        for entry in entries.flatten() {
            let directory = entry.path();
            if !directory.is_dir() {
                continue;
            }
            let name = directory
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("");
            let protected = protected_fingerprints.iter().any(|item| item == name);
            let mut size = 0_u64;
            let mut modified = std::time::SystemTime::UNIX_EPOCH;
            if let Ok(files) = walk(&directory) {
                for file in files {
                    if let Ok(metadata) = file.metadata() {
                        size = size.saturating_add(metadata.len());
                        if let Ok(time) = metadata.modified() {
                            if time > modified {
                                modified = time;
                            }
                        }
                    }
                }
            }
            let age = now.duration_since(modified).unwrap_or_default();
            if !protected && age > max_age {
                let _ = std::fs::remove_dir_all(&directory);
            } else {
                infos.push((directory, modified, size));
            }
        }
        infos.sort_by_key(|info| std::cmp::Reverse(info.1));
        let mut retained = 0_u64;
        for (directory, _, size) in infos {
            retained = retained.saturating_add(size);
            let name = directory
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("");
            if retained > max_bytes && !protected_fingerprints.iter().any(|item| item == name) {
                let _ = std::fs::remove_dir_all(&directory);
            }
        }
    }
}

fn walk(directory: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for entry in std::fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            files.extend(walk(&path)?);
        } else {
            files.push(path);
        }
    }
    Ok(files)
}

/// 黄金哈希采用 LF 规范化内容。
#[must_use]
pub fn sha_file(path: &Path) -> String {
    let bytes = std::fs::read(path).unwrap_or_default();
    let text = String::from_utf8_lossy(&bytes);
    pieblock_core::sha256_hex(text.replace("\r\n", "\n").as_bytes())
}

fn atomic_copy(source: &Path, destination: &Path) -> std::io::Result<()> {
    retry_file_system(
        || {
            let temporary = destination.with_file_name(format!(
                "{}.tmp",
                destination
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or("artifact")
            ));
            if temporary.exists() {
                std::fs::remove_file(&temporary)?;
            }
            std::fs::copy(source, &temporary)?;
            if destination.exists() {
                std::fs::remove_file(destination)?;
            }
            std::fs::rename(&temporary, destination)?;
            Ok(())
        },
        4,
        std::time::Duration::from_millis(120),
        std::time::Duration::from_secs(2),
        &|_| {},
    )
}

fn atomic_write(destination: &Path, contents: &str) -> std::io::Result<()> {
    retry_file_system(
        || {
            let temporary = destination.with_file_name(format!(
                "{}.tmp",
                destination
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or("artifact")
            ));
            std::fs::write(&temporary, contents)?;
            if destination.exists() {
                std::fs::remove_file(destination)?;
            }
            std::fs::rename(&temporary, destination)?;
            Ok(())
        },
        4,
        std::time::Duration::from_millis(120),
        std::time::Duration::from_secs(2),
        &|_| {},
    )
}
