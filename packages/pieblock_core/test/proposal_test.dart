import 'dart:convert';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

import 'support/infantry_fixture.dart';

Map<String, Object?> _withConfigValue(
  Map<String, Object?> documentJson,
  String key,
  Object? value,
) {
  final copy = Map<String, Object?>.from(
    jsonDecode(jsonEncode(documentJson)) as Map,
  );
  final config = Map<String, Object?>.from(copy['config']! as Map);
  config[key] = value;
  copy['config'] = config;
  return copy;
}

/// 修改嵌套字段：`['chassis', 'normal_speed']`。
Map<String, Object?> _withNestedValue(
  Map<String, Object?> documentJson,
  List<String> path,
  Object? value,
) {
  final copy = Map<String, Object?>.from(
    jsonDecode(jsonEncode(documentJson)) as Map,
  );
  final root = Map<String, Object?>.from(copy['config']! as Map);
  var cursor = root;
  for (var index = 0; index < path.length - 1; index += 1) {
    final next = Map<String, Object?>.from(cursor[path[index]]! as Map);
    cursor[path[index]] = next;
    cursor = next;
  }
  cursor[path.last] = value;
  copy['config'] = root;
  return copy;
}

void main() {
  final base = validInfantryDocument();
  final baseJson = base.toJson();
  final baseHash = sha256Hex(utf8.encode(jsonEncode(baseJson)));

  test('构建提案：记录改动路径与基线哈希，可 JSON 往返', () {
    final candidateJson = _withNestedValue(baseJson, [
      'chassis',
      'normal_speed',
    ], 4200);
    final proposal = ProjectProposal.create(
      base: base,
      candidateJson: candidateJson,
      baseSha256: baseHash,
    );
    expect(proposal.changedPaths, contains('chassis.normal_speed'));
    expect(proposal.baseSha256, baseHash);
    expect(
      (proposal.document.config as InfantryConfig).chassis.normalSpeed,
      4200,
    );

    final decoded = ProjectProposal.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(proposal.toJson())) as Map,
      ),
    );
    expect(decoded.baseSha256, baseHash);
    expect(decoded.changedPaths, proposal.changedPaths);
    expect(
      (decoded.document.config as InfantryConfig).chassis.normalSpeed,
      4200,
    );
  });

  test('候选与基线没有差异：拒绝', () {
    expect(
      () => ProjectProposal.create(
        base: base,
        candidateJson: Map<String, Object?>.from(
          jsonDecode(jsonEncode(baseJson)) as Map,
        ),
        baseSha256: baseHash,
      ),
      throwsA(
        isA<ProposalException>().having(
          (error) => error.code,
          'code',
          'empty_changes',
        ),
      ),
    );
  });

  test('工程类型不一致：拒绝', () {
    final other = ProjectDocument.create(ProjectKind.debug).toJson();
    expect(
      () => ProjectProposal.create(
        base: base,
        candidateJson: other,
        baseSha256: baseHash,
      ),
      throwsA(
        isA<ProposalException>().having(
          (error) => error.code,
          'code',
          'kind_mismatch',
        ),
      ),
    );
  });

  test('未知字段无法被模型读回：拒绝并给出字段路径', () {
    final candidateJson = _withConfigValue(baseJson, 'bogus_field', 1);
    expect(
      () => ProjectProposal.create(
        base: base,
        candidateJson: candidateJson,
        baseSha256: baseHash,
      ),
      throwsA(
        isA<ProposalException>()
            .having((error) => error.code, 'code', 'unroundtripped_value')
            .having((error) => error.fields, 'fields', contains('bogus_field')),
      ),
    );
  });

  test('配置存在 error：拒绝', () {
    final candidateJson = _withNestedValue(baseJson, [
      'remote',
      'channel',
    ], 999);
    expect(
      () => ProjectProposal.create(
        base: base,
        candidateJson: candidateJson,
        baseSha256: baseHash,
      ),
      throwsA(
        isA<ProposalException>()
            .having((error) => error.code, 'code', 'invalid_config')
            .having(
              (error) => error.fields,
              'fields',
              contains('remote.channel'),
            ),
      ),
    );
  });

  test('工程本身有错误时，提案只对新增错误负责', () {
    // 基线：遥控器通道 999 不合法（模拟用户配置到一半的状态）。
    final invalidBaseJson = _withNestedValue(baseJson, [
      'remote',
      'channel',
    ], 999);
    final invalidBase = ProjectDocument.fromJson(invalidBaseJson);
    expect(
      ProjectValidator.validate(invalidBase.config)
          .where((issue) => issue.severity == IssueSeverity.error),
      isNotEmpty,
    );

    // 只改一个无关字段、保留既有错误：允许。
    final allowedJson = _withNestedValue(invalidBaseJson, [
      'chassis',
      'normal_speed',
    ], 4200);
    final proposal = ProjectProposal.create(
      base: invalidBase,
      candidateJson: allowedJson,
      baseSha256: baseHash,
    );
    expect(proposal.changedPaths, contains('chassis.normal_speed'));

    // 候选新引入一个错误：拒绝，并且只报新增的那个。
    final badJson = _withNestedValue(invalidBaseJson, [
      'chassis',
      'normal_speed',
    ], -1);
    expect(
      () => ProjectProposal.create(
        base: invalidBase,
        candidateJson: badJson,
        baseSha256: baseHash,
      ),
      throwsA(
        isA<ProposalException>()
            .having((error) => error.code, 'code', 'invalid_config')
            .having(
              (error) => error.fields,
              'fields',
              contains('chassis.normal_speed'),
            ),
      ),
    );
  });

  test('提案文件 schema 不合法：拒绝', () {
    final proposal = ProjectProposal.create(
      base: base,
      candidateJson: _withNestedValue(baseJson, [
        'chassis',
        'normal_speed',
      ], 4200),
      baseSha256: baseHash,
    );
    final json = Map<String, Object?>.from(proposal.toJson());
    json['schema'] = 99;
    expect(
      () => ProjectProposal.fromJson(json),
      throwsA(
        isA<ProposalException>().having(
          (error) => error.code,
          'code',
          'unsupported_schema',
        ),
      ),
    );
  });

  test('diff 递归到数组下标', () {
    final before = <String, Object?>{
      'modes': [
        {
          'rows': [
            {'speed': 1},
          ],
        },
      ],
      'name': 'a',
    };
    final after = <String, Object?>{
      'modes': [
        {
          'rows': [
            {'speed': 2},
          ],
        },
      ],
      'name': 'a',
    };
    final changes = diffConfigs(before, after);
    expect(changes, hasLength(1));
    expect(changes.single.path, 'modes[0].rows[0].speed');
    expect(changes.single.before, 1);
    expect(changes.single.after, 2);
  });

  test('提案文件命名固定', () {
    expect(
      proposalPathFor(r'C:\p\robot.pieproj'),
      r'C:\p\robot.pieproj.proposed',
    );
    expect(
      proposalResultPathFor(r'C:\p\robot.pieproj'),
      r'C:\p\robot.pieproj.proposed.result',
    );
  });

  test('SHA-256 与标准向量一致', () {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
