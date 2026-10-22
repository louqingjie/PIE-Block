import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart'
    hide MaterialShapes, RoundedPolygon;
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';
import 'design/app_card.dart';
import 'design/app_theme.dart';
import 'design/connected_button_group.dart';
import 'design/press_scale.dart';
import 'design/shape_badge.dart';
import 'platform/document_io.dart';
import 'platform/paths.dart';
import 'project_kind_ui.dart';
import 'project_templates.dart';

const _brandCyan = Color(0xff02acc0);
const _brandCoral = Color(0xffef685d);
const _projectFileSuffix = '.pieproj';

/// 路径中最后一个目录分隔符的位置，-1 表示没有分隔符。
///
/// 用户可能粘贴 Windows 或 POSIX 风格的路径，两种分隔符都要认。
int _lastDirectorySeparator(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  return slash > backslash ? slash : backslash;
}

/// 项目名称 → 文件名；名称已经带 .pieproj 后缀时不再重复追加。
String _projectFileName(String projectName) {
  final trimmed = projectName.trim();
  return trimmed.toLowerCase().endsWith(_projectFileSuffix)
      ? trimmed
      : '$trimmed$_projectFileSuffix';
}

/// 保存位置路径 → 项目名称；路径末尾没有文件名时返回 null。
String? _projectNameFromPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final fileName = trimmed.substring(_lastDirectorySeparator(trimmed) + 1);
  if (fileName.isEmpty) return null;
  return fileName.toLowerCase().endsWith(_projectFileSuffix)
      ? fileName.substring(0, fileName.length - _projectFileSuffix.length)
      : fileName;
}

class ProjectFileDialogs {
  const ProjectFileDialogs({this.documentIo = const AppDocumentIo()});

  final AppDocumentIo documentIo;

  /// 返回整份文件而不只是引用：Web 上引用只是一个文件名，导入时需要内容。
  Future<SelectedDocument?> chooseProjectToOpen() async {
    return documentIo.open(
      label: 'PIE-Block 项目',
      extensions: const ['pieproj'],
      mimeTypes: const [
        'application/json',
        'application/octet-stream',
        'text/plain',
      ],
    );
  }

  Future<String?> chooseProjectSavePath({
    required String suggestedName,
    String? initialDirectory,
  }) async {
    return documentIo.create(
      suggestedName: suggestedName,
      mimeType: 'application/json',
      extensions: const ['pieproj'],
      initialDirectory: initialDirectory,
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    this.fileDialogs = const ProjectFileDialogs(),
    this.templates = const ProjectTemplates(),
  });

  final ProjectFileDialogs fileDialogs;
  final ProjectTemplates templates;

  Future<String?> _chooseSavePath(
    BuildContext context, {
    required String suggestedName,
    String? initialDirectory,
  }) async {
    try {
      return await fileDialogs.chooseProjectSavePath(
        suggestedName: suggestedName,
        initialDirectory: initialDirectory,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开文件选择器：$error')));
      }
      return null;
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(text: '我的机器人');
    final desktop = defaultDesktopDirectory();
    // Web 上没有可写目录，项目名就是文件名，这里不需要「保存位置」。
    final path = TextEditingController(
      text: kIsWeb
          ? ''
          : desktop == null
          ? ''
          : p.join(desktop, '我的机器人.pieproj'),
    );
    String? androidReference;
    var kind = ProjectKind.infantry;
    var useTemplate = false;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    // 项目名称与保存位置里的文件名双向同步：改一处，另一处同时跟着变。
    // Web 没有保存位置输入框；Android 的保存位置来自只读的系统文档选择器，
    // 只能由选中的文件回填名称，不能反过来重命名文件。
    var syncingFileName = false;
    name.addListener(() {
      if (syncingFileName || kIsWeb || android) return;
      final current = path.text;
      if (current.trim().isEmpty) return;
      final directory = current.substring(
        0,
        _lastDirectorySeparator(current) + 1,
      );
      syncingFileName = true;
      path.text = name.text.trim().isEmpty
          ? directory
          : '$directory${_projectFileName(name.text)}';
      syncingFileName = false;
    });
    path.addListener(() {
      if (syncingFileName) return;
      final projectName = _projectNameFromPath(path.text);
      if (projectName == null || projectName == name.text) return;
      syncingFileName = true;
      name.text = projectName;
      syncingFileName = false;
    });
    // 弹窗存续期间不再碰 ref：创建按钮的回调里有 await，届时外层弹窗可能已经
    // 不在挂载状态。这里一次性取出控制器和提示偏好快照供整个弹窗使用。
    final appController = ref.read(appControllerProvider.notifier);
    var suppressTemplateGuide = ref
        .read(appControllerProvider)
        .suppressTemplateGuide;
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
                  ConnectedButtonGroup<ProjectKind>(
                    semanticLabel: '项目类型',
                    segments: [
                      for (final projectKind in ProjectKind.values)
                        ConnectedSegment(
                          value: projectKind,
                          icon: projectKind.icon,
                          label: projectKind.label,
                        ),
                    ],
                    value: kind,
                    onChanged: (value) => setState(() => kind = value),
                  ),
                  SwitchListTile(
                    key: const ValueKey('new_project.template'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: useTemplate,
                    title: const Text('模板工程'),
                    subtitle: const Text('载入示例配置，预填当前所选类型的全部机器人字段'),
                    onChanged: (value) async {
                      if (value && !suppressTemplateGuide) {
                        final result = await _confirmTemplateUsage(context);
                        if (!context.mounted) return;
                        if (result.suppress) {
                          suppressTemplateGuide = true;
                          appController.suppressTemplateGuide();
                        }
                        if (!result.confirmed) return;
                      }
                      setState(() => useTemplate = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '项目名称'),
                  ),
                  const SizedBox(height: 12),
                  if (!kIsWeb)
                    Builder(
                      builder: (context) {
                        final field = TextField(
                          controller: path,
                          readOnly: android,
                          decoration: InputDecoration(
                            labelText: '保存位置',
                            helperText: android
                                ? '使用系统文档选择器保存，可在创建时选择'
                                : '选择或输入完整的 .pieproj 文件路径',
                            prefixIcon: const Icon(Icons.folder_outlined),
                          ),
                        );
                        final browse = OutlinedButton.icon(
                          onPressed: () async {
                            final currentPath = path.text.trim();
                            final selected = await _chooseSavePath(
                              context,
                              suggestedName: _projectFileName(
                                name.text.trim().isEmpty ? '我的机器人' : name.text,
                              ),
                              initialDirectory: currentPath.isEmpty
                                  ? desktop
                                  : android
                                  ? null
                                  : p.dirname(currentPath),
                            );
                            if (selected != null && context.mounted) {
                              if (android) {
                                androidReference = selected;
                                path.text = AppDocumentIo.displayName(selected);
                              } else {
                                path.text = selected;
                              }
                            }
                          },
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('浏览'),
                        );
                        if (MediaQuery.sizeOf(context).width < 600) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              field,
                              const SizedBox(height: 10),
                              browse,
                            ],
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
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: name,
              builder: (context, value, _) {
                // 项目名称为空时直接禁用创建，避免点击后静默无响应。
                final canCreate = value.text.trim().isNotEmpty;
                return PressScale(
                  enabled: canCreate,
                  child: FilledButton(
                    onPressed: canCreate
                        ? () async {
                            final projectName = name.text.trim();
                            if (projectName.isEmpty) return;
                            if (androidReference == null && android) {
                              final selected = await _chooseSavePath(
                                context,
                                suggestedName: '$projectName.pieproj',
                              );
                              if (selected == null || !context.mounted) return;
                              androidReference = selected;
                              path.text = AppDocumentIo.displayName(selected);
                            }
                            // Web 上没有目录可选：项目名就是文件名，内容存在浏览器里。
                            final projectPath = kIsWeb
                                ? '$projectName.pieproj'
                                : androidReference ?? path.text;
                            if (projectPath.trim().isEmpty) return;
                            final projectKind = kind;
                            ProjectConfig? template;
                            if (useTemplate) {
                              // 载入失败就中止：静默退化成空项目会让用户以为字段已填好，
                              // 到向导里才发现满屏红字。
                              try {
                                template = await templates.config(projectKind);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('模板载入失败：$error')),
                                  );
                                }
                                return;
                              }
                            }
                            if (!context.mounted) return;
                            // 先关闭新建弹窗，再切换根页面；否则根页面重建会在弹窗
                            // 仍挂载时卸载其 InheritedElement，Android 上会触发
                            // framework.dart 的 `_dependents.isEmpty` 断言。
                            Navigator.pop(context);
                            await appController.createProject(
                              projectPath,
                              projectName,
                              projectKind,
                              template: template,
                            );
                          }
                        : null,
                    child: const Text('创建项目'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    // showDialog 返回时弹窗仍可能处于退出动画中，TextField 还会被重建。
    // 控制器随后不再被引用，交由 GC 回收，避免过早 dispose 导致 Flutter
    // 在动画帧中访问已释放的 TextEditingController。
  }

  /// 打开「模板工程」开关前的劝阻式确认。返回用户是否确认，以及是否要求
  /// 以后不再提示——两者分开返回，因为「取消 + 勾了不再提示」是有效组合。
  Future<({bool confirmed, bool suppress})> _confirmTemplateUsage(
    BuildContext context,
  ) async {
    var suppress = false;
    final confirmed = await showDialog<bool>(
      context: context,
      // 允许点遮罩关闭会把「不再提示」的勾选静默丢掉。
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('确认使用模板工程？'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('模板工程会一次性写入全部机器人配置字段，创建后可直接进入审查与生成环节。'),
                  const SizedBox(height: 12),
                  const Text(
                    '使用模板将跳过逐项配置过程。初次使用者难以借此了解各配置项与遥控器按键、'
                    'IO 端口、执行器方向之间的对应关系，也不易判断自身设备的实际取值。',
                  ),
                  const SizedBox(height: 12),
                  const Text('建议先以空白项目跟随引导完整配置一次，再视需要使用模板。'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: suppress,
                    onChanged: (value) =>
                        setDialogState(() => suppress = value ?? false),
                    title: const Text('以后不再显示此提示'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回空白项目'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('我已了解，继续使用模板'),
            ),
          ],
        ),
      ),
    );
    return (confirmed: confirmed == true, suppress: suppress);
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      final selected = await fileDialogs.chooseProjectToOpen();
      if (selected == null) return;
      final controller = ref.read(appControllerProvider.notifier);
      // Web 上项目存在浏览器里，选到的文件要先落库再打开；桌面与 Android
      // 的引用本身就是可再次读取的位置，直接打开即可。
      if (kIsWeb) {
        await controller.importProject(selected);
      } else {
        await controller.openProject(selected.reference);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开文件选择器：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final recentProjects = state.recentProjects;
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
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  key: const ValueKey('home-scroll-view'),
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
                                subtitle: '从步兵、工程、调试或音乐类型开始分步配置',
                                button: '新建项目',
                                accent: _brandCyan,
                                foreground: const Color(0xff00363d),
                                onPressed: () => _create(context, ref),
                              ),
                              _ActionCard(
                                icon: Icons.folder_open,
                                title: '打开已有项目',
                                // 版本号取自代码而不是写死，避免每次升格式都漏改文案。
                                subtitle:
                                    '仅支持当前格式 ${ProjectDocument.formatVersion} 的 .pieproj',
                                button: '打开项目',
                                accent: _brandCoral,
                                foreground: const Color(0xff3d0b08),
                                onPressed: () => _open(context, ref),
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
                        if (recentProjects.isNotEmpty) ...[
                          const SizedBox(height: 36),
                          Text('最近项目', style: AppText.sectionTitle(context)),
                          const SizedBox(height: 12),
                          AppCard(
                            key: const ValueKey('home.recent-projects'),
                            padding: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (final entry in recentProjects.indexed)
                                  ListTile(
                                    leading: Icon(
                                      recentProjectIcon(entry.$2.kind),
                                    ),
                                    title: Text(
                                      AppDocumentIo.displayName(entry.$2.path),
                                    ),
                                    subtitle: Text(
                                      entry.$2.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    shape: AppShape.of(
                                      BorderRadius.vertical(
                                        top: entry.$1 == 0
                                            ? const Radius.circular(
                                                AppCorner.lg,
                                              )
                                            : Radius.zero,
                                        bottom:
                                            entry.$1 ==
                                                recentProjects.length - 1
                                            ? const Radius.circular(
                                                AppCorner.lg,
                                              )
                                            : Radius.zero,
                                      ),
                                    ),
                                    onTap: () => ref
                                        .read(appControllerProvider.notifier)
                                        .openProject(entry.$2.path),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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

  Widget _brandIcon() => ShapeBadge(
    shape: MaterialShapes.cookie6Sided,
    color: _brandCyan,
    size: 56,
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
          'RoboMaster 机甲大师赛机器人图形化配置集成开发环境',
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
              height: 36,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: '首都师范大学',
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'RoboMaster 机甲大师赛机器人图形化配置集成开发环境',
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
      // const SizedBox(height: 5),
      // const Text('用清晰的步骤配置机器人，生成可靠的控制代码'),
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
              // Web 版固定暗色，不提供主题切换。
              children: [_brandIcon(), if (!kIsWeb) _themeButton()],
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
          if (!kIsWeb) _themeButton(),
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return AppCard(
      variant: AppCardVariant.hero,
      color: Color.alphaBlend(
        accent.withValues(alpha: dark ? .055 : .025),
        AppSurface.card.colorOf(scheme),
      ),
      padding: EdgeInsets.all(compact ? 20 : 28),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            end: -42,
            top: -54,
            child: ShapeBadge(
              shape: MaterialShapes.cookie12Sided,
              color: accent.withValues(alpha: .08),
              size: 180,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShapeBadge(
                shape: MaterialShapes.cookie6Sided,
                color: scheme.primaryContainer,
                size: 56,
                child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text(title, style: AppText.sectionTitle(context)),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 28),
              PressScale(
                child: FilledButton.icon(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: foreground,
                  ),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(button, style: AppText.cta(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
