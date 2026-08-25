import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';

const _brandCyan = Color(0xff02acc0);
const _brandCoral = Color(0xffef685d);
const _pieProjectType = XTypeGroup(
  label: 'PIE-Block 项目',
  extensions: ['pieproj'],
);

class ProjectFileDialogs {
  const ProjectFileDialogs();

  Future<String?> chooseProjectToOpen() async {
    final file = await openFile(acceptedTypeGroups: const [_pieProjectType]);
    return file?.path;
  }

  Future<String?> chooseProjectSavePath({
    required String suggestedName,
    String? initialDirectory,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_pieProjectType],
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      canCreateDirectories: true,
    );
    return location?.path;
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.fileDialogs = const ProjectFileDialogs()});

  final ProjectFileDialogs fileDialogs;

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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
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
                      ButtonSegment(
                        value: ProjectKind.debug,
                        icon: Icon(Icons.science_outlined),
                        label: Text('调试'),
                      ),
                      ButtonSegment(
                        value: ProjectKind.music,
                        icon: Icon(Icons.piano),
                        label: Text('音乐'),
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
                  Builder(
                    builder: (context) {
                      final field = TextField(
                        controller: path,
                        decoration: const InputDecoration(
                          labelText: '保存位置',
                          helperText: '选择或输入完整的 .pieproj 文件路径',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                      );
                      final browse = OutlinedButton.icon(
                        onPressed: () async {
                          final currentPath = path.text.trim();
                          final selected = await fileDialogs.chooseProjectSavePath(
                            suggestedName:
                                '${name.text.trim().isEmpty ? '我的机器人' : name.text.trim()}.pieproj',
                            initialDirectory: currentPath.isEmpty
                                ? desktop
                                : File(currentPath).parent.path,
                          );
                          if (selected != null && context.mounted) {
                            path.text = selected;
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('浏览'),
                      );
                      if (MediaQuery.sizeOf(context).width < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [field, const SizedBox(height: 10), browse],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: browse,
                          ),
                        ],
                      );
                    },
                  ),
                ],
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
    name.dispose();
    path.dispose();
  }

  Future<void> _open(WidgetRef ref) async {
    final path = await fileDialogs.chooseProjectToOpen();
    if (path == null || path.trim().isEmpty) return;
    await ref.read(appControllerProvider.notifier).openProject(path);
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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 600 ? 18 : 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HomeHeader(
                        dark: dark,
                        themeMode: state.themeMode,
                        onCycleTheme: ref
                            .read(appControllerProvider.notifier)
                            .cycleTheme,
                      ),
                      const SizedBox(height: 44),
                      LayoutBuilder(
                        builder: (context, c) {
                          final cards = [
                            _ActionCard(
                              icon: Icons.add_circle_outline,
                              title: '新建机器人项目',
                              subtitle: '从步兵、工程、调试或音乐模板开始分步配置',
                              button: '新建项目',
                              accent: _brandCyan,
                              foreground: const Color(0xff00363d),
                              onPressed: () => _create(context, ref),
                            ),
                            _ActionCard(
                              icon: Icons.folder_open,
                              title: '打开已有项目',
                              subtitle: '仅支持新版格式 14 的 .pieproj',
                              button: '打开项目',
                              accent: _brandCoral,
                              foreground: const Color(0xff3d0b08),
                              onPressed: () => _open(ref),
                            ),
                          ];
                          if (c.maxWidth < 600) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                cards.first,
                                const SizedBox(height: 16),
                                cards.last,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: cards.first),
                              const SizedBox(width: 20),
                              Expanded(child: cards.last),
                            ],
                          );
                        },
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
          ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.dark,
    required this.themeMode,
    required this.onCycleTheme,
  });

  final bool dark;
  final ThemeMode themeMode;
  final VoidCallback onCycleTheme;

  Widget _brandIcon() => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: _brandCyan,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Icon(Icons.hub_outlined, color: Color(0xff00363d), size: 30),
  );

  Widget _themeButton() => IconButton.filledTonal(
    onPressed: onCycleTheme,
    tooltip: '切换浅色 / 深色 / 跟随系统',
    icon: Icon(
      themeMode == ThemeMode.dark
          ? Icons.dark_mode
          : themeMode == ThemeMode.light
          ? Icons.light_mode
          : Icons.brightness_auto,
    ),
  );

  Widget _title({required bool compact}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (compact) ...[
        Image.asset(
          dark ? 'assets/images/cnu-white.png' : 'assets/images/cnu-blue.png',
          height: 32,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: '首都师范大学',
        ),
        const SizedBox(height: 10),
        const Text(
          'RoboMaster机甲大师赛机器人图形化配置集成开发环境',
          style: TextStyle(
            fontSize: 21,
            height: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ] else
        Row(
          children: [
            Image.asset(
              dark
                  ? 'assets/images/cnu-white.png'
                  : 'assets/images/cnu-blue.png',
              height: 42,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: '首都师范大学',
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'RoboMaster机甲大师赛机器人图形化配置集成开发环境',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 23,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      const SizedBox(height: 5),
      const Text('用清晰的步骤配置机器人，生成可靠的控制代码'),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_brandIcon(), _themeButton()],
            ),
            const SizedBox(height: 20),
            _title(compact: true),
          ],
        );
      }
      return Row(
        children: [
          _brandIcon(),
          const SizedBox(width: 16),
          Expanded(child: _title(compact: false)),
          const SizedBox(width: 18),
          _themeButton(),
        ],
      );
    },
  );
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
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 28),
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
