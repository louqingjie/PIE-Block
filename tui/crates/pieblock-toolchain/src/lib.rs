//! SDCC/Keil 工具链编排（M2 里程碑）。
//!
//! 已移植：Intel HEX 解析/应用区与 SDCC MAP 布局校验、构建模型、文件操作重试、
//! 运行时部署（`.ready`/staging/rename/退避/残留清理）、SDCC 目标文件缓存、
//! SDCC 构建计划（清单解析/中断声明头/编译链接参数）。
//! 后续提交补齐 FirmwareBuilder（调用 SDCC/Keil）、产物仓库与 LST/HEX 校验整合。

pub mod artifact_repository;
pub mod builder;
pub mod file_ops;
pub mod hex;
pub mod models;
pub mod sdcc_build_plan;
pub mod sdcc_object_cache;
pub mod sdcc_runtime_deployer;

pub use artifact_repository::BuildArtifactRepository;
pub use builder::{
    FirmwareBuilder, ProcessOutput, ProcessRunner, SystemProcessRunner, firmware_content_hash,
    firmware_project_for,
};
pub use file_ops::{copy_directory, retry_file_system};
pub use hex::{HexImage, HexValidationResult, IntelHexValidator};
pub use models::{
    BuildArtifact, BuildEvent, BuildEventLevel, BuildFingerprint, BuildRequest, BuildResult,
    BuildStage, CompilerKind,
};
pub use sdcc_build_plan::SdccBuildPlan;
pub use sdcc_object_cache::{CachedSdccObject, SDCC_OBJECT_CACHE_VERSION, SdccObjectCache};
pub use sdcc_runtime_deployer::{
    SdccDeploymentException, SdccRuntimeDeployer, SdccRuntimeDeployment,
};

/// 内置工具链清单的固定相对路径（发布包内）。
pub const BUNDLE_MANIFEST_RELATIVE_PATH: &str = "sdcc-toolchain/bundle_manifest.json";

/// 固件构建清单的固定相对路径（发布包内）。
pub const BUILD_MANIFEST_RELATIVE_PATH: &str = "stc32g_sdcc/build_manifest.json";

/// 构建指纹的 schema 版本前缀（与 Flutter 版一致）。
pub const BUILD_SCHEMA_PREFIX: &str = "flutter_build_v5";

/// M2 阶段能力描述。
#[must_use]
pub const fn stage() -> &'static str {
    "M2 进行中：HEX/MAP、部署、缓存、构建计划已移植；FirmwareBuilder/原生 HID/真机待完成"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_paths_and_prefix() {
        assert!(BUNDLE_MANIFEST_RELATIVE_PATH.ends_with("bundle_manifest.json"));
        assert!(BUILD_MANIFEST_RELATIVE_PATH.ends_with("build_manifest.json"));
        assert_eq!(BUILD_SCHEMA_PREFIX, "flutter_build_v5");
    }
}
