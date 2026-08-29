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
  static const _duration = Duration(milliseconds: 420);

  late final AnimationController _controller;
  late final Animation<double> _curve;
  late final Animation<Offset> _editorOffset;
  var _showHomeBackdrop = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.showEditor ? 1 : 0,
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _editorOffset = Tween<Offset>(
      begin: const Offset(.045, 0),
      end: Offset.zero,
    ).animate(_curve);
  }

  @override
  void didUpdateWidget(covariant _AppPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showEditor == oldWidget.showEditor) return;
    if (widget.showEditor) {
      _showHomeBackdrop = true;
      _controller.forward(from: 0).whenComplete(() {
        if (mounted && widget.showEditor) {
          setState(() => _showHomeBackdrop = false);
        }
      });
    } else {
      _controller
        ..stop()
        ..value = 0;
      _showHomeBackdrop = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showEditor) return const HomeScreen();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
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
                child: Opacity(
                  opacity: 1 - .18 * _curve.value,
                  child: Transform.scale(
                    scale: 1 - .015 * _curve.value,
                    child: const RepaintBoundary(
                      key: ValueKey('home-page-transition-backdrop'),
                      child: HomeScreen(),
                    ),
                  ),
                ),
              ),
            FadeTransition(
              opacity: _curve,
              child: SlideTransition(position: _editorOffset, child: child),
            ),
          ],
        ),
      ),
      child: const RepaintBoundary(
        key: ValueKey('editor-page-transition'),
        child: WizardScreen(),
      ),
    );
  }
}
