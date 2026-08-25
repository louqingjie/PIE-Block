import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

void main() {
  test('Android 构建计划将项目类型解析为固件清单项目', () async {
    final temporary = await Directory.systemTemp.createTemp('pieblock-alias-');
    addTearDown(() => temporary.delete(recursive: true));
    final resource = Directory(p.join(temporary.path, 'resource'));
    final firmware = Directory(p.join(resource.path, 'firmware'));
    final toolchain = Directory(p.join(resource.path, 'toolchain'));
    final project = 'ROBOMASTER_INFANTRY';
    for (final path in [
      p.join(firmware.path, 'startup', 'common.c'),
      p.join(firmware.path, 'projects', project, 'src', 'isr.c'),
      p.join(firmware.path, 'projects', project, 'inc', '.keep'),
      p.join(firmware.path, 'include', '.keep'),
      p.join(toolchain.path, 'include', '.keep'),
      p.join(toolchain.path, 'include', 'mcs51', '.keep'),
      p.join(toolchain.path, 'lib', 'mcs251-large-stack-auto', '.keep'),
    ]) {
      await File(path).create(recursive: true);
    }
    final mainSource = File(p.join(temporary.path, 'main.c'));
    await mainSource.writeAsString('void main(void) {}');
    await File(p.join(firmware.path, 'build_manifest.json')).writeAsString(
      jsonEncode({
        'kind_projects': {'infantry': project},
        'include_dirs': ['include'],
        'compile_flags': ['-mmcs251', '-c'],
        'link_flags': ['-mmcs251', '--nostdlib'],
        'runtime_libraries': ['mcs251.lib'],
        'source_groups': {
          'common': ['startup/common.c'],
        },
        'projects': {
          project: {'library_groups': <String>[]},
        },
      }),
    );

    final plan = await SdccBuildPlan.prepare(
      resourceRoot: resource.path,
      projectName: 'infantry',
      mainSourcePath: mainSource.path,
      outputDirectory: p.join(temporary.path, 'output'),
    );

    expect(plan.projectName, project);
    expect(
      plan.sourcePaths,
      contains(p.join(firmware.path, 'projects', project, 'src', 'isr.c')),
    );
    expect(
      plan.compileArguments,
      contains('-I${p.join(firmware.path, 'projects', project, 'inc')}'),
    );
  });
}
