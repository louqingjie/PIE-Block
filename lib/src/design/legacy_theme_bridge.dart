import 'package:flutter/material.dart' as legacy;
import 'package:material_ui/material_ui.dart';

/// 给仍使用 `flutter/material` 主题的第三方子树（目前是 re_editor）提供
/// 一份与 M3E 主题同色同亮度的桥。
///
/// `material_ui` 与 `flutter/material` 的主题是两套 `_InheritedTheme`，
/// 不能互相读取；这里只包编辑器，不污染全局。
class LegacyMaterialThemeBridge extends StatelessWidget {
  const LegacyMaterialThemeBridge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final legacyScheme =
        legacy.ColorScheme.fromSeed(
          seedColor: scheme.primary,
          brightness: brightness,
        ).copyWith(
          primary: scheme.primary,
          surface: scheme.surface,
          onSurface: scheme.onSurface,
        );
    return legacy.Theme(
      data: legacy.ThemeData(
        brightness: brightness,
        colorScheme: legacyScheme,
        textTheme: legacy.TextTheme(
          bodyLarge: legacy.TextStyle(color: scheme.onSurface),
          bodyMedium: legacy.TextStyle(color: scheme.onSurface),
          bodySmall: legacy.TextStyle(color: scheme.onSurfaceVariant),
        ),
        textSelectionTheme: legacy.TextSelectionThemeData(
          cursorColor: scheme.primary,
          selectionColor: scheme.primary.withValues(alpha: .34),
          selectionHandleColor: scheme.primary,
        ),
      ),
      child: child,
    );
  }
}
