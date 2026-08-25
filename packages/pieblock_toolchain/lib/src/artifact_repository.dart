import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'hex_validator.dart';
import 'models.dart';

class BuildArtifactRepository {
  BuildArtifactRepository({String? root}) : root = root ?? _defaultRoot();

  final String root;

  static String _defaultRoot() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return p.join(base, 'PIE-Block', 'builds');
  }

  Future<BuildArtifact?> findFresh(BuildFingerprint fingerprint) async {
    final metadata = File(p.join(root, fingerprint.value, 'artifact.json'));
    try {
      if (!await metadata.exists()) return null;
      final artifact = BuildArtifact.fromJson(
        (jsonDecode(await metadata.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      if (artifact.fingerprint != fingerprint.value ||
          artifact.sourceSha256 != fingerprint.sourceHash) {
        return null;
      }
      final hex = File(artifact.hexPath);
      if (!await hex.exists() || await _shaFile(hex) != artifact.hexSha256) {
        return null;
      }
      if (!(await IntelHexValidator.validateApplication(hex.path)).ok) {
        return null;
      }
      return artifact;
    } catch (_) {
      return null;
    }
  }

  Future<BuildArtifact> store({
    required String sourceHex,
    required BuildArtifact artifact,
    required String log,
  }) async {
    final directory = Directory(p.join(root, artifact.fingerprint));
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, 'firmware.hex'));
    await _atomicCopy(File(sourceHex), destination);
    final stored = BuildArtifact(
      hexPath: destination.path,
      hexSha256: await _shaFile(destination),
      fingerprint: artifact.fingerprint,
      sourceSha256: artifact.sourceSha256,
      compiler: artifact.compiler,
      compilerFingerprint: artifact.compilerFingerprint,
      templateVersion: artifact.templateVersion,
      builtAt: artifact.builtAt,
      byteCount: artifact.byteCount,
      warningCount: artifact.warningCount,
      lastFlashedAt: artifact.lastFlashedAt,
    );
    await _atomicWrite(File(p.join(directory.path, 'build.log')), log);
    await _atomicWrite(
      File(p.join(directory.path, 'artifact.json')),
      const JsonEncoder.withIndent('  ').convert(stored.toJson()),
    );
    return stored;
  }

  Future<void> markFlashed(BuildArtifact artifact) async {
    final updated = artifact.copyWith(lastFlashedAt: DateTime.now());
    await _atomicWrite(
      File(p.join(root, artifact.fingerprint, 'artifact.json')),
      const JsonEncoder.withIndent('  ').convert(updated.toJson()),
    );
  }

  Future<void> prune({
    Duration maxAge = const Duration(days: 30),
    int maxBytes = 1 << 30,
    Set<String> protectedFingerprints = const {},
  }) async {
    final base = Directory(root);
    if (!await base.exists()) return;
    final entries = await base
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    final now = DateTime.now();
    final infos = <(Directory, DateTime, int)>[];
    for (final directory in entries) {
      final protected = protectedFingerprints.contains(
        p.basename(directory.path),
      );
      var size = 0;
      var modified = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          size += stat.size;
          if (stat.modified.isAfter(modified)) modified = stat.modified;
        }
      }
      if (!protected && now.difference(modified) > maxAge) {
        await directory.delete(recursive: true);
      } else {
        infos.add((directory, modified, size));
      }
    }
    infos.sort((a, b) => b.$2.compareTo(a.$2));
    var retained = 0;
    for (final info in infos) {
      retained += info.$3;
      if (retained > maxBytes &&
          !protectedFingerprints.contains(p.basename(info.$1.path))) {
        await info.$1.delete(recursive: true);
      }
    }
  }

  static Future<String> _shaFile(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  static Future<void> _atomicCopy(File source, File destination) async {
    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await source.copy(temporary.path);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  static Future<void> _atomicWrite(File destination, String contents) async {
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }
}
