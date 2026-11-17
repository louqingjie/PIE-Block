// 冒烟脚本：进程内起一个 MCP 服务，再用最小客户端走完整链路。
//
// 用法：dart run tool/mcp_smoke.dart
//
// 覆盖：initialize → tools/list → handshake → get_context → propose → apply
// → 校验 revision 与配置确实变了。审批在这里自动通过，真实宿主会弹卡片。

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/http.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

/// 只服务本脚本的宿主：没有界面，审批直接放行。
class _DemoHost implements McpHost {
  _DemoHost(this.document);

  ProjectDocument document;
  int _revision = 0;

  @override
  String get appVersion => 'smoke';

  @override
  int? get revision => _revision;

  @override
  McpSnapshot? snapshot() => McpSnapshot(
    kind: document.kind.name,
    config: document.config.toJson(),
    issues: ProjectValidator.validate(document.config),
    steps: const ['remote', 'mechanism', 'controls', 'review', 'code', 'deploy'],
    currentStepId: document.guideProgress.currentStepId,
  );

  @override
  List<ValidationIssue> issuesOf(ProjectConfig config) =>
      ProjectValidator.validate(config);

  @override
  Future<McpApplyResult> apply(
    McpPatchPlan plan,
    McpApprovalRequest request,
  ) async {
    document = document.copyWith(config: plan.config);
    _revision += 1;
    return McpApplyResult(McpApplyOutcome.applied, revision: _revision);
  }

  @override
  void record(McpAuditEntry entry) {}
}

Future<Map<String, Object?>> post(
  HttpClient client,
  Uri uri,
  String token,
  Object payload,
) async {
  final request = await client.postUrl(uri);
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
    ..contentType = ContentType.json;
  request.write(jsonEncode(payload));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}: $body');
  }
  return Map<String, Object?>.from(jsonDecode(body) as Map);
}

Future<Map<String, Object?>> call(
  HttpClient client,
  Uri uri,
  String token,
  String name, [
  Map<String, Object?> arguments = const {},
]) async {
  final response = await post(client, uri, token, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  });
  final result = Map<String, Object?>.from(response['result'] as Map);
  if (result['isError'] == true) {
    throw StateError('$name 失败：${result['content']}');
  }
  return Map<String, Object?>.from(result['structuredContent'] as Map);
}

Future<void> main() async {
  final host = _DemoHost(ProjectDocument.create(ProjectKind.infantry));
  final server = McpHttpServer(
    mcp: McpServer(host: host),
    token: 'smoke-token',
  );
  final client = HttpClient();
  var failures = 0;

  void check(bool condition, String message) {
    stdout.writeln('${condition ? '  ok' : 'FAIL'}  $message');
    if (!condition) failures += 1;
  }

  await server.start();
  try {
    final uri = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    stdout.writeln('MCP 冒烟：${server.endpoint}');

    final initialize = await post(client, uri, 'smoke-token', {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': McpProtocol.latest,
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'smoke', 'version': '0'},
      },
    });
    final initResult = Map<String, Object?>.from(initialize['result'] as Map);
    check(
      initResult['protocolVersion'] == McpProtocol.latest,
      'initialize 协商到 ${initResult['protocolVersion']}',
    );

    final tools = await post(client, uri, 'smoke-token', {
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    final listed = ((tools['result'] as Map)['tools'] as List).length;
    check(listed == McpToolRegistry.toolNames.length, 'tools/list 返回 $listed 个工具');

    final handshake = await call(client, uri, 'smoke-token', 'pieblock_handshake');
    final project = Map<String, Object?>.from(handshake['project'] as Map);
    check(project['revision'] == 0, 'handshake 报告 revision 0');

    final context = await call(
      client,
      uri,
      'smoke-token',
      'pieblock_get_context',
      {'stepId': 'remote'},
    );
    final fields = (context['fields'] as List).length;
    check(fields > 0, 'get_context 返回 $fields 个字段');

    final patch = await call(
      client,
      uri,
      'smoke-token',
      'pieblock_propose_patch',
      {
        'baseRevision': 0,
        'ops': [
          {'op': 'set', 'path': 'chassis.normal_speed', 'value': 4200},
        ],
      },
    );
    check(patch['patchId'] is String, 'propose 返回 patchId');
    check((patch['diff'] as List).length == 1, 'propose 返回 1 条 diff');

    final applied = await call(
      client,
      uri,
      'smoke-token',
      'pieblock_apply_patch',
      {'patchId': patch['patchId']},
    );
    check(applied['revision'] == 1, 'apply 后 revision 变为 1');
    check(
      (host.document.config as InfantryConfig).chassis.normalSpeed == 4200,
      '配置确实写进去了',
    );

    final stale = await post(client, uri, 'smoke-token', {
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'pieblock_propose_patch',
        'arguments': {
          'baseRevision': 0,
          'ops': [
            {'op': 'set', 'path': 'chassis.normal_speed', 'value': 5000},
          ],
        },
      },
    });
    final staleResult = Map<String, Object?>.from(stale['result'] as Map);
    final staleData = Map<String, Object?>.from(
      staleResult['structuredContent'] as Map,
    );
    check(
      staleResult['isError'] == true &&
          staleData['code'] == McpToolErrorCode.staleRevision,
      '旧 revision 被拒为 stale_revision',
    );
  } finally {
    client.close(force: true);
    await server.stop();
  }

  if (failures > 0) {
    stderr.writeln('冒烟失败：$failures 项');
    exitCode = 1;
  } else {
    stdout.writeln('冒烟通过');
  }
}
