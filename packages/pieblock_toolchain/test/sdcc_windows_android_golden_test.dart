import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';
import 'support/android_sdcc_golden_matrix.dart';

void main() {
  final enabled = Platform.environment['PIEBLOCK_RUN_SDCC_GOLDEN'] == '1';

  test('Android SDCC 黄金矩阵与固定基线清单一致', () {
    final baseline = jsonDecode(
      File('../../tools/android_sdcc_baseline.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final hashes = Map<String, Object?>.from(
      baseline['windows_golden_sha256']! as Map,
    );
    expect(hashes.keys, unorderedEquals(sdccGoldenCases.map((item) => item.id)));
    for (final golden in sdccGoldenCases) {
      expect(hashes[golden.id], golden.expectedHexSha256);
    }
  });

  for (final golden in sdccGoldenCases) {
    test(
      'Windows 与 Android ${golden.id} SDCC 固件字节级一致',
      () async {
        final validationErrors = ProjectValidator.validate(
          golden.config,
        ).where((issue) => issue.severity == IssueSeverity.error);
        expect(validationErrors, isEmpty, reason: '$validationErrors');
        final directory = await Directory.systemTemp.createTemp(
          'pieblock-sdcc-golden-${golden.id}-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final builder = FirmwareBuilder(
          runtimeRoot: '${directory.path}/runtime',
          workRoot: '${directory.path}/work',
          artifacts: BuildArtifactRepository(
            root: '${directory.path}/artifacts',
          ),
        );
        final compilerFingerprint = await builder.resolveCompilerFingerprint(
          CompilerKind.sdcc,
        );
        final operation = builder.start(
          BuildRequest(
            projectKind: golden.kind,
            sourceCode: CodeGenerator.generate(golden.config),
            compiler: CompilerKind.sdcc,
            compilerFingerprint: compilerFingerprint,
          ),
        );
        final result = await operation.result;
        expect(result.success, isTrue, reason: result.log);
        final artifact = result.artifact!;
        stdout.writeln(
          '${golden.id}: windowsSha256=${artifact.hexSha256}, '
          'bytes=${artifact.byteCount}',
        );
        if (golden.expectedHexSha256.isNotEmpty) {
          expect(artifact.hexSha256, golden.expectedHexSha256);
        }
      },
      skip: enabled ? false : '设置 PIEBLOCK_RUN_SDCC_GOLDEN=1 后运行',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
