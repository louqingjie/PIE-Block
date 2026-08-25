import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/controller.dart';
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
      title: 'Pie-Block',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: state.themeMode,
      home: state.document == null ? const HomeScreen() : const WizardScreen(),
    );
  }
}
