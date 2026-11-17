/// 传输无关的 MCP 会话核心：一条 JSON-RPC 消息进来，一条响应出去。
///
/// HTTP 层只负责鉴权、路由与序列化，stdio 之类的其它传输将来也接在这里，
/// 不用改业务。
library;

import '../domain/host.dart';
import '../domain/patch.dart';
import '../protocol/json_rpc.dart';
import '../protocol/mcp_message.dart';
import '../tools/registry.dart';

/// 给模型看的工作流说明，随 `initialize` 下发。
const defaultInstructions = '''
PIE-Block 是 RoboMaster 机器人的图形化配置工具。推荐流程：
1. pieblock_handshake 看当前项目与 revision；
2. pieblock_get_context 读要改的字段（只有这里列出的字段可写）；
3. pieblock_propose_patch 提交改动草案，读 diff 与改动后的校验结果；
4. 把改动讲给用户听，再 pieblock_apply_patch；用户在窗口里点确认后才会写入。
revision 过期就重新读上下文，不要重试同一份补丁。''';

/// MCP 会话。
class McpServer {
  McpServer({
    required this.host,
    this.serverName = 'pieblock',
    PatchEngine? engine,
  }) : engine = engine ?? PatchEngine() {
    registry = McpToolRegistry(
      host: host,
      engine: this.engine,
      protocolVersion: _protocolVersion,
    );
  }

  final McpHost host;
  final String serverName;
  final PatchEngine engine;

  late final McpToolRegistry registry;

  String _protocolVersion = McpProtocol.latest;
  String get protocolVersion => _protocolVersion;

  McpServerInfo get serverInfo => McpServerInfo(
    name: serverName,
    version: host.appVersion,
    title: 'PIE-Block',
    instructions: defaultInstructions,
  );

  /// 处理一条已解码的 JSON 消息体（单条或批量）。
  ///
  /// 返回要写回的 JSON 对象：批量请求回数组，通知与「只有通知的批量」回 null。
  Future<Object?> handlePayload(Object? payload) async {
    final isBatch = payload is List;
    final List<JsonRpcRequest> requests;
    try {
      requests = JsonRpcRequest.parseBatch(payload);
    } on JsonRpcException catch (error) {
      return jsonRpcFailure(null, error);
    }
    final responses = <Object?>[];
    for (final request in requests) {
      final response = await handle(request);
      if (response != null) responses.add(response);
    }
    if (responses.isEmpty) return null;
    return isBatch ? responses : responses.first;
  }

  /// 处理单条请求；通知返回 null。
  Future<Map<String, Object?>?> handle(JsonRpcRequest request) async {
    try {
      switch (request.method) {
        case McpMethod.initialize:
          _protocolVersion = McpProtocol.negotiate(
            request.params?['protocolVersion'],
          );
          registry.protocolVersion = _protocolVersion;
          return jsonRpcSuccess(
            request.id,
            buildInitializeResult(
              protocolVersion: _protocolVersion,
              server: serverInfo,
            ),
          );

        case McpMethod.initialized:
        case McpMethod.cancelled:
          // 通知：不需要回包。
          return null;

        case McpMethod.ping:
          return jsonRpcSuccess(request.id, <String, Object?>{});

        case McpMethod.toolsList:
          return jsonRpcSuccess(request.id, {
            'tools': [for (final tool in registry.tools) tool.toJson()],
          });

        case McpMethod.toolsCall:
          return await _callTool(request);

        default:
          throw JsonRpcException(
            JsonRpcErrorCode.methodNotFound,
            '未知方法 ${request.method}',
            data: {'method': request.method},
          );
      }
    } on JsonRpcException catch (error) {
      return request.isNotification ? null : jsonRpcFailure(request.id, error);
    } catch (error) {
      // 兜底：任何未预期的异常都要变成合法响应，否则客户端会一直等。
      return request.isNotification
          ? null
          : jsonRpcFailure(
              request.id,
              JsonRpcException(
                JsonRpcErrorCode.internalError,
                '服务内部错误：$error',
              ),
            );
    }
  }

  Future<Map<String, Object?>> _callTool(JsonRpcRequest request) async {
    final name = request.requireString('name');
    final rawArguments = request.params?['arguments'];
    final arguments = rawArguments is Map
        ? Map<String, Object?>.from(rawArguments)
        : const <String, Object?>{};

    final revisionBefore = host.revision;
    final result = await registry.call(name, arguments);
    host.record(
      McpAuditEntry(
        at: DateTime.now(),
        method: name,
        outcome: result.isError
            ? (result.structuredContent?['code']?.toString() ?? 'error')
            : 'ok',
        revisionBefore: revisionBefore,
        revisionAfter: host.revision,
        detail: result.isError ? result.text : null,
      ),
    );
    return jsonRpcSuccess(request.id, result.toJson());
  }
}
