import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';

const _brandCyan = Color(0xff02acc0);
const _brandCoral = Color(0xffef685d);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(text: '我的机器人');
    final desktop =
        '${Platform.environment['USERPROFILE'] ?? Directory.current.path}${Platform.pathSeparator}Desktop';
    final path = TextEditingController(
      text: '$desktop${Platform.pathSeparator}我的机器人.pieproj',
    );
    var kind = ProjectKind.infantry;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建项目'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<ProjectKind>(
                  segments: const [
                    ButtonSegment(
                      value: ProjectKind.infantry,
                      icon: Icon(Icons.sports_esports),
                      label: Text('步兵'),
                    ),
                    ButtonSegment(
                      value: ProjectKind.engineer,
                      icon: Icon(Icons.precision_manufacturing),
                      label: Text('工程'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => setState(() => kind = v.first),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '项目名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: path,
                  decoration: const InputDecoration(
                    labelText: '保存位置',
                    helperText: '输入完整的 .pieproj 文件路径',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || path.text.trim().isEmpty) {
                  return;
                }
                final ok = await ref
                    .read(appControllerProvider.notifier)
                    .createProject(path.text, name.text, kind);
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('创建项目'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final path = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开项目'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '.pieproj 文件路径',
              prefixIcon: Icon(Icons.folder_open),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (path.text.trim().isEmpty) return;
              final ok = await ref
                  .read(appControllerProvider.notifier)
                  .openProject(path.text);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      _brandCyan.withValues(alpha: dark ? .20 : .14),
                      colors.surface,
                    ),
                    colors.surface,
                    Color.alphaBlend(
                      _brandCoral.withValues(alpha: dark ? .16 : .11),
                      colors.surface,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _brandCyan,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.hub_outlined,
                            color: Color(0xff00363d),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PIE-Block',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text('用清晰的步骤配置机器人，生成可靠的控制代码'),
                          ],
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: ref
                              .read(appControllerProvider.notifier)
                              .cycleTheme,
                          tooltip: '切换浅色 / 深色 / 跟随系统',
                          icon: Icon(
                            state.themeMode == ThemeMode.dark
                                ? Icons.dark_mode
                                : state.themeMode == ThemeMode.light
                                ? Icons.light_mode
                                : Icons.brightness_auto,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 44),
                    LayoutBuilder(
                      builder: (context, c) => Row(
                        children: [
                          Expanded(
                            child: _ActionCard(
                              icon: Icons.add_circle_outline,
                              title: '新建机器人项目',
                              subtitle: '从步兵或工程模板开始分步配置',
                              button: '新建项目',
                              accent: _brandCyan,
                              foreground: const Color(0xff00363d),
                              onPressed: () => _create(context, ref),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _ActionCard(
                              icon: Icons.folder_open,
                              title: '打开已有项目',
                              subtitle: '仅支持新版格式 12 的 .pieproj',
                              button: '打开项目',
                              accent: _brandCoral,
                              foreground: const Color(0xff3d0b08),
                              onPressed: () => _open(context, ref),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: MaterialBanner(
                          content: Text(state.message!),
                          leading: const Icon(Icons.error_outline),
                          actions: [
                            TextButton(
                              onPressed: ref
                                  .read(appControllerProvider.notifier)
                                  .clearMessage,
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 36),
                    Text(
                      '最近项目',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: state.recentPaths.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(28),
                              child: Row(
                                children: [
                                  Icon(Icons.history),
                                  SizedBox(width: 12),
                                  Text('还没有最近打开的项目'),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                for (final path in state.recentPaths)
                                  ListTile(
                                    leading: const Icon(
                                      Icons.description_outlined,
                                    ),
                                    title: Text(
                                      path.split(Platform.pathSeparator).last,
                                    ),
                                    subtitle: Text(
                                      path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => ref
                                        .read(appControllerProvider.notifier)
                                        .openProject(path),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.accent,
    required this.foreground,
    required this.onPressed,
  });
  final IconData icon;
  final String title, subtitle, button;
  final Color accent, foreground;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Card(
    color: Color.alphaBlend(
      accent.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .055 : .025,
      ),
      Theme.of(context).colorScheme.surface,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: accent.withValues(alpha: .34)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 38, color: accent),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(subtitle),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: foreground,
            ),
            icon: const Icon(Icons.arrow_forward),
            label: Text(button),
          ),
        ],
      ),
    ),
  );
}
