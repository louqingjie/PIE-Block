import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/proposal/proposal_service_io.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'support/valid_project.dart';

void main() {
  late Directory temp;
  late String projectPath;
  late String projectText;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pieblock-proposal-');
    projectPath = '${temp.path}${Platform.pathSeparator}robot.pieproj';
    projectText = jsonEncode(validInfantryDocument().toJson());
    File(projectPath).writeAsStringSync(projectText);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String baseHash() => sha256Hex(utf8.encode(projectText));

  void writeProposalText(String text) {
    File(proposalPathFor(projectPath)).writeAsStringSync(text);
  }

  void writeValidProposal({Map<String, Object?>? candidate}) {
    final base = ProjectDocument.fromJson(
      Map<String, Object?>.from(jsonDecode(projectText) as Map),
    );
    final proposal = ProjectProposal.create(
      base: base,
      candidateJson: candidate ?? projectJsonWithSpeed(4321),
      baseSha256: baseHash(),
    );
    writeProposalText(encodeProposal(proposal));
  }

  ProjectDocument currentDocument() => ProjectDocument.fromJson(
    Map<String, Object?>.from(jsonDecode(projectText) as Map),
  );

  test('没有提案文件：none', () {
    final inspection = inspectProposalFile(projectPath, currentDocument());
    expect(inspection.status, ProposalStatus.none);
  });

  test('合法提案：pending，且不 stale / dirty', () {
    writeValidProposal();
    final inspection = inspectProposalFile(projectPath, currentDocument());
    expect(inspection.status, ProposalStatus.pending);
    expect(inspection.stale, isFalse);
    expect(inspection.dirty, isFalse);
    expect(inspection.proposal!.changedPaths, contains('chassis.normal_speed'));
  });

  test('提案生成后工程被保存过：标记 stale', () {
    writeValidProposal();
    // 模拟用户在应用里保存了别的改动。
    final saved = jsonEncode(projectJsonWithSpeed(4100));
    File(projectPath).writeAsStringSync(saved);
    final diskDocument = ProjectDocument.fromJson(
      Map<String, Object?>.from(jsonDecode(saved) as Map),
    );
    final inspection = inspectProposalFile(projectPath, diskDocument);
    expect(inspection.status, ProposalStatus.pending);
    expect(inspection.stale, isTrue);
    expect(inspection.dirty, isFalse);
  });

  test('内存里有未保存改动：标记 dirty', () {
    writeValidProposal();
    final edited = ProjectDocument.fromJson(projectJsonWithSpeed(4600));
    final inspection = inspectProposalFile(projectPath, edited);
    expect(inspection.status, ProposalStatus.pending);
    expect(inspection.stale, isFalse);
    expect(inspection.dirty, isTrue);
  });

  test('提案文件损坏：invalid', () {
    writeProposalText('{ not json');
    final inspection = inspectProposalFile(projectPath, currentDocument());
    expect(inspection.status, ProposalStatus.invalid);
    expect(inspection.error, isNotNull);
  });

  test('提案工程类型不一致：invalid', () {
    final other = ProjectDocument.create(ProjectKind.debug);
    writeProposalText(
      jsonEncode({
        'schema': 1,
        'kind': 'pieblock-proposal',
        'baseSha256': baseHash(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'changedPaths': const <String>[],
        'document': other.toJson(),
      }),
    );
    final inspection = inspectProposalFile(projectPath, currentDocument());
    expect(inspection.status, ProposalStatus.invalid);
    expect(inspection.error, contains('类型'));
  });

  test('提案配置有 error：invalid', () {
    final json = projectJsonWithSpeed(4321);
    final config = Map<String, Object?>.from(json['config']! as Map);
    final remote = Map<String, Object?>.from(config['remote']! as Map);
    remote['channel'] = 999;
    config['remote'] = remote;
    json['config'] = config;
    writeProposalText(
      jsonEncode({
        'schema': 1,
        'kind': 'pieblock-proposal',
        'baseSha256': baseHash(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'changedPaths': const <String>[],
        'document': json,
      }),
    );
    final inspection = inspectProposalFile(projectPath, currentDocument());
    expect(inspection.status, ProposalStatus.invalid);
    expect(inspection.error, contains('错误'));
  });

  test('工程本身有错误：保留既有错误的提案可以 pending，并提示剩余错误数', () {
    // 基线是错误状态（通道 999），候选保留这个错误、只改普通速度。
    final invalidBase = _withChannel(projectJsonWithSpeed(4000), 999);
    final invalidText = jsonEncode(invalidBase);
    File(projectPath).writeAsStringSync(invalidText);
    final invalidDocument = ProjectDocument.fromJson(
      Map<String, Object?>.from(jsonDecode(invalidText) as Map),
    );
    final proposal = ProjectProposal.create(
      base: invalidDocument,
      candidateJson: _withSpeed(invalidBase, 4321),
      baseSha256: sha256Hex(utf8.encode(invalidText)),
    );
    writeProposalText(encodeProposal(proposal));

    final inspection = inspectProposalFile(projectPath, invalidDocument);
    expect(inspection.status, ProposalStatus.pending);
    expect(inspection.remainingErrors, 1);
    expect(inspection.stale, isFalse);
    expect(inspection.dirty, isFalse);
    expect(inspection.proposal!.changedPaths, contains('chassis.normal_speed'));
  });
}

Map<String, Object?> _withChannel(Map<String, Object?> json, int channel) {
  final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  final config = Map<String, Object?>.from(copy['config']! as Map);
  final remote = Map<String, Object?>.from(config['remote']! as Map);
  remote['channel'] = channel;
  config['remote'] = remote;
  copy['config'] = config;
  return copy;
}

Map<String, Object?> _withSpeed(Map<String, Object?> json, int speed) {
  final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  final config = Map<String, Object?>.from(copy['config']! as Map);
  final chassis = Map<String, Object?>.from(config['chassis']! as Map);
  chassis['normal_speed'] = speed;
  config['chassis'] = chassis;
  copy['config'] = config;
  return copy;
}
