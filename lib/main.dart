import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/controller.dart';
import 'src/deploy_controller.dart';
import 'src/home_screen.dart';
import 'src/wizard_screen.dart';

void main() => runApp(const ProviderScope(child: PieBlockApp()));

class PieBlockApp extends ConsumerStatefulWidget {
  const PieBlockApp({super.key});

  @override
  ConsumerState<PieBlockApp> createState() => _PieBlockAppState();
}

class _PieBlockAppState extends ConsumerState<PieBlockApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        ref.read(deployControllerProvider.notifier).cancelAll();
        await ref.read(appControllerProvider.notifier).saveNow();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff087f8c),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'PieBlockSans',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Segoe UI',
        'Segoe UI Symbol',
        'Segoe UI Emoji',
      ],
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff6f8fa)
          : const Color(0xff101416),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        useIndicator: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PIE-Block',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: state.themeMode,
      home: _AppPageTransition(showEditor: state.document != null),
    );
  }
}

class _AppPageTransition extends StatefulWidget {
  const _AppPageTransition({required this.showEditor});

  final bool showEditor;

  @override
  State<_AppPageTransition> createState() => _AppPageTransitionState();
}

class _AppPageTransitionState extends State<_AppPageTransition>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);
  static const _homeBackdropKey = ValueKey('home-page-transition-backdrop');
  static const _editorKey = ValueKey('editor-page-transition');

  late final AnimationController _controller;
  late final Animation<Offset> _editorSlide;
  var _showHomeBackdrop = false;
  var _transitionEpoch = 0;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.showEditor ? 1 : 0,
    );
    _editorSlide = Tween<Offset>(
      begin: const Offset(.025, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(covariant _AppPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showEditor == oldWidget.showEditor) return;
    if (!widget.showEditor) {
      // 返回首页：立即切换，并取消一切待执行的动画回调，
      // 避免已关闭项目的编辑页继续监听空状态。
      _transitionEpoch++;
      _controller
        ..stop()
        ..value = 0;
      _showHomeBackdrop = false;
      return;
    }
    if (_reduceMotion) {
      // 系统启用“减少动态效果”时直接切换，不播放动画。
      _controller.value = 1;
      return;
    }
    // 进入编辑页：本帧先挂载编辑页（停在起始偏移）并保留首页静止背景，
    // 首帧完成后再启动动画，让编辑页首次构建的耗时停在动画开始之前。
    _showHomeBackdrop = true;
    _scheduleEditorEntrance();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleEditorEntrance() {
    final epoch = ++_transitionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _transitionEpoch) return;
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted || epoch != _transitionEpoch) return;
        // 动画结束后卸载首页背景，避免长期双页面渲染。
        setState(() => _showHomeBackdrop = false);
      });
    });
  }

  // 直接定格到编辑页：用于“减少动态效果”，以及减少动态效果期间进入
  // 编辑页后又关闭该选项等未经过动画的路径，防止编辑页残留在起始偏移。
  void _snapToEditor() {
    _transitionEpoch++;
    _showHomeBackdrop = false;
    if (_controller.isAnimating || _controller.value != 1) {
      final epoch = _transitionEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _transitionEpoch) return;
        _controller
          ..stop()
          ..value = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showEditor) return const HomeScreen();
    if (_reduceMotion) {
      _snapToEditor();
      return const WizardScreen();
    }
    if (!_showHomeBackdrop &&
        !_controller.isAnimating &&
        _controller.value != 1) {
      // 未经过动画路径进入编辑页：直接完整展示，不补播动画。
      _snapToEditor();
      return const WizardScreen();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => IgnorePointer(
        ignoring: !_controller.isCompleted,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_showHomeBackdrop)
              ExcludeSemantics(
                child: const RepaintBoundary(
                  key: _homeBackdropKey,
                  child: HomeScreen(),
                ),
              ),
            // ClipRect 限制滑入区域，编辑页只在自身范围内横向位移。
            ClipRect(
              child: SlideTransition(position: _editorSlide, child: child),
            ),
          ],
        ),
      ),
      child: const RepaintBoundary(key: _editorKey, child: WizardScreen()),
    );
  }
}
