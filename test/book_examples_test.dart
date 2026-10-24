import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../tool/book_examples.dart';

typedef _ExpectedRow = ({
  ActionOutputKind outputKind,
  String? variable,
  String? pin,
  String expression,
});

/// 教材第 5 章的动作表：这里按行钉死，JSON 改一个符号测试就会失败。
///
/// 行顺序即 `RunMode1` 里的执行顺序：先算变量，再把结果写进电机/舵机。
/// 输入固定为「未指定」，所以方向/控制方式/参数必须全空。
const _expectedActions = <String, List<_ExpectedRow>>{
  'mecanum4': [
    (
      outputKind: ActionOutputKind.integer,
      variable: 'vx',
      pin: null,
      expression: '-LY',
    ),
    (
      outputKind: ActionOutputKind.integer,
      variable: 'vy',
      pin: null,
      expression: '-LX',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P74',
      expression: '(vx-vy)*10000/2047',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P75',
      expression: '(vx+vy)*10000/2047',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P76',
      expression: '(vx+vy)*10000/2047',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P77',
      expression: '(vx-vy)*10000/2047',
    ),
  ],
  'omni3': [
    (
      outputKind: ActionOutputKind.integer,
      variable: 'vx',
      pin: null,
      expression: '-LY',
    ),
    (
      outputKind: ActionOutputKind.integer,
      variable: 'vy',
      pin: null,
      expression: '-LX',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P74',
      expression: 'vx*10000/2047',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P75',
      expression: '(-0.5*vx+0.866*vy)*10000/2047',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'P76',
      expression: '(-0.5*vx-0.866*vy)*10000/2047',
    ),
  ],
  'arm2dof': [
    (
      outputKind: ActionOutputKind.rational,
      variable: 'x',
      pin: null,
      expression: 'max(RX*0.05,20.0)',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'y',
      pin: null,
      expression: 'max(-RY*0.05,0.0)',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'r2',
      pin: null,
      expression: 'x*x+y*y',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'c2',
      pin: null,
      expression: '(r2-24400.0)/24000.0',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'c2c',
      pin: null,
      expression: 'min(max(c2,-1.0),1.0)',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 's2',
      pin: null,
      expression: 'sqrt(1.0-c2c*c2c)',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'q1',
      pin: null,
      expression: 'atan2(y,x)-atan2(100.0*s2,120.0+100.0*c2c)',
    ),
    (
      outputKind: ActionOutputKind.rational,
      variable: 'q2',
      pin: null,
      expression: 'atan2(s2,c2c)',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'MP03',
      expression: 'q1*180.0/PI',
    ),
    (
      outputKind: ActionOutputKind.pin,
      variable: null,
      pin: 'MP74',
      expression: 'q2*180.0/PI-90.0',
    ),
  ],
};

/// 8 个扩展脚的角色：麦轮/全向把 PWM 组按 50Hz+10000Hz 分组，机械臂全留给
/// 主舵机，所以三份工程的角色表都不允许「未填写」。
const _expectedRoles = <String, Map<String, PinRole>>{
  'mecanum4': {
    'P60': PinRole.unused,
    'P62': PinRole.unused,
    'P64': PinRole.unused,
    'P66': PinRole.unused,
    'P74': PinRole.motor,
    'P75': PinRole.motor,
    'P76': PinRole.motor,
    'P77': PinRole.motor,
  },
  'omni3': {
    'P60': PinRole.unused,
    'P62': PinRole.unused,
    'P64': PinRole.unused,
    'P66': PinRole.unused,
    'P74': PinRole.motor,
    'P75': PinRole.motor,
    'P76': PinRole.motor,
    'P77': PinRole.unused,
  },
  'arm2dof': {
    'P60': PinRole.unused,
    'P62': PinRole.unused,
    'P64': PinRole.unused,
    'P66': PinRole.unused,
    'P74': PinRole.unused,
    'P75': PinRole.unused,
    'P76': PinRole.unused,
    'P77': PinRole.unused,
  },
};

const _expectedFrequencies = <String, (PwmFrequency, PwmFrequency)>{
  'mecanum4': (PwmFrequency.hz50, PwmFrequency.hz10000),
  'omni3': (PwmFrequency.hz50, PwmFrequency.hz10000),
  'arm2dof': (PwmFrequency.hz50, PwmFrequency.hz50),
};

void main() {
  group('示例工程文件', () {
    for (final example in bookExamples) {
      test('${example.name} 可解析、零 error 并生成固件源码', () {
        final project = loadBookExample(example);
        expect(project.document.kind, ProjectKind.engineer);
        expect(
          project.errors
              .map((issue) => '${issue.fieldPath}: ${issue.message}')
              .toList(),
          isEmpty,
          reason: '示例工程必须能零 error 导入',
        );
        final config = project.config;

        // 工程项目必须关闭预制底盘，四轮由动作行接管；模式数为 1。
        expect(config.chassis.enabled, isFalse);
        expect(config.chassis.normalSpeed, isNull);
        for (final wheel in [
          config.chassis.leftFront,
          config.chassis.leftRear,
          config.chassis.rightFront,
          config.chassis.rightRear,
        ]) {
          expect(wheel.pin, isNull);
          expect(wheel.direction, isNull);
        }
        expect(config.modeCount, 1);
        expect(config.modes, hasLength(1));
        expect(config.modes.single.preserveChassis, isFalse);
        expect(
          config.modes.single.actions,
          hasLength(_expectedActions[example.name]!.length),
        );

        // PWM 角色：8 个扩展脚全部显式；两组的初始化频率与教材一致。
        expect(config.pwm.pinRoles, _expectedRoles[example.name]);
        expect(config.pwm.pinRoles.keys, unorderedEquals(expansionPins));
        final (pwma, pwmb) = _expectedFrequencies[example.name]!;
        expect(config.pwm.pwma, pwma);
        expect(config.pwm.pwmb, pwmb);

        // 动作表逐行比对：表达式、输出类型、变量名/引脚，且方向/方式/参数为空。
        final actions = config.modes.single.actions;
        final expectedRows = _expectedActions[example.name]!;
        for (var index = 0; index < expectedRows.length; index++) {
          final action = actions[index], expected = expectedRows[index];
          expect(action.inputKind, ActionInputKind.unspecified);
          expect(action.key, isNull);
          expect(action.expression, expected.expression);
          expect(action.outputKind, expected.outputKind);
          expect(action.variableName, expected.variable);
          expect(action.pin, expected.pin);
          expect(action.direction, isNull);
          expect(action.mode, isNull);
          expect(action.parameter, isNull);
        }

        // 生成源码：单模式 + 每条表达式行都有可回填的行号标记。
        final program = project.program!;
        final source = program.source;
        expect(source, contains('void RunMode1(void)'));
        expect(source, contains('// 单模式，无需切换'));
        expect(program.expressionLineFields, hasLength(expectedRows.length));
        final lines = source.split('\n');
        for (final entry in program.expressionLineFields.entries) {
          expect(
            entry.value,
            matches(RegExp(r'^modes\.0\.actions\.\d+\.expression$')),
          );
          expect(lines[entry.key - 1], contains('/*@expr:${entry.value}*/'));
        }
        // helper 与变量/输出都必须真的落到源码里。
        for (final helper in example.expectedHelpers) {
          expect(
            source,
            contains('$helper('),
            reason: '${example.name} 生成代码应引用 $helper',
          );
        }
        for (final action in actions) {
          final variable = action.variableName, pin = action.pin;
          if (variable != null) {
            expect(source, contains('pbv_$variable'));
          }
          if (pin != null) {
            if (expansionPins.contains(pin)) {
              expect(
                source,
                contains('dutyOfMotor[${expansionPins.indexOf(pin)}]'),
              );
            } else {
              expect(
                source,
                contains('mainServoDuty[${pin == 'MP74' ? 1 : 0}]'),
              );
            }
          }
        }
      });
    }
  });

  group('共享小库', () {
    test('表达式行标记剥离后行号不变，RunMode1 可单独提取', () {
      final project = loadBookExample(bookExamples.first);
      final source = project.program!.source;
      expect(source, contains('/*@expr:modes.0.actions.0.expression*/'));
      final stripped = stripExpressionMarkers(source);
      expect(stripped, isNot(contains('@expr')));
      expect(stripped.split('\n'), hasLength(source.split('\n').length));
      final runMode1 = extractRunMode1(stripped);
      expect(runMode1, startsWith('void RunMode1(void)'));
      expect(runMode1, endsWith('}'));
      expect(runMode1, contains('pbv_vx'));
    });

    test('示例按应用保存格式落盘，重新保存不产生 diff', () {
      for (final example in bookExamples) {
        final raw = File(example.projectPath).readAsStringSync();
        expect(raw, endsWith('\n'));
        final json = jsonDecode(raw);
        expect(
          (json as Map)['format_version'],
          ProjectDocument.formatVersion,
          reason: '示例必须与当前项目格式版本一致',
        );
        final document = ProjectDocument.fromJson(
          Map<String, Object?>.from(json),
        );
        final encoded = const JsonEncoder.withIndent('  ')
            .convert(document.toJson());
        expect('$encoded\n', raw, reason: '${example.name} 重新保存后不应产生 diff');
      }
    });
  });

  group('麦轮试算', () {
    EngineerConfig config() => loadBookExample(
      bookExamples.firstWhere((example) => example.name == 'mecanum4'),
    ).config;

    test('LY=-2047 时四轮同向 10000', () {
      final preview = EngineerPreview.evaluateMode(config(), 0, {
        'LY': -2047,
        'LX': 0,
      });
      expect(preview.rows, hasLength(6));
      expect(preview.rows.where((row) => row.error != null), isEmpty);
      expect(
        [for (final row in preview.rows) row.value],
        [2047, 0, 10000, 10000, 10000, 10000],
      );
      expect(preview.variables['vx'], 2047);
      expect(preview.variables['vy'], 0);
    });

    test('纯横向输入时两侧轮子反向、同一侧同向', () {
      final preview = EngineerPreview.evaluateMode(config(), 0, {
        'LY': 0,
        'LX': -2047,
      });
      // P74/P77 走 vx-vy，P75/P76 走 vx+vy：横向平移必须让两侧电机反转。
      expect(
        [for (final row in preview.rows) row.value],
        [0, 2047, -10000, 10000, 10000, -10000],
      );
    });
  });

  group('全向轮试算', () {
    EngineerConfig config() => loadBookExample(
      bookExamples.firstWhere((example) => example.name == 'omni3'),
    ).config;

    test('LY=-2047 时 P74=10000、P75/P76=-5000', () {
      final preview = EngineerPreview.evaluateMode(config(), 0, {
        'LY': -2047,
        'LX': 0,
      });
      expect(preview.rows, hasLength(5));
      expect(preview.rows.where((row) => row.error != null), isEmpty);
      final values = [for (final row in preview.rows) row.value!];
      expect(values[0], 2047);
      expect(values[1], 0);
      expect(values[2], 10000);
      expect(values[3], closeTo(-5000, 1e-6));
      expect(values[4], closeTo(-5000, 1e-6));
    });

    test('纯横向输入时三路按 120° 分配，幅值为 8660', () {
      final preview = EngineerPreview.evaluateMode(config(), 0, {
        'LY': 0,
        'LX': -2047,
      });
      final values = [for (final row in preview.rows) row.value!];
      expect(values[2], closeTo(0, 1e-6));
      expect(values[3], closeTo(8660, 1e-3));
      expect(values[4], closeTo(-8660, 1e-3));
    });
  });

  group('机械臂试算', () {
    EngineerConfig config() => loadBookExample(
      bookExamples.firstWhere((example) => example.name == 'arm2dof'),
    ).config;

    test('RX=1023、RY=-1023 时逆解出 q1≈-11.3°、q2≈143.0°', () {
      final preview = EngineerPreview.evaluateMode(config(), 0, {
        'RX': 1023,
        'RY': -1023,
      });
      expect(preview.rows, hasLength(10));
      expect(preview.rows.where((row) => row.error != null), isEmpty);
      const degreesPerRadian = 180 / math.pi;
      expect(preview.rows[0].value, closeTo(51.15, 1e-6)); // x
      expect(preview.rows[1].value, closeTo(51.15, 1e-6)); // y
      final q1Degrees = preview.rows[6].value! * degreesPerRadian;
      final q2Degrees = preview.rows[7].value! * degreesPerRadian;
      expect(q1Degrees, closeTo(-11.3, 0.1));
      // 按给定几何参数（L1=120、L2=100）与 RX=RY=1023 精确逆解为
      // q1≈-11.30°、q2≈143.00°；0.1° 容差用来卡住公式/常数改动。
      expect(q2Degrees, closeTo(143.0, 0.1));
      // 主舵机角度 = 关节角换算后 -90°~90° 内，MP74 还要再减 90°。
      final servoAngles = [preview.rows[8].value!, preview.rows[9].value!];
      expect(servoAngles[0], closeTo(-11.3, 0.1));
      expect(servoAngles[1], closeTo(53.0, 0.1));
      for (final angle in servoAngles) {
        expect(angle.abs(), lessThanOrEqualTo(90));
      }
    });

    test('生成的固件把主舵机角度钳位在 ±90°', () {
      final source = loadBookExample(
        bookExamples.firstWhere((example) => example.name == 'arm2dof'),
      ).program!.source;
      expect(source, contains('mainServoDuty[0] = pb_servo_duty(pb_clamp_f('));
      expect(source, contains('mainServoDuty[1] = pb_servo_duty(pb_clamp_f('));
      expect(source, contains('-90.0f, 90.0f'));
    });
  });
}
