import 'dart:math' as math;

/// 表达式的值类型。整数按 C 的 `int32_t` 语义，有理数按 `float` 语义。
enum ExpressionType { integer, rational }

extension ExpressionTypeC on ExpressionType {
  String get cType => this == ExpressionType.integer ? 'int32_t' : 'float';
}

/// 表达式解析/类型检查诊断。`offset` 是原字符串中的字符偏移，便于 UI 标记。
class ExpressionDiagnostic {
  const ExpressionDiagnostic(this.message, this.offset);
  final String message;
  final int offset;
}

/// 表达式输入别名：遥控器轴与按键在表达式里的只读名字。
const expressionAxisInputs = ['LX', 'LY', 'RX', 'RY'];
const expressionButtonInputs = [
  'UP',
  'DOWN',
  'LEFT',
  'RIGHT',
  'A',
  'B',
  'C',
  'D',
  'E',
  'LC',
  'RC',
];
const expressionBuiltinInputs = [
  ...expressionAxisInputs,
  ...expressionButtonInputs,
];

/// 表达式别名到 `.pieproj` 遥控器输入的映射。
const expressionInputAliases = <String, String>{
  'LX': 'LX',
  'LY': 'LY',
  'RX': 'RX',
  'RY': 'RY',
  'UP': '↑',
  'DOWN': '↓',
  'LEFT': '←',
  'RIGHT': '→',
  'A': 'A',
  'B': 'B',
  'C': 'C',
  'D': 'D',
  'E': 'E',
  'LC': 'LC',
  'RC': 'RC',
};

/// 允许的数学常量。
const expressionConstants = <String, double>{'PI': math.pi, 'E': math.e};

/// 允许的函数及参数个数/返回类型规则。
enum _FunctionKind { abs, min, max, sign, sqrt, atan2 }

const _functionKinds = <String, _FunctionKind>{
  'abs': _FunctionKind.abs,
  'min': _FunctionKind.min,
  'max': _FunctionKind.max,
  'sign': _FunctionKind.sign,
  'sqrt': _FunctionKind.sqrt,
  'atan2': _FunctionKind.atan2,
};

const _functionArity = <String, ({int min, int max})>{
  'abs': (min: 1, max: 1),
  'min': (min: 2, max: 64),
  'max': (min: 2, max: 64),
  'sign': (min: 1, max: 1),
  'sqrt': (min: 1, max: 1),
  'atan2': (min: 2, max: 2),
};

/// 变量名不允许与内置输入、常量、函数、C 关键字冲突。
final expressionReservedNames = <String>{
  ...expressionBuiltinInputs,
  ...expressionConstants.keys,
  ..._functionKinds.keys,
  'int',
  'float',
  'long',
  'char',
  'void',
  'return',
  'if',
  'else',
  'for',
  'while',
  'switch',
  'case',
  'do',
  'break',
  'continue',
  'static',
  'const',
  'signed',
  'unsigned',
  'short',
  'struct',
  'typedef',
  'union',
  'enum',
  'sizeof',
  'main',
  'true',
  'false',
};

final _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// 用户输入的变量名是否合法（语法 + 保留字层面；作用域唯一性由校验器负责）。
bool isValidVariableName(String name) =>
    _identifierPattern.hasMatch(name) &&
    !expressionReservedNames.contains(name) &&
    !name.startsWith('_') &&
    name.length <= 24;

sealed class ExpressionNode {
  const ExpressionNode(this.type);
  final ExpressionType type;
}

final class ExpressionLiteral extends ExpressionNode {
  const ExpressionLiteral(super.type, this.value);
  final num value;
}

final class ExpressionInput extends ExpressionNode {
  const ExpressionInput(this.name) : super(ExpressionType.integer);
  final String name;
}

final class ExpressionVariable extends ExpressionNode {
  const ExpressionVariable(this.name, super.type);
  final String name;
}

final class ExpressionUnary extends ExpressionNode {
  const ExpressionUnary(this.operator, this.operand, super.type);
  final String operator;
  final ExpressionNode operand;
}

final class ExpressionBinary extends ExpressionNode {
  const ExpressionBinary(this.operator, this.left, this.right, super.type);
  final String operator;
  final ExpressionNode left;
  final ExpressionNode right;
}

final class ExpressionTernary extends ExpressionNode {
  const ExpressionTernary(
    this.condition,
    this.whenTrue,
    this.whenFalse,
    super.type,
  );
  final ExpressionNode condition;
  final ExpressionNode whenTrue;
  final ExpressionNode whenFalse;
}

final class ExpressionCall extends ExpressionNode {
  const ExpressionCall(this.name, this.arguments, super.type);
  final String name;
  final List<ExpressionNode> arguments;
}

class ParsedExpression {
  const ParsedExpression(this.root, this.diagnostics);
  final ExpressionNode? root;
  final List<ExpressionDiagnostic> diagnostics;
  bool get ok => root != null && diagnostics.isEmpty;
}

class _SyntaxError implements Exception {
  _SyntaxError(this.message, this.offset);
  final String message;
  final int offset;
}

abstract final class ExpressionParser {
  /// 解析单条表达式。`variables` 提供当前作用域内的变量及类型。
  static ParsedExpression parse(
    String source, {
    Map<String, ExpressionType> variables = const {},
  }) {
    final parser = _Parser(source, variables);
    try {
      return ParsedExpression(parser.parseTop(), const []);
    } on _SyntaxError catch (error) {
      return ParsedExpression(null, [
        ExpressionDiagnostic(error.message, error.offset),
      ]);
    }
  }
}

class _Parser {
  _Parser(this.source, this.variables);
  final String source;
  final Map<String, ExpressionType> variables;
  int index = 0;

  bool get atEnd => index >= source.length;

  String get _peek => atEnd ? '' : source[index];

  void _skipWhitespace() {
    while (!atEnd) {
      final code = source.codeUnitAt(index);
      if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
        index++;
      } else {
        break;
      }
    }
  }

  bool _match(String token) {
    _skipWhitespace();
    if (source.startsWith(token, index)) {
      index += token.length;
      return true;
    }
    return false;
  }

  void _expect(String token) {
    if (!_match(token)) {
      _fail('缺少 "$token"');
    }
  }

  Never _fail(String message) {
    throw _SyntaxError(message, index);
  }

  ExpressionNode parseTop() {
    _skipWhitespace();
    if (atEnd) _fail('表达式不能为空');
    final node = _parseTernary();
    _skipWhitespace();
    if (!atEnd) _fail('表达式末尾有多余字符');
    return node;
  }

  ExpressionNode _parseTernary() {
    final condition = _parseLogicalOr();
    if (!_match('?')) return condition;
    final whenTrue = _parseTernary();
    _expect(':');
    final whenFalse = _parseTernary();
    final type = _unify(whenTrue.type, whenFalse.type);
    return ExpressionTernary(condition, whenTrue, whenFalse, type);
  }

  ExpressionNode _parseLogicalOr() {
    var left = _parseLogicalAnd();
    while (_match('||')) {
      final right = _parseLogicalAnd();
      left = ExpressionBinary('||', left, right, ExpressionType.integer);
    }
    return left;
  }

  ExpressionNode _parseLogicalAnd() {
    var left = _parseEquality();
    while (_match('&&')) {
      final right = _parseEquality();
      left = ExpressionBinary('&&', left, right, ExpressionType.integer);
    }
    return left;
  }

  ExpressionNode _parseEquality() {
    var left = _parseRelational();
    while (true) {
      if (_match('==')) {
        left = ExpressionBinary(
          '==',
          left,
          _parseRelational(),
          ExpressionType.integer,
        );
      } else if (_match('!=')) {
        left = ExpressionBinary(
          '!=',
          left,
          _parseRelational(),
          ExpressionType.integer,
        );
      } else {
        return left;
      }
    }
  }

  ExpressionNode _parseRelational() {
    var left = _parseAdditive();
    while (true) {
      if (_match('<=')) {
        left = ExpressionBinary(
          '<=',
          left,
          _parseAdditive(),
          ExpressionType.integer,
        );
      } else if (_match('>=')) {
        left = ExpressionBinary(
          '>=',
          left,
          _parseAdditive(),
          ExpressionType.integer,
        );
      } else if (_match('<')) {
        left = ExpressionBinary(
          '<',
          left,
          _parseAdditive(),
          ExpressionType.integer,
        );
      } else if (_match('>')) {
        left = ExpressionBinary(
          '>',
          left,
          _parseAdditive(),
          ExpressionType.integer,
        );
      } else {
        return left;
      }
    }
  }

  ExpressionNode _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      if (_match('+')) {
        final right = _parseMultiplicative();
        left = ExpressionBinary(
          '+',
          left,
          right,
          _unify(left.type, right.type),
        );
      } else if (_match('-')) {
        final right = _parseMultiplicative();
        left = ExpressionBinary(
          '-',
          left,
          right,
          _unify(left.type, right.type),
        );
      } else {
        return left;
      }
    }
  }

  ExpressionNode _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      if (_match('*')) {
        final right = _parseUnary();
        left = ExpressionBinary(
          '*',
          left,
          right,
          _unify(left.type, right.type),
        );
      } else if (_match('/')) {
        final right = _parseUnary();
        _checkConstantDivisor(right, '除法');
        left = ExpressionBinary(
          '/',
          left,
          right,
          _unify(left.type, right.type),
        );
      } else if (_match('%')) {
        final right = _parseUnary();
        if (left.type != ExpressionType.integer ||
            right.type != ExpressionType.integer) {
          _fail('取模运算只支持整数');
        }
        _checkConstantDivisor(right, '取模');
        left = ExpressionBinary('%', left, right, ExpressionType.integer);
      } else {
        return left;
      }
    }
  }

  ExpressionNode _parseUnary() {
    if (_match('-')) {
      final operand = _parseUnary();
      return ExpressionUnary('-', operand, operand.type);
    }
    if (_match('!')) {
      final operand = _parseUnary();
      return ExpressionUnary('!', operand, ExpressionType.integer);
    }
    if (_match('+')) return _parseUnary();
    return _parsePrimary();
  }

  ExpressionNode _parsePrimary() {
    _skipWhitespace();
    if (atEnd) _fail('表达式不完整');
    if (_peek == '(') {
      index++;
      final node = _parseTernary();
      _expect(')');
      return node;
    }
    final code = source.codeUnitAt(index);
    if ((code >= 0x30 && code <= 0x39) || _peek == '.') {
      return _parseNumber();
    }
    if (_isIdentifierStart(code)) {
      final name = _parseIdentifier();
      _skipWhitespace();
      if (_match('(')) {
        return _parseCall(name);
      }
      if (expressionConstants.containsKey(name)) {
        return ExpressionLiteral(
          ExpressionType.rational,
          expressionConstants[name]!,
        );
      }
      if (expressionBuiltinInputs.contains(name)) {
        return ExpressionInput(name);
      }
      final declared = variables[name];
      if (declared != null) return ExpressionVariable(name, declared);
      _fail('未定义变量 "$name"');
    }
    _fail('无法识别的字符 "${source[index]}"');
  }

  ExpressionNode _parseNumber() {
    _skipWhitespace();
    final start = index;
    var seenDot = false;
    var seenExponent = false;
    while (!atEnd) {
      final code = source.codeUnitAt(index);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isDigit) {
        index++;
      } else if (code == 0x2E && !seenDot && !seenExponent) {
        seenDot = true;
        index++;
      } else if ((code == 0x65 || code == 0x45) && !seenExponent) {
        seenExponent = true;
        index++;
        if (!atEnd && (source[index] == '+' || source[index] == '-')) {
          index++;
        }
      } else {
        break;
      }
    }
    final text = source.substring(start, index);
    if (text.isEmpty || text == '.') _fail('数字格式不正确');
    if (seenDot || seenExponent) {
      final value = double.tryParse(text);
      if (value == null || !value.isFinite) _fail('数字格式不正确');
      return ExpressionLiteral(ExpressionType.rational, value);
    }
    final value = int.tryParse(text);
    if (value == null) _fail('整数超出范围');
    if (value > 0x7FFFFFFF || value < -0x80000000) {
      _fail('整数超出 int32 范围');
    }
    return ExpressionLiteral(ExpressionType.integer, value);
  }

  String _parseIdentifier() {
    final start = index;
    index++;
    while (!atEnd && _isIdentifierPart(source.codeUnitAt(index))) {
      index++;
    }
    return source.substring(start, index);
  }

  ExpressionNode _parseCall(String name) {
    final kind = _functionKinds[name];
    if (kind == null) _fail('不支持的函数 "$name"');
    final arguments = <ExpressionNode>[];
    _skipWhitespace();
    if (!_match(')')) {
      while (true) {
        arguments.add(_parseTernary());
        if (_match(')')) break;
        _expect(',');
      }
    }
    final arity = _functionArity[name]!;
    if (arguments.length < arity.min || arguments.length > arity.max) {
      _fail(
        '函数 $name 需要 ${arity.min == arity.max ? arity.min : '${arity.min}–${arity.max}'} 个参数',
      );
    }
    final resultType = switch (kind) {
      _FunctionKind.abs => arguments.first.type,
      _FunctionKind.min ||
      _FunctionKind.max => arguments.map((node) => node.type).reduce(_unify),
      _FunctionKind.sign => ExpressionType.integer,
      _FunctionKind.sqrt => ExpressionType.rational,
      _FunctionKind.atan2 => ExpressionType.rational,
    };
    if (kind == _FunctionKind.sqrt &&
        (_constantValue(arguments.first) ?? 0) < 0) {
      _fail('sqrt 的参数不能为负数');
    }
    return ExpressionCall(name, List.unmodifiable(arguments), resultType);
  }

  void _checkConstantDivisor(ExpressionNode divisor, String label) {
    if (_constantValue(divisor) == 0) _fail('$label 的除数不能为 0');
  }

  num? _constantValue(ExpressionNode node) {
    if (node is ExpressionLiteral) return node.value;
    if (node is ExpressionUnary && node.operator == '-') {
      final value = _constantValue(node.operand);
      return value == null ? null : -value;
    }
    return null;
  }

  static bool _isIdentifierStart(int code) =>
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F;

  static bool _isIdentifierPart(int code) =>
      _isIdentifierStart(code) || (code >= 0x30 && code <= 0x39);

  static ExpressionType _unify(ExpressionType a, ExpressionType b) =>
      a == ExpressionType.rational || b == ExpressionType.rational
      ? ExpressionType.rational
      : ExpressionType.integer;
}

abstract final class ExpressionEvaluator {
  /// 供 UI 试算与单元测试使用；语义与生成的 C 保持一致（除零→0、负数开方→0）。
  static num evaluate(
    ExpressionNode node, {
    Map<String, num> inputs = const {},
    Map<String, num> variables = const {},
  }) {
    switch (node) {
      case ExpressionLiteral(:final value):
        return value;
      case ExpressionInput(:final name):
        return inputs[name] ?? 0;
      case ExpressionVariable(:final name):
        return variables[name] ?? 0;
      case ExpressionUnary(:final operator, :final operand):
        final value = evaluate(operand, inputs: inputs, variables: variables);
        if (operator == '!') return value == 0 ? 1 : 0;
        return node.type == ExpressionType.integer
            ? -value.toInt()
            : -value.toDouble();
      case ExpressionBinary(:final operator, :final left, :final right):
        final a = evaluate(left, inputs: inputs, variables: variables);
        final b = evaluate(right, inputs: inputs, variables: variables);
        if (operator == '&&') {
          if (a == 0) return 0;
          return b != 0 ? 1 : 0;
        }
        if (operator == '||') {
          if (a != 0) return 1;
          return b != 0 ? 1 : 0;
        }
        if (const {'==', '!=', '<', '<=', '>', '>='}.contains(operator)) {
          final result = switch (operator) {
            '==' => a == b,
            '!=' => a != b,
            '<' => a < b,
            '<=' => a <= b,
            '>' => a > b,
            _ => a >= b,
          };
          return result ? 1 : 0;
        }
        if (node.type == ExpressionType.integer) {
          final ai = a.toInt(), bi = b.toInt();
          return switch (operator) {
            '+' => ai + bi,
            '-' => ai - bi,
            '*' => ai * bi,
            '/' => bi == 0 ? 0 : ai ~/ bi,
            '%' => bi == 0 ? 0 : ai % bi,
            _ => 0,
          };
        }
        final af = a.toDouble(), bf = b.toDouble();
        return switch (operator) {
          '+' => af + bf,
          '-' => af - bf,
          '*' => af * bf,
          '/' => bf == 0 ? 0.0 : af / bf,
          _ => 0.0,
        };
      case ExpressionTernary(
        :final condition,
        :final whenTrue,
        :final whenFalse,
      ):
        final value = evaluate(condition, inputs: inputs, variables: variables);
        return evaluate(
          value != 0 ? whenTrue : whenFalse,
          inputs: inputs,
          variables: variables,
        );
      case ExpressionCall(:final name, :final arguments):
        final values = [
          for (final argument in arguments)
            evaluate(argument, inputs: inputs, variables: variables),
        ];
        return switch (name) {
          'abs' =>
            node.type == ExpressionType.integer
                ? values[0].toInt().abs()
                : values[0].toDouble().abs(),
          'min' => _evaluateMinMax(values, node.type, min: true),
          'max' => _evaluateMinMax(values, node.type, min: false),
          'sign' => values[0] > 0 ? 1 : (values[0] < 0 ? -1 : 0),
          'sqrt' =>
            values[0].toDouble() <= 0 ? 0.0 : math.sqrt(values[0].toDouble()),
          'atan2' =>
            values[0] == 0 && values[1] == 0
                ? 0.0
                : math.atan2(values[0].toDouble(), values[1].toDouble()),
          _ => 0,
        };
    }
  }

  static num _evaluateMinMax(
    List<num> values,
    ExpressionType type, {
    required bool min,
  }) {
    if (type == ExpressionType.integer) {
      final ints = values.map((value) => value.toInt()).toList();
      return min ? ints.reduce(math.min) : ints.reduce(math.max);
    }
    final doubles = values.map((value) => value.toDouble()).toList();
    return min ? doubles.reduce(math.min) : doubles.reduce(math.max);
  }
}

class ExpressionEmitter {
  ExpressionEmitter({required this.inputCode, required this.variableCode});
  final String Function(String name) inputCode;
  final String Function(String name) variableCode;
  final Set<String> helpers = {};

  String emit(ExpressionNode node) => _emit(node);

  String emitCast(ExpressionNode node, ExpressionType target) =>
      _cast(node, target);

  String _cast(ExpressionNode node, ExpressionType target) {
    final code = _emit(node);
    if (node.type == target) return code;
    return '(( ${target.cType})($code))';
  }

  String _emit(ExpressionNode node) {
    switch (node) {
      case ExpressionLiteral(:final type, :final value):
        if (type == ExpressionType.integer) {
          return '((int32_t)${value.toInt()}L)';
        }
        return '((float)${_formatFloat(value.toDouble())})';
      case ExpressionInput(:final name):
        return '((int32_t)(${inputCode(name)}))';
      case ExpressionVariable(:final name, :final type):
        return '((${type.cType})(${variableCode(name)}))';
      case ExpressionUnary(:final operator, :final operand, :final type):
        if (operator == '!') {
          return '((int32_t)!(${_emit(operand)}))';
        }
        return '(${type.cType == 'int32_t' ? '-((int32_t)' : '-((float)'}${_emit(operand)}))';
      case ExpressionBinary(
        :final operator,
        :final left,
        :final right,
        :final type,
      ):
        if (operator == '&&' || operator == '||') {
          return '((int32_t)((( ${_emit(left)}) != 0) $operator ((${_emit(right)}) != 0)))';
        }
        if (const {'==', '!=', '<', '<=', '>', '>='}.contains(operator)) {
          final castType = type == ExpressionType.rational
              ? 'float'
              : 'int32_t';
          return '((int32_t)(($castType)(${_emit(left)}) $operator ($castType)(${_emit(right)})))';
        }
        if (type == ExpressionType.integer) {
          final a = '((int32_t)(${_emit(left)}))';
          final b = '((int32_t)(${_emit(right)}))';
          return switch (operator) {
            '+' => '(($a) + ($b))',
            '-' => '(($a) - ($b))',
            '*' => '(($a) * ($b))',
            '/' => _helperCall('div_i', '$a, $b', record: 'div_i'),
            '%' => _helperCall('mod_i', '$a, $b', record: 'mod_i'),
            _ => '0',
          };
        }
        final af = '((float)(${_emit(left)}))';
        final bf = '((float)(${_emit(right)}))';
        return switch (operator) {
          '+' => '(($af) + ($bf))',
          '-' => '(($af) - ($bf))',
          '*' => '(($af) * ($bf))',
          '/' => _helperCall('div_f', '$af, $bf', record: 'div_f'),
          _ => '0.0f',
        };
      case ExpressionTernary(
        :final condition,
        :final whenTrue,
        :final whenFalse,
        :final type,
      ):
        return '(((${_emit(condition)}) != 0) ? (${_cast(whenTrue, type)}) : (${_cast(whenFalse, type)}))';
      case ExpressionCall(:final name, :final arguments, :final type):
        return _emitCall(name, arguments, type);
    }
  }

  String _emitCall(
    String name,
    List<ExpressionNode> arguments,
    ExpressionType type,
  ) {
    switch (name) {
      case 'abs':
        final arg = _cast(arguments.first, type);
        return _helperCall(
          type == ExpressionType.integer ? 'abs_i' : 'abs_f',
          arg,
          record: type == ExpressionType.integer ? 'abs_i' : 'abs_f',
        );
      case 'min' || 'max':
        var current = _cast(arguments.first, type);
        var index = 1;
        while (index < arguments.length) {
          final next = _cast(arguments[index], type);
          current = _helperCall(
            type == ExpressionType.integer ? '${name}_i' : '${name}_f',
            '$current, $next',
            record: type == ExpressionType.integer ? '${name}_i' : '${name}_f',
          );
          index++;
        }
        return current;
      case 'sign':
        final argType = arguments.first.type;
        return _helperCall(
          argType == ExpressionType.integer ? 'sign_i' : 'sign_f',
          _emit(arguments.first),
          record: argType == ExpressionType.integer ? 'sign_i' : 'sign_f',
        );
      case 'sqrt':
        return _helperCall(
          'sqrt_f',
          '((float)(${_emit(arguments.first)}))',
          record: 'sqrt_f',
        );
      case 'atan2':
        return _helperCall(
          'atan2_f',
          '((float)(${_emit(arguments.first)})), ((float)(${_emit(arguments[1])}))',
          record: 'atan2_f',
        );
      default:
        return '0';
    }
  }

  String _helperCall(String name, String arguments, {required String record}) {
    helpers.add(record);
    final helperName = switch (record) {
      'div_i' => 'pb_div_i',
      'mod_i' => 'pb_mod_i',
      'div_f' => 'pb_div_f',
      'abs_i' => 'pb_abs_i',
      'abs_f' => 'pb_abs_f',
      'min_i' => 'pb_min_i',
      'min_f' => 'pb_min_f',
      'max_i' => 'pb_max_i',
      'max_f' => 'pb_max_f',
      'sign_i' => 'pb_sign_i',
      'sign_f' => 'pb_sign_f',
      'sqrt_f' => 'pb_sqrt',
      'atan2_f' => 'pb_atan2',
      _ => 'pb_$name',
    };
    return '$helperName($arguments)';
  }

  static String _formatFloat(double value) {
    final text = value.toString();
    if (text.contains('e') || text.contains('E')) return text;
    if (text.contains('.')) return text;
    return '$text.0';
  }
}

/// 生成表达式运行时 helper（仅包含实际用到的部分），保持旧配置输出不变。
abstract final class ExpressionRuntime {
  static const _orderedHelpers = [
    'clamp_i',
    'clamp_f',
    'servo_duty',
    'div_i',
    'mod_i',
    'div_f',
    'abs_i',
    'abs_f',
    'min_i',
    'min_f',
    'max_i',
    'max_f',
    'sign_i',
    'sign_f',
    'sqrt_f',
    'atan2_f',
  ];

  static String code(Set<String> helpers) {
    final used = [
      for (final name in _orderedHelpers)
        if (helpers.contains(name)) name,
    ];
    if (used.isEmpty) return '';
    final usesMath = helpers.contains('sqrt_f') || helpers.contains('atan2_f');
    final buffer = StringBuffer();
    if (usesMath) {
      buffer
        ..writeln('#if defined(__SDCC)')
        ..writeln('#include <math.h>')
        ..writeln('#define PB_ATAN2 atan2f')
        ..writeln('#define PB_SQRT sqrtf')
        ..writeln('#else')
        ..writeln('#include "MATH.H"')
        ..writeln('#define PB_ATAN2 atan2')
        ..writeln('#define PB_SQRT sqrt')
        ..writeln('#endif');
    }
    for (final name in used) {
      buffer.writeln(_helperSource(name));
    }
    return buffer.toString();
  }

  static String _helperSource(String name) => switch (name) {
    'clamp_i' =>
      '''static int32_t pb_clamp_i(int32_t value, int32_t min, int32_t max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
''',
    'clamp_f' =>
      '''static float pb_clamp_f(float value, float min, float max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
''',
    'servo_duty' =>
      '''static int pb_servo_duty(float angle)
{
    if (angle < -90.0f) angle = -90.0f;
    if (angle > 90.0f) angle = 90.0f;
    return (int)(750.0f + angle * 5.5555556f);
}
''',
    'div_i' =>
      '''static int32_t pb_div_i(int32_t a, int32_t b)
{
    return b == 0 ? 0 : a / b;
}
''',
    'mod_i' =>
      '''static int32_t pb_mod_i(int32_t a, int32_t b)
{
    return b == 0 ? 0 : a % b;
}
''',
    'div_f' =>
      '''static float pb_div_f(float a, float b)
{
    return b == 0.0f ? 0.0f : a / b;
}
''',
    'abs_i' =>
      '''static int32_t pb_abs_i(int32_t value)
{
    return value < 0 ? -value : value;
}
''',
    'abs_f' =>
      '''static float pb_abs_f(float value)
{
    return value < 0.0f ? -value : value;
}
''',
    'min_i' =>
      '''static int32_t pb_min_i(int32_t a, int32_t b)
{
    return a < b ? a : b;
}
''',
    'min_f' =>
      '''static float pb_min_f(float a, float b)
{
    return a < b ? a : b;
}
''',
    'max_i' =>
      '''static int32_t pb_max_i(int32_t a, int32_t b)
{
    return a > b ? a : b;
}
''',
    'max_f' =>
      '''static float pb_max_f(float a, float b)
{
    return a > b ? a : b;
}
''',
    'sign_i' =>
      '''static int32_t pb_sign_i(int32_t value)
{
    return value > 0 ? 1 : (value < 0 ? -1 : 0);
}
''',
    'sign_f' =>
      '''static int32_t pb_sign_f(float value)
{
    return value > 0.0f ? 1 : (value < 0.0f ? -1 : 0);
}
''',
    'sqrt_f' =>
      '''static float pb_sqrt(float value)
{
    return value <= 0.0f ? 0.0f : (float)PB_SQRT(value);
}
''',
    'atan2_f' =>
      '''static float pb_atan2(float y, float x)
{
    if (x == 0.0f && y == 0.0f) return 0.0f;
    return (float)PB_ATAN2(y, x);
}
''',
    _ => '',
  };
}
