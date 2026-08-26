import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class SelectedDocument {
  const SelectedDocument({
    required this.reference,
    required this.name,
    required this.bytes,
  });

  final String reference;
  final String name;
  final Uint8List bytes;
}

/// Cross-platform document access.
///
/// Android references are persistent Storage Access Framework content URIs.
/// Desktop references remain ordinary file-system paths.
class AppDocumentIo {
  const AppDocumentIo();

  static const _channel = MethodChannel('cn.edu.cnu.pieblock/documents');

  Future<SelectedDocument?> open({
    required String label,
    required List<String> extensions,
    required List<String> mimeTypes,
  }) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'openDocument',
        {'mimeTypes': mimeTypes, 'extensions': extensions},
      );
      if (result == null) return null;
      return SelectedDocument(
        reference: result['uri']! as String,
        name: result['name']! as String,
        bytes: result['bytes']! as Uint8List,
      );
    }

    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions, mimeTypes: mimeTypes),
      ],
    );
    if (file == null) return null;
    return SelectedDocument(
      reference: file.path,
      name: file.name,
      bytes: await file.readAsBytes(),
    );
  }

  Future<String?> create({
    required String suggestedName,
    required String mimeType,
    Uint8List? bytes,
    String? initialDirectory,
    List<String> extensions = const [],
  }) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'createDocument',
        {
          'suggestedName': suggestedName,
          'mimeType': mimeType,
          'bytes': bytes,
          'extensions': extensions,
        },
      );
      return result?['uri'] as String?;
    }

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        XTypeGroup(
          label: suggestedName,
          extensions: extensions,
          mimeTypes: [mimeType],
        ),
      ],
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      canCreateDirectories: true,
    );
    if (location == null) return null;
    if (bytes != null) await File(location.path).writeAsBytes(bytes);
    return location.path;
  }

  Future<Uint8List> read(String reference) async {
    if (_isContentUri(reference)) {
      final bytes = await _channel.invokeMethod<Uint8List>('readDocument', {
        'uri': reference,
      });
      if (bytes == null) throw const FileSystemException('无法读取所选文档');
      return bytes;
    }
    return File(reference).readAsBytes();
  }

  Future<void> write(String reference, Uint8List bytes) async {
    if (_isContentUri(reference)) {
      await _channel.invokeMethod<void>('writeDocument', {
        'uri': reference,
        'bytes': bytes,
      });
      return;
    }
    await File(reference).writeAsBytes(bytes);
  }

  static bool _isContentUri(String reference) =>
      Platform.isAndroid && Uri.tryParse(reference)?.scheme == 'content';

  static String displayName(String reference) {
    if (Uri.tryParse(reference)?.scheme != 'content') {
      return reference.split(Platform.pathSeparator).last;
    }
    final uri = Uri.tryParse(reference);
    if (uri == null || uri.pathSegments.isEmpty) return reference;
    // `pathSegments` are already percent-decoded by `Uri`. Decoding the
    // segment again breaks filenames that contain a literal `%`.
    final decoded = uri.pathSegments.last;
    final separator = decoded.lastIndexOf(':');
    final name = separator < 0 ? decoded : decoded.substring(separator + 1);
    return name.split('/').last;
  }
}
