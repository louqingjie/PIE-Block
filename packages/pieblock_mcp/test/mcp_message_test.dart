import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('版本协商', () {
    test('认识的版本原样回', () {
      for (final version in McpProtocol.supported) {
        expect(McpProtocol.negotiate(version), version);
      }
    });

    test('不认识的版本回最新', () {
      expect(McpProtocol.negotiate('2099-01-01'), McpProtocol.latest);
      expect(McpProtocol.negotiate(null), McpProtocol.latest);
      expect(McpProtocol.negotiate(42), McpProtocol.latest);
    });

    test('supported 列表新的在前且包含 latest', () {
      expect(McpProtocol.supported.first, McpProtocol.latest);
      expect(McpProtocol.supported, contains(McpProtocol.latest));
    });
  });

  group('initialize 结果', () {
    test('形状符合规范', () {
      final result = buildInitializeResult(
        protocolVersion: McpProtocol.latest,
        server: const McpServerInfo(
          name: 'pieblock',
          version: '1.8.0',
          instructions: '先 handshake',
        ),
      );
      expect(result['protocolVersion'], McpProtocol.latest);
      expect(result['serverInfo'], {'name': 'pieblock', 'version': '1.8.0'});
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
      expect(result['instructions'], '先 handshake');
    });

    test('instructions 为空时不下发', () {
      final result = buildInitializeResult(
        protocolVersion: McpProtocol.latest,
        server: const McpServerInfo(name: 'pieblock', version: '1.8.0'),
      );
      expect(result.containsKey('instructions'), isFalse);
    });
  });

  group('工具结果', () {
    test('成功结果带 text content', () {
      final encoded = McpToolResult.ok('已校验', {'issues': 0}).toJson();
      expect(encoded['content'], [
        {'type': 'text', 'text': '已校验'},
      ]);
      expect(encoded['structuredContent'], {'issues': 0});
      expect(encoded.containsKey('isError'), isFalse);
    });

    test('失败结果带 code 与 isError', () {
      final result = McpToolResult.failure(
        McpToolErrorCode.staleRevision,
        '项目已经被改过，请重新读取上下文',
        details: {'currentRevision': 12},
      );
      final encoded = result.toJson();
      expect(encoded['isError'], isTrue);
      expect(encoded['structuredContent'], {
        'code': 'stale_revision',
        'message': '项目已经被改过，请重新读取上下文',
        'currentRevision': 12,
      });
    });
  });

  group('工具声明', () {
    test('默认注解保守且全部下发', () {
      const spec = McpToolSpec(
        name: 'pieblock_validate',
        title: '校验',
        description: '只读校验',
        inputSchema: {'type': 'object'},
      );
      final encoded = spec.toJson();
      expect(encoded['name'], 'pieblock_validate');
      expect(encoded.containsKey('outputSchema'), isFalse);
      expect(encoded['annotations'], {
        'readOnlyHint': false,
        'destructiveHint': false,
        'idempotentHint': false,
        'openWorldHint': false,
      });
    });
  });
}
