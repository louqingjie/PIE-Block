import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/http.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

typedef Reply = ({int status, String? contentType, Object? body});

Reply _decode(HttpClientResponse response, String raw) => (
  status: response.statusCode,
  contentType: response.headers.contentType?.mimeType,
  body: raw.isEmpty ? null : jsonDecode(raw),
);

Future<Reply> request(
  McpHttpServer server,
  String method,
  String path, {
  Object? payload,
  String? bearer,
  String? queryToken,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(
      'http://127.0.0.1:${server.port}$path'
      '${queryToken == null ? '' : '?token=$queryToken'}',
    );
    final outgoing = await client.openUrl(method, uri);
    if (bearer != null) {
      outgoing.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    if (payload != null) {
      outgoing.headers.contentType = ContentType.json;
      outgoing.write(jsonEncode(payload));
    }
    final response = await outgoing.close();
    final raw = await response.transform(utf8.decoder).join();
    return _decode(response, raw);
  } finally {
    client.close(force: true);
  }
}

const _initialize = {
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': {
    'protocolVersion': '2025-06-18',
    'capabilities': <String, Object?>{},
    'clientInfo': {'name': 'test', 'version': '0'},
  },
};

void main() {
  late McpHttpServer server;

  setUp(() async {
    server = McpHttpServer(
      mcp: McpServer(
        host: FakeHost(document: ProjectDocument.create(ProjectKind.infantry)),
      ),
      token: 'test-token',
    );
    await server.start();
  });

  tearDown(() async => server.stop());

  group('路由与鉴权', () {
    test('只绑 127.0.0.1 并给出可用端点', () {
      expect(server.port, isNotNull);
      expect(server.endpoint.toString(), contains('127.0.0.1'));
      expect(server.endpoint!.path, '/mcp');
    });

    test('没有 token 返回 401', () async {
      final reply = await request(server, 'POST', '/mcp', payload: _initialize);
      expect(reply.status, 401);
      expect(reply.body, {'error': 'unauthorized'});
    });

    test('token 不对返回 401', () async {
      final reply = await request(
        server,
        'POST',
        '/mcp',
        payload: _initialize,
        bearer: 'wrong',
      );
      expect(reply.status, 401);
    });

    test('查询参数带 token 也能过', () async {
      final reply = await request(
        server,
        'POST',
        '/mcp',
        payload: _initialize,
        queryToken: 'test-token',
      );
      expect(reply.status, 200);
    });

    test('路径不对返回 404', () async {
      final reply = await request(
        server,
        'POST',
        '/other',
        payload: _initialize,
        bearer: 'test-token',
      );
      expect(reply.status, 404);
    });

    test('GET 返回 405 且声明 Allow', () async {
      final client = HttpClient();
      final outgoing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      );
      final response = await outgoing.close();
      await response.drain<void>();
      expect(response.statusCode, 405);
      expect(response.headers.value(HttpHeaders.allowHeader), 'POST');
      client.close(force: true);
    });
  });

  group('消息往返', () {
    test('initialize 正常返回 JSON', () async {
      final reply = await request(
        server,
        'POST',
        '/mcp',
        payload: _initialize,
        bearer: 'test-token',
      );
      expect(reply.status, 200);
      expect(reply.contentType, 'application/json');
      final body = Map<String, Object?>.from(reply.body! as Map);
      final result = Map<String, Object?>.from(body['result'] as Map);
      expect(result['protocolVersion'], '2025-06-18');
    });

    test('通知回 202 且没有 body', () async {
      final reply = await request(
        server,
        'POST',
        '/mcp',
        payload: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        bearer: 'test-token',
      );
      expect(reply.status, 202);
      expect(reply.body, isNull);
    });

    test('批量请求回数组', () async {
      final reply = await request(
        server,
        'POST',
        '/mcp',
        payload: [
          _initialize,
          {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
        ],
        bearer: 'test-token',
      );
      expect(reply.status, 200);
      expect(reply.body, isA<List>());
    });

    test('坏 JSON 返回 400 与 parse error', () async {
      final client = HttpClient();
      final outgoing = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      );
      outgoing.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer test-token',
      );
      outgoing.write('{not json');
      final response = await outgoing.close();
      final raw = await response.transform(utf8.decoder).join();
      client.close(force: true);
      expect(response.statusCode, 400);
      final body = Map<String, Object?>.from(jsonDecode(raw) as Map);
      expect((body['error'] as Map)['code'], JsonRpcErrorCode.parseError);
    });

    test('请求体超限返回 413', () async {
      final small = McpHttpServer(
        mcp: McpServer(host: FakeHost()),
        token: 'tiny',
        maxBodyBytes: 32,
      );
      await small.start();
      try {
        final reply = await request(
          small,
          'POST',
          '/mcp',
          payload: _initialize,
          bearer: 'tiny',
        );
        expect(reply.status, 413);
      } finally {
        await small.stop();
      }
    });
  });

  group('发现文件', () {
    test('启动写 bridge.json，退出删除', () async {
      final dir = await Directory.systemTemp.createTemp('pieblock_mcp_test');
      final bridge = '${dir.path}/bridge.json';
      final local = McpHttpServer(
        mcp: McpServer(host: FakeHost()),
        token: 'bridge-token',
      );
      await local.start(bridgeFile: bridge);
      try {
        final file = File(bridge);
        expect(file.existsSync(), isTrue);
        final info = Map<String, Object?>.from(
          jsonDecode(file.readAsStringSync()) as Map,
        );
        expect(info['token'], 'bridge-token');
        expect(info['port'], local.port);
        expect(info['endpoint'], contains('127.0.0.1'));
        expect(info['pid'], pid);
      } finally {
        await local.stop();
      }
      expect(File(bridge).existsSync(), isFalse);
      await dir.delete(recursive: true);
    });
  });
}
