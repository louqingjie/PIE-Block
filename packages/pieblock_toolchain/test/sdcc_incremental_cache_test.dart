import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

import 'support/android_sdcc_golden_matrix.dart';

void main() {
  final enabled = Platform.environment['PIEBLOCK_RUN_SDCC_GOLDEN'] == '1';

  test(
    '配置变化后只重新编译 main.c 并复用库目标文件',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pieblock-incremental-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final builder = FirmwareBuilder(
        runtimeRoot: '${directory.path}/runtime',
        workRoot: '${directory.path}/work',
        artifacts: BuildArtifactRepository(
          root: '${directory.path}/artifacts',
        ),
      );
      final golden = sdccGoldenCases.first;
      final fingerprint = await builder.resolveCompilerFingerprint(
        CompilerKind.sdcc,
      );
      final source = CodeGenerator.generate(golden.config);
      var buildCount = 0;

      Future<(BuildResult, List<BuildEvent>)> build(String sourceCode) async {
        buildCount++;
        final operation = builder.start(
          BuildRequest(
            projectKind: golden.kind,
            sourceCode: sourceCode,
            compiler: CompilerKind.sdcc,
            compilerFingerprint: fingerprint,
          ),
        );
        final eventsFuture = operation.events.toList();
        final result = await operation.result;
        return (result, await eventsFuture);
      }

      int reuseCount(List<BuildEvent> events) =>
          events.where((event) => event.message.contains('复用缓存')).length;
      int compileCount(List<BuildEvent> events) => events
          .where((event) => RegExp(r'\]\s*编译 ').hasMatch(event.message))
          .length;

      final (first, firstEvents) = await build(source);
      expect(first.success, isTrue, reason: first.log);
      final firstHash = first.artifact!.hexSha256;
      final total = firstEvents
          .map(
            (event) =>
                RegExp(r'\[(\d+)/(\d+)\]').firstMatch(event.message)?.group(2),
          )
          .whereType<String>()
          .map(int.parse)
          .first;
      expect(reuseCount(firstEvents), 0);
      expect(compileCount(firstEvents), total);

      final changed = '$source\n/* incremental cache probe */\n';
      final (second, secondEvents) = await build(changed);
      expect(second.success, isTrue, reason: second.log);
      expect(second.artifact!.hexSha256, firstHash);
      expect(reuseCount(secondEvents), total - 1);
      expect(compileCount(secondEvents), 1);
      expect(
        secondEvents.map((event) => event.message),
        contains(contains('重新编译 1 个模块')),
      );

      final (third, thirdEvents) = await build(changed);
      expect(third.success, isTrue, reason: third.log);
      expect(third.artifact!.hexSha256, firstHash);
      expect(reuseCount(thirdEvents), total - 1);
      expect(compileCount(thirdEvents), 1);
      expect(buildCount, 3);
    },
    skip: enabled ? false : '设置 PIEBLOCK_RUN_SDCC_GOLDEN=1 后运行',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
