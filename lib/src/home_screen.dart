import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';
import 'platform/document_io.dart';
import 'platform/paths.dart';
import 'project_kind_ui.dart';
import 'project_templates.dart';
import 'recent_project.dart';

const _brandCyan = Color(0xff02acc0);
const _brandCoral = Color(0xffef685d);
const _projectFileSuffix = '.pieproj';

// 欢迎页的 M3 Expressive 形状与节奏 token。卡片使用超级椭圆
// （superellipse）而不是普通圆角，观感更接近 M3E 的柔和形状语汇；
// 圆角、时长全部集中在这里，避免散落的魔法数字。
const _homeCardRadius = 28.0;
const _homeBadgeRadius = 18.0;
const _homeTileRadius = 20.0;
const _homeEntranceDuration = Durations.medium4; // 400ms
const _homePressDuration = Durations.short3; // 150ms
const _coralInkLight = Color(0xff9b3f37);
const _coralInkDark = Color(0xffffb4ab);

/// 欢迎页统一的超级椭圆形状；side 为 null 时表示无描边。
RoundedSuperellipseBorder _expressiveShape(
  double radius, {
  BorderSide side = BorderSide.none,
}) => RoundedSuperellipseBorder(
  borderRadius: BorderRadius.circular(radius),
  side: side,
);

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
                  SegmentedButton<ProjectKind>(
                    segments: [
                      for (final projectKind in ProjectKind.values)
                        ButtonSegment(
                          value: projectKind,
                          icon: Icon(projectKind.icon),
                          label: Text(projectKind.label),
                        ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => setState(() => kind = v.first),
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
            FilledButton(
              onPressed: () async {
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
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('模板载入失败：$error')));
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
              },
              child: const Text('创建项目'),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _HomeBackdrop(colors: colors, dark: dark),
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
                    child: _HomeEntrance(
                      builder: (context, animate, progress) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Reveal(
                            progress: progress,
                            animate: animate,
                            interval: const Interval(
                              0,
                              .55,
                              curve: Easing.emphasizedDecelerate,
                            ),
                            child: _HomeHeader(
                              key: const ValueKey('home.hero'),
                              dark: dark,
                              themeMode: state.themeMode,
                              onCycleTheme: ref
                                  .read(appControllerProvider.notifier)
                                  .cycleTheme,
                            ),
                          ),
                          const SizedBox(height: 48),
                          _Reveal(
                            progress: progress,
                            animate: animate,
                            interval: const Interval(
                              .1,
                              .75,
                              curve: Easing.emphasizedDecelerate,
                            ),
                            child: _ActionCards(
                              onCreate: () => _create(context, ref),
                              onOpen: () => _open(context, ref),
                            ),
                          ),
                          if (state.message != null) ...[
                            const SizedBox(height: 24),
                            _Reveal(
                              progress: progress,
                              animate: animate,
                              interval: const Interval(
                                .18,
                                .8,
                                curve: Easing.emphasizedDecelerate,
                              ),
                              child: _MessageBanner(
                                message: state.message!,
                                onDismiss: ref
                                    .read(appControllerProvider.notifier)
                                    .clearMessage,
                              ),
                            ),
                          ],
                          if (recentProjects.isNotEmpty) ...[
                            const SizedBox(height: 40),
                            _Reveal(
                              progress: progress,
                              animate: animate,
                              interval: const Interval(
                                .25,
                                1,
                                curve: Easing.emphasizedDecelerate,
                              ),
                              child: _RecentProjectsSection(
                                projects: recentProjects,
                                onOpen: (entry) => ref
                                    .read(appControllerProvider.notifier)
                                    .openProject(entry.path),
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
          ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    super.key,
    required this.dark,
    required this.themeMode,
    required this.onCycleTheme,
  });

  final bool dark;
  final ThemeMode themeMode;
  final VoidCallback onCycleTheme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final titleSize = compact
          ? 22.0
          : (constraints.maxWidth < 900 ? 25.0 : 28.0);
      final brand = _BrandMark(compact: compact);
      final title = _BrandTitle(
        dark: dark,
        compact: compact,
        titleSize: titleSize,
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                brand,
                const Spacer(),
                // Web 版固定暗色，不提供主题切换。
                if (!kIsWeb)
                  _ThemeToggle(themeMode: themeMode, onPressed: onCycleTheme),
              ],
            ),
            const SizedBox(height: 20),
            title,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          brand,
          const SizedBox(width: 20),
          Expanded(child: title),
          const SizedBox(width: 24),
          if (!kIsWeb)
            _ThemeToggle(themeMode: themeMode, onPressed: onCycleTheme),
        ],
      );
    },
  );
}

/// 品牌标：primaryContainer 底 + 超级椭圆，比默认圆角更接近 M3E 形状语汇。
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = compact ? 56.0 : 64.0;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: _expressiveShape(compact ? _homeBadgeRadius : 20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            Color.lerp(colors.primaryContainer, Colors.black, .18)!,
          ],
        ),
      ),
      child: Icon(
        Icons.hub_outlined,
        size: compact ? 28 : 32,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}

/// 品牌区：eyebrow → 标题 → 说明，建立 M3E 式的三级排版层级。
///
/// 校徽是软件正式名称的一部分（"首都师范大学 RoboMaster …"），
/// 因此与标题文字组成同一个 masthead，而不是右侧的装饰图。
class _BrandTitle extends StatelessWidget {
  const _BrandTitle({
    required this.dark,
    required this.compact,
    required this.titleSize,
  });

  final bool dark;
  final bool compact;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final logo = Image.asset(
      dark ? 'assets/images/cnu-white.png' : 'assets/images/cnu-blue.png',
      height: compact ? 30 : 34,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '首都师范大学',
    );
    final eyebrow = Text(
      'PIE-BLOCK',
      style: textTheme.labelLarge?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow,
        const SizedBox(height: 6),
        // 校徽 + 标题组成完整软件名称，校徽紧贴标题上方。
        logo,
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            'RoboMaster 机甲大师赛机器人图形化配置集成开发环境',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineSmall?.copyWith(
              fontSize: titleSize,
              height: compact ? 1.3 : 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '用清晰的步骤配置机器人，生成可靠的控制代码',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// 主题切换按钮：胶囊形 + 图标缩放淡入淡出。
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.themeMode, required this.onPressed});

  final ThemeMode themeMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = switch (themeMode) {
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.system => Icons.brightness_auto,
    };
    return IconButton.filledTonal(
      key: const ValueKey('home.theme-toggle'),
      onPressed: onPressed,
      tooltip: '切换浅色 / 深色 / 跟随系统',
      style: IconButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
      ),
      icon: AnimatedSwitcher(
        duration: _homePressDuration,
        switchInCurve: Easing.emphasizedDecelerate,
        switchOutCurve: Easing.emphasizedAccelerate,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(icon, key: ValueKey<ThemeMode>(themeMode), size: 22),
      ),
    );
  }
}

class _ActionCards extends StatelessWidget {
  const _ActionCards({required this.onCreate, required this.onOpen});

  final VoidCallback onCreate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final create = _ActionCard(
      key: const ValueKey('home.action.new'),
      primary: true,
      icon: Icons.add_circle_outline,
      title: '新建机器人项目',
      subtitle: '从步兵、工程、调试或音乐类型开始分步配置',
      button: '新建项目',
      onPressed: onCreate,
    );
    final open = _ActionCard(
      key: const ValueKey('home.action.open'),
      primary: false,
      icon: Icons.folder_open,
      title: '打开已有项目',
      // 版本号取自代码而不是写死，避免每次升格式都漏改文案。
      subtitle: '仅支持当前格式 ${ProjectDocument.formatVersion} 的 .pieproj',
      button: '打开项目',
      onPressed: onOpen,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [create, const SizedBox(height: 20), open],
          );
        }
        // 宽屏把「新建」放大到 3:2，建立 M3E 式的主次层级。
        final wide = constraints.maxWidth >= 900;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: wide ? 3 : 1, child: create),
              const SizedBox(width: 24),
              Expanded(flex: wide ? 2 : 1, child: open),
            ],
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.primary,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onPressed,
  });

  final bool primary;
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final dark = theme.brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final coralInk = dark ? _coralInkDark : _coralInkLight;
    final accent = primary ? colors.primary : coralInk;
    final background = primary
        ? Color.alphaBlend(
            colors.primaryContainer.withValues(alpha: dark ? .18 : .14),
            colors.surfaceContainerLow,
          )
        : Color.alphaBlend(
            _brandCoral.withValues(alpha: dark ? .05 : .04),
            colors.surfaceContainerLow,
          );
    final border = primary
        ? colors.primary.withValues(alpha: .38)
        : colors.outlineVariant.withValues(alpha: .7);
    final badgeBackground = primary
        ? colors.primaryContainer
        : Color.alphaBlend(
            _brandCoral.withValues(alpha: dark ? .22 : .14),
            colors.surfaceContainerLow,
          );
    final badgeForeground = primary ? colors.onPrimaryContainer : coralInk;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: _expressiveShape(_homeCardRadius, side: BorderSide(color: border)),
      child: InkWell(
        onTap: onPressed,
        // 交互语义由内部按钮承担，避免读屏重复播报两个按钮。
        excludeFromSemantics: true,
        customBorder: _expressiveShape(_homeCardRadius),
        hoverColor: accent.withValues(alpha: .04),
        highlightColor: accent.withValues(alpha: .06),
        child: Padding(
          padding: EdgeInsets.all(compact ? 24 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: icon,
                background: badgeBackground,
                foreground: badgeForeground,
                size: compact ? 56 : 64,
              ),
              SizedBox(height: compact ? 20 : 24),
              Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  fontSize: compact ? 22 : 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              SizedBox(height: compact ? 24 : 28),
              _SpringPress(
                enabled:
                    !(MediaQuery.maybeOf(context)?.disableAnimations ?? false),
                child: primary
                    ? FilledButton.icon(
                        onPressed: onPressed,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          textStyle: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                        label: Text(button),
                      )
                    : OutlinedButton.icon(
                        onPressed: onPressed,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: coralInk,
                          side: BorderSide(
                            color: coralInk.withValues(alpha: .45),
                          ),
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          textStyle: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_rounded, size: 20),
                        label: Text(button),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.size,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: ShapeDecoration(
      shape: _expressiveShape(_homeBadgeRadius),
      color: background,
    ),
    child: Icon(icon, size: size * .46, color: foreground),
  );
}

/// 弹簧按压反馈：按下缩到 .97，抬起用轻微过冲的弹簧回弹。
///
/// M3E 的按压反馈基于弹簧物理；这里用 [SpringSimulation] 近似，
/// `disableAnimations` 时直接置值，保证无障碍与测试稳定。
class _SpringPress extends StatefulWidget {
  const _SpringPress({required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<_SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<_SpringPress>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 650,
    damping: 30,
  );

  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  void _animateTo(double target) {
    if (!widget.enabled) {
      _scale.value = target;
      return;
    }
    _scale.animateWith(SpringSimulation(_spring, _scale.value, target, 0));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _animateTo(.97),
    onPointerUp: (_) => _animateTo(1),
    onPointerCancel: (_) => _animateTo(1),
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: MaterialBanner(
        backgroundColor: colors.errorContainer,
        leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
        content: Text(
          message,
          style: TextStyle(color: colors.onErrorContainer),
        ),
        actions: [
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              foregroundColor: colors.onErrorContainer,
            ),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _RecentProjectsSection extends StatelessWidget {
  const _RecentProjectsSection({required this.projects, required this.onOpen});

  final List<RecentProject> projects;
  final ValueChanged<RecentProject> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '最近项目',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${projects.length} 个',
              style: textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          key: const ValueKey('home.recent-projects'),
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colors.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: _expressiveShape(
            _homeCardRadius,
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
          ),
          child: Column(
            children: [
              for (final (index, entry) in projects.indexed) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 72,
                    endIndent: 16,
                    color: colors.outlineVariant.withValues(alpha: .5),
                  ),
                ListTile(
                  shape: _expressiveShape(_homeTileRadius),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: _IconBadge(
                    icon: recentProjectIcon(entry.kind),
                    background: colors.secondaryContainer,
                    foreground: colors.onSecondaryContainer,
                    size: 40,
                  ),
                  title: Text(
                    AppDocumentIo.displayName(entry.path),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    entry.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpen(entry),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 背景：surface 底 + 品牌双色径向光斑，宽屏再叠一个描边圆环。
class _HomeBackdrop extends StatelessWidget {
  const _HomeBackdrop({required this.colors, required this.dark});

  final ColorScheme colors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  colors.primary.withValues(alpha: dark ? .07 : .05),
                  colors.surface,
                ),
                colors.surface,
                Color.alphaBlend(
                  _brandCoral.withValues(alpha: dark ? .05 : .04),
                  colors.surface,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: -180,
          top: -180,
          child: _Glow(
            color: _brandCyan.withValues(alpha: dark ? .10 : .14),
            size: 520,
          ),
        ),
        Positioned(
          right: -220,
          bottom: -200,
          child: _Glow(
            color: _brandCoral.withValues(alpha: dark ? .09 : .10),
            size: 560,
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

/// 首屏入场：header → cards → recent 分段淡入上移。
///
/// 系统开启「减少动态效果」时不启动 ticker，并跳过过渡节点。
class _HomeEntrance extends StatefulWidget {
  const _HomeEntrance({required this.builder});

  final Widget Function(
    BuildContext context,
    bool animate,
    Animation<double> progress,
  )
  builder;

  @override
  State<_HomeEntrance> createState() => _HomeEntranceState();
}

class _HomeEntranceState extends State<_HomeEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _homeEntranceDuration,
  );
  var _started = false;
  var _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled) {
      _animate = false;
      if (_controller.isAnimating) {
        _controller.stop();
      }
      if (_controller.value != 1) {
        _controller.value = 1;
      }
    } else {
      _animate = true;
      if (!_started) {
        _started = true;
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _animate, _controller);
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.progress,
    required this.animate,
    required this.interval,
    required this.child,
  });

  final Animation<double> progress;
  final bool animate;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) {
      return child;
    }
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = interval.transform(progress.value);
        if (t >= 1) {
          return child!;
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: child,
          ),
        );
      },
    );
  }
}
