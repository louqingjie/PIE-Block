import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

ProjectDocument loadFixture(String name) {
  final file = File('../pieblock_core/test/fixtures/$name');
  return ProjectDocument.fromJson(
    Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
  );
}

Future<Map<String, Object?>> send(
  McpServer server,
  String method, {
  Object? id = 1,
  Map<String, Object?>? params,
}) async {
  final response = await server.handlePayload({
    'jsonrpc': '2.0',
    'id': ?id,
    'method': method,
    'params': ?params,
  });
  return Map<String, Object?>.from(response as Map);
}

Future<Map<String, Object?>> callTool(
  McpServer server,
  String name, [
  Map<String, Object?> arguments = const {},
]) async {
  final response = await send(
    server,
    McpMethod.toolsCall,
    params: {'name': name, 'arguments': arguments},
  );
  return Map<String, Object?>.from(response['result'] as Map);
}

Map<String, Object?> structured(Map<String, Object?> result) =>
    Map<String, Object?>.from(result['structuredContent'] as Map);

void main() {
  group('会话分发', () {
    test('initialize 协商版本并声明 tools 能力', () async {
      final server = McpServer(host: FakeHost());
      final response = await send(
        server,
        McpMethod.initialize,
        params: {'protocolVersion': '2025-03-26'},
      );
      final result = Map<String, Object?>.from(response['result'] as Map);
      expect(result['protocolVersion'], '2025-03-26');
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
      expect((result['serverInfo'] as Map)['name'], 'pieblock');
      expect(server.protocolVersion, '2025-03-26');
    });

    test('tools/list 列出六个工具且都带 schema', () async {
      final server = McpServer(host: FakeHost());
      final response = await send(server, McpMethod.toolsList);
      final tools = (response['result'] as Map)['tools'] as List;
      expect(tools, hasLength(6));
      expect(
        tools.map((tool) => (tool as Map)['name']),
        containsAll(McpToolRegistry.toolNames),
      );
      for (final tool in tools) {
        expect((tool as Map)['description'], isNotEmpty);
        expect(tool['inputSchema']['type'], 'object');
      }
    });

    test('通知不回包', () async {
      final server = McpServer(host: FakeHost());
      final response = await server.handlePayload({
        'jsonrpc': '2.0',
        'method': McpMethod.initialized,
      });
      expect(response, isNull);
    });

    test('未知方法返回 methodNotFound', () async {
      final server = McpServer(host: FakeHost());
      final response = await send(server, 'resources/list');
      final error = Map<String, Object?>.from(response['error'] as Map);
      expect(error['code'], JsonRpcErrorCode.methodNotFound);
    });

    test('tools/call 缺 name 返回 invalidParams', () async {
      final server = McpServer(host: FakeHost());
      final response = await send(
        server,
        McpMethod.toolsCall,
        params: {'arguments': <String, Object?>{}},
      );
      final error = Map<String, Object?>.from(response['error'] as Map);
      expect(error['code'], JsonRpcErrorCode.invalidParams);
    });

    test('未知工具返回 invalidParams', () async {
      final server = McpServer(host: FakeHost());
      final response = await send(
        server,
        McpMethod.toolsCall,
        params: {'name': 'pieblock_hack'},
      );
      final error = Map<String, Object?>.from(response['error'] as Map);
      expect(error['code'], JsonRpcErrorCode.invalidParams);
    });

    test('非法 JSON 返回 parse error 且 id 为 null', () async {
      final server = McpServer(host: FakeHost());
      final response = await server.handlePayload({'boom': true});
      final map = Map<String, Object?>.from(response as Map);
      expect(map['id'], isNull);
      expect(
        (map['error'] as Map)['code'],
        JsonRpcErrorCode.invalidRequest,
      );
    });
  });

  group('handshake', () {
    test('没有项目时 project 为 null', () async {
      final server = McpServer(host: FakeHost());
      final result = await callTool(server, 'pieblock_handshake');
      final data = structured(result);
      expect(data['project'], isNull);
      expect(data['projectFormatVersion'], ProjectDocument.formatVersion);
      expect(result['content'], isNotEmpty);
    });

    test('有项目时给出类型、revision 与步骤', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final data = structured(await callTool(server, 'pieblock_handshake'));
      final project = Map<String, Object?>.from(data['project'] as Map);
      expect(project['kind'], 'infantry');
      expect(project['revision'], 0);
      expect(project['steps'], contains('mechanism'));
    });

    test('没有项目时读写工具都返回 no_project', () async {
      final server = McpServer(host: FakeHost());
      for (final tool in [
        'pieblock_get_context',
        'pieblock_validate',
        'pieblock_propose_patch',
        'pieblock_generate_code',
      ]) {
        final result = await callTool(server, tool);
        expect(result['isError'], isTrue, reason: tool);
        expect(structured(result)['code'], McpToolErrorCode.noProject);
      }
    });
  });

  group('get_context', () {
    test('按步骤过滤', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final data = structured(
        await callTool(server, 'pieblock_get_context', {'stepId': 'controls'}),
      );
      final fields = (data['fields'] as List).cast<Map>();
      expect(fields, isNotEmpty);
      expect(fields.every((field) => field['step'] == 'controls'), isTrue);
    });

    test('未知步骤给出可用列表', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final result = await callTool(server, 'pieblock_get_context', {
        'stepId': 'nope',
      });
      expect(result['isError'], isTrue);
      expect(structured(result)['message'], contains('remote'));
    });

    test('数组字段聚合成一条并给出数量', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.music));
      final server = McpServer(host: host);
      final data = structured(
        await callTool(server, 'pieblock_get_context', {'stepId': 'music'}),
      );
      final notes = (data['fields'] as List)
          .cast<Map>()
          .firstWhere((field) => field['path'] == 'notes[*].pitch');
      expect(notes['aggregate'], isTrue);
      expect(notes['arrayCount'], 0);
    });

    test('全量上下文带截断标记', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.engineer));
      final server = McpServer(host: host);
      final data = structured(await callTool(server, 'pieblock_get_context'));
      expect(data['fields'], isNotEmpty);
      expect(data['truncated'], isA<bool>());
    });
  });

  group('validate', () {
    test('校验当前配置', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final result = await callTool(server, 'pieblock_validate');
      final data = structured(result);
      expect(data['errorCount'], greaterThan(0));
      expect(data['issues'], isNotEmpty);
    });

    test('校验传入的假设配置', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final data = structured(
        await callTool(server, 'pieblock_validate', {
          'config': ProjectDocument.create(ProjectKind.infantry).config.toJson(),
        }),
      );
      expect(data['issues'], isNotEmpty);
    });

    test('config 类型不对时报错', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final result = await callTool(server, 'pieblock_validate', {'config': 1});
      expect(result['isError'], isTrue);
    });
  });

  group('propose / apply', () {
    late FakeHost host;
    late McpServer server;

    setUp(() {
      host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      server = McpServer(host: host);
    });

    Future<Map<String, Object?>> proposeNormalSpeed(num value) async =>
        structured(
          await callTool(server, 'pieblock_propose_patch', {
            'baseRevision': 0,
            'ops': [
              {'op': 'set', 'path': 'chassis.normal_speed', 'value': value},
            ],
          }),
        );

    test('propose 不修改文档', () async {
      final data = await proposeNormalSpeed(4000);
      expect(data['patchId'], isNotEmpty);
      expect(host.revision, 0);
      expect(host.appliedCount, 0);
      expect((data['diff'] as List).single['label'], '普通速度');
    });

    test('baseRevision 过期返回 stale_revision', () async {
      final result = await callTool(server, 'pieblock_propose_patch', {
        'baseRevision': 9,
        'ops': [
          {'op': 'set', 'path': 'chassis.normal_speed', 'value': 4000},
        ],
      });
      expect(result['isError'], isTrue);
      final data = structured(result);
      expect(data['code'], McpToolErrorCode.staleRevision);
      expect(data['currentRevision'], 0);
    });

    test('用户拒绝时返回 denied 且不改文档', () async {
      final data = await proposeNormalSpeed(4000);
      host.decide = (_) async =>
          const McpApplyResult(McpApplyOutcome.denied, message: '用户点了拒绝');
      final result = await callTool(server, 'pieblock_apply_patch', {
        'patchId': data['patchId'],
      });
      expect(result['isError'], isTrue);
      expect(structured(result)['code'], McpToolErrorCode.denied);
      expect(host.appliedCount, 0);
      expect(host.revision, 0);
    });

    test('确认超时返回 approval_timeout', () async {
      final data = await proposeNormalSpeed(4000);
      host.decide = (_) async =>
          const McpApplyResult(McpApplyOutcome.timeout, message: '等待超时');
      final result = await callTool(server, 'pieblock_apply_patch', {
        'patchId': data['patchId'],
      });
      expect(structured(result)['code'], McpToolErrorCode.approvalTimeout);
      expect(host.appliedCount, 0);
    });

    test('确认后写入并递增 revision', () async {
      final data = await proposeNormalSpeed(4000);
      host.decide = (request) async {
        expect(request.diff.single.after, 4000);
        return const McpApplyResult(McpApplyOutcome.applied, revision: 1);
      };
      final result = await callTool(server, 'pieblock_apply_patch', {
        'patchId': data['patchId'],
      });
      final applied = structured(result);
      expect(applied['revision'], 1);
      expect(host.revision, 1);
      expect(host.appliedCount, 1);
      final config = host.snapshot()!.config;
      expect((config['chassis'] as Map)['normal_speed'], 4000);
    });

    test('patchId 只能用一次', () async {
      final data = await proposeNormalSpeed(4000);
      host.decide = (_) async =>
          const McpApplyResult(McpApplyOutcome.denied, message: '拒绝');
      await callTool(server, 'pieblock_apply_patch', {'patchId': data['patchId']});
      final second = await callTool(server, 'pieblock_apply_patch', {
        'patchId': data['patchId'],
      });
      expect(structured(second)['code'], McpToolErrorCode.patchExpired);
    });

    test('未知字段返回 invalid_path', () async {
      final result = await callTool(server, 'pieblock_propose_patch', {
        'baseRevision': 0,
        'ops': [
          {'op': 'set', 'path': 'chassis.magic', 'value': 1},
        ],
      });
      expect(structured(result)['code'], McpToolErrorCode.invalidPath);
    });

    test('审计记录每次工具调用', () async {
      await proposeNormalSpeed(4000);
      await callTool(server, 'pieblock_handshake');
      expect(host.audits.map((entry) => entry.method), contains('pieblock_handshake'));
      expect(
        host.audits.any((entry) => entry.method == 'pieblock_propose_patch'),
        isTrue,
      );
    });
  });

  group('generate_code', () {
    test('配置有错误时拒绝生成', () async {
      final host = FakeHost(document: ProjectDocument.create(ProjectKind.infantry));
      final server = McpServer(host: host);
      final result = await callTool(server, 'pieblock_generate_code');
      expect(result['isError'], isTrue);
      expect(structured(result)['code'], McpToolErrorCode.incompleteConfig);
    });

    test('合法配置返回分页代码', () async {
      final host = FakeHost(document: loadFixture('format18_debug.pieproj'));
      final server = McpServer(host: host);
      final result = await callTool(server, 'pieblock_generate_code', {
        'limit': 5,
      });
      final data = structured(result);
      expect(data['lines'], hasLength(5));
      expect(data['totalLines'], greaterThan(5));
      expect(data['hasMore'], isTrue);
    });
  });
}
