import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

Map<String, Object?> configJson(ProjectKind kind) =>
    ProjectDocument.create(kind).config.toJson();

McpPatchPlan propose(
  PatchEngine engine,
  ProjectKind kind,
  List<Object?> ops, {
  int revision = 1,
}) => engine.propose(
  kind: kind.name,
  baseConfig: configJson(kind),
  baseRevision: revision,
  rawOps: ops,
);

void main() {
  late PatchEngine engine;

  setUp(() => engine = PatchEngine());

  group('set', () {
    test('改标量：值落库、diff 带中文名', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {'op': 'set', 'path': 'chassis.normal_speed', 'value': 4200},
      ]);
      expect(plan.diff, hasLength(1));
      expect(plan.diff.single.label, '普通速度');
      expect(plan.diff.single.before, isNull);
      expect(plan.diff.single.after, 4200);
      expect(plan.config, isA<InfantryConfig>());
      expect(
        (plan.config as InfantryConfig).chassis.normalSpeed,
        4200,
      );
      expect(plan.patchId, isNotEmpty);
      expect(plan.baseRevision, 1);
    });

    test('改枚举：合法值通过', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {'op': 'set', 'path': 'chassis.left_front.direction', 'value': 'reverse'},
      ]);
      expect(
        (plan.config as InfantryConfig).chassis.leftFront.direction,
        Direction.reverse,
      );
    });

    test('改枚举：非法值被拒，不会静默回退', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'chassis.left_front.direction', 'value': 'sideways'},
        ]),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.invalidValue,
          ),
        ),
      );
    });

    test('未知路径被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'chassis.no_such_field', 'value': 1},
        ]),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.invalidPath,
          ),
        ),
      );
    });

    test('id 字段只读', () {
      expect(
        () => propose(engine, ProjectKind.engineer, [
          {'op': 'set', 'path': 'modes[0].id', 'value': 'hacked'},
        ]),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.notWritable,
          ),
        ),
      );
    });

    test('数组追加：可以省略重建结果为 null 的键', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {
          'op': 'set',
          'path': 'yaw[1]',
          'value': {
            'drive': 'servo',
            'pin': 'MP03',
            'direction': 'forward',
          },
        },
      ]);
      expect((plan.config as InfantryConfig).yawActuators, hasLength(2));
    });

    test('省略的键保持未填写，并由校验器点名', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {
          'op': 'set',
          'path': 'yaw[1]',
          'value': {'drive': 'servo', 'pin': 'MP03'},
        },
      ]);
      expect((plan.config as InfantryConfig).yawActuators[1].direction, isNull);
      expect(plan.issues, isNotEmpty);
    });

    test('改完与改前一样会被拦下（兜住键名拼错）', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'chassis.normal_speed', 'value': null},
        ]),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.invalidValue,
          ),
        ),
      );
    });

    test('下标越界被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'yaw[5]', 'value': <String, Object?>{}},
        ]),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.invalidPath,
          ),
        ),
      );
    });

    test('路径语法错误被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'chassis..normal_speed', 'value': 1},
        ]),
        throwsA(isA<PatchException>()),
      );
    });
  });

  group('remove', () {
    test('删除数组元素', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {'op': 'remove', 'path': 'yaw[0]'},
      ]);
      expect((plan.config as InfantryConfig).yawActuators, isEmpty);
      expect(plan.diff.single.removed, isTrue);
    });

    test('删除不存在的元素被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'remove', 'path': 'yaw[3]'},
        ]),
        throwsA(isA<PatchException>()),
      );
    });
  });

  group('参数校验', () {
    test('空补丁被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, const []),
        throwsA(
          isA<PatchException>().having(
            (e) => e.code,
            'code',
            McpToolErrorCode.emptyPatch,
          ),
        ),
      );
    });

    test('未知 op 被拒', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'append', 'path': 'yaw', 'value': 1},
        ]),
        throwsA(isA<PatchException>()),
      );
    });

    test('set 缺 value 被拒，显式 null 可以清空已有值', () {
      expect(
        () => propose(engine, ProjectKind.infantry, [
          {'op': 'set', 'path': 'remote.channel'},
        ]),
        throwsA(isA<PatchException>()),
      );
      final filled = engine.propose(
        kind: 'infantry',
        baseConfig: configJson(ProjectKind.infantry),
        baseRevision: 1,
        rawOps: [
          {'op': 'set', 'path': 'remote.channel', 'value': 36},
        ],
      );
      final cleared = engine.propose(
        kind: 'infantry',
        baseConfig: filled.configJson,
        baseRevision: 2,
        rawOps: [
          {'op': 'set', 'path': 'remote.channel', 'value': null},
        ],
      );
      expect((cleared.config as InfantryConfig).remote.channel, isNull);
    });
  });

  group('校验结果', () {
    test('补丁自带改动后的 issues', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {'op': 'set', 'path': 'chassis.normal_speed', 'value': 100},
      ]);
      expect(
        plan.issues.any((issue) => issue.fieldPath == 'chassis.normal_speed'),
        isTrue,
      );
    });

    test('propose 不改动传入的基准 JSON', () {
      final base = configJson(ProjectKind.infantry);
      engine.propose(
        kind: 'infantry',
        baseConfig: base,
        baseRevision: 1,
        rawOps: [
          {'op': 'set', 'path': 'chassis.normal_speed', 'value': 4200},
        ],
      );
      expect(base, configJson(ProjectKind.infantry));
    });
  });

  group('补丁缓存', () {
    test('取出即作废', () {
      final plan = propose(engine, ProjectKind.infantry, [
        {'op': 'set', 'path': 'remote.channel', 'value': 36},
      ]);
      expect(engine.cache.take(plan.patchId), isNotNull);
      expect(engine.cache.take(plan.patchId), isNull);
    });

    test('过期后取不到', () {
      var now = DateTime(2026, 1, 1);
      final cache = PatchPlanCache(clock: () => now);
      final local = PatchEngine(cache: cache);
      final plan = propose(local, ProjectKind.infantry, [
        {'op': 'set', 'path': 'remote.channel', 'value': 36},
      ]);
      now = now.add(const Duration(minutes: 6));
      expect(cache.take(plan.patchId), isNull);
    });

    test('容量上限淘汰最旧的', () {
      final cache = PatchPlanCache(capacity: 2);
      final local = PatchEngine(cache: cache);
      final first = propose(local, ProjectKind.infantry, [
        {'op': 'set', 'path': 'remote.channel', 'value': 36},
      ]);
      propose(local, ProjectKind.infantry, [
        {'op': 'set', 'path': 'remote.channel', 'value': 37},
      ]);
      propose(local, ProjectKind.infantry, [
        {'op': 'set', 'path': 'remote.channel', 'value': 38},
      ]);
      expect(cache.length, 2);
      expect(cache.take(first.patchId), isNull);
    });
  });

  group('往返幂等', () {
    test('四类默认配置 toJson → fromJson → toJson 一致', () {
      for (final kind in ProjectKind.values) {
        final config = ProjectDocument.create(kind).config;
        final once = config.toJson();
        final twice = decodeConfig(kind.name, once).toJson();
        expect(twice, once, reason: '${kind.name} 往返不幂等');
      }
    });
  });
}
