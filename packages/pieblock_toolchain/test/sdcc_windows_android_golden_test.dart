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
        // 链接后应带回生成模块的列表文件（main_<序号>.rst），供「生成代码」页
        // 的汇编栏展示：地址 + 机器码 + [周期] + 行号 + 汇编，C 源码带锚点。
        final listing = result.listing;
        expect(listing, isNotNull, reason: '构建结果应带回 main_*.rst');
        expect(listing, contains('.module'));
        expect(listing, matches(RegExp(r'[0-9A-F]{6} [0-9A-F]{2} ')));
        expect(listing, contains('main.c:'));
        stdout.writeln('${golden.id}: listingBytes=${listing!.length}');
        if (golden.expectedHexSha256.isNotEmpty) {
          expect(artifact.hexSha256, golden.expectedHexSha256);
        }
      },
      skip: enabled ? false : '设置 PIEBLOCK_RUN_SDCC_GOLDEN=1 后运行',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
