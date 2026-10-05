import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pieblock_core/pieblock_core.dart';

Future<String> _rootBundleTemplate(String assetPath) =>
    rootBundle.loadString(assetPath);

/// 新建项目时可选的模板工程：内容是与正式项目完全同格式的 `.pieproj` 文件。
///
/// 用真实项目文件而不是代码里的常量，是为了让模板本身就被 v16 的解析和校验
/// 约束住——格式版本一升级，模板忘记重存会直接被测试拦下，而不是静默生成一份
/// 打开就报错的项目。
class ProjectTemplates {
  const ProjectTemplates({this.loader = _rootBundleTemplate});

  /// 单独抽出读取动作，让测试不必依赖 Flutter 的资产包。
  final Future<String> Function(String assetPath) loader;

  static String assetFor(ProjectKind kind) =>
      'assets/templates/${kind.name}.pieproj';

  /// 返回 [kind] 对应的模板配置。加载或解析失败时抛错，由调用方中止创建：
  /// 静默退化成空项目会让用户以为字段已经填好了。
  Future<ProjectConfig> config(ProjectKind kind) async {
    final decoded = jsonDecode(await loader(assetFor(kind)));
    if (decoded is! Map) {
      throw const FormatException('模板文件不是有效的 JSON 对象');
    }
    final document = ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
    // ProjectDocument.copyWith 沿用旧 kind，模板与所选类型不一致会造出
    // 「kind 说步兵、config 是工程」的项目，向导步骤和代码生成都会错。
    if (document.kind != kind) {
      throw StateError('模板类型与所选项目类型不一致');
    }
    return document.config;
  }
}
