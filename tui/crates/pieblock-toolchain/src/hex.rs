//! Intel HEX 解析与主控板布局校验（与 `hex_validator.dart` 对齐）。
//!
//! Windows 上的 SDCC/Keil 工具链可能按 ANSI 代码页写 MAP/LST，这里与 Dart 一样
//! 按 UTF-8 宽松解码（非法字节替换为 U+FFFD），只依赖 ASCII 关键字与符号。

use std::collections::BTreeMap;
use std::path::Path;

/// 解析后的 HEX 字节镜像：地址 → 字节。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HexImage {
    pub bytes: BTreeMap<i64, u8>,
}

impl HexImage {
    #[must_use]
    pub fn min_address(&self) -> Option<i64> {
        self.bytes.keys().next().copied()
    }

    #[must_use]
    pub fn max_address(&self) -> Option<i64> {
        self.bytes.keys().next_back().copied()
    }
}

/// 校验结果；`ok=true` 时携带解析出的镜像。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HexValidationResult {
    pub ok: bool,
    pub message: String,
    pub image: Option<HexImage>,
}

impl HexValidationResult {
    fn ok(message: impl Into<String>, image: HexImage) -> Self {
        Self {
            ok: true,
            message: message.into(),
            image: Some(image),
        }
    }

    fn error(message: impl Into<String>) -> Self {
        Self {
            ok: false,
            message: message.into(),
            image: None,
        }
    }
}

const APPLICATION_BASE: i64 = 0x00fe_0000;
const VECTOR_BASE: i64 = 0x00ff_0000;
const VECTOR_LIMIT: i64 = 0x00ff_1000;
const XRAM_BASE: i64 = 0x0001_0000;
const XRAM_LIMIT: i64 = 0x0001_2000;
const IRAM_LIMIT: i64 = 0x0000_1000;

/// Intel HEX 解析/校验器。
pub struct IntelHexValidator;

impl IntelHexValidator {
    /// 读取并校验主控板应用区布局。
    pub fn validate_application(path: &Path) -> HexValidationResult {
        let parsed = Self::parse(path);
        if !parsed.ok {
            return parsed;
        }
        let image = parsed.image.clone().unwrap_or_default();
        if image.bytes.is_empty() {
            return HexValidationResult::error("HEX 中没有数据");
        }
        let min = image.min_address().unwrap_or(0);
        let max = image.max_address().unwrap_or(0);
        if min < APPLICATION_BASE || max > 0x00ff_ffff {
            return HexValidationResult::error(format!(
                "HEX 地址超出主控板应用区：0x{:x}–0x{:x}",
                min, max
            ));
        }
        if !image.bytes.keys().any(|address| *address < VECTOR_BASE) {
            return HexValidationResult::error("HEX 缺少 0xFE0000 用户代码区");
        }
        if !image.bytes.keys().any(|address| *address >= VECTOR_BASE) {
            return HexValidationResult::error("HEX 缺少 0xFF0000 向量或关键数据区");
        }
        if image.bytes.get(&VECTOR_BASE) != Some(&0x02)
            || !image.bytes.contains_key(&(VECTOR_BASE + 1))
            || !image.bytes.contains_key(&(VECTOR_BASE + 2))
        {
            return HexValidationResult::error("HEX 缺少完整的 0xFF0000 LJMP 复位向量");
        }
        HexValidationResult::ok(
            format!("HEX 布局有效，共 {} 字节", image.bytes.len()),
            image,
        )
    }

    /// 解析 HEX 文本（不校验应用区布局）。
    pub fn parse(path: &Path) -> HexValidationResult {
        if !path.exists() {
            return HexValidationResult::error("HEX 文件不存在");
        }
        let Ok(bytes) = std::fs::read(path) else {
            return HexValidationResult::error("HEX 文件不存在");
        };
        let text = String::from_utf8_lossy(&bytes);
        let mut image: BTreeMap<i64, u8> = BTreeMap::new();
        let mut upper: i64 = 0;
        for (line_index, raw) in text.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() {
                continue;
            }
            if !line.starts_with(':') || (line.len() - 1) % 2 != 0 {
                return HexValidationResult::error(format!("HEX 第 {} 行格式无效", line_index + 1));
            }
            let chars: Vec<char> = line.chars().collect();
            let mut values: Vec<i64> = Vec::new();
            for position in (1..chars.len()).step_by(2) {
                let pair: String = chars[position..position + 2].iter().collect();
                match i64::from_str_radix(&pair, 16) {
                    Ok(value) => values.push(value),
                    Err(_) => {
                        return HexValidationResult::error(format!(
                            "HEX 第 {} 行包含非法十六进制字符",
                            line_index + 1
                        ));
                    }
                }
            }
            if values.len() < 5 || i64::try_from(values.len()).unwrap_or(0) != values[0] + 5 {
                return HexValidationResult::error(format!("HEX 第 {} 行长度错误", line_index + 1));
            }
            if values.iter().fold(0_i64, |sum, value| (sum + value) & 0xff) != 0 {
                return HexValidationResult::error(format!(
                    "HEX 第 {} 行校验和错误",
                    line_index + 1
                ));
            }
            let count = values[0];
            let address = (values[1] << 8) | values[2];
            let record_type = values[3];
            match record_type {
                0 => {
                    for index in 0..count {
                        image.insert(
                            upper + address + index,
                            values[4 + usize::try_from(index).unwrap_or(0)] as u8,
                        );
                    }
                }
                2 | 4 => {
                    if values.len() < 6 {
                        return HexValidationResult::error(format!(
                            "HEX 第 {} 行长度错误",
                            line_index + 1
                        ));
                    }
                    let extended = (values[4] << 8) | values[5];
                    upper = if record_type == 2 {
                        extended << 4
                    } else {
                        extended << 16
                    };
                }
                1 | 3 | 5 => {}
                _ => {
                    return HexValidationResult::error(format!(
                        "HEX 第 {} 行记录类型不受支持",
                        line_index + 1
                    ));
                }
            }
        }
        HexValidationResult::ok("HEX 解析成功", HexImage { bytes: image })
    }

    /// 校验 SDCC C251 后端产出的 HEX/MAP 链接布局。
    pub fn validate_sdcc_layout(hex_path: &Path, map_path: &Path) -> HexValidationResult {
        let parsed = Self::validate_application(hex_path);
        if !parsed.ok {
            return parsed;
        }
        let image = parsed.image.clone().unwrap_or_default();
        for address in VECTOR_BASE..VECTOR_BASE + 3 {
            if !image.bytes.contains_key(&address) {
                return HexValidationResult::error("复位向量 0xFF0000 不完整");
            }
        }
        if image.bytes.get(&VECTOR_BASE) != Some(&0x02) {
            let value = image.bytes.get(&VECTOR_BASE).copied().unwrap_or(0);
            return HexValidationResult::error(format!(
                "复位向量首字节为 0x{value:02x}，应为 LJMP 0x02"
            ));
        }
        if image.bytes.keys().any(|address| *address >= VECTOR_LIMIT) {
            return HexValidationResult::error("向量区数据越过 0xFF1000");
        }
        if !map_path.exists() {
            return HexValidationResult::error("缺少 SDCC MAP 文件");
        }
        let Ok(map_bytes) = std::fs::read(map_path) else {
            return HexValidationResult::error("缺少 SDCC MAP 文件");
        };
        let map_text = String::from_utf8_lossy(&map_bytes);
        for line in map_text.lines() {
            let trimmed = line.trim_start();
            let mut parts = trimmed.split_whitespace();
            let Some(name) = parts.next() else {
                continue;
            };
            if !matches!(
                name,
                "HOME"
                    | "GSINIT"
                    | "GSFINAL"
                    | "CSEG"
                    | "CONST"
                    | "XINIT"
                    | "XISEG"
                    | "DSEG"
                    | "SSEG"
                    | "PSEG"
                    | "XSEG"
            ) {
                continue;
            }
            let Some(start_text) = parts.next() else {
                continue;
            };
            let Some(length_text) = parts.next() else {
                continue;
            };
            let Some(equals) = parts.next() else {
                continue;
            };
            if !equals.starts_with('=') {
                continue;
            }
            let (Ok(start), Ok(length)) = (
                i64::from_str_radix(start_text, 16),
                i64::from_str_radix(length_text, 16),
            ) else {
                continue;
            };
            if start_text.len() != 8 || length_text.len() != 8 {
                continue;
            }
            let end = start + length;
            let error: Option<String> = if name == "HOME" {
                if start != VECTOR_BASE || end > VECTOR_LIMIT {
                    Some("HOME 超出向量区".to_owned())
                } else {
                    None
                }
            } else if matches!(name, "GSINIT" | "GSFINAL" | "CSEG" | "CONST" | "XINIT") {
                if length > 0
                    && !((APPLICATION_BASE..VECTOR_BASE).contains(&start) && end <= VECTOR_BASE)
                {
                    Some(format!("{name} 超出用户程序区"))
                } else {
                    None
                }
            } else if matches!(name, "XSEG" | "XISEG") {
                if length > 0 && !(start >= XRAM_BASE && end <= XRAM_LIMIT) {
                    Some(format!("{name} 超出 STC32G XRAM"))
                } else {
                    None
                }
            } else if length > 0 && !(start >= 0 && end <= IRAM_LIMIT) {
                Some(format!("{name} 超出 STC32G EDATA"))
            } else {
                None
            };
            if let Some(error) = error {
                return HexValidationResult::error(format!("{error}：0x{start:08x}–0x{end:08x}"));
            }
        }
        for symbol in [
            "__sdcc_mcs251_reset_trampoline",
            "__sdcc_gsinit_startup",
            "_Default_Isr",
        ] {
            if !map_text.contains(symbol) {
                return HexValidationResult::error(format!("MAP 缺少启动或向量符号：{symbol}"));
            }
        }
        HexValidationResult::ok(
            format!("SDCC HEX/MAP 布局校验通过，共 {} 字节", image.bytes.len()),
            image,
        )
    }
}
