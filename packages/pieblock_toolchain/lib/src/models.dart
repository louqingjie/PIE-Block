import 'dart:async';

import 'package:pieblock_core/pieblock_core.dart';

enum CompilerKind { sdcc, keil }

enum BuildStage { preparing, compiling, linking, validating, done }

enum BuildEventLevel { info, warning, error }

class BuildRequest {
  const BuildRequest({
    required this.projectKind,
    required this.sourceCode,
    required this.compiler,
    required this.compilerFingerprint,
    this.keilRoot,
  });

  final ProjectKind projectKind;
  final String sourceCode;
  final CompilerKind compiler;
  final String compilerFingerprint;
  final String? keilRoot;
}

class BuildEvent {
  const BuildEvent({
    required this.stage,
    required this.message,
    this.level = BuildEventLevel.info,
    this.current,
    this.total,
  });

  final BuildStage stage;
  final BuildEventLevel level;
  final String message;
  final int? current;
  final int? total;
}

class BuildFingerprint {
  const BuildFingerprint({required this.value, required this.sourceHash});

  final String value;
  final String sourceHash;
}

class BuildArtifact {
  const BuildArtifact({
    required this.hexPath,
    required this.hexSha256,
    required this.fingerprint,
    required this.sourceSha256,
    required this.compiler,
    required this.compilerFingerprint,
    required this.templateVersion,
    required this.builtAt,
    required this.byteCount,
    required this.warningCount,
    this.lastFlashedAt,
  });

  final String hexPath;
  final String hexSha256;
  final String fingerprint;
  final String sourceSha256;
  final CompilerKind compiler;
  final String compilerFingerprint;
  final String templateVersion;
  final DateTime builtAt;
  final int byteCount;
  final int warningCount;
  final DateTime? lastFlashedAt;

  BuildArtifact copyWith({DateTime? lastFlashedAt}) => BuildArtifact(
    hexPath: hexPath,
    hexSha256: hexSha256,
    fingerprint: fingerprint,
    sourceSha256: sourceSha256,
    compiler: compiler,
    compilerFingerprint: compilerFingerprint,
    templateVersion: templateVersion,
    builtAt: builtAt,
    byteCount: byteCount,
    warningCount: warningCount,
    lastFlashedAt: lastFlashedAt ?? this.lastFlashedAt,
  );

  Map<String, Object?> toJson() => {
    'hex_path': hexPath,
    'hex_sha256': hexSha256,
    'fingerprint': fingerprint,
    'source_sha256': sourceSha256,
    'compiler': compiler.name,
    'compiler_fingerprint': compilerFingerprint,
    'template_version': templateVersion,
    'built_at': builtAt.toUtc().toIso8601String(),
    'byte_count': byteCount,
    'warning_count': warningCount,
    if (lastFlashedAt != null)
      'last_flashed_at': lastFlashedAt!.toUtc().toIso8601String(),
  };

  factory BuildArtifact.fromJson(Map<String, Object?> json) => BuildArtifact(
    hexPath: json['hex_path']! as String,
    hexSha256: json['hex_sha256']! as String,
    fingerprint: json['fingerprint']! as String,
    sourceSha256: json['source_sha256']! as String,
    compiler: CompilerKind.values.byName(json['compiler']! as String),
    compilerFingerprint: json['compiler_fingerprint']! as String,
    templateVersion: json['template_version']! as String,
    builtAt: DateTime.parse(json['built_at']! as String),
    byteCount: (json['byte_count']! as num).toInt(),
    warningCount: (json['warning_count']! as num).toInt(),
    lastFlashedAt: json['last_flashed_at'] == null
        ? null
        : DateTime.parse(json['last_flashed_at']! as String),
  );
}

class BuildResult {
  const BuildResult({
    required this.success,
    required this.log,
    this.artifact,
    this.exitCode,
    this.canceled = false,
    this.licenseFailure = false,
  });

  final bool success;
  final BuildArtifact? artifact;
  final String log;
  final int? exitCode;
  final bool canceled;
  final bool licenseFailure;
}

class BuildOperation {
  BuildOperation(this.events, this.result, this._cancel);

  final Stream<BuildEvent> events;
  final Future<BuildResult> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}
