import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/http.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import '../controller.dart';
import '../version.dart' as app_info;
import 'approval_controller.dart';
import 'mcp_models.dart';

/// 本地 MCP 服务。
///
/// 它只做三件事：按开关起停、把 `McpHost` 接到 `AppController`、维护审计。
/// 所有业务规则都在 `packages/pieblock_mcp` 里。
final mcpServiceProvider = NotifierProvider<McpService, McpServiceState>(
  McpService.new,
);

class McpService extends Notifier<McpServiceState> {
  static const _maxAudit = 100;

  McpHttpServer? _server;
  bool _switching = false;

  @override
  McpServiceState build() {
    // 用 listen 而不是 watch：审计记录存在 state 里，build 重跑会把它清掉。
    ref.listen(
      appControllerProvider.select((state) => state.mcpEnabled),
      (_, enabled) => unawaited(enabled ? start() : stop()),
      fireImmediately: true,
    );
    // 销毁阶段不能再写 state，只能收尾 socket。
    ref.onDispose(() => unawaited(_shutdown()));
    return const McpServiceState();
  }

  Future<void> start() async {
    if (_server != null || _switching) return;
    _switching = true;
    try {
      final bridge = await _bridgeFile();
      final server = McpHttpServer(
        mcp: McpServer(host: _HostBinding(ref, onRecord: appendAudit)),
      );
      await server.start(bridgeFile: bridge);
      if (!ref.mounted) {
        // 启动过程中应用被关掉了：直接收摊，别留一个没人管的监听端口。
        await server.stop();
        return;
      }
      _server = server;
      state = state.copyWith(
        running: true,
        endpoint: server.endpoint?.toString(),
        token: server.token,
        bridgePath: bridge,
        clearError: true,
      );
    } catch (error) {
      if (ref.mounted) {
        state = McpServiceState(
          error: 'MCP 服务启动失败：$error',
          audit: state.audit,
        );
      }
    } finally {
      _switching = false;
    }
  }

  Future<void> stop() async {
    await _shutdown();
    if (!ref.mounted) return;
    try {
      ref
          .read(mcpApprovalControllerProvider.notifier)
          .rejectAll('MCP 服务已关闭，改动未应用');
    } catch (_) {
      // 容器已经销毁时读不到，忽略即可。
    }
    if (state.running) {
      state = McpServiceState(error: state.error, audit: state.audit);
    }
  }

  /// 只关 socket 与发现文件，不碰 state——销毁阶段唯一能做的事。
  Future<void> _shutdown() async {
    final server = _server;
    _server = null;
    await server?.stop();
  }

  /// 重启：端口和 token 都会变，客户端需要重新读 `mcp-bridge.json`。
  Future<void> restart() async {
    await stop();
    await start();
  }

  void appendAudit(McpAuditEntry entry) {
    if (!ref.mounted) return;
    state = state.copyWith(
      audit: [entry, ...state.audit].take(_maxAudit).toList(),
    );
  }

  Future<String> _bridgeFile() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}mcp-bridge.json';
  }
}

/// 把契约层的 `McpHost` 接到应用状态上。
class _HostBinding implements McpHost {
  _HostBinding(this.ref, {required this.onRecord});

  final Ref ref;

  /// 由 `McpService` 直接传入自己的审计方法。
  ///
  /// 这里不能 `ref.read(mcpServiceProvider.notifier)`：那会让服务 provider
  /// 在自己构造宿主时依赖自己，Riverpod 直接断言失败，所有工具调用都报 -32603。
  final void Function(McpAuditEntry entry) onRecord;

  @override
  String get appVersion => app_info.appVersion;

  @override
  int? get revision {
    final state = ref.read(appControllerProvider);
    return state.document == null ? null : state.revision;
  }

  @override
  McpSnapshot? snapshot() {
    final state = ref.read(appControllerProvider);
    final document = state.document;
    if (document == null) return null;
    return McpSnapshot(
      kind: document.kind.name,
      config: document.config.toJson(),
      issues: ProjectValidator.validate(document.config),
      steps: ref.read(appControllerProvider.notifier).stepIds(document.kind),
      currentStepId: document.guideProgress.currentStepId,
      path: state.path,
    );
  }

  @override
  List<ValidationIssue> issuesOf(ProjectConfig config) =>
      ProjectValidator.validate(config);

  @override
  Future<McpApplyResult> apply(
    McpPatchPlan plan,
    McpApprovalRequest request,
  ) => ref.read(mcpApprovalControllerProvider.notifier).enqueue(plan, request);

  @override
  void record(McpAuditEntry entry) => onRecord(entry);
}
