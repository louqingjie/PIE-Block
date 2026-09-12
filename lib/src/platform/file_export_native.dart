import 'dart:io';

import 'package:flutter/material.dart';

import 'paths.dart';

Future<bool> exportGeneratedText(
  BuildContext context, {
  required String suggestedName,
  required String text,
  String mimeType = 'text/plain',
}) async {
  final desktop = defaultDesktopDirectory();
  final path = TextEditingController(
    text: desktop == null
        ? suggestedName
        : '$desktop${Platform.pathSeparator}$suggestedName',
  );
  var saved = false;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('导出 $suggestedName'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: TextField(
            controller: path,
            decoration: const InputDecoration(labelText: '完整文件路径'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await File(path.text).writeAsString(text);
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
