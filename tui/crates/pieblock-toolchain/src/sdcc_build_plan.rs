//! SDCC 构建计划：解析 `build_manifest.json`、生成中断声明头、拼编译/链接参数。
//!
//! 与 `sdcc_build_plan.dart` 对齐（桌面端资源布局：`resourceRoot/{firmware,toolchain}`）。

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use serde_json::Value;

/// 一份 SDCC 构建计划。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SdccBuildPlan {
    pub project_name: String,
    pub source_paths: Vec<String>,
    pub library_source_paths: Vec<String>,
    pub compile_arguments: Vec<String>,
    pub link_arguments: Vec<String>,
    pub interrupt_header_path: String,
}

impl SdccBuildPlan {
    /// 读取清单并准备源码/参数/中断声明头。
    pub fn prepare(
        resource_root: &Path,
        project_name: &str,
        main_source_path: &str,
        output_directory: &Path,
    ) -> Result<Self, String> {
        let firmware = resource_root.join("firmware");
        let toolchain = resource_root.join("toolchain");
        let manifest_path = firmware.join("build_manifest.json");
        let text = std::fs::read_to_string(&manifest_path)
            .map_err(|error| format!("Android SDCC 资源缺少 build_manifest.json：{error}"))?;
        let manifest: Value = serde_json::from_str(&text)
            .map_err(|error| format!("build_manifest.json 非法：{error}"))?;
        let groups = manifest
            .get("source_groups")
            .and_then(Value::as_object)
            .ok_or_else(|| "build_manifest.json 缺少 source_groups".to_owned())?;
        let projects = manifest
            .get("projects")
            .and_then(Value::as_object)
            .ok_or_else(|| "build_manifest.json 缺少 projects".to_owned())?;
        let kind_projects = manifest.get("kind_projects").and_then(Value::as_object);
        let resolved = if projects.contains_key(project_name) {
            Some(project_name.to_owned())
        } else {
            kind_projects
                .and_then(|mapping| mapping.get(project_name))
                .and_then(Value::as_str)
                .map(str::to_owned)
        };
        let Some(resolved) = resolved else {
            return Err(format!("SDCC 构建清单缺少项目：{project_name}"));
        };
        let spec = projects
            .get(&resolved)
            .and_then(Value::as_object)
            .ok_or_else(|| format!("SDCC 构建清单缺少项目：{project_name}"))?;

        let mut relative_sources: Vec<String> = Vec::new();
        let mut relative_libraries: Vec<String> = Vec::new();
        let mut add_source = |value: &str| {
            if !relative_sources.iter().any(|item| item == value) {
                relative_sources.push(value.to_owned());
            }
        };
        for value in groups
            .get("common")
            .and_then(Value::as_array)
            .ok_or_else(|| "SDCC 构建清单缺少 common 源码组".to_owned())?
        {
            add_source(value.as_str().unwrap_or(""));
        }
        add_source(&format!("projects/{resolved}/src/isr.c"));
        add_source(&format!("projects/{resolved}/src/main.c"));
        for group_name in spec
            .get("library_groups")
            .and_then(Value::as_array)
            .ok_or_else(|| "SDCC 构建清单缺少 library_groups".to_owned())?
        {
            let group_name = group_name.as_str().unwrap_or("");
            let group = groups
                .get(group_name)
                .and_then(Value::as_array)
                .ok_or_else(|| format!("SDCC 构建清单缺少源码组：{group_name}"))?;
            for value in group {
                let relative = value.as_str().unwrap_or("");
                add_source(relative);
                if !relative_libraries.iter().any(|item| item == relative) {
                    relative_libraries.push(relative.to_owned());
                }
            }
        }

        let resolve_source = |relative: &str| -> String {
            if relative.ends_with("/src/main.c") {
                main_source_path.to_owned()
            } else {
                firmware
                    .join(relative.replace('/', std::path::MAIN_SEPARATOR_STR))
                    .display()
                    .to_string()
            }
        };
        let sources: Vec<String> = relative_sources
            .iter()
            .map(|item| resolve_source(item))
            .collect();
        for source in &sources {
            if !Path::new(source).exists() {
                return Err(format!("Android SDCC 固件源码缺失：{source}"));
            }
        }
        let library_sources: Vec<String> = relative_libraries
            .iter()
            .map(|item| resolve_source(item))
            .collect();

        std::fs::create_dir_all(output_directory)
            .map_err(|error| format!("创建 SDCC 输出目录失败：{error}"))?;
        let interrupt_header = output_directory.join("generated_interrupt_declarations.h");
        write_interrupt_header(&sources, &interrupt_header)?;

        let include_arguments = {
            let mut args = vec![
                format!("-I{}", toolchain.join("include").display()),
                format!("-I{}", toolchain.join("include").join("mcs51").display()),
            ];
            for directory in manifest
                .get("include_dirs")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                args.push(format!(
                    "-I{}",
                    firmware
                        .join(
                            directory
                                .as_str()
                                .unwrap_or("")
                                .replace('/', std::path::MAIN_SEPARATOR_STR)
                        )
                        .display()
                ));
            }
            args.push(format!(
                "-I{}",
                firmware
                    .join("projects")
                    .join(&resolved)
                    .join("inc")
                    .display()
            ));
            args
        };
        let mut compile_arguments = Vec::new();
        for flag in manifest
            .get("compile_flags")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            compile_arguments.push(flag.as_str().unwrap_or("").to_owned());
        }
        compile_arguments.extend(include_arguments.iter().cloned());

        let mut link_arguments = Vec::new();
        for flag in manifest
            .get("link_flags")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            link_arguments.push(flag.as_str().unwrap_or("").to_owned());
        }
        link_arguments.push(format!(
            "-L{}",
            toolchain
                .join("lib")
                .join("mcs251-large-stack-auto")
                .display()
        ));
        link_arguments.extend(include_arguments);
        for library in manifest
            .get("runtime_libraries")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            link_arguments.push(library.as_str().unwrap_or("").to_owned());
        }

        Ok(Self {
            project_name: resolved,
            source_paths: sources,
            library_source_paths: library_sources,
            compile_arguments,
            link_arguments,
            interrupt_header_path: interrupt_header.display().to_string(),
        })
    }
}

fn write_interrupt_header(sources: &[String], destination: &Path) -> Result<(), String> {
    let mut declarations: BTreeSet<String> = BTreeSet::new();
    for source in sources {
        let text = std::fs::read_to_string(source)
            .map_err(|error| format!("读取固件源码失败：{source}：{error}"))?;
        for line in text.lines() {
            if let Some(declaration) = parse_interrupt_declaration(line) {
                declarations.insert(declaration);
            }
        }
    }
    let sorted: Vec<String> = declarations.into_iter().collect();
    let body = format!(
        "#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n\
         #define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n\
         #include \"STC32Gxx.h\"\n\
         #include <stdlib.h>\n\
         {}\n\
         #endif\n",
        sorted.join("\n")
    );
    std::fs::write(destination, body)
        .map_err(|error| format!("写入中断声明头失败：{}：{error}", destination.display()))
}

/// 解析 `[static] void name(void) __interrupt (n)` 一行。
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
    if name.is_empty() || name.chars().next().is_some_and(|ch| ch.is_ascii_digit()) {
        return None;
    }
    let rest = rest[name_end..].trim_start();
    let rest = rest.strip_prefix("(void)")?.trim_start();
    let rest = rest.strip_prefix("__interrupt")?.trim_start();
    let rest = rest.strip_prefix('(')?;
    let end = rest.find(')')?;
    let value = rest[..end].trim();
    Some(format!("void {name}(void) __interrupt ({value});"))
}

#[must_use]
pub fn path_for_display(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[must_use]
pub fn default_output_directory(root: &Path) -> PathBuf {
    root.join("generated")
}
