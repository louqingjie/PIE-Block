// 开发期基准生成器：改动提案 golden（固定时间，编码文本逐字节 + 错误码/文案）。
//
// 运行：cd tui/parity/tools && dart run bin/export_proposal_goldens.dart
import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}proposal');
  outputDir.createSync(recursive: true);

  final infantry = _load(repoRoot, 'assets/templates/infantry.pieproj');
  final engineer = _load(repoRoot, 'assets/templates/engineer.pieproj');
  final music = _load(repoRoot, 'assets/templates/music.pieproj');
  final debug = _load(repoRoot, 'assets/templates/debug.pieproj');

  final validCandidate = _clone(infantry.toJson());
  ((validCandidate['config']! as Map)['remote']! as Map)['channel'] = 12;

  final badCandidate = _clone(infantry.toJson());
  ((badCandidate['config']! as Map)['remote']! as Map)['channel'] = 999;

  final unroundtrippedUnknown = _clone(infantry.toJson());
  (unroundtrippedUnknown['config']! as Map)['unknown_option'] = true;

  final unroundtrippedEnum = _clone(infantry.toJson());
  (unroundtrippedEnum['config']! as Map)['feeder_direction'] = 'sideways';

  final cases = <({String name, ProjectDocument base, Map<String, Object?> candidate})>[
    (
      name: 'valid_change',
      base: infantry,
      candidate: validCandidate,
    ),
    (
      name: 'invalid_config',
      base: infantry,
      candidate: badCandidate,
    ),
    (
      name: 'unroundtripped_unknown_key',
      base: infantry,
      candidate: unroundtrippedUnknown,
    ),
    (
      name: 'unroundtripped_enum',
      base: infantry,
      candidate: unroundtrippedEnum,
    ),
    (
      name: 'empty_changes',
      base: infantry,
      candidate: infantry.toJson(),
    ),
    (
      name: 'kind_mismatch',
      base: infantry,
      candidate: engineer.toJson(),
    ),
    (
      name: 'missing_config',
      base: music,
      candidate: {...music.toJson()}..remove('config'),
    ),
    (
      name: 'music_valid_change',
      base: music,
      candidate: (() {
        final json = _clone(music.toJson());
        (json['config']! as Map)['key_signature_fifths'] = -3;
        return json;
      })(),
    ),
    (
      name: 'debug_valid_change',
      base: debug,
      candidate: (() {
        final json = _clone(debug.toJson());
        final tests = (json['config']! as Map)['tests']! as List<Object?>;
        (tests[0]! as Map)['duration_ms'] = 4000;
        return json;
      })(),
    ),
  ];

  final results = <Object?>[];
  String? validEncoded;
  for (final item in cases) {
    final payload = <String, Object?>{
      'name': item.name,
      'base': item.base.toJson(),
      'candidate': item.candidate,
    };
    try {
      final proposal = ProjectProposal.create(
        base: item.base,
        candidateJson: Map<String, Object?>.from(item.candidate),
        baseSha256: 'a' * 64,
        tool: 'pieblock-cli/1.0.0',
        now: DateTime.utc(2026, 1, 1),
      );
      payload['ok'] = true;
      payload['encoded'] = encodeProposal(proposal);
      validEncoded ??= payload['encoded']! as String;
    } on ProposalException catch (error) {
      payload
        ..['ok'] = false
        ..['code'] = error.code
        ..['message'] = error.message
        ..['fields'] = error.fields;
    }
    results.add(payload);
  }

  // fromJson / isValidProposalJson 用例。
  final roundtrip = <Object?>[];
  if (validEncoded != null) {
    final parsed = jsonDecode(validEncoded) as Map<String, Object?>;
    final proposal = ProjectProposal.fromJson(parsed);
    roundtrip.add({
      'name': 'roundtrip_valid',
      'json': parsed,
      'isValid': isValidProposalJson(parsed),
      'encoded': encodeProposal(proposal),
      'baseSha256': proposal.baseSha256,
      'changedPaths': proposal.changedPaths,
    });
  }
  for (final (name, brokenJson) in <(String, Map<String, Object?>)>[
    ('schema_too_new', <String, Object?>{'schema': 2, 'kind': 'pieblock-proposal'}),
    ('kind_mismatch', <String, Object?>{'schema': 1, 'kind': 'other'}),
    ('bad_base_sha', <String, Object?>{'schema': 1, 'kind': 'pieblock-proposal', 'baseSha256': 'x'}),
    ('missing_document', <String, Object?>{
      'schema': 1,
      'kind': 'pieblock-proposal',
      'baseSha256': 'a' * 64,
    }),
  ]) {
    var code = '';
    var message = '';
    try {
      ProjectProposal.fromJson(brokenJson);
    } on ProposalException catch (error) {
      code = error.code;
      message = error.message;
    }
    roundtrip.add({
      'name': name,
      'json': brokenJson,
      'isValid': isValidProposalJson(brokenJson),
      'code': code,
      'message': message,
    });
  }

  final target = File('${outputDir.path}${Platform.pathSeparator}proposal.json');
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'cases': results,
      'roundtrip': roundtrip,
    })}\n',
  );
  stdout.writeln('proposal golden: ${target.path}');
}

ProjectDocument _load(Directory repoRoot, String relative) {
  final file = File('${repoRoot.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}');
  return ProjectDocument.fromJson(
    Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
  );
}

Map<String, Object?> _clone(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
