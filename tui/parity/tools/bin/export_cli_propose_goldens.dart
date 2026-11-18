// 开发期基准生成器：CLI propose 的退出码/stdout/stderr/提案文件 golden。
//
// 运行：cd tui/parity/tools && dart run bin/export_cli_propose_goldens.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final projectsDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}cli'
      '${Platform.pathSeparator}projects');
  final candidatesDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}cli'
      '${Platform.pathSeparator}propose');
  final goldenDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}cli');
  candidatesDir.createSync(recursive: true);

  final base = File('${projectsDir.path}${Platform.pathSeparator}infantry_template.pieproj');
  final baseJson =
      jsonDecode(base.readAsStringSync()) as Map<String, Object?>;

  Map<String, Object?> mutate(void Function(Map<String, Object?> config) action) {
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(baseJson)) as Map,
    );
    action(copy['config']! as Map<String, Object?>);
    return copy;
  }

  final channel = mutate((config) {
    (config['remote']! as Map<String, Object?>)['channel'] = 12;
  });
  final bad = mutate((config) {
    (config['remote']! as Map<String, Object?>)['channel'] = 999;
  });
  final same = Map<String, Object?>.from(
    jsonDecode(jsonEncode(baseJson)) as Map,
  );
  _write(candidatesDir, 'infantry_channel.pieproj', channel);
  _write(candidatesDir, 'infantry_bad.pieproj', bad);
  _write(candidatesDir, 'infantry_same.pieproj', same);

  final cases = <Object?>[];
  final baseRelative = 'tui/parity/cli/projects/infantry_template.pieproj';
  final proposalPath =
      '${repoRoot.path}${Platform.pathSeparator}tui${Platform.pathSeparator}parity'
      '${Platform.pathSeparator}cli${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}infantry_template.pieproj.proposed';

  void runCase(
    String name,
    List<String> args, {
    bool preCreate = false,
  }) {
    final proposal = File(proposalPath);
    if (proposal.existsSync()) proposal.deleteSync();
    if (preCreate) proposal.writeAsStringSync('stale\n');
    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'packages/pieblock_core/bin/pieblock.dart', ...args],
      workingDirectory: repoRoot.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final rawProposalFile = proposal.existsSync()
        ? proposal.readAsStringSync()
        : null;
    if (proposal.existsSync()) proposal.deleteSync();
    cases.add({
      'name': name,
      'args': args,
      'preCreateProposal': preCreate,
      'exitCode': result.exitCode,
      'stdout': _normalize(result.stdout),
      'stderr': result.stderr,
      'proposal': rawProposalFile == null ? null : _normalize(rawProposalFile),
    });
  }

  final candidateRelative = 'tui/parity/cli/propose/infantry_channel.pieproj';
  runCase('success_channel', ['propose', baseRelative, '--config', candidateRelative]);
  runCase('success_force', [
    'propose',
    baseRelative,
    '--config',
    candidateRelative,
    '--force',
  ], preCreate: true);
  runCase('conflict_existing', [
    'propose',
    baseRelative,
    '--config',
    candidateRelative,
  ], preCreate: true);
  runCase('invalid_config', [
    'propose',
    baseRelative,
    '--config',
    'tui/parity/cli/propose/infantry_bad.pieproj',
  ]);
  runCase('kind_mismatch', [
    'propose',
    baseRelative,
    '--config',
    'tui/parity/cli/projects/engineer_template.pieproj',
  ]);
  runCase('empty_changes', [
    'propose',
    baseRelative,
    '--config',
    'tui/parity/cli/propose/infantry_same.pieproj',
  ]);
  runCase('missing_candidate', [
    'propose',
    baseRelative,
    '--config',
    'tui/parity/cli/propose/no-such.pieproj',
  ]);

  final target = File('${goldenDir.path}${Platform.pathSeparator}cli_propose.json');
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'cases': cases})}\n',
  );
  stdout.writeln('cli propose golden: ${target.path}');
}

String _normalize(String text) {
  final pattern = RegExp(r'("createdAt"\s*:\s*")[^"]+(")');
  return text.replaceAllMapped(pattern, (match) => '${match[1]}<iso>${match[2]}');
}

void _write(Directory dir, String name, Map<String, Object?> value) {
  File('${dir.path}${Platform.pathSeparator}$name').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
