import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

// 十路 IO 状态回传的生成契约：只允许出现在步兵/工程 main() 末尾，参数顺序固定为
// P60/P62/P64/P66/P74/P75/P76/P77/MP03/MP74，舵机按角度、其余按有符号输出值。
// 配置构件复用 tool/verify_runtime.dart，避免与运行时场景两处漂移。
import '../tool/verify_runtime.dart' as v;

/// 从生成源码里取出唯一一处 `RemoteStatusSend(...)` 的 10 个参数。
List<String> remoteStatusArgs(String source) {
  final matches = RegExp(
    r'^        RemoteStatusSend\((.*)\);$',
    multiLine: true,
  ).allMatches(source).toList();
  expect(matches, hasLength(1), reason: '应只有一处 RemoteStatusSend 调用');
  final body = matches.single.group(1)!;
  final args = <String>[];
  var depth = 0;
  var start = 0;
  for (var index = 0; index < body.length; index++) {
    final char = body[index];
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      args.add(body.substring(start, index).trim());
      start = index + 1;
    }
  }
  args.add(body.substring(start).trim());
  expect(args, hasLength(10), reason: 'RemoteStatusSend 应有 10 个参数');
  return args;
}

/// 十路 IO 状态回传里的舵机角度表达式（与固件侧 750 中位、±500 duty 一致）。
String angle(String duty) => '(int)(((int32_t)($duty) - 750L) * 180L / 1000L)';

/// 断言调用位于 main() 主循环 `nrf_handler()` 之后、末尾 `Ms_Delay(10)` 之前。
void expectTailCall(String source) {
  final call = source.indexOf('RemoteStatusSend(');
  expect(call, greaterThan(source.lastIndexOf('nrf_handler();')));
  expect(
    source.lastIndexOf('        Ms_Delay(10);'),
    greaterThan(call),
    reason: 'RemoteStatusSend 应插在主循环末尾 Ms_Delay(10) 之前',
  );
  expect(RegExp(r'RemoteStatusSend\(').allMatches(source), hasLength(1));
}

DebugConfig debugConfig() => DebugConfig(
  tests: [
    for (final pin in debugPins)
      DebugTestItem(
        pin: pin,
        enabled: pin == 'P64',
        driveType: pin == 'P64' ? DebugDriveType.friction : null,
        value: pin == 'P64' ? 800 : null,
      ),
  ],
);

MusicConfig musicConfig() => MusicConfig(
  sourceName: 'melody.mid',
  trackName: '主旋律',
  notes: const [
    MusicNote(id: 'a', pitch: 60, startTick: 0, durationTicks: 480),
  ],
  tempoEvents: const [
    TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
  ],
);

void main() {
  group('步兵十路 IO 状态回传', () {
    test('默认配置：唯一调用、位置正确、10 参数顺序与换算正确', () {
      final source = CodeGenerator.generate(v.infantryBase());
      expectTailCall(source);
      expect(remoteStatusArgs(source), [
        '(int)(dutyOfMotor[0])', // P60 拨弹
        '(int)(dutyOfMotor[1])', // P62
        '(int)(frictionDutyP64)', // P64 摩擦轮
        '(int)(frictionDutyP66)', // P66 摩擦轮
        '(int)(dutyOfMotor[4])', // P74 底盘
        '(int)(dutyOfMotor[5])', // P75
        '(int)(dutyOfMotor[6])', // P76
        '(int)(dutyOfMotor[7])', // P77
        angle('pitchDuty'), // MP03 云台舵机
        angle('yawDuty'), // MP74 云台舵机
      ]);
    });

    test('扩展脚舵机回传角度，关摩擦轮时摩擦脚回传电机 duty，未用主控脚回传 0', () {
      final config = v.infantryBase(
        frictionMode: FrictionMode.disabled,
        yaw: const [
          AxisActuator(
            drive: DriveType.servo,
            pin: 'MP74',
            direction: Direction.forward,
            midOffset: 0,
          ),
          AxisActuator(
            drive: DriveType.servo,
            pin: 'P66',
            direction: Direction.forward,
            midOffset: 0,
          ),
        ],
        pitch: const [
          AxisActuator(
            drive: DriveType.motor,
            pin: 'P64',
            direction: Direction.reverse,
          ),
        ],
      );
      final source = CodeGenerator.generate(config);
      expectTailCall(source);
      expect(remoteStatusArgs(source), [
        '(int)(dutyOfMotor[0])',
        '(int)(dutyOfMotor[1])',
        '(int)(dutyOfMotor[2])', // P64 改为电机输出，按 duty 回传
        angle('yawDuty2'), // P66 第二路 yaw 舵机
        '(int)(dutyOfMotor[4])',
        '(int)(dutyOfMotor[5])',
        '(int)(dutyOfMotor[6])',
        '(int)(dutyOfMotor[7])',
        '0', // MP03 未接执行器
        angle('yawDuty'), // MP74 第一路 yaw 舵机
      ]);
    });
  });

  group('工程十路 IO 状态回传', () {
    test('默认角色：扩展脚舵机回传角度、其余回传 duty；未用主控脚回传 0', () {
      final source = CodeGenerator.generate(v.engineerBase());
      expectTailCall(source);
      expect(remoteStatusArgs(source), [
        angle('dutyOfMotor[0]'), // P60 舵机
        angle('dutyOfMotor[1]'), // P62 舵机
        '(int)(dutyOfMotor[2])', // P64 摩擦轮脚按扩展脚规则回传 duty
        '(int)(dutyOfMotor[3])', // P66
        '(int)(dutyOfMotor[4])',
        '(int)(dutyOfMotor[5])',
        '(int)(dutyOfMotor[6])',
        '(int)(dutyOfMotor[7])',
        '0', // MP03 舵机角色但未被动作引用
        '0', // MP74 同上
      ]);
    });

    test('主控脚只回传真正在输出的角色：舵机用角度、摩擦轮用 duty', () {
      final servoConfig = v.engineerBase(
        modes: [
          EngineerModeConfig(
            preserveChassis: true,
            actions: [
              v.action(
                'A',
                pin: 'P60',
                mode: ControlMode.direct,
                direction: Direction.forward,
                parameter: 45,
              ),
              v.action(
                'D',
                pin: 'MP03',
                mode: ControlMode.direct,
                direction: Direction.forward,
                parameter: 30,
              ),
            ],
          ),
        ],
      );
      final servoArgs = remoteStatusArgs(CodeGenerator.generate(servoConfig));
      expect(servoArgs[0], angle('dutyOfMotor[0]'));
      expect(servoArgs[8], angle('mainServoDuty[0]'));
      expect(servoArgs[9], '0');

      final frictionConfig = v.engineerBase(
        roles: const {
          'P60': PinRole.servo,
          'P62': PinRole.servo,
          'P64': PinRole.friction,
          'P66': PinRole.friction,
          'P74': PinRole.motor,
          'P75': PinRole.motor,
          'P76': PinRole.motor,
          'P77': PinRole.motor,
          'MP03': PinRole.unused,
          'MP74': PinRole.friction,
        },
        frictionMax: const {'P64': 800, 'P66': 700, 'MP74': 600},
      );
      final frictionArgs = remoteStatusArgs(
        CodeGenerator.generate(frictionConfig),
      );
      expect(frictionArgs[8], '0'); // MP03 未使用
      expect(frictionArgs[9], '(int)(mainServoDuty[1])'); // MP74 摩擦轮
    });
  });

  group('调试/音乐工程不回传状态', () {
    test('调试工程生成代码不含 RemoteStatusSend', () {
      final source = CodeGenerator.generate(debugConfig());
      expect(source, isNot(contains('RemoteStatusSend')));
    });

    test('音乐工程生成代码不含 RemoteStatusSend', () {
      final source = CodeGenerator.generate(musicConfig());
      expect(source, isNot(contains('RemoteStatusSend')));
    });
  });
}
