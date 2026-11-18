import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/mcp/mcp_models.dart';
import 'package:pieblock_app/src/mcp/mcp_service.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 让服务把发现文件写到临时目录，不碰真实应用数据。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}

class _DocController extends AppController {
  _DocController(this.document);

  final ProjectDocument document;

  @override
  AppState build() => AppState(document: document);
}

/// 固定端口可能被用户正在运行的 PIE-Block 占用，测试里先挑一个空闲端口。
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _seedIdentity(Directory directory, int port, String token) async {
  await File(
    '${directory.path}${Platform.pathSeparator}mcp-identity.json',
  ).writeAsString(
    jsonEncode({'schema': 1, 'port': port, 'token': token}),
  );
}

Future<McpServiceState> _wait(
  ProviderContainer container, {
  required bool running,
  String? previousToken,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = container.read(mcpServiceProvider);
    if (state.running == running &&
        (previousToken == null || state.token != previousToken)) {
      return state;
    }
  }
  throw StateError('等待 MCP 服务状态超时：running=$running');
}

void main() {
  test('本地服务能完整响应工具调用（审计不得造成 provider 自依赖）', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock_mcp_service');
    final testPort = await _freePort();
    await _seedIdentity(directory, testPort, 'test-token');
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(directory);
    addTearDown(() {
      PathProviderPlatform.instance = previousPathProvider;
      directory.deleteSync(recursive: true);
    });

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          () => _DocController(ProjectDocument.create(ProjectKind.infantry)),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(appControllerProvider.notifier).setMcpEnabled(true);

    // start() 里有异步路径解析：等它真正监听成功，或拿到失败原因。
    late McpServiceState service;
    for (var attempt = 0; attempt < 50; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service = container.read(mcpServiceProvider);
      if (service.running || service.error != null) break;
    }
    expect(service.error, isNull, reason: '服务启动失败：${service.error}');
    expect(service.running, isTrue);
    expect(service.endpoint, isNotNull);
    expect(service.token, isNotNull);
    expect(File(service.bridgePath!).existsSync(), isTrue);

    final client = HttpClient();
    addTearDown(client.close);
    final uri = Uri.parse('${service.endpoint}?token=${service.token}');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': 'pieblock_handshake', 'arguments': <String, Object?>{}},
    }));
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    final decoded = Map<String, Object?>.from(jsonDecode(raw) as Map);

    expect(response.statusCode, 200, reason: raw);
    expect(decoded['error'], isNull, reason: raw);
    final result = Map<String, Object?>.from(decoded['result'] as Map);
    expect(result['isError'], isNot(true), reason: raw);
    final data = Map<String, Object?>.from(result['structuredContent'] as Map);
    expect((data['project'] as Map)['kind'], 'infantry');

    container.read(appControllerProvider.notifier).setMcpEnabled(false);
  });

  test('端口与令牌跨重启保持，只有主动重置才变化', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock_mcp_identity');
    final testPort = await _freePort();
    await _seedIdentity(directory, testPort, 'test-token');
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(directory);
    addTearDown(() {
      PathProviderPlatform.instance = previousPathProvider;
      directory.deleteSync(recursive: true);
    });

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          () => _DocController(ProjectDocument.create(ProjectKind.infantry)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final app = container.read(appControllerProvider.notifier);
    final service = container.read(mcpServiceProvider.notifier);

    app.setMcpEnabled(true);
    final first = await _wait(container, running: true);
    expect(first.endpoint, contains(':$testPort/mcp'));

    app.setMcpEnabled(false);
    await _wait(container, running: false);
    expect(File('${directory.path}${Platform.pathSeparator}mcp-bridge.json')
        .existsSync(), isFalse);

    app.setMcpEnabled(true);
    final second = await _wait(container, running: true);
    expect(second.endpoint, first.endpoint);
    expect(second.token, first.token);
    expect(File('${directory.path}${Platform.pathSeparator}mcp-identity.json')
        .existsSync(), isTrue);

    await service.rotateToken();
    final third = await _wait(
      container,
      running: true,
      previousToken: first.token,
    );
    expect(third.endpoint, first.endpoint);
    expect(third.token, isNot(first.token));

    app.setMcpEnabled(false);
  });
}
