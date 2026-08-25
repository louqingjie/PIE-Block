import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class SdccBuildPlan {
  const SdccBuildPlan({
    required this.projectName,
    required this.sourcePaths,
    required this.librarySourcePaths,
    required this.compileArguments,
    required this.linkArguments,
    required this.interruptHeaderPath,
  });

  final String projectName;
  final List<String> sourcePaths;
  final List<String> librarySourcePaths;
  final List<String> compileArguments;
  final List<String> linkArguments;
  final String interruptHeaderPath;

  static Future<SdccBuildPlan> prepare({
    required String resourceRoot,
    required String projectName,
    required String mainSourcePath,
    required String outputDirectory,
  }) async {
    final firmware = p.join(resourceRoot, 'firmware');
    final toolchain = p.join(resourceRoot, 'toolchain');
    final manifestFile = File(p.join(firmware, 'build_manifest.json'));
    if (!await manifestFile.exists()) {
      throw StateError('Android SDCC 资源缺少 build_manifest.json');
    }
    final manifest = (jsonDecode(await manifestFile.readAsString()) as Map)
        .cast<String, Object?>();
    final groups = (manifest['source_groups']! as Map).cast<String, Object?>();
    final projects = (manifest['projects']! as Map).cast<String, Object?>();
    final kindProjects = (manifest['kind_projects'] as Map?)
        ?.cast<String, Object?>();
    final resolvedProject = projects.containsKey(projectName)
        ? projectName
        : kindProjects?[projectName] as String?;
    final spec = (projects[resolvedProject] as Map?)?.cast<String, Object?>();
    if (spec == null || resolvedProject == null) {
      throw StateError('SDCC 构建清单缺少项目：$projectName');
    }

    final relativeSources = <String>[];
    final relativeLibraries = <String>[];
    void addSource(String value) {
      if (!relativeSources.contains(value)) relativeSources.add(value);
    }

    for (final value in groups['common']! as List) {
      addSource('$value');
    }
    addSource('projects/$resolvedProject/src/isr.c');
    addSource('projects/$resolvedProject/src/main.c');
    for (final groupName in spec['library_groups']! as List) {
      final group = groups['$groupName'] as List?;
      if (group == null) throw StateError('SDCC 构建清单缺少源码组：$groupName');
      for (final value in group) {
        final relative = '$value';
        addSource(relative);
        if (!relativeLibraries.contains(relative)) {
          relativeLibraries.add(relative);
        }
      }
    }

    String resolveSource(String relative) => relative.endsWith('/src/main.c')
        ? mainSourcePath
        : p.join(firmware, relative.replaceAll('/', p.separator));
    final sources = relativeSources.map(resolveSource).toList(growable: false);
    for (final source in sources) {
      if (!await File(source).exists()) {
        throw StateError('Android SDCC 固件源码缺失：$source');
      }
    }

    await Directory(outputDirectory).create(recursive: true);
    final interruptHeader = p.join(
      outputDirectory,
      'generated_interrupt_declarations.h',
    );
    await _writeInterruptHeader(sources, interruptHeader);
    final includeArguments = <String>[
      '-I${p.join(toolchain, 'include')}',
      '-I${p.join(toolchain, 'include', 'mcs51')}',
      for (final directory in manifest['include_dirs']! as List)
        '-I${p.join(firmware, '$directory')}',
      '-I${p.join(firmware, 'projects', resolvedProject, 'inc')}',
    ];
    final compileArguments = <String>[
      for (final flag in manifest['compile_flags']! as List) '$flag',
      ...includeArguments,
    ];
    final linkArguments = <String>[
      for (final flag in manifest['link_flags']! as List) '$flag',
      '-L${p.join(toolchain, 'lib', 'mcs251-large-stack-auto')}',
      ...includeArguments,
      for (final library in manifest['runtime_libraries']! as List) '$library',
    ];
    return SdccBuildPlan(
      projectName: resolvedProject,
      sourcePaths: sources,
      librarySourcePaths: relativeLibraries
          .map(resolveSource)
          .toList(growable: false),
      compileArguments: compileArguments,
      linkArguments: linkArguments,
      interruptHeaderPath: interruptHeader,
    );
  }

  static Future<void> _writeInterruptHeader(
    List<String> sources,
    String destination,
  ) async {
    final declarations = <String>{};
    final pattern = RegExp(
      r'^\s*(?:static\s+)?void\s+([A-Za-z_]\w*)\s*\(\s*void\s*\)\s*__interrupt\s*\(\s*([^)]*?)\s*\)',
      multiLine: true,
    );
    for (final source in sources) {
      final text = await File(source).readAsString();
      for (final match in pattern.allMatches(text)) {
        declarations.add(
          'void ${match.group(1)}(void) __interrupt (${match.group(2)!.trim()});',
        );
      }
    }
    final sorted = declarations.toList()..sort();
    await File(destination).writeAsString(
      '#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
      '#define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
      '#include "STC32Gxx.h"\n#include <stdlib.h>\n'
      '${sorted.join('\n')}\n#endif\n',
      flush: true,
    );
  }
}
