import 'dart:convert';
import 'dart:io';

/// 读取 Windows 工具链产出的文本文件（SDCC MAP、列表文件、Keil 日志）。
///
/// SDCC/ASlink 与 Keil 在 Windows 上按系统 ANSI 代码页写这些文件：只要路径里
/// 有中文（例如 `C:\Users\吕先生\AppData\...`），文件里就会出现 GBK 等非
/// UTF-8 字节，直接 [File.readAsString] 会抛
/// `Failed to decode data using encoding 'utf-8'`。
///
/// 构建链只需要识别 ASCII 关键字、区域与符号名，因此这里按 UTF-8 宽松解码：
/// 非法字节替换为 U+FFFD，不会中断构建。
Future<String> readToolOutputText(String path) async =>
    utf8.decode(await File(path).readAsBytes(), allowMalformed: true);
