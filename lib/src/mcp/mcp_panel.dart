import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import '../controller.dart';
import 'mcp_models.dart';
import 'mcp_service.dart';

/// 打开「AI 接入」面板。
Future<void> showMcpPanel(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const McpPanel(),
);

/// AI 接入面板：开关、连接信息、审计记录。
///
/// P0 不自动改写任何客户端配置，只把连接信息摆出来让用户复制——写别人环境里
/// 的文件是下一步的事，先把「能连上、能审批」验证清楚。
class McpPanel extends ConsumerWidget {
  const McpPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      appControllerProvider.select((state) => state.mcpEnabled),
    );
    final service = ref.watch(mcpServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('AI 接入（MCP）'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: mcpSupported
                    ? (value) => ref
                          .read(appControllerProvider.notifier)
                          .setMcpEnabled(value)
                    : null,
                title: const Text('允许外部 AI 读写当前项目'),
                subtitle: Text(
                  mcpSupported
                      ? '只监听本机 127.0.0.1。任何改动都会先弹确认卡片，你点了应用才会写进项目。'
                      : service.error ?? '当前平台不支持本地 MCP 服务',
                ),
              ),
              const SizedBox(height: 8),
              if (enabled && service.running) ...[
                _kv(context, '服务地址', service.endpoint ?? ''),
                _kv(context, '访问令牌', service.token ?? ''),
                _kv(
                  context,
                  '发现文件',
                  service.bridgePath ?? '',
                  small: true,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyConfig(context, service),
                    icon: const Icon(Icons.copy_all, size: 18),
                    label: const Text('复制客户端配置'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '把复制到的 JSON 贴进客户端（CodeBuddy / Qoder / DSH 等）的 MCP 配置里，'
                  '重启客户端后即可连接。端口与令牌已保存在本机，以后重启 PIE-Block '
                  '无需重新配置客户端。网页版与手机版不提供这个服务。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (enabled && service.error != null)
                Text(
                  service.error!,
                  style: TextStyle(color: scheme.error),
                )
              else if (!enabled)
                Text(
                  '开启后，外部 AI 可以读取字段含义、提出配置改动，但每次写入都要你在这里确认。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 20),
              Text('最近的调用', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (service.audit.isEmpty)
                Text(
                  '还没有调用记录',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final entry in service.audit.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${_time(entry.at)}  ${entry.method}  →  ${entry.outcome}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (enabled)
          TextButton(
            onPressed: () => _rotateToken(context, ref),
            child: const Text('重置令牌'),
          ),
        if (enabled)
          FilledButton.tonal(
            onPressed: () => ref.read(mcpServiceProvider.notifier).restart(),
            child: const Text('重启服务'),
          ),
      ],
    );
  }

  Widget _kv(
    BuildContext context,
    String label,
    String value, {
    bool small = false,
  }) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'PieBlockMono',
      fontSize: small ? 11 : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: SelectableText(value, style: style)),
        ],
      ),
    );
  }

  Future<void> _rotateToken(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重置访问令牌？'),
        content: const Text(
          '重置后现有客户端会连不上，需要重新复制一次配置。'
          '只有怀疑令牌泄露时才需要这么做。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(mcpServiceProvider.notifier).rotateToken();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('令牌已重置，请重新复制客户端配置')),
    );
  }

  Future<void> _copyConfig(
    BuildContext context,
    McpServiceState service,
  ) async {
    final endpoint = service.endpoint;
    final token = service.token;
    if (endpoint == null || token == null) return;
    final payload = {
      'mcpServers': {
        'pieblock': {
          'url': '$endpoint?token=$token',
        },
      },
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 MCP 配置，贴进客户端的 MCP 设置即可')),
    );
  }

  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

/// 当前平台是否可能提供本地 MCP 服务：只有桌面端。
bool get mcpSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// 供外部（首页按钮）判断是否显示入口。
bool get mcpEntryVisible => mcpSupported;

/// 工具名 → 中文，审计列表里直接显示码值太硬。
String describeTool(String method) => switch (method) {
  'pieblock_handshake' => '握手',
  'pieblock_get_context' => '读上下文',
  'pieblock_validate' => '校验',
  'pieblock_propose_patch' => '提交改动草案',
  'pieblock_apply_patch' => '应用改动',
  'pieblock_generate_code' => '查看代码',
  _ => method,
};

/// 错误码 → 中文，卡片与审计共用。
String describeOutcome(String outcome) => switch (outcome) {
  'ok' => '成功',
  McpToolErrorCode.denied => '用户拒绝',
  McpToolErrorCode.approvalTimeout => '确认超时',
  McpToolErrorCode.staleRevision => 'revision 过期',
  McpToolErrorCode.noProject => '未打开项目',
  McpToolErrorCode.invalidPath => '字段不存在',
  McpToolErrorCode.notWritable => '字段只读',
  McpToolErrorCode.invalidValue => '取值不合法',
  McpToolErrorCode.patchExpired => '补丁已过期',
  McpToolErrorCode.incompleteConfig => '配置不完整',
  _ => outcome,
};
