//! SDCC 目标文件缓存（与 `sdcc_object_cache.dart` 对齐）。

use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::file_ops::retry_file_system;

/// 目标文件缓存格式版本。
pub const SDCC_OBJECT_CACHE_VERSION: &str = "v1";

/// 缓存命中结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CachedSdccObject {
    pub object_path: PathBuf,
    pub warning_count: i64,
}

/// 按「工具链/固件指纹 + 工程 + 源文件相对路径」缓存 SDCC 目标文件。
pub struct SdccObjectCache {
    pub root: PathBuf,
    pub compiler_fingerprint: String,
    pub project: String,
}

impl SdccObjectCache {
    #[must_use]
    pub fn new(
        runtime_root: &Path,
        compiler_fingerprint: impl Into<String>,
        project: impl Into<String>,
    ) -> Self {
        Self {
            root: runtime_root
                .join("object-cache")
                .join(SDCC_OBJECT_CACHE_VERSION),
            compiler_fingerprint: compiler_fingerprint.into(),
            project: project.into(),
        }
    }

    #[must_use]
    pub fn project_root(&self) -> PathBuf {
        self.root
            .join(&self.compiler_fingerprint)
            .join(&self.project)
    }

    #[must_use]
    pub fn cache_path(&self, relative: &str) -> PathBuf {
        let normalized = relative.replace('\\', "/");
        self.project_root()
            .join(format!("{normalized}.rel").replace('/', std::path::MAIN_SEPARATOR_STR))
    }

    #[must_use]
    pub fn listing_cache_path(&self, relative: &str) -> PathBuf {
        with_extension(&self.cache_path(relative), "lst")
    }

    #[must_use]
    pub fn metadata_path(&self, object_path: &Path) -> PathBuf {
        with_extension_string(object_path, "json")
    }

    /// 清理其它指纹目录，避免旧目标文件无限累积。
    pub fn prune_other_fingerprints(&self) {
        let Ok(entries) = std::fs::read_dir(&self.root) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("");
            if path.is_dir() && name != self.compiler_fingerprint {
                let _ = std::fs::remove_dir_all(&path);
            }
        }
    }

    /// 命中时把缓存对象与 `.lst` 复制到 `destination`，返回警告条数。
    pub fn lookup(&self, relative: &str, destination: &Path) -> Option<CachedSdccObject> {
        let source = self.cache_path(relative);
        let listing = self.listing_cache_path(relative);
        let metadata = self.metadata_path(&source);
        let text = std::fs::read_to_string(&metadata).ok()?;
        let json: Value = serde_json::from_str(&text).ok()?;
        let map = json.as_object()?;
        let size = map.get("size")?.as_i64()?;
        let hash = map.get("sha256")?.as_str()?;
        let listing_size = map.get("listing_size")?.as_i64()?;
        let listing_hash = map.get("listing_sha256")?.as_str()?;
        let warning_count = map
            .get("warning_count")
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let bytes = std::fs::read(&source).ok()?;
        let listing_bytes = std::fs::read(&listing).ok()?;
        if i64::try_from(bytes.len()).ok()? != size
            || pieblock_core::sha256_hex(&bytes) != hash
            || i64::try_from(listing_bytes.len()).ok()? != listing_size
            || pieblock_core::sha256_hex(&listing_bytes) != listing_hash
        {
            return None;
        }
        let temporary = temp_path(destination);
        let _ = std::fs::create_dir_all(destination.parent()?);
        atomic_copy(&source, destination).ok()?;
        atomic_copy(&listing, &with_extension(destination, "lst")).ok()?;
        let _ = std::fs::remove_file(temporary);
        Some(CachedSdccObject {
            object_path: destination.to_path_buf(),
            warning_count,
        })
    }

    /// 编译成功后写回目标文件、`.lst` 与元数据。
    pub fn store(
        &self,
        relative: &str,
        object_path: &Path,
        warning_count: i64,
    ) -> std::io::Result<()> {
        let listing_source = with_extension(object_path, "lst");
        if !listing_source.exists() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("编译未产出 .lst：{}", object_path.display()),
            ));
        }
        let destination = self.cache_path(relative);
        let listing_destination = self.listing_cache_path(relative);
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent)?;
        }
        atomic_copy(object_path, &destination)?;
        atomic_copy(&listing_source, &listing_destination)?;
        let bytes = std::fs::read(&destination)?;
        let listing_bytes = std::fs::read(&listing_destination)?;
        let mut metadata = Map::new();
        metadata.insert("warning_count".to_owned(), Value::from(warning_count));
        metadata.insert("size".to_owned(), Value::from(bytes.len()));
        metadata.insert(
            "sha256".to_owned(),
            Value::String(pieblock_core::sha256_hex(&bytes)),
        );
        metadata.insert("listing_size".to_owned(), Value::from(listing_bytes.len()));
        metadata.insert(
            "listing_sha256".to_owned(),
            Value::String(pieblock_core::sha256_hex(&listing_bytes)),
        );
        atomic_write(
            &self.metadata_path(&destination),
            &serde_json::to_string(&Value::Object(metadata)).expect("metadata json"),
        )
    }
}

fn atomic_copy(source: &Path, destination: &Path) -> std::io::Result<()> {
    retry_file_system(
        || {
            let temporary = temp_path(destination);
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
            let temporary = temp_path(destination);
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

fn temp_path(destination: &Path) -> PathBuf {
    let micros = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_micros());
    destination.with_file_name(format!(
        "{}.{}-{micros}.tmp",
        destination
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("cache"),
        std::process::id()
    ))
}

fn with_extension(path: &Path, extension: &str) -> PathBuf {
    path.with_extension(extension)
}

fn with_extension_string(path: &Path, extension: &str) -> PathBuf {
    let mut text = path.as_os_str().to_os_string();
    text.push(".");
    text.push(extension);
    PathBuf::from(text)
}
