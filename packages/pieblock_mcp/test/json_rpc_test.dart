import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('JsonRpcRequest.parse', () {
    test('解析普通请求', () {
      final request = JsonRpcRequest.parse({
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'tools/list',
        'params': {'cursor': null},
      });
      expect(request.method, 'tools/list');
      expect(request.id, 7);
      expect(request.isNotification, isFalse);
      expect(request.params, {'cursor': null});
    });

    test('没有 id 就是通知', () {
      final request = JsonRpcRequest.parse({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      expect(request.isNotification, isTrue);
      expect(request.params, isNull);
    });

    test('字符串 id 合法', () {
      final request = JsonRpcRequest.parse({
        'jsonrpc': '2.0',
        'id': 'req-1',
        'method': 'ping',
      });
      expect(request.id, 'req-1');
    });

    test('拒绝非 2.0', () {
      expect(
        () => JsonRpcRequest.parse({'jsonrpc': '1.0', 'method': 'ping'}),
        throwsA(
          isA<JsonRpcException>().having(
            (e) => e.code,
            'code',
            JsonRpcErrorCode.invalidRequest,
          ),
        ),
      );
    });

    test('拒绝缺失 method', () {
      expect(
        () => JsonRpcRequest.parse({'jsonrpc': '2.0', 'id': 1}),
        throwsA(isA<JsonRpcException>()),
      );
    });

    test('拒绝非对象的 params', () {
      expect(
        () => JsonRpcRequest.parse({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': [1, 2],
        }),
        throwsA(
          isA<JsonRpcException>().having(
            (e) => e.code,
            'code',
            JsonRpcErrorCode.invalidParams,
          ),
        ),
      );
    });

    test('拒绝非法 id 类型', () {
      expect(
        () => JsonRpcRequest.parse({
          'jsonrpc': '2.0',
          'id': {'nested': 1},
          'method': 'ping',
        }),
        throwsA(isA<JsonRpcException>()),
      );
    });

    test('空字符串 method 不合法', () {
      expect(
        () => JsonRpcRequest.parse({'jsonrpc': '2.0', 'id': 1, 'method': ''}),
        throwsA(isA<JsonRpcException>()),
      );
    });
  });

  group('JsonRpcRequest.parseBatch', () {
    test('批量请求按顺序展开', () {
      final requests = JsonRpcRequest.parseBatch([
        {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      ]);
      expect(requests, hasLength(2));
      expect(requests.last.isNotification, isTrue);
    });

    test('空批量不合法', () {
      expect(
        () => JsonRpcRequest.parseBatch(<Object?>[]),
        throwsA(isA<JsonRpcException>()),
      );
    });

    test('批量里有一条坏数据整体报错', () {
      expect(
        () => JsonRpcRequest.parseBatch([
          {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          {'jsonrpc': '2.0'},
        ]),
        throwsA(isA<JsonRpcException>()),
      );
    });
  });

  group('参数助手', () {
    test('requireString 取值', () {
      const request = JsonRpcRequest(
        method: 'x',
        params: {'name': 'pieblock_validate'},
      );
      expect(request.requireString('name'), 'pieblock_validate');
    });

    test('requireString 缺失时报 invalid params', () {
      const request = JsonRpcRequest(method: 'x', params: {});
      expect(
        () => request.requireString('name'),
        throwsA(
          isA<JsonRpcException>().having(
            (e) => e.code,
            'code',
            JsonRpcErrorCode.invalidParams,
          ),
        ),
      );
    });
  });

  group('应答编码', () {
    test('成功应答带 id 与 result', () {
      expect(jsonRpcSuccess(1, {'ok': true}), {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'ok': true},
      });
    });

    test('失败应答带 error 对象', () {
      final encoded = jsonRpcFailure(
        2,
        const JsonRpcException(
          JsonRpcErrorCode.methodNotFound,
          '未知方法',
          data: {'method': 'x'},
        ),
      );
      expect(encoded['jsonrpc'], '2.0');
      expect(encoded['id'], 2);
      expect(encoded['error'], {
        'code': JsonRpcErrorCode.methodNotFound,
        'message': '未知方法',
        'data': {'method': 'x'},
      });
    });
  });
}
