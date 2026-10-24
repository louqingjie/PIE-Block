import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

void main() {
  group('表达式解析与类型', () {
    ExpressionNode parse(
      String source, {
      Map<String, ExpressionType> variables = const {},
    }) {
      final result = ExpressionParser.parse(source, variables: variables);
      expect(result.diagnostics, isEmpty, reason: source);
      return result.root!;
    }

    test('优先级与类型推断', () {
      expect(parse('1 + 2 * 3').type, ExpressionType.integer);
      expect(parse('1 + 2.0').type, ExpressionType.rational);
      expect(parse('LX > 0 ? 1 : 2').type, ExpressionType.integer);
      expect(parse('LX > 0 ? 1 : 2.0').type, ExpressionType.rational);
      expect(parse('sqrt(4)').type, ExpressionType.rational);
      expect(parse('min(1, 2, 3)').type, ExpressionType.integer);
      expect(parse('min(1, 2.0)').type, ExpressionType.rational);
      expect(parse('sign(RX)').type, ExpressionType.integer);
      expect(
        parse('abs(x)', variables: {'x': ExpressionType.rational}).type,
        ExpressionType.rational,
      );
    });

    test('语法与静态错误', () {
      for (final source in [
        '',
        '1 +',
        '1 + * 2',
        'undefined + 1',
        'sqrt()',
        'atan2(1)',
        'unknown(1)',
        '1 / 0',
        '1 % 0',
        'sqrt(-1)',
        '1.0 % 2',
        '1 2',
        '2147483648',
      ]) {
        final result = ExpressionParser.parse(source);
        expect(result.ok, isFalse, reason: source);
      }
    });

    test('常量与内置输入', () {
      final root = parse('PI + E');
      expect(root.type, ExpressionType.rational);
      final input = parse('LX + A');
      expect(input.type, ExpressionType.integer);
    });
  });

  group('表达式求值', () {
    num eval(
      String source, {
      Map<String, num> inputs = const {},
      Map<String, num> variables = const {},
    }) {
      final result = ExpressionParser.parse(
        source,
        variables: {
          for (final entry in variables.entries)
            entry.key: ExpressionType.rational,
        },
      );
      expect(result.ok, isTrue, reason: source);
      return ExpressionEvaluator.evaluate(
        result.root!,
        inputs: inputs,
        variables: variables,
      );
    }

    test('四则、比较、逻辑与三元', () {
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('7 / 2'), 3);
      expect(eval('7.0 / 2'), 3.5);
      expect(eval('LX > 10 && A == 1 ? 5 : 6', inputs: {'LX': 20, 'A': 1}), 5);
      expect(eval('LX > 10 || A == 1 ? 5 : 6', inputs: {'LX': 0, 'A': 0}), 6);
      expect(eval('0 && (1 / LX)', inputs: {'LX': 0}), 0);
      expect(eval('1 || (1 / LX)', inputs: {'LX': 0}), 1);
    });

    test('函数与除零/负数开方守卫', () {
      expect(eval('abs(-3)'), 3);
      expect(eval('min(3, 1, 2)'), 1);
      expect(eval('max(3, 1, 2)'), 3);
      expect(eval('sign(-2)'), -1);
      expect(eval('sqrt(4)'), 2.0);
      expect(eval('sqrt(x)', variables: {'x': -4.0}), 0.0);
      expect(eval('atan2(0, 0)'), 0.0);
      expect(eval('1 / LX', inputs: {'LX': 0}), 0);
    });
  });

  group('表达式 C 生成', () {
    ExpressionEmitter emitter() => ExpressionEmitter(
      inputCode: (name) => 'IN_$name',
      variableCode: (name) => 'v_$name',
    );

    ExpressionNode parse(
      String source, {
      Map<String, ExpressionType> variables = const {},
    }) {
      final result = ExpressionParser.parse(source, variables: variables);
      expect(result.ok, isTrue, reason: source);
      return result.root!;
    }

    test('生成 int32/float 表达式并记录 helper', () {
      final e = emitter();
      final code = e.emit(
        parse('LX * 2 + A', variables: {'x': ExpressionType.rational}),
      );
      expect(code, contains('int32_t'));
      expect(code, contains('IN_LX'));
      expect(code, contains('IN_A'));

      final rational = emitter();
      rational.emit(
        parse('sqrt(x) + PI', variables: {'x': ExpressionType.rational}),
      );
      expect(rational.helpers, contains('sqrt_f'));

      final division = emitter();
      division.emit(parse('LX / 2'));
      expect(division.helpers, contains('div_i'));

      final variable = emitter();
      variable.emit(parse('x + 1', variables: {'x': ExpressionType.rational}));
      expect(variable.helpers, isEmpty);
    });

    test('运行时 helper 只生成用到的部分', () {
      expect(ExpressionRuntime.code({}), isEmpty);
      final code = ExpressionRuntime.code({'div_i', 'sqrt_f', 'atan2_f'});
      expect(code, contains('pb_div_i'));
      expect(code, contains('#define PB_SQRT sqrtf'));
      expect(code, contains('pb_atan2'));
      expect(code, isNot(contains('pb_clamp_i')));
    });
  });

  test('变量名规则', () {
    expect(isValidVariableName('speed'), isTrue);
    expect(isValidVariableName('a1'), isTrue);
    expect(isValidVariableName('LX'), isFalse);
    expect(isValidVariableName('sqrt'), isFalse);
    expect(isValidVariableName('int'), isFalse);
    expect(isValidVariableName('_x'), isFalse);
    expect(isValidVariableName('1x'), isFalse);
    expect(isValidVariableName('中文'), isFalse);
  });
}
