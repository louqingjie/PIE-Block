//! JSON 取值与枚举辅助。
//!
//! Dart 版本对存档字段非常宽容：数值字段接受 int/double（`toInt()` 截断），
//! 枚举未知值回退默认或 null，缺失的 map/list 视为空。这里提供同语义的辅助函数，
//! 保证迁移与读取行为一致。

use serde_json::{Map, Value};

pub type JsonMap = Map<String, Value>;

/// 把 JSON 值当作对象读取。
#[must_use]
pub fn as_map(value: Option<&Value>) -> Option<&JsonMap> {
    value.and_then(Value::as_object)
}

/// 对象字段。
#[must_use]
pub fn field<'a>(map: &'a JsonMap, key: &str) -> Option<&'a Value> {
    map.get(key)
}

/// 数值字段按 Dart `(num?)?.toInt()` 语义转换：int 原样，double 截断。
#[must_use]
pub fn int_of(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(number) => number
            .as_i64()
            .or_else(|| number.as_f64().map(|float| float.trunc() as i64)),
        _ => None,
    }
}

#[must_use]
pub fn int_field(map: &JsonMap, key: &str) -> Option<i64> {
    int_of(field(map, key))
}

#[must_use]
pub fn string_field(map: &JsonMap, key: &str) -> Option<String> {
    field(map, key)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

#[must_use]
pub fn bool_field(map: &JsonMap, key: &str) -> Option<bool> {
    field(map, key).and_then(Value::as_bool)
}

/// Dart `item.toString()` 语义：null 变成 "null"。
#[must_use]
pub fn to_dart_string(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => "null".to_owned(),
        other => other.to_string(),
    }
}

#[must_use]
pub fn opt_int_to_json(value: Option<i64>) -> Value {
    value.map_or(Value::Null, Value::from)
}

#[must_use]
pub fn opt_string_to_json(value: Option<&str>) -> Value {
    value.map_or(Value::Null, |text| Value::String(text.to_owned()))
}

#[must_use]
pub fn string_list(map: &JsonMap, key: &str) -> Vec<String> {
    match field(map, key) {
        Some(Value::Array(items)) => items.iter().map(to_dart_string).collect(),
        _ => Vec::new(),
    }
}

#[must_use]
pub fn map_list<'a>(map: &'a JsonMap, key: &str) -> Vec<&'a JsonMap> {
    match field(map, key) {
        Some(Value::Array(items)) => items.iter().filter_map(Value::as_object).collect(),
        _ => Vec::new(),
    }
}

#[must_use]
pub fn child_map<'a>(map: &'a JsonMap, key: &str) -> Option<&'a JsonMap> {
    as_map(field(map, key))
}

/// 定义“稳定英文名”枚举：序列化/反序列化都按 Dart 的 `enum.name` 与
/// `enumValue` 语义（未知值返回 None，由调用方回退）。
#[macro_export]
macro_rules! string_enum {
    ($(#[$meta:meta])* $name:ident { $($variant:ident => $text:literal),+ $(,)? }) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub enum $name {
            $($variant),+
        }

        impl $name {
            pub const ALL: &'static [Self] = &[$(Self::$variant),+];

            #[must_use]
            pub const fn as_str(self) -> &'static str {
                match self {
                    $(Self::$variant => $text),+
                }
            }

            #[must_use]
            pub fn from_str_lenient(text: &str) -> Option<Self> {
                match text {
                    $($text => Some(Self::$variant),)+
                    _ => None,
                }
            }

            #[must_use]
            pub fn from_value(value: Option<&serde_json::Value>) -> Option<Self> {
                value.and_then(serde_json::Value::as_str).and_then(Self::from_str_lenient)
            }

            #[must_use]
            pub fn from_value_or(value: Option<&serde_json::Value>, fallback: Self) -> Self {
                Self::from_value(value).unwrap_or(fallback)
            }

            #[must_use]
            pub fn to_json(self) -> serde_json::Value {
                serde_json::Value::String(self.as_str().to_owned())
            }
        }
    };
}

/// 动作参数：Dart 里是 `num?`，可能写成整数或带小数（最多两位）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ParamNum {
    Int(i64),
    Float(f64),
}

impl ParamNum {
    #[must_use]
    pub fn from_value(value: Option<&Value>) -> Option<Self> {
        match value? {
            Value::Number(number) => {
                if let Some(int) = number.as_i64() {
                    Some(Self::Int(int))
                } else {
                    number.as_f64().map(Self::Float)
                }
            }
            _ => None,
        }
    }

    #[must_use]
    pub fn to_json(self) -> Value {
        match self {
            Self::Int(value) => Value::from(value),
            Self::Float(value) => Value::from(value),
        }
    }

    #[must_use]
    pub fn negated(self) -> Self {
        match self {
            Self::Int(value) => Self::Int(-value),
            Self::Float(value) => Self::Float(-value),
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn int_of_truncates_double_like_dart() {
        assert_eq!(int_of(Some(&json!(3))), Some(3));
        assert_eq!(int_of(Some(&json!(3.9))), Some(3));
        assert_eq!(int_of(Some(&json!(-2.7))), Some(-2));
        assert_eq!(int_of(Some(&json!("3"))), None);
    }

    #[test]
    fn param_num_preserves_int_and_float() {
        assert_eq!(
            ParamNum::from_value(Some(&json!(5))),
            Some(ParamNum::Int(5))
        );
        assert_eq!(
            ParamNum::from_value(Some(&json!(-1.5))),
            Some(ParamNum::Float(-1.5))
        );
        assert_eq!(ParamNum::Int(5).negated(), ParamNum::Int(-5));
        assert_eq!(ParamNum::Float(1.25).negated(), ParamNum::Float(-1.25));
    }
}
