import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/http.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import '../controller.dart';
import '../version.dart' as app_info;
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

  /// 固定默认端口，配合持久化的 token，客户端只需配置一次。
  static const defaultPort = 47173;

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
      final identity = await _loadIdentity();
      final bridge = await _bridgeFile();
      final server = McpHttpServer(
        mcp: McpServer(host: _HostBinding(ref, onRecord: appendAudit)),
        token: identity.token,
      );
      await server.start(port: identity.port, bridgeFile: bridge);
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

  /// 重启：端口和 token 都保持不变，客户端配置无需改动。
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// 换一个新令牌：只有怀疑令牌泄露时才用，客户端要重新配一次。
  ///
  /// 端口保持不变，否则会在别的客户端配置里留下一个无效端口。
  Future<void> rotateToken() async {
    final current = await _loadIdentity();
    final file = await _identityFile();
    if (file.existsSync()) await file.delete();
    await _loadIdentity(preferredPort: current.port);
    await restart();
  }

  /// 改端口：默认端口被占用时用；令牌保持不变，客户端只改 URL 即可。
  Future<void> setPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError.value(port, 'port', '端口必须在 1024–65535 之间');
    }
    final current = await _loadIdentity();
    final file = await _identityFile();
    if (file.existsSync()) await file.delete();
    await _loadIdentity(preferredPort: port, preferredToken: current.token);
    await restart();
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

  /// 端口与令牌存在独立的 `mcp-identity.json`，退出时不删。
  ///
  /// 它和 `mcp-bridge.json` 分开：后者是运行时的发现文件，每次启动重写、退出
  /// 删除；前者是本机身份，让客户端永远不用重新配置。
  Future<File> _identityFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}mcp-identity.json',
    );
  }

  Future<({int port, String token})> _loadIdentity({
    int? preferredPort,
    String? preferredToken,
  }) async {
    final file = await _identityFile();
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final port = (decoded['port'] as num?)?.toInt();
          final token = decoded['token']?.toString();
          if (decoded['schema'] == 1 &&
              port != null &&
              port > 0 &&
              port <= 65535 &&
              token != null &&
              token.isNotEmpty) {
            return (port: port, token: token);
          }
        }
      }
    } on FormatException {
      // 文件坏了就重建，不让它把服务卡死。
    }
    final identity = (
      port: preferredPort ?? defaultPort,
      token: preferredToken ?? McpHttpServer.generateToken(),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'port': identity.port,
        'token': identity.token,
      })}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } on ProcessException {
        // 没有 chmod 的环境跳过。
      }
    }
    return identity;
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
  ) async {
    // 不做逐次弹窗：开关本身就是授权。关掉 MCP 或重置令牌即可切断外部写入。
    final state = ref.read(appControllerProvider);
    if (state.document == null) {
      return const McpApplyResult(
        McpApplyOutcome.denied,
        message: '项目已关闭，改动未应用',
      );
    }
    if (plan.baseRevision != state.revision) {
      return McpApplyResult(
        McpApplyOutcome.conflict,
        message: '项目已被改动（当前 revision ${state.revision}），改动未应用',
      );
    }
    ref.read(appControllerProvider.notifier).updateConfig(plan.config);
    return McpApplyResult(
      McpApplyOutcome.applied,
      revision: state.revision + 1,
    );
  }

  @override
  void record(McpAuditEntry entry) => onRecord(entry);
}
