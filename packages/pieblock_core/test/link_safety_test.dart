import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

// 断链失效保护的生成契约：运行时 API 守卫、初始化失败提示、阻塞收包助手、
// 以及 RemoteSafeState 的「电机/摩擦轮归零、舵机保持」取舍。
import '../tool/verify_runtime.dart' as v;

/// 取出生成源码中 RemoteSafeState 的函数体（函数内只有赋值语句）。
String safeStateBody(String source) {
  final start = source.indexOf('static void RemoteSafeState(void)');
  expect(start, greaterThanOrEqualTo(0), reason: '未找到 RemoteSafeState');
  final end = source.indexOf('\n}', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  group('断链安全状态生成契约', () {
    test('步兵：非舵机扩展脚全部归零，摩擦轮与蜂鸣器关闭', () {
      final code = CodeGenerator.generate(v.infantryBase());
      expect(
        code,
        contains(
          '#if !defined(PIEBLOCK_RADIO_API) || (PIEBLOCK_RADIO_API < 2)',
        ),
      );
      expect(code, contains('if (RcKeyValueRead(KEY_RCDISCONNECTED))'));
      expect(code, contains('RemoteSafeState();'));

      final body = safeStateBody(code);
      for (var slot = 0; slot < 8; slot++) {
        expect(body, contains('dutyOfMotor[$slot] = 0;'));
      }
      expect(body, contains('frictionEnabled = 0;'));
      expect(body, contains('frictionTargetDutyP64 = 0;'));
      expect(body, contains('PWM_SET_Frequency(BUZZER_CH, 500, 0);'));
    });

    test('步兵：扩展脚舵机在断链时保持最后位置', () {
      final code = CodeGenerator.generate(
        v.infantryBase(
          frictionMode: FrictionMode.disabled,
          yaw: const [
            AxisActuator(
              drive: DriveType.servo,
              pin: 'P66',
              direction: Direction.forward,
              midOffset: 0,
            ),
          ],
        ),
      );
      final body = safeStateBody(code);
      expect(body, isNot(contains('dutyOfMotor[3] = 0;')));
      expect(body, contains('dutyOfMotor[0] = 0;')); // 拨弹脚
      expect(body, contains('dutyOfMotor[4] = 0;')); // 底盘
    });

    test('工程：舵机保持，电机/摩擦轮归零', () {
      final code = CodeGenerator.generate(v.engineerBase());
      final body = safeStateBody(code);
      // 默认角色：P60/P62 舵机（slot 0/1），P64/P66 摩擦轮，P74~P77 电机。
      expect(body, isNot(contains('dutyOfMotor[0] = 0;')));
      expect(body, isNot(contains('dutyOfMotor[1] = 0;')));
      for (final slot in [2, 3, 4, 5, 6, 7]) {
        expect(body, contains('dutyOfMotor[$slot] = 0;'));
      }
    });

    test('工程：主控板摩擦轮在断链时清零，摩擦轮状态栈复位', () {
      final code = CodeGenerator.generate(
        v.engineerBase(
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
          modes: [
            EngineerModeConfig(
              preserveChassis: true,
              actions: [
                v.action(
                  'A',
                  pin: 'MP74',
                  mode: ControlMode.frictionToggle,
                  parameter: 100,
                ),
              ],
            ),
          ],
        ),
      );
      final body = safeStateBody(code);
      expect(body, contains('mainServoDuty[1] = 0;'));
      expect(body, contains('frictionLevel = 0;'));
      expect(body, contains('frictionTargetDutyMP74 = 0;'));
      expect(body, contains('frictionDutyMP74 = 0;'));
    });

    test('初始化失败提示与阻塞收包助手', () {
      final code = CodeGenerator.generate(
        v.infantryBase(feedMode: FeedMode.blockingOpenLoop),
      );
      expect(
        code,
        contains('static uint8_t remoteControlInitWithTimeout(void)'),
      );
      expect(code, contains('radioOk = remoteControlInitWithTimeout();'));
      expect(code, contains('if (!radioOk)'));
      expect(code, contains('static void BlockingDelayWithRadio(uint16_t ms)'));
      expect(code, contains('BlockingDelayWithRadio(250)'));

      final visual = CodeGenerator.generate(
        v.infantryBase(feedMode: FeedMode.visualClosedLoop),
      );
      expect(visual, isNot(contains('BlockingDelayWithRadio')));

      final engineer = CodeGenerator.generate(v.engineerBase());
      expect(engineer, contains('if (!radioOk)'));
      expect(engineer, isNot(contains('BlockingDelayWithRadio')));
    });
  });
}
