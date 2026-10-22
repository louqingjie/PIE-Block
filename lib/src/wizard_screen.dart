import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'as251_highlight_mode.dart';
import 'asm_hover.dart';
import 'asm_preview_controller.dart';
import 'controller.dart';
import 'debug_cue_preview.dart';
import 'deploy_controller.dart';
import 'design/app_card.dart';
import 'design/app_theme.dart';
import 'design/asm_hover_card.dart';
import 'design/connected_button_group.dart';
import 'design/legacy_theme_bridge.dart';
import 'design/press_scale.dart';
import 'design/wavy_progress_indicator.dart';
import 'motion.dart';
import 'platform/file_export.dart';
import 'platform/keil_discovery.dart';
import 'platform/udev_rule.dart';
import 'music_editor.dart';
import 'udev_rule_controller.dart';

part 'wizard/wizard_common.dart';
part 'wizard/wizard_shell_widgets.dart';
part 'wizard/wizard_form_widgets.dart';
part 'wizard/wizard_pages_remote.dart';
part 'wizard/wizard_pages_pwm.dart';
part 'wizard/wizard_pages_infantry.dart';
part 'wizard/wizard_pages_engineer.dart';
part 'wizard/wizard_pages_debug.dart';
part 'wizard/wizard_pages_review.dart';
part 'wizard/wizard_pages_code.dart';
part 'wizard/wizard_pages_deploy.dart';

class WizardScreen extends ConsumerWidget {
  const WizardScreen({super.key, this.debugCuePreview});

  /// 调试提示音试听实现，仅供测试注入；为空时用 flutter_soloud 出声。
  final DebugCuePreviewService? debugCuePreview;

  static const infantrySteps = [
    '遥控器与底盘',
    '云台与拨弹',
    '控制与摩擦轮',
    '检查与摘要',
    '生成代码',
    '烧录',
  ];
  static const engineerSteps = [
    '遥控器与底盘',
    'PWM 与引脚',
    '模式切换',
    '动作映射',
    '检查与摘要',
    '生成代码',
    '烧录',
  ];
  static const debugSteps = ['测试序列', '检查与摘要', '生成代码', '烧录'];
  static const musicSteps = ['钢琴卷帘', '检查与摘要', '生成代码', '烧录'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider),
        controller = ref.read(appControllerProvider.notifier);
    void goToStep(int step) {
      _endTextInput(ref);
      controller.goToStep(step);
    }

    final document = state.document!,
        steps = switch (document.kind) {
          ProjectKind.infantry => infantrySteps,
          ProjectKind.engineer => engineerSteps,
          ProjectKind.debug => debugSteps,
          ProjectKind.music => musicSteps,
        };
    final page = switch (document.kind) {
      ProjectKind.infantry => switch (state.step) {
        0 => const _RemotePage(),
        1 => const _InfantryMechanismPage(),
        2 => const _InfantryControlsPage(),
        3 => const _ReviewPage(),
        4 => const _CodePage(),
        _ => const _DeployPage(),
      },
      ProjectKind.engineer => switch (state.step) {
        0 => const _RemotePage(),
        1 => const _PwmPage(),
        2 => const _EngineerStrategyPage(),
        3 => const _EngineerMappingsPage(),
        4 => const _ReviewPage(),
        5 => const _CodePage(),
        _ => const _DeployPage(),
      },
      ProjectKind.debug => switch (state.step) {
        0 => _DebugTestsPage(cuePreview: debugCuePreview),
        1 => const _ReviewPage(),
        2 => const _CodePage(),
        _ => const _DeployPage(),
      },
      ProjectKind.music => switch (state.step) {
        0 => _FieldAnchor(path: 'music.notes', child: MusicEditorPage()),
        1 => const _ReviewPage(),
        2 => const _CodePage(),
        _ => const _DeployPage(),
      },
    };
    if (state.pendingFieldPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToField(state.pendingFieldPath!, requestFocus: false);
        controller.clearPendingField();
      });
    }
    final deploy = ref.watch(deployControllerProvider);
    final asmPreview = ref.watch(asmPreviewControllerProvider);
    final compact = _isCompact(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: compact ? 4 : 20,
        title: Row(
          children: [
            IconButton(
              onPressed: deploy.busy
                  ? () => _confirmCancelOperation(
                      context,
                      ref,
                      controller.closeProject,
                    )
                  : controller.closeProject,
              tooltip: '返回项目首页',
              icon: const Icon(Icons.arrow_back),
            ),
            SizedBox(width: compact ? 2 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (!compact)
                    Text(switch (document.kind) {
                      ProjectKind.infantry => '步兵项目',
                      ProjectKind.engineer => '工程项目',
                      ProjectKind.debug => '调试项目',
                      ProjectKind.music => '音乐项目',
                    }, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            if (compact)
              _CompactSaveBadge(state.saveStatus)
            else
              _SaveBadge(state.saveStatus),
          ],
        ),
      ),
      body: Column(
        children: [
          if (state.message != null)
            MaterialBanner(
              content: Text(state.message!),
              leading: const Icon(Icons.info_outline),
              actions: [
                TextButton(
                  onPressed: controller.clearMessage,
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                // M3E：透明度走 effects 曲线，缩放走 spatial 曲线，两者分开。
                final effectsEnd =
                    AppMotion.defaultEffectsDuration.inMilliseconds /
                    AppMotion.defaultSpatialDuration.inMilliseconds;
                final content = MediaQuery.disableAnimationsOf(context)
                    ? page
                    : AnimatedSwitcher(
                        duration: AppMotion.defaultSpatial(context),
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation.drive(
                            CurveTween(
                              curve: Interval(
                                0,
                                effectsEnd,
                                curve: AppMotion.expressiveDefaultEffects,
                              ),
                            ),
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .98, end: 1).animate(
                              animation.drive(
                                CurveTween(
                                  curve: AppMotion.expressiveDefaultSpatial,
                                ),
                              ),
                            ),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(state.step),
                          child: page,
                        ),
                      );
                // 生成代码页正在构建汇编列表时，用全屏遮罩挡住整个内容区。
                Widget withCompileOverlay(Widget child) => Stack(
                  children: [
                    child,
                    if (asmPreview.compiling)
                      Positioned.fill(
                        child: _AsmCompilingOverlay(
                          progress: asmPreview.progress,
                        ),
                      ),
                  ],
                );
                if (!wide) {
                  return withCompileOverlay(
                    Column(
                      children: [
                        _CompactStepPicker(
                          steps: steps,
                          selected: state.step,
                          busy: deploy.busy,
                        ),
                        Expanded(child: content),
                      ],
                    ),
                  );
                }
                return withCompileOverlay(
                  Row(
                    children: [
                      SizedBox(
                        width: 260,
                        child: Material(
                          color: AppSurface.block.colorOf(
                            Theme.of(context).colorScheme,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (var i = 0; i < steps.length; i++)
                                _StepTile(
                                  index: i,
                                  title: steps[i],
                                  visual: _stepVisual(i, state),
                                  onTap: deploy.busy
                                      ? () {}
                                      : () => goToStep(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: ShapeDecoration(
                color: AppSurface.block.colorOf(Theme.of(context).colorScheme),
                shape: AppShape.top(AppCorner.lgIncreased),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 28,
                vertical: compact ? 8 : 14,
              ),
              child: Row(
                children: [
                  compact
                      ? IconButton.outlined(
                          onPressed: state.step > 0 && !deploy.busy
                              ? () => goToStep(state.step - 1)
                              : null,
                          tooltip: '上一步',
                          icon: const Icon(Icons.arrow_back),
                        )
                      : PressScale(
                          enabled: state.step > 0 && !deploy.busy,
                          child: OutlinedButton.icon(
                            onPressed: state.step > 0 && !deploy.busy
                                ? () => goToStep(state.step - 1)
                                : null,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('上一步'),
                          ),
                        ),
                  const Spacer(),
                  Text(
                    '${state.step + 1} / ${steps.length}',
                    style: AppText.count(context),
                  ),
                  const Spacer(),
                  compact
                      ? IconButton.filled(
                          onPressed:
                              state.step < steps.length - 1 && !deploy.busy
                              ? () => goToStep(state.step + 1)
                              : null,
                          tooltip:
                              state.step == controller.reviewStep(document.kind)
                              ? '生成代码'
                              : state.step == controller.codeStep(document.kind)
                              ? '烧录'
                              : state.step ==
                                    controller.deployStep(document.kind)
                              ? '烧录'
                              : '下一步',
                          icon: const Icon(Icons.arrow_forward),
                        )
                      : PressScale(
                          enabled:
                              state.step < steps.length - 1 && !deploy.busy,
                          child: FilledButton.icon(
                            onPressed:
                                state.step < steps.length - 1 && !deploy.busy
                                ? () => goToStep(state.step + 1)
                                : null,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              state.step == controller.reviewStep(document.kind)
                                  ? '生成代码'
                                  : state.step ==
                                        controller.codeStep(document.kind)
                                  ? '烧录'
                                  : state.step ==
                                        controller.deployStep(document.kind)
                                  ? '烧录'
                                  : '下一步',
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
