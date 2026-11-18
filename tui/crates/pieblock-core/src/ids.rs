//! 时间戳与 id 工具。
//!
//! Dart 侧用 `DateTime.now().toUtc().toIso8601String()`（毫秒三位 + `Z`）与
//! `microsecondsSinceEpoch` 生成时间戳/新 id；这里保持同样的外部形态。

use std::time::{SystemTime, UNIX_EPOCH};

/// 当前 UTC 时间的 Dart `toIso8601String()` 形态：`YYYY-MM-DDTHH:MM:SS.mmmZ`。
#[must_use]
pub fn now_iso8601() -> String {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let total_seconds = duration.as_secs();
    let millis = duration.subsec_millis();
    let days = i64::try_from(total_seconds / 86_400).unwrap_or(0);
    let seconds_of_day = total_seconds % 86_400;
    let (year, month, day) = civil_from_days(days);
    let hour = seconds_of_day / 3_600;
    let minute = (seconds_of_day % 3_600) / 60;
    let second = seconds_of_day % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

/// 与 Dart `DateTime.now().microsecondsSinceEpoch.toString()` 对齐的新 id。
#[must_use]
pub fn new_id() -> String {
    let micros = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_micros())
        .unwrap_or_default();
    micros.to_string()
}

/// Howard Hinnant 的 civil_from_days（由 `days since 1970-01-01` 求公历日期）。
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    let era = if shifted >= 0 {
        shifted
    } else {
        shifted - 146_096
    } / 146_097;
    let day_of_era = u64::try_from(shifted - era * 146_097).unwrap_or(0);
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = i64::try_from(year_of_era).unwrap_or(0) + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = u32::try_from(day_of_year - (153 * month_prime + 2) / 5 + 1).unwrap_or(1);
    let month = if month_prime < 10 {
        month_prime + 3
    } else {
        month_prime - 9
    };
    let month = u32::try_from(month).unwrap_or(1);
    let year = if month <= 2 { year + 1 } else { year };
    (year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso8601_shape_matches_dart() {
        let text = now_iso8601();
        assert_eq!(text.len(), 24, "got {text}");
        assert!(text.ends_with('Z'));
        assert_eq!(&text[4..5], "-");
        assert_eq!(&text[10..11], "T");
        assert_eq!(&text[19..20], ".");
    }

    #[test]
    fn civil_epoch_is_1970() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(1), (1970, 1, 2));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
    }

    #[test]
    fn new_id_is_numeric() {
        let id = new_id();
        assert!(id.chars().all(|ch| ch.is_ascii_digit()), "got {id}");
    }
}
