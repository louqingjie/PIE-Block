// CLI 输出契约的回归测试：锁住 stdout/stderr 双通道、JSON 结构与退出码。
// 这些契约是 AI Agent 通过 pieblock-cli 命令行操作工程的基础，不能随意变动。

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

import 'support/infantry_fixture.dart';

final _cli = Uri.file('bin/pieblock.dart').toString();

/// 构造一份能通过校验的完整步兵工程，写入临时文件。
File _validProject({String name = 'valid.pieproj'}) {
  final doc = validInfantryDocument();
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
  file.writeAsStringSync(jsonEncode(doc.toJson()));
  return file;
}

ProcessResult _run(List<String> args) => Process.runSync(
  Platform.resolvedExecutable,
  ['run', _cli, ...args],
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

void main() {
  group('pieblock-cli 输出契约', () {
    late File project;
    setUp(() => project = _validProject());
    tearDown(() => project.existsSync() ? project.deleteSync() : null);

    test('describe 输出机器可读契约，stderr 为空', () {
      final r = _run(['describe']);
      expect(r.exitCode, 0);
      expect(r.stderr, isEmpty);
      final json = jsonDecode(r.stdout as String) as Map;
      expect(json['name'], 'pieblock-cli');
      // release 对应应用发布版本，formatVersion 对应工程格式；两者都不能靠猜。
      expect(json['release'], pieblockRelease);
      expect(json['formatVersion'], ProjectDocument.formatVersion);
      expect(json['version'], isNotEmpty);
      expect(json['exitCodes'], containsPair('2', anything));
      expect(json['exitCodes'], containsPair('5', anything));
      expect(json['exitCodes'], containsPair('6', anything));
      final commands = json['commands'] as List;
      expect(
        commands.map((command) => (command as Map)['name']),
        containsAll(['validate', 'codegen', 'propose', 'describe']),
      );
    });

    test('validate 合法工程：exit 0、valid true、errors 为 0', () {
      final r = _run(['validate', project.path]);
      expect(r.exitCode, 0, reason: r.stderr as String);
      final json = jsonDecode(r.stdout as String) as Map;
      expect(json['ok'], isTrue);
      expect(json['valid'], isTrue);
      expect(json['counts'], containsPair('errors', 0));
      final issues = json['issues'] as List;
      expect(
        issues.where((i) => (i as Map)['severity'] == 'error'),
        isEmpty,
      );
      expect((r.stderr as String), contains('校验完成'));
    });

    test('validate 非法工程：exit 2、valid false、issues 带字段路径', () {
      final map = jsonDecode(project.readAsStringSync()) as Map<String, Object?>;
      final config = Map<String, Object?>.from(map['config'] as Map);
      config['remote'] = {...(config['remote'] as Map), 'channel': 999};
      map['config'] = config;
      project.writeAsStringSync(jsonEncode(map));

      final r = _run(['validate', project.path]);
      expect(r.exitCode, 2);
      final json = jsonDecode(r.stdout as String) as Map;
      expect(json['valid'], isFalse);
      expect(json['counts'], containsPair('errors', 1));
      final issue = (json['issues'] as List).first as Map;
      expect(issue['fieldPath'], 'remote.channel');
      expect(issue['severity'], 'error');
    });

    test('codegen stdout 是纯 C 源码，摘要走 stderr', () {
      final r = _run(['codegen', project.path]);
      expect(r.exitCode, 0, reason: r.stderr as String);
      expect(r.stdout, contains('#include'));
      expect(r.stdout, isNot(contains('已生成')));
      expect(r.stderr, contains('已生成'));
    });

    test('codegen 非法工程：exit 2、stdout 空、错误走 stderr', () {
      final map = jsonDecode(project.readAsStringSync()) as Map<String, Object?>;
      final config = Map<String, Object?>.from(map['config'] as Map);
      config['remote'] = {...(config['remote'] as Map), 'channel': 999};
      map['config'] = config;
      project.writeAsStringSync(jsonEncode(map));

      final r = _run(['codegen', project.path]);
      expect(r.exitCode, 2);
      expect(r.stdout, isEmpty);
      expect(r.stderr, contains('不能生成代码'));
    });

    test('文件不存在：exit 3', () {
      final r = _run(['validate', '${Directory.systemTemp.path}/no-such.pieproj']);
      expect(r.exitCode, 3);
      expect(r.stderr, contains('不存在'));
    });

    test('工程内容结构错误：exit 3、不向调用方抛 Dart 栈', () {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}bad-type.pieproj',
      );
      file.writeAsStringSync(jsonEncode({
        'format_version': ProjectDocument.formatVersion,
        'project_kind': 'infantry',
        'config': 'not-a-map',
      }));
      try {
        final r = _run(['validate', file.path]);
        expect(r.exitCode, 3, reason: r.stderr as String);
        expect(r.stdout, isEmpty);
        expect(r.stderr as String, contains('无法解析'));
        expect(r.stderr as String, isNot(contains('#0')));
      } finally {
        if (file.existsSync()) file.deleteSync();
      }
    });

    test('工程顶层不是 JSON 对象：exit 3', () {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}top-array.pieproj',
      );
      file.writeAsStringSync('[]');
      try {
        final r = _run(['validate', file.path]);
        expect(r.exitCode, 3);
        expect(r.stderr as String, contains('不是 JSON 对象'));
      } finally {
        if (file.existsSync()) file.deleteSync();
      }
    });

    test('缺少参数：exit 1', () {
      final r = _run(['validate']);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('缺少'));
    });
  });
}
