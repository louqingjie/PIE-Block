// `pieblock-cli propose` 的契约测试：只写提案、不改工程，失败有明确退出码。
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

import 'support/infantry_fixture.dart';

final _cli = Uri.file('bin/pieblock.dart').toString();

ProcessResult _run(List<String> args) => Process.runSync(
  Platform.resolvedExecutable,
  ['run', _cli, ...args],
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

Map<String, Object?> _validJson() => validInfantryDocument().toJson();

/// 在 config 的嵌套路径上改一个值（路径为 map 的键序列）。
Map<String, Object?> _changedJson(List<String> path, Object? value) {
  final json = jsonDecode(jsonEncode(_validJson())) as Map<String, Object?>;
  Map<String, Object?> cursor = Map<String, Object?>.from(
    json['config']! as Map,
  );
  final root = cursor;
  for (var index = 0; index < path.length - 1; index += 1) {
    final next = Map<String, Object?>.from(cursor[path[index]]! as Map);
    cursor[path[index]] = next;
    cursor = next;
  }
  cursor[path.last] = value;
  json['config'] = root;
  return json;
}

void main() {
  late Directory temp;
  late File project;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pieblock-cli-propose-');
    project = File('${temp.path}${Platform.pathSeparator}robot.pieproj')
      ..writeAsStringSync(jsonEncode(_validJson()));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File candidate(
    Map<String, Object?> json, {
    String name = 'candidate.pieproj',
  }) {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(jsonEncode(json));
    return file;
  }

  test('成功：写出提案文件、stdout 输出 JSON、工程本身不变', () {
    final edited = candidate(_changedJson(['chassis', 'normal_speed'], 4200));
    final r = _run(['propose', project.path, '--config', edited.path]);
    expect(r.exitCode, 0, reason: r.stderr as String);

    final output = jsonDecode(r.stdout as String) as Map;
    expect(output['ok'], isTrue);
    expect(output['changed'], 1);
    expect(output['paths'], contains('chassis.normal_speed'));
    expect(output['baseSha256'], hasLength(64));

    final proposalFile = File(proposalPathFor(project.path));
    expect(proposalFile.existsSync(), isTrue);
    final proposalJson =
        jsonDecode(proposalFile.readAsStringSync()) as Map<String, Object?>;
    expect(proposalJson['schema'], 1);
    expect(proposalJson['kind'], 'pieblock-proposal');
    expect(proposalJson['baseSha256'], output['baseSha256']);
    expect(proposalJson['document'], isA<Map>());

    // 工程文件没有被 CLI 改写。
    final unchanged =
        jsonDecode(project.readAsStringSync()) as Map<String, Object?>;
    final chassis = (unchanged['config']! as Map)['chassis'] as Map;
    expect(chassis['normal_speed'], 4000);
  });

  test('候选有校验错误：exit 2，不写提案', () {
    final edited = candidate(_changedJson(['remote', 'channel'], 999));
    final r = _run(['propose', project.path, '--config', edited.path]);
    expect(r.exitCode, 2, reason: r.stderr as String);
    expect(r.stdout, isEmpty);
    expect(r.stderr, contains('remote.channel'));
    expect(File(proposalPathFor(project.path)).existsSync(), isFalse);
  });

  test('未知字段无法往返：exit 2，stderr 给出字段路径', () {
    final json = _changedJson(['chassis', 'normal_speed'], 4200);
    final config = Map<String, Object?>.from(json['config']! as Map);
    config['bogus_field'] = 1;
    json['config'] = config;
    final edited = candidate(json);
    final r = _run(['propose', project.path, '--config', edited.path]);
    expect(r.exitCode, 2, reason: r.stderr as String);
    expect(r.stderr, contains('bogus_field'));
  });

  test('已有提案：exit 6；--force 覆盖', () {
    final edited = candidate(_changedJson(['chassis', 'normal_speed'], 4200));
    expect(
      _run(['propose', project.path, '--config', edited.path]).exitCode,
      0,
    );

    final r = _run(['propose', project.path, '--config', edited.path]);
    expect(r.exitCode, 6, reason: r.stderr as String);
    expect(r.stderr, contains('--force'));

    final forced = _run([
      'propose',
      project.path,
      '--config',
      edited.path,
      '--force',
    ]);
    expect(forced.exitCode, 0, reason: forced.stderr as String);
  });

  test('候选文件不存在：exit 3', () {
    final r = _run([
      'propose',
      project.path,
      '--config',
      '${temp.path}${Platform.pathSeparator}missing.pieproj',
    ]);
    expect(r.exitCode, 3);
    expect(r.stderr, contains('不存在'));
  });

  test('工程类型不一致：exit 2', () {
    final other = ProjectDocument.create(ProjectKind.debug);
    final edited = candidate(other.toJson());
    final r = _run(['propose', project.path, '--config', edited.path]);
    expect(r.exitCode, 2, reason: r.stderr as String);
    expect(r.stderr, contains('不一致'));
  });

  test('缺少 --config：exit 1', () {
    final r = _run(['propose', project.path]);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('--config'));
  });
}
