import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'document_io.dart';
import 'paths.dart';

/// 导出对话框：能输入完整路径，也能点「浏览」调系统文件管理器。
///
/// - 桌面：`浏览` 回填系统保存对话框选出的路径，`导出` 再落盘；路径框可自由编辑。
/// - Android：SAF 没有可输入的路径，`浏览` 与 `导出` 都直接走系统文档选择器写入
///   内容（不再用 `File(路径)` 写盘，那在 scoped storage 下必然失败）。
///
/// [documentIo] 只为测试注入，默认走各平台真实实现。
Future<bool> exportGeneratedText(
  BuildContext context, {
  required String suggestedName,
  required String text,
  String mimeType = 'text/plain',
  AppDocumentIo documentIo = const AppDocumentIo(),
}) async {
  final desktop = defaultDesktopDirectory();
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final extension = _extensionOf(suggestedName);
  final path = TextEditingController(
    text: desktop == null
        ? suggestedName
        : '$desktop${Platform.pathSeparator}$suggestedName',
  );
  var saved = false;

  void notify(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Android：交给系统文档选择器直接落盘（SAF 返回的是 content URI）。
  Future<void> saveViaSystemPicker() async {
    try {
      final reference = await documentIo.create(
        suggestedName: suggestedName,
        mimeType: mimeType,
        bytes: Uint8List.fromList(utf8.encode(text)),
        extensions: [extension],
      );
      if (reference == null) return;
      saved = true;
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      notify('导出失败：$error');
    }
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('导出 $suggestedName'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('export-path-field'),
              controller: path,
              readOnly: android,
              decoration: InputDecoration(
                labelText: android ? '保存到' : '完整文件路径',
                helperText: android
                    ? '使用系统文档选择器保存，可在导出时选择'
                    : '可直接输入，或点「浏览」选择位置',
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('export-browse'),
              onPressed: () async {
                if (android) return saveViaSystemPicker();
                final current = path.text.trim();
                try {
                  final selected = await documentIo.create(
                    suggestedName: suggestedName,
                    mimeType: mimeType,
                    extensions: [extension],
                    initialDirectory: current.isEmpty
                        ? null
                        : File(current).parent.path,
                  );
                  if (selected != null && context.mounted) path.text = selected;
                } catch (error) {
                  notify('无法打开文件管理器：$error');
                }
              },
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('浏览'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (android) return saveViaSystemPicker();
            try {
              // 走 documentIo 而不是直接 File(...)：Android 的 content URI 与
              // 桌面路径共用同一条写入路径，测试也能注入假实现。
              await documentIo.write(
                path.text.trim(),
                Uint8List.fromList(utf8.encode(text)),
              );
            } catch (error) {
              notify('导出失败：$error');
              return;
            }
            saved = true;
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('导出'),
        ),
      ],
    ),
  );
  return saved;
}

/// 取文件名后缀用于系统保存对话框的类型过滤；没有后缀时给个兜底。
String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return 'txt';
  return fileName.substring(dot + 1);
}
