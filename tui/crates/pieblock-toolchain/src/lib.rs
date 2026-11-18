//! SDCC/Keil 工具链编排（M2 里程碑）。
//!
//! 已移植：Intel HEX 解析、主控板应用区校验、SDCC HEX/MAP 链接布局校验。
//! 后续提交补齐构建指纹、运行时部署、SDCC/Keil 构建与产物缓存。

pub mod hex;

pub use hex::{HexImage, HexValidationResult, IntelHexValidator};

/// 内置工具链清单的固定相对路径（发布包内）。
pub const BUNDLE_MANIFEST_RELATIVE_PATH: &str = "sdcc-toolchain/bundle_manifest.json";

/// 固件构建清单的固定相对路径（发布包内）。
pub const BUILD_MANIFEST_RELATIVE_PATH: &str = "stc32g_sdcc/build_manifest.json";

/// 构建指纹的 schema 版本前缀（与 Flutter 版一致）。
pub const BUILD_SCHEMA_PREFIX: &str = "flutter_build_v5";

/// M2 阶段能力描述。
#[must_use]
pub const fn stage() -> &'static str {
    "M2 进行中：HEX/MAP 校验已移植，构建/部署/缓存待移植"
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
