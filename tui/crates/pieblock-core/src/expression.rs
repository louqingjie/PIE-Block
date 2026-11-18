//! 受限表达式：解析、类型检查、求值、C 发射与运行时 helper。
//!
//! 行为与 `packages/pieblock_core/lib/src/expression.dart` 对齐：语法/优先级、
//! 诊断文案与 UTF-16 偏移、整数/有理数类型推导、求值语义（除零→0、负数开方→0、
//! Dart 取模）、C 代码字符串与运行时 helper 表。

use std::collections::{BTreeMap, BTreeSet};
use std::f64::consts::{E, PI};

use serde_json::{Map, Value};

use crate::model::{ActionInputKind, ActionOutputKind, EngineerConfig};

/// 表达式值类型：整数按 C `int32_t`，有理数按 `float`。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ExpressionType {
    Integer,
    Rational,
}

impl ExpressionType {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Integer => "integer",
            Self::Rational => "rational",
        }
    }

    #[must_use]
    pub const fn c_type(self) -> &'static str {
        match self {
            Self::Integer => "int32_t",
            Self::Rational => "float",
        }
    }
}

/// 表达式求值/字面量的数值；保留整数与浮点两种形态以匹配 Dart `num`。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Number {
    Integer(i64),
    Float(f64),
}

impl Number {
    #[must_use]
    pub fn to_int(self) -> i64 {
        match self {
            Self::Integer(value) => value,
            Self::Float(value) => value.trunc() as i64,
        }
    }

    #[must_use]
    pub fn to_float(self) -> f64 {
        match self {
            Self::Integer(value) => value as f64,
            Self::Float(value) => value,
        }
    }

    #[must_use]
    pub fn negated(self) -> Self {
        match self {
            Self::Integer(value) => Self::Integer(value.wrapping_neg()),
            Self::Float(value) => Self::Float(-value),
        }
    }

    /// Dart `num.toString()`：整数裸写；浮点保留 `.0` 与 `e+` 指数形态。
    #[must_use]
    pub fn to_dart_string(self) -> String {
        match self {
            Self::Integer(value) => value.to_string(),
            Self::Float(value) => format_dart_float(value),
        }
    }
}

/// Dart `double.toString()` 的近似实现（最短往返 + 整数值补 `.0` + 正指数带 `+`）。
#[must_use]
pub fn format_dart_float(value: f64) -> String {
    if !value.is_finite() {
        return if value.is_nan() {
            "NaN".to_owned()
        } else if value.is_sign_negative() {
            "-Infinity".to_owned()
        } else {
            "Infinity".to_owned()
        };
    }
    let mut text = format!("{value}");
    if let Some(index) = text.find(['e', 'E']) {
        let (mantissa, exponent) = text.split_at(index);
        let exponent = exponent[1..].to_owned();
        let exponent = if exponent.starts_with(['+', '-']) {
            exponent
        } else {
            format!("+{exponent}")
        };
        text = format!("{mantissa}e{exponent}");
    } else if !text.contains('.') {
        text.push_str(".0");
    }
    text
}

/// 解析/类型检查诊断；`offset` 为 UTF-16 偏移（与 Dart 字符串下标一致）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExpressionDiagnostic {
    pub message: String,
    pub offset: usize,
}

impl ExpressionDiagnostic {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("message".to_owned(), Value::String(self.message.clone()));
        map.insert("offset".to_owned(), Value::from(self.offset));
        Value::Object(map)
    }
}

pub const AXIS_INPUTS: &[&str] = &["LX", "LY", "RX", "RY"];
pub const BUTTON_INPUTS: &[&str] = &[
    "UP", "DOWN", "LEFT", "RIGHT", "A", "B", "C", "D", "E", "LC", "RC",
];

#[must_use]
pub fn is_builtin_input(name: &str) -> bool {
    AXIS_INPUTS.contains(&name) || BUTTON_INPUTS.contains(&name)
}

/// 表达式别名 → `.pieproj` 遥控器按键。
#[must_use]
pub fn input_alias(name: &str) -> Option<&'static str> {
    Some(match name {
        "LX" => "LX",
        "LY" => "LY",
        "RX" => "RX",
        "RY" => "RY",
        "UP" => "↑",
        "DOWN" => "↓",
        "LEFT" => "←",
        "RIGHT" => "→",
        "A" => "A",
        "B" => "B",
        "C" => "C",
        "D" => "D",
        "E" => "E",
        "LC" => "LC",
        "RC" => "RC",
        _ => return None,
    })
}

/// 遥控器按键 → 表达式别名（`↑` → `UP`）。
#[must_use]
pub fn alias_of_remote_key(key: &str) -> Option<&'static str> {
    Some(match key {
        "LX" => "LX",
        "LY" => "LY",
        "RX" => "RX",
        "RY" => "RY",
        "↑" => "UP",
        "↓" => "DOWN",
        "←" => "LEFT",
        "→" => "RIGHT",
        "A" => "A",
        "B" => "B",
        "C" => "C",
        "D" => "D",
        "E" => "E",
        "LC" => "LC",
        "RC" => "RC",
        _ => return None,
    })
}

/// 保留字：内置输入、常量、函数、C 关键字。
pub const RESERVED_NAMES: &[&str] = &[
    "LX", "LY", "RX", "RY", "UP", "DOWN", "LEFT", "RIGHT", "A", "B", "C", "D", "E", "LC", "RC",
    "PI", "E", "abs", "min", "max", "sign", "sqrt", "atan2", "int", "float", "long", "char",
    "void", "return", "if", "else", "for", "while", "switch", "case", "do", "break", "continue",
    "static", "const", "signed", "unsigned", "short", "struct", "typedef", "union", "enum",
    "sizeof", "main", "true", "false",
];

/// 用户变量名是否合法（语法 + 保留字；作用域唯一性由校验器负责）。
#[must_use]
pub fn is_valid_variable_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first.is_ascii_alphabetic() || first == '_') {
        return false;
    }
    if !chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_') {
        return false;
    }
    !RESERVED_NAMES.contains(&name) && !name.starts_with('_') && name.chars().count() <= 24
}

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Literal {
        kind: ExpressionType,
        value: Number,
    },
    Input(String),
    Variable {
        name: String,
        kind: ExpressionType,
    },
    Unary {
        operator: char,
        operand: Box<Expr>,
        kind: ExpressionType,
    },
    Binary {
        operator: BinaryOp,
        left: Box<Expr>,
        right: Box<Expr>,
        kind: ExpressionType,
    },
    Ternary {
        condition: Box<Expr>,
        when_true: Box<Expr>,
        when_false: Box<Expr>,
        kind: ExpressionType,
    },
    Call {
        name: String,
        arguments: Vec<Expr>,
        kind: ExpressionType,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
    Or,
    And,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
}

impl BinaryOp {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Or => "||",
            Self::And => "&&",
            Self::Equal => "==",
            Self::NotEqual => "!=",
            Self::Less => "<",
            Self::LessEqual => "<=",
            Self::Greater => ">",
            Self::GreaterEqual => ">=",
            Self::Add => "+",
            Self::Subtract => "-",
            Self::Multiply => "*",
            Self::Divide => "/",
            Self::Modulo => "%",
        }
    }

    #[must_use]
    const fn is_comparison(self) -> bool {
        matches!(
            self,
            Self::Equal
                | Self::NotEqual
                | Self::Less
                | Self::LessEqual
                | Self::Greater
                | Self::GreaterEqual
        )
    }

    #[must_use]
    const fn is_logical(self) -> bool {
        matches!(self, Self::Or | Self::And)
    }
}

impl Expr {
    #[must_use]
    pub const fn kind(&self) -> ExpressionType {
        match self {
            Self::Literal { kind, .. }
            | Self::Variable { kind, .. }
            | Self::Unary { kind, .. }
            | Self::Binary { kind, .. }
            | Self::Ternary { kind, .. }
            | Self::Call { kind, .. } => *kind,
            Self::Input(_) => ExpressionType::Integer,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ParsedExpression {
    pub root: Option<Expr>,
    pub diagnostics: Vec<ExpressionDiagnostic>,
}

impl ParsedExpression {
    #[must_use]
    pub fn is_ok(&self) -> bool {
        self.root.is_some() && self.diagnostics.is_empty()
    }
}

/// 解析单条表达式；`variables` 为当前作用域内已定义变量及类型。
#[must_use]
pub fn parse(source: &str, variables: &BTreeMap<String, ExpressionType>) -> ParsedExpression {
    Parser::new(source, variables).parse_top()
}

struct SyntaxError {
    message: String,
    offset: usize,
}

type ParseResult = Result<Expr, SyntaxError>;

struct Parser<'a> {
    chars: Vec<char>,
    variables: &'a BTreeMap<String, ExpressionType>,
    index: usize,
}

impl<'a> Parser<'a> {
    fn new(source: &'a str, variables: &'a BTreeMap<String, ExpressionType>) -> Self {
        Self {
            chars: source.chars().collect(),
            variables,
            index: 0,
        }
    }

    fn offset(&self) -> usize {
        self.chars[..self.index]
            .iter()
            .map(|ch| ch.len_utf16())
            .sum()
    }

    fn at_end(&self) -> bool {
        self.index >= self.chars.len()
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.index).copied()
    }

    fn fail<T>(&self, message: impl Into<String>) -> Result<T, SyntaxError> {
        Err(SyntaxError {
            message: message.into(),
            offset: self.offset(),
        })
    }

    fn skip_whitespace(&mut self) {
        while let Some(ch) = self.peek() {
            if matches!(ch, ' ' | '\t' | '\n' | '\r') {
                self.index += 1;
            } else {
                break;
            }
        }
    }

    fn starts_with(&self, token: &str) -> bool {
        for (offset, expected) in token.chars().enumerate() {
            if self.chars.get(self.index + offset) != Some(&expected) {
                return false;
            }
        }
        true
    }

    fn try_match(&mut self, token: &str) -> bool {
        self.skip_whitespace();
        if self.starts_with(token) {
            self.index += token.chars().count();
            true
        } else {
            false
        }
    }

    fn expect(&mut self, token: &str) -> Result<(), SyntaxError> {
        if self.try_match(token) {
            Ok(())
        } else {
            self.fail(format!("缺少 \"{token}\""))
        }
    }

    fn parse_top(mut self) -> ParsedExpression {
        match self.parse_top_inner() {
            Ok(root) => ParsedExpression {
                root: Some(root),
                diagnostics: Vec::new(),
            },
            Err(error) => ParsedExpression {
                root: None,
                diagnostics: vec![ExpressionDiagnostic {
                    message: error.message,
                    offset: error.offset,
                }],
            },
        }
    }

    fn parse_top_inner(&mut self) -> ParseResult {
        self.skip_whitespace();
        if self.at_end() {
            return self.fail("表达式不能为空");
        }
        let node = self.parse_ternary()?;
        self.skip_whitespace();
        if !self.at_end() {
            return self.fail("表达式末尾有多余字符");
        }
        Ok(node)
    }

    fn parse_ternary(&mut self) -> ParseResult {
        let condition = self.parse_logical_or()?;
        if !self.try_match("?") {
            return Ok(condition);
        }
        let when_true = self.parse_ternary()?;
        self.expect(":")?;
        let when_false = self.parse_ternary()?;
        let kind = unify(when_true.kind(), when_false.kind());
        Ok(Expr::Ternary {
            condition: Box::new(condition),
            when_true: Box::new(when_true),
            when_false: Box::new(when_false),
            kind,
        })
    }

    fn parse_logical_or(&mut self) -> ParseResult {
        let mut left = self.parse_logical_and()?;
        while self.try_match("||") {
            let right = self.parse_logical_and()?;
            left = Expr::Binary {
                operator: BinaryOp::Or,
                left: Box::new(left),
                right: Box::new(right),
                kind: ExpressionType::Integer,
            };
        }
        Ok(left)
    }

    fn parse_logical_and(&mut self) -> ParseResult {
        let mut left = self.parse_equality()?;
        while self.try_match("&&") {
            let right = self.parse_equality()?;
            left = Expr::Binary {
                operator: BinaryOp::And,
                left: Box::new(left),
                right: Box::new(right),
                kind: ExpressionType::Integer,
            };
        }
        Ok(left)
    }

    fn parse_equality(&mut self) -> ParseResult {
        let mut left = self.parse_relational()?;
        loop {
            let operator = if self.try_match("==") {
                BinaryOp::Equal
            } else if self.try_match("!=") {
                BinaryOp::NotEqual
            } else {
                return Ok(left);
            };
            let right = self.parse_relational()?;
            left = Expr::Binary {
                operator,
                left: Box::new(left),
                right: Box::new(right),
                kind: ExpressionType::Integer,
            };
        }
    }

    fn parse_relational(&mut self) -> ParseResult {
        let mut left = self.parse_additive()?;
        loop {
            let operator = if self.try_match("<=") {
                BinaryOp::LessEqual
            } else if self.try_match(">=") {
                BinaryOp::GreaterEqual
            } else if self.try_match("<") {
                BinaryOp::Less
            } else if self.try_match(">") {
                BinaryOp::Greater
            } else {
                return Ok(left);
            };
            let right = self.parse_additive()?;
            left = Expr::Binary {
                operator,
                left: Box::new(left),
                right: Box::new(right),
                kind: ExpressionType::Integer,
            };
        }
    }

    fn parse_additive(&mut self) -> ParseResult {
        let mut left = self.parse_multiplicative()?;
        loop {
            let operator = if self.try_match("+") {
                BinaryOp::Add
            } else if self.try_match("-") {
                BinaryOp::Subtract
            } else {
                return Ok(left);
            };
            let right = self.parse_multiplicative()?;
            let kind = unify(left.kind(), right.kind());
            left = Expr::Binary {
                operator,
                left: Box::new(left),
                right: Box::new(right),
                kind,
            };
        }
    }

    fn parse_multiplicative(&mut self) -> ParseResult {
        let mut left = self.parse_unary()?;
        loop {
            let operator = if self.try_match("*") {
                BinaryOp::Multiply
            } else if self.try_match("/") {
                BinaryOp::Divide
            } else if self.try_match("%") {
                BinaryOp::Modulo
            } else {
                return Ok(left);
            };
            let right = self.parse_unary()?;
            if operator == BinaryOp::Modulo
                && (left.kind() != ExpressionType::Integer
                    || right.kind() != ExpressionType::Integer)
            {
                return self.fail("取模运算只支持整数");
            }
            if operator == BinaryOp::Divide || operator == BinaryOp::Modulo {
                let label = if operator == BinaryOp::Divide {
                    "除法"
                } else {
                    "取模"
                };
                if constant_value(&right) == Some(Number::Integer(0)) {
                    return self.fail(format!("{label} 的除数不能为 0"));
                }
            }
            let kind = if operator == BinaryOp::Modulo {
                ExpressionType::Integer
            } else {
                unify(left.kind(), right.kind())
            };
            left = Expr::Binary {
                operator,
                left: Box::new(left),
                right: Box::new(right),
                kind,
            };
        }
    }

    fn parse_unary(&mut self) -> ParseResult {
        if self.try_match("-") {
            let operand = self.parse_unary()?;
            let kind = operand.kind();
            return Ok(Expr::Unary {
                operator: '-',
                operand: Box::new(operand),
                kind,
            });
        }
        if self.try_match("!") {
            let operand = self.parse_unary()?;
            return Ok(Expr::Unary {
                operator: '!',
                operand: Box::new(operand),
                kind: ExpressionType::Integer,
            });
        }
        if self.try_match("+") {
            return self.parse_unary();
        }
        self.parse_primary()
    }

    fn parse_primary(&mut self) -> ParseResult {
        self.skip_whitespace();
        let Some(ch) = self.peek() else {
            return self.fail("表达式不完整");
        };
        if ch == '(' {
            self.index += 1;
            let node = self.parse_ternary()?;
            self.expect(")")?;
            return Ok(node);
        }
        if ch.is_ascii_digit() || ch == '.' {
            return self.parse_number();
        }
        if is_identifier_start(ch) {
            let name = self.parse_identifier();
            self.skip_whitespace();
            if self.try_match("(") {
                return self.parse_call(&name);
            }
            if name == "PI" {
                return Ok(Expr::Literal {
                    kind: ExpressionType::Rational,
                    value: Number::Float(PI),
                });
            }
            if name == "E" {
                return Ok(Expr::Literal {
                    kind: ExpressionType::Rational,
                    value: Number::Float(E),
                });
            }
            if is_builtin_input(&name) {
                return Ok(Expr::Input(name));
            }
            if let Some(kind) = self.variables.get(&name) {
                return Ok(Expr::Variable { name, kind: *kind });
            }
            return self.fail(format!("未定义变量 \"{name}\""));
        }
        self.fail(format!("无法识别的字符 \"{ch}\""))
    }

    fn parse_number(&mut self) -> ParseResult {
        self.skip_whitespace();
        let start = self.index;
        let mut seen_dot = false;
        let mut seen_exponent = false;
        while let Some(ch) = self.peek() {
            let is_digit = ch.is_ascii_digit();
            if is_digit {
                self.index += 1;
            } else if ch == '.' && !seen_dot && !seen_exponent {
                seen_dot = true;
                self.index += 1;
            } else if (ch == 'e' || ch == 'E') && !seen_exponent {
                seen_exponent = true;
                self.index += 1;
                if matches!(self.peek(), Some('+' | '-')) {
                    self.index += 1;
                }
            } else {
                break;
            }
        }
        let text: String = self.chars[start..self.index].iter().collect();
        if text.is_empty() || text == "." {
            return self.fail("数字格式不正确");
        }
        if seen_dot || seen_exponent {
            match text.parse::<f64>() {
                Ok(value) if value.is_finite() => Ok(Expr::Literal {
                    kind: ExpressionType::Rational,
                    value: Number::Float(value),
                }),
                _ => self.fail("数字格式不正确"),
            }
        } else {
            match text.parse::<i64>() {
                Ok(value) if value <= i64::from(i32::MAX) => Ok(Expr::Literal {
                    kind: ExpressionType::Integer,
                    value: Number::Integer(value),
                }),
                Ok(_) => self.fail("整数超出 int32 范围"),
                Err(_) => self.fail("整数超出范围"),
            }
        }
    }

    fn parse_identifier(&mut self) -> String {
        let start = self.index;
        self.index += 1;
        while let Some(ch) = self.peek() {
            if is_identifier_part(ch) {
                self.index += 1;
            } else {
                break;
            }
        }
        self.chars[start..self.index].iter().collect()
    }

    fn parse_call(&mut self, name: &str) -> ParseResult {
        let (min, max) = match name {
            "abs" => (1, 1),
            "min" => (2, 64),
            "max" => (2, 64),
            "sign" => (1, 1),
            "sqrt" => (1, 1),
            "atan2" => (2, 2),
            _ => return self.fail(format!("不支持的函数 \"{name}\"")),
        };
        let mut arguments = Vec::new();
        self.skip_whitespace();
        if !self.try_match(")") {
            loop {
                arguments.push(self.parse_ternary()?);
                if self.try_match(")") {
                    break;
                }
                self.expect(",")?;
            }
        }
        if arguments.len() < min || arguments.len() > max {
            let arity = if min == max {
                min.to_string()
            } else {
                format!("{min}–{max}")
            };
            return self.fail(format!("函数 {name} 需要 {arity} 个参数"));
        }
        let kind = match name {
            "abs" => arguments[0].kind(),
            "min" | "max" => arguments
                .iter()
                .map(Expr::kind)
                .reduce(unify)
                .unwrap_or(ExpressionType::Integer),
            "sign" => ExpressionType::Integer,
            "sqrt" | "atan2" => ExpressionType::Rational,
            _ => ExpressionType::Integer,
        };
        if name == "sqrt" {
            if let Some(Number::Integer(value)) = constant_value(&arguments[0]) {
                if value < 0 {
                    return self.fail("sqrt 的参数不能为负数");
                }
            }
            if let Some(Number::Float(value)) = constant_value(&arguments[0]) {
                if value < 0.0 {
                    return self.fail("sqrt 的参数不能为负数");
                }
            }
        }
        Ok(Expr::Call {
            name: name.to_owned(),
            arguments,
            kind,
        })
    }
}

fn constant_value(node: &Expr) -> Option<Number> {
    match node {
        Expr::Literal { value, .. } => Some(*value),
        Expr::Unary {
            operator: '-',
            operand,
            ..
        } => constant_value(operand).map(Number::negated),
        _ => None,
    }
}

fn is_identifier_start(ch: char) -> bool {
    ch.is_ascii_alphabetic() || ch == '_'
}

fn is_identifier_part(ch: char) -> bool {
    is_identifier_start(ch) || ch.is_ascii_digit()
}

fn unify(a: ExpressionType, b: ExpressionType) -> ExpressionType {
    if a == ExpressionType::Rational || b == ExpressionType::Rational {
        ExpressionType::Rational
    } else {
        ExpressionType::Integer
    }
}

/// 求值；语义与生成的 C 一致（除零→0、负数开方→0）。
#[must_use]
pub fn evaluate(
    node: &Expr,
    inputs: &BTreeMap<String, Number>,
    variables: &BTreeMap<String, Number>,
) -> Number {
    use ExpressionType::{Integer, Rational};
    match node {
        Expr::Literal { value, .. } => *value,
        Expr::Input(name) => inputs.get(name).copied().unwrap_or(Number::Integer(0)),
        Expr::Variable { name, .. } => variables.get(name).copied().unwrap_or(Number::Integer(0)),
        Expr::Unary {
            operator, operand, ..
        } => {
            let value = evaluate(operand, inputs, variables);
            if *operator == '!' {
                return Number::Integer(if value.to_float() == 0.0 { 1 } else { 0 });
            }
            match node.kind() {
                Integer => Number::Integer(value.to_int().wrapping_neg()),
                Rational => Number::Float(-value.to_float()),
            }
        }
        Expr::Binary {
            operator,
            left,
            right,
            kind,
        } => {
            let a = evaluate(left, inputs, variables);
            let b = evaluate(right, inputs, variables);
            if *operator == BinaryOp::And {
                if a.to_float() == 0.0 {
                    return Number::Integer(0);
                }
                return Number::Integer(if b.to_float() != 0.0 { 1 } else { 0 });
            }
            if *operator == BinaryOp::Or {
                if a.to_float() != 0.0 {
                    return Number::Integer(1);
                }
                return Number::Integer(if b.to_float() != 0.0 { 1 } else { 0 });
            }
            if operator.is_comparison() {
                let af = a.to_float();
                let bf = b.to_float();
                let result = match operator {
                    BinaryOp::Equal => af == bf,
                    BinaryOp::NotEqual => af != bf,
                    BinaryOp::Less => af < bf,
                    BinaryOp::LessEqual => af <= bf,
                    BinaryOp::Greater => af > bf,
                    _ => af >= bf,
                };
                return Number::Integer(i64::from(result));
            }
            if *kind == Integer {
                let ai = a.to_int();
                let bi = b.to_int();
                let result = match operator {
                    BinaryOp::Add => Number::Integer(ai.wrapping_add(bi)),
                    BinaryOp::Subtract => Number::Integer(ai.wrapping_sub(bi)),
                    BinaryOp::Multiply => Number::Integer(ai.wrapping_mul(bi)),
                    BinaryOp::Divide => {
                        if bi == 0 {
                            Number::Integer(0)
                        } else {
                            Number::Integer(ai.wrapping_div(bi))
                        }
                    }
                    BinaryOp::Modulo => {
                        if bi == 0 {
                            Number::Integer(0)
                        } else {
                            // Dart 的 `%` 是欧几里得取模，结果非负。
                            Number::Integer(ai.rem_euclid(bi.abs()))
                        }
                    }
                    _ => Number::Integer(0),
                };
                return result;
            }
            let af = a.to_float();
            let bf = b.to_float();
            match operator {
                BinaryOp::Add => Number::Float(af + bf),
                BinaryOp::Subtract => Number::Float(af - bf),
                BinaryOp::Multiply => Number::Float(af * bf),
                BinaryOp::Divide => {
                    if bf == 0.0 {
                        Number::Float(0.0)
                    } else {
                        Number::Float(af / bf)
                    }
                }
                _ => Number::Float(0.0),
            }
        }
        Expr::Ternary {
            condition,
            when_true,
            when_false,
            ..
        } => {
            let value = evaluate(condition, inputs, variables);
            if value.to_float() != 0.0 {
                evaluate(when_true, inputs, variables)
            } else {
                evaluate(when_false, inputs, variables)
            }
        }
        Expr::Call {
            name,
            arguments,
            kind,
        } => {
            let values: Vec<Number> = arguments
                .iter()
                .map(|argument| evaluate(argument, inputs, variables))
                .collect();
            match name.as_str() {
                "abs" => match kind {
                    Integer => Number::Integer(values[0].to_int().wrapping_abs()),
                    Rational => Number::Float(values[0].to_float().abs()),
                },
                "min" | "max" => {
                    let is_min = name == "min";
                    match kind {
                        Integer => {
                            let mut value = values[0].to_int();
                            for candidate in &values[1..] {
                                let candidate = candidate.to_int();
                                value = if is_min {
                                    value.min(candidate)
                                } else {
                                    value.max(candidate)
                                };
                            }
                            Number::Integer(value)
                        }
                        Rational => {
                            let mut value = values[0].to_float();
                            for candidate in &values[1..] {
                                let candidate = candidate.to_float();
                                value = if is_min {
                                    value.min(candidate)
                                } else {
                                    value.max(candidate)
                                };
                            }
                            Number::Float(value)
                        }
                    }
                }
                "sign" => {
                    let value = values[0].to_float();
                    Number::Integer(if value > 0.0 {
                        1
                    } else if value < 0.0 {
                        -1
                    } else {
                        0
                    })
                }
                "sqrt" => {
                    let value = values[0].to_float();
                    Number::Float(if value <= 0.0 { 0.0 } else { value.sqrt() })
                }
                "atan2" => {
                    let y = values[0].to_float();
                    let x = values[1].to_float();
                    Number::Float(if x == 0.0 && y == 0.0 {
                        0.0
                    } else {
                        y.atan2(x)
                    })
                }
                _ => Number::Integer(0),
            }
        }
    }
}

/// C 代码发射器；`helpers` 记录实际用到的运行时 helper。
pub struct ExpressionEmitter<FI, FV>
where
    FI: Fn(&str) -> String,
    FV: Fn(&str) -> String,
{
    input_code: FI,
    variable_code: FV,
    pub helpers: BTreeSet<&'static str>,
}

impl<FI, FV> ExpressionEmitter<FI, FV>
where
    FI: Fn(&str) -> String,
    FV: Fn(&str) -> String,
{
    pub fn new(input_code: FI, variable_code: FV) -> Self {
        Self {
            input_code,
            variable_code,
            helpers: BTreeSet::new(),
        }
    }

    #[must_use]
    pub fn emit(&mut self, node: &Expr) -> String {
        match node {
            Expr::Literal { kind, value } => match kind {
                ExpressionType::Integer => format!("((int32_t){}L)", value.to_int()),
                ExpressionType::Rational => {
                    format!("((float){})", format_dart_float(value.to_float()))
                }
            },
            Expr::Input(name) => format!("((int32_t)({}))", (self.input_code)(name)),
            Expr::Variable { name, kind } => {
                format!("(({})({}))", kind.c_type(), (self.variable_code)(name))
            }
            Expr::Unary {
                operator,
                operand,
                kind,
            } => {
                let inner = self.emit(operand);
                if *operator == '!' {
                    format!("((int32_t)!({inner}))")
                } else {
                    format!("(-(({}){inner}))", kind.c_type())
                }
            }
            Expr::Binary {
                operator,
                left,
                right,
                kind,
            } => {
                if operator.is_logical() {
                    return format!(
                        "((int32_t)((( {}) != 0) {} (({}) != 0)))",
                        self.emit(left),
                        operator.as_str(),
                        self.emit(right)
                    );
                }
                if operator.is_comparison() {
                    let cast_type = if *kind == ExpressionType::Rational {
                        "float"
                    } else {
                        "int32_t"
                    };
                    return format!(
                        "((int32_t)(({cast_type})({}) {} ({cast_type})({})))",
                        self.emit(left),
                        operator.as_str(),
                        self.emit(right)
                    );
                }
                if *kind == ExpressionType::Integer {
                    let a = format!("((int32_t)({}))", self.emit(left));
                    let b = format!("((int32_t)({}))", self.emit(right));
                    return match operator {
                        BinaryOp::Add => format!("(({a}) + ({b}))"),
                        BinaryOp::Subtract => format!("(({a}) - ({b}))"),
                        BinaryOp::Multiply => format!("(({a}) * ({b}))"),
                        BinaryOp::Divide => self.helper_call("div_i", &format!("{a}, {b}")),
                        BinaryOp::Modulo => self.helper_call("mod_i", &format!("{a}, {b}")),
                        _ => "0".to_owned(),
                    };
                }
                let af = format!("((float)({}))", self.emit(left));
                let bf = format!("((float)({}))", self.emit(right));
                match operator {
                    BinaryOp::Add => format!("(({af}) + ({bf}))"),
                    BinaryOp::Subtract => format!("(({af}) - ({bf}))"),
                    BinaryOp::Multiply => format!("(({af}) * ({bf}))"),
                    BinaryOp::Divide => self.helper_call("div_f", &format!("{af}, {bf}")),
                    _ => "0.0f".to_owned(),
                }
            }
            Expr::Ternary {
                condition,
                when_true,
                when_false,
                kind,
            } => format!(
                "((({}) != 0) ? ({}) : ({}))",
                self.emit(condition),
                self.cast(when_true, *kind),
                self.cast(when_false, *kind)
            ),
            Expr::Call {
                name,
                arguments,
                kind,
            } => self.emit_call(name, arguments, *kind),
        }
    }

    fn cast(&mut self, node: &Expr, target: ExpressionType) -> String {
        let code = self.emit(node);
        if node.kind() == target {
            return code;
        }
        format!("(( {})({code}))", target.c_type())
    }

    fn emit_call(&mut self, name: &str, arguments: &[Expr], kind: ExpressionType) -> String {
        match name {
            "abs" => {
                let arg = self.cast(&arguments[0], kind);
                let helper = if kind == ExpressionType::Integer {
                    "abs_i"
                } else {
                    "abs_f"
                };
                self.helper_call(helper, &arg)
            }
            "min" | "max" => {
                let mut current = self.cast(&arguments[0], kind);
                for argument in &arguments[1..] {
                    let next = self.cast(argument, kind);
                    let helper = if kind == ExpressionType::Integer {
                        if name == "min" { "min_i" } else { "max_i" }
                    } else if name == "min" {
                        "min_f"
                    } else {
                        "max_f"
                    };
                    current = self.helper_call(helper, &format!("{current}, {next}"));
                }
                current
            }
            "sign" => {
                let arg_type = arguments[0].kind();
                let helper = if arg_type == ExpressionType::Integer {
                    "sign_i"
                } else {
                    "sign_f"
                };
                let arg = self.emit(&arguments[0]);
                self.helper_call(helper, &arg)
            }
            "sqrt" => {
                let arg = format!("((float)({}))", self.emit(&arguments[0]));
                self.helper_call("sqrt_f", &arg)
            }
            "atan2" => {
                let y = format!("((float)({}))", self.emit(&arguments[0]));
                let x = format!("((float)({}))", self.emit(&arguments[1]));
                self.helper_call("atan2_f", &format!("{y}, {x}"))
            }
            _ => "0".to_owned(),
        }
    }

    fn helper_call(&mut self, record: &'static str, arguments: &str) -> String {
        self.helpers.insert(record);
        let name = match record {
            "div_i" => "pb_div_i",
            "mod_i" => "pb_mod_i",
            "div_f" => "pb_div_f",
            "abs_i" => "pb_abs_i",
            "abs_f" => "pb_abs_f",
            "min_i" => "pb_min_i",
            "min_f" => "pb_min_f",
            "max_i" => "pb_max_i",
            "max_f" => "pb_max_f",
            "sign_i" => "pb_sign_i",
            "sign_f" => "pb_sign_f",
            "sqrt_f" => "pb_sqrt",
            "atan2_f" => "pb_atan2",
            _ => record,
        };
        format!("{name}({arguments})")
    }
}

/// 生成表达式运行时 helper（仅包含实际用到的部分），保持旧配置输出不变。
#[must_use]
pub fn runtime_code(helpers: &BTreeSet<&str>) -> String {
    const ORDERED: [&str; 16] = [
        "clamp_i",
        "clamp_f",
        "servo_duty",
        "div_i",
        "mod_i",
        "div_f",
        "abs_i",
        "abs_f",
        "min_i",
        "min_f",
        "max_i",
        "max_f",
        "sign_i",
        "sign_f",
        "sqrt_f",
        "atan2_f",
    ];
    let used: Vec<&str> = ORDERED
        .iter()
        .copied()
        .filter(|name| helpers.contains(name))
        .collect();
    if used.is_empty() {
        return String::new();
    }
    let mut output = String::new();
    if helpers.contains("sqrt_f") || helpers.contains("atan2_f") {
        output.push_str(
            "#if defined(__SDCC)\n\
             #include <math.h>\n\
             #define PB_ATAN2 atan2f\n\
             #define PB_SQRT sqrtf\n\
             #else\n\
             #include \"MATH.H\"\n\
             #define PB_ATAN2 atan2\n\
             #define PB_SQRT sqrt\n\
             #endif\n",
        );
    }
    for name in used {
        output.push_str(helper_source(name));
        // Dart 侧每个 helper 用 `writeln` 追加，多出一个换行。
        output.push('\n');
    }
    output
}

fn helper_source(name: &str) -> &'static str {
    match name {
        "clamp_i" => {
            "static int32_t pb_clamp_i(int32_t value, int32_t min, int32_t max)\n{\n    if (value < min) return min;\n    if (value > max) return max;\n    return value;\n}\n"
        }
        "clamp_f" => {
            "static float pb_clamp_f(float value, float min, float max)\n{\n    if (value < min) return min;\n    if (value > max) return max;\n    return value;\n}\n"
        }
        "servo_duty" => {
            "static int pb_servo_duty(float angle)\n{\n    if (angle < -90.0f) angle = -90.0f;\n    if (angle > 90.0f) angle = 90.0f;\n    return (int)(750.0f + angle * 5.5555556f);\n}\n"
        }
        "div_i" => {
            "static int32_t pb_div_i(int32_t a, int32_t b)\n{\n    return b == 0 ? 0 : a / b;\n}\n"
        }
        "mod_i" => {
            "static int32_t pb_mod_i(int32_t a, int32_t b)\n{\n    return b == 0 ? 0 : a % b;\n}\n"
        }
        "div_f" => {
            "static float pb_div_f(float a, float b)\n{\n    return b == 0.0f ? 0.0f : a / b;\n}\n"
        }
        "abs_i" => {
            "static int32_t pb_abs_i(int32_t value)\n{\n    return value < 0 ? -value : value;\n}\n"
        }
        "abs_f" => {
            "static float pb_abs_f(float value)\n{\n    return value < 0.0f ? -value : value;\n}\n"
        }
        "min_i" => {
            "static int32_t pb_min_i(int32_t a, int32_t b)\n{\n    return a < b ? a : b;\n}\n"
        }
        "min_f" => "static float pb_min_f(float a, float b)\n{\n    return a < b ? a : b;\n}\n",
        "max_i" => {
            "static int32_t pb_max_i(int32_t a, int32_t b)\n{\n    return a > b ? a : b;\n}\n"
        }
        "max_f" => "static float pb_max_f(float a, float b)\n{\n    return a > b ? a : b;\n}\n",
        "sign_i" => {
            "static int32_t pb_sign_i(int32_t value)\n{\n    return value > 0 ? 1 : (value < 0 ? -1 : 0);\n}\n"
        }
        "sign_f" => {
            "static int32_t pb_sign_f(float value)\n{\n    return value > 0.0f ? 1 : (value < 0.0f ? -1 : 0);\n}\n"
        }
        "sqrt_f" => {
            "static float pb_sqrt(float value)\n{\n    return value <= 0.0f ? 0.0f : (float)PB_SQRT(value);\n}\n"
        }
        "atan2_f" => {
            "static float pb_atan2(float y, float x)\n{\n    if (x == 0.0f && y == 0.0f) return 0.0f;\n    return (float)PB_ATAN2(y, x);\n}\n"
        }
        _ => "",
    }
}

/// 单个模式表达式试算的结果行。
#[derive(Debug, Clone, PartialEq)]
pub struct EngineerPreviewRow {
    pub label: String,
    pub field_path: String,
    pub value: Option<Number>,
    pub error: Option<String>,
}

/// 模式试算结果：最终变量与逐行结果（顺序与动作行一致）。
#[derive(Debug, Clone, PartialEq)]
pub struct EngineerPreviewResult {
    pub variables: BTreeMap<String, Number>,
    pub rows: Vec<EngineerPreviewRow>,
}

/// 按模式顺序试算变量/表达式行；远程输入按别名取值，未提供的按 0。
#[must_use]
pub fn evaluate_mode(
    config: &EngineerConfig,
    mode_index: usize,
    inputs: &BTreeMap<String, Number>,
) -> EngineerPreviewResult {
    let mut rows = Vec::new();
    let mut variables: BTreeMap<String, Number> = BTreeMap::new();
    let Some(mode) = config.modes.get(mode_index) else {
        return EngineerPreviewResult { variables, rows };
    };
    let counts = variable_mode_counts(config);
    for action in &mode.actions {
        if action.output_kind == ActionOutputKind::Pin {
            continue;
        }
        let name = action.variable_name.as_deref().unwrap_or("");
        if !name.is_empty() && counts.get(name).is_some_and(|modes| modes.len() >= 2) {
            variables.insert(name.to_owned(), Number::Integer(0));
        }
    }
    let variable_types = variable_types(config, &variables);
    for (index, action) in mode.actions.iter().enumerate() {
        let field_path = format!("modes.{mode_index}.actions.{index}");
        let label = format!("第 {} 行", index + 1);
        if action.input_kind == ActionInputKind::Unspecified {
            let parsed = parse(action.expression.as_deref().unwrap_or(""), &variable_types);
            if !parsed.is_ok() {
                if let Some(error) = parsed.diagnostics.first() {
                    rows.push(EngineerPreviewRow {
                        label,
                        field_path: format!("{field_path}.expression"),
                        value: None,
                        error: Some(error.message.clone()),
                    });
                    continue;
                }
            }
            let Some(root) = parsed.root else {
                continue;
            };
            let value = evaluate(&root, inputs, &variables);
            if action.output_kind != ActionOutputKind::Pin {
                let name = action.variable_name.as_deref().unwrap_or("");
                variables.insert(name.to_owned(), value);
            }
            rows.push(EngineerPreviewRow {
                label,
                field_path: if action.output_kind == ActionOutputKind::Pin {
                    format!("{field_path}.expression")
                } else {
                    format!("{field_path}.variable")
                },
                value: Some(value),
                error: None,
            });
        } else if action.output_kind != ActionOutputKind::Pin {
            let alias = action.key.as_deref().and_then(alias_of_remote_key);
            let value = alias
                .and_then(|alias| inputs.get(alias))
                .copied()
                .unwrap_or(Number::Integer(0));
            let name = action.variable_name.as_deref().unwrap_or("");
            variables.insert(name.to_owned(), value);
            rows.push(EngineerPreviewRow {
                label,
                field_path: format!("{field_path}.variable"),
                value: Some(value),
                error: None,
            });
        }
    }
    EngineerPreviewResult { variables, rows }
}

fn variable_mode_counts(config: &EngineerConfig) -> BTreeMap<String, BTreeSet<usize>> {
    let mut counts: BTreeMap<String, BTreeSet<usize>> = BTreeMap::new();
    for (mode_index, mode) in config.modes.iter().enumerate() {
        for action in &mode.actions {
            if action.output_kind == ActionOutputKind::Pin {
                continue;
            }
            let name = action.variable_name.as_deref().unwrap_or("");
            if name.is_empty() {
                continue;
            }
            counts
                .entry(name.to_owned())
                .or_default()
                .insert(mode_index);
        }
    }
    counts
}

fn variable_types(
    config: &EngineerConfig,
    available: &BTreeMap<String, Number>,
) -> BTreeMap<String, ExpressionType> {
    let mut result = BTreeMap::new();
    for mode in &config.modes {
        for action in &mode.actions {
            if action.output_kind == ActionOutputKind::Pin {
                continue;
            }
            let name = action.variable_name.as_deref().unwrap_or("");
            if name.is_empty() || !available.contains_key(name) {
                continue;
            }
            result.insert(
                name.to_owned(),
                if action.output_kind == ActionOutputKind::Integer {
                    ExpressionType::Integer
                } else {
                    ExpressionType::Rational
                },
            );
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_ok(source: &str) -> Expr {
        let parsed = parse(source, &BTreeMap::new());
        assert!(parsed.is_ok(), "{source}: {:?}", parsed.diagnostics);
        parsed.root.expect("root")
    }

    #[test]
    fn basic_parsing_and_types() {
        assert_eq!(parse_ok("1 + 2").kind(), ExpressionType::Integer);
        assert_eq!(parse_ok("1 + 2.5").kind(), ExpressionType::Rational);
        assert_eq!(parse_ok("LX > 100").kind(), ExpressionType::Integer);
        assert_eq!(parse_ok("min(LX, LY)").kind(), ExpressionType::Integer);
        assert_eq!(parse_ok("sqrt(LX)").kind(), ExpressionType::Rational);
        assert_eq!(parse_ok("PI").kind(), ExpressionType::Rational);
    }

    #[test]
    fn diagnostics_match_dart() {
        let parsed = parse("", &BTreeMap::new());
        assert_eq!(parsed.diagnostics[0].message, "表达式不能为空");
        let parsed = parse("1 +", &BTreeMap::new());
        assert_eq!(parsed.diagnostics[0].message, "表达式不完整");
        let parsed = parse("foo + 1", &BTreeMap::new());
        assert_eq!(parsed.diagnostics[0].message, "未定义变量 \"foo\"");
        let parsed = parse("1/0", &BTreeMap::new());
        assert_eq!(parsed.diagnostics[0].message, "除法 的除数不能为 0");
        let parsed = parse("%", &BTreeMap::new());
        assert_eq!(parsed.diagnostics[0].message, "无法识别的字符 \"%\"");
    }

    #[test]
    fn evaluation_semantics() {
        let node = parse_ok("-7 % 3");
        assert_eq!(
            evaluate(&node, &BTreeMap::new(), &BTreeMap::new()),
            Number::Integer(2)
        );
        let mut scope = BTreeMap::new();
        scope.insert("a".to_owned(), ExpressionType::Integer);
        scope.insert("b".to_owned(), ExpressionType::Integer);
        let parsed = parse("a / b", &scope);
        assert!(parsed.is_ok());
        let mut values = BTreeMap::new();
        values.insert("a".to_owned(), Number::Integer(1));
        values.insert("b".to_owned(), Number::Integer(0));
        assert_eq!(
            evaluate(&parsed.root.unwrap(), &BTreeMap::new(), &values),
            Number::Integer(0)
        );
        let node = parse_ok("sqrt(LX - 200)");
        let mut sqrt_inputs = BTreeMap::new();
        sqrt_inputs.insert("LX".to_owned(), Number::Integer(1));
        assert!(matches!(
            evaluate(&node, &sqrt_inputs, &BTreeMap::new()),
            Number::Float(value) if value == 0.0
        ));
    }

    #[test]
    fn variable_names_follow_dart_rules() {
        assert!(is_valid_variable_name("speed1"));
        assert!(is_valid_variable_name("a"));
        assert!(!is_valid_variable_name("_x"));
        assert!(!is_valid_variable_name("1x"));
        assert!(!is_valid_variable_name("LX"));
        assert!(!is_valid_variable_name("int"));
        assert!(!is_valid_variable_name("abcdefghijklmnopqrstuvwxy"));
    }
}
