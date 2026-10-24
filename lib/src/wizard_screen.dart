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
import 'design/app_dialog.dart';
import 'design/app_logo.dart';
import 'design/app_theme.dart';
import 'design/asm_hover_card.dart';
import 'design/connected_button_group.dart';
import 'design/legacy_theme_bridge.dart';
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
    // 构建汇编列表时不让翻页：汇编构建与烧录共用同一套工具链工作目录，
    // 同时发起两次构建会互相踩。这里只禁用入口，不再整页遮挡内容。
    final compiling = asmPreview.compiling;
    final busy = deploy.busy || compiling;
    final compact = _isCompact(context);
    final nextLabel = state.step == controller.reviewStep(document.kind)
        ? '生成代码'
        : state.step == controller.codeStep(document.kind)
        ? '烧录'
        : state.step == controller.deployStep(document.kind)
        ? '烧录'
        : '下一步';
    final actionCluster = _WizardActionCluster(
      compact: compact,
      step: state.step,
      totalSteps: steps.length,
      nextLabel: nextLabel,
      onPrevious: state.step > 0 && !busy
          ? () => goToStep(state.step - 1)
          : null,
      onNext: state.step < steps.length - 1 && !busy
          ? () => goToStep(state.step + 1)
          : null,
    );
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
                  : compiling
                  ? null
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
                // M3 fade-through：旧页在前 30% 淡出，新页从 30% 开始淡入、
                // 轻微放大。两页不会在同一位置同时可读，避免切换瞬间出现
                // “字叠字”的重影；透明度走 effects 曲线，缩放走 spatial 曲线。
                const fadeOut = Interval(
                  .7,
                  1,
                  curve: AppMotion.expressiveFastEffects,
                );
                const fadeIn = Interval(
                  .3,
                  1,
                  curve: AppMotion.expressiveDefaultEffects,
                );
                const scaleIn = Interval(
                  .3,
                  1,
                  curve: AppMotion.expressiveDefaultSpatial,
                );
                final content = MediaQuery.disableAnimationsOf(context)
                    ? page
                    : AnimatedSwitcher(
                        duration: AppMotion.fastSpatial(context),
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        transitionBuilder: (child, animation) {
                          // AnimatedSwitcher 给旧页的是反向动画；用当前步骤
                          // 判断哪一份是新页：新页延迟淡入，旧页先淡出。
                          final incoming = child.key == ValueKey(state.step);
                          if (!incoming) {
                            return FadeTransition(
                              opacity: animation.drive(
                                CurveTween(curve: fadeOut),
                              ),
                              child: child,
                            );
                          }
                          return FadeTransition(
                            opacity: animation.drive(
                              CurveTween(curve: fadeIn),
                            ),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .98, end: 1).animate(
                                animation.drive(
                                  CurveTween(curve: scaleIn),
                                ),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(state.step),
                          child: page,
                        ),
                      );
                // 生成代码页的编译进度就地显示在汇编栏里，不再遮挡整个内容区。
                Widget withActions(Widget child) => Stack(
                  children: [
                    Positioned.fill(child: child),
                    PositionedDirectional(
                      end: compact ? 12 : 24,
                      bottom:
                          (compact ? 12 : 24) +
                          MediaQuery.paddingOf(context).bottom,
                      child: actionCluster,
                    ),
                  ],
                );
                if (!wide) {
                  return Column(
                    children: [
                      _CompactStepPicker(
                        steps: steps,
                        selected: state.step,
                        busy: busy,
                      ),
                      Expanded(child: withActions(content)),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: AppSurface.block.colorOf(
                          Theme.of(context).colorScheme,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  for (var i = 0; i < steps.length; i++)
                                    _StepTile(
                                      index: i,
                                      title: steps[i],
                                      visual: _stepVisual(i, state),
                                      onTap: busy ? () {} : () => goToStep(i),
                                    ),
                                ],
                              ),
                            ),
                            // 品牌区固定在步骤栏底部：不占 AppBar，也不会在
                            // 短窗口里被步骤列表滚走；这里只展示从官方标识
                            // 顶部裁出的 W.PIE 词标，不显示“首都师范大学”
                            // “学生创新实验室”两行中文。词标按主题自动切换
                            // 透明彩色 / 白色单通道资源；实验室全名仍保留在
                            // 无障碍标签里，读屏用户不会丢失信息。
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16 + MediaQuery.paddingOf(context).bottom,
                              ),
                              child: const Center(
                                child: WpieWordmark(
                                  key: ValueKey('wizard.lab-logo'),
                                  height: 64,
                                  semanticLabel: '首都师范大学学生创新实验室',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: withActions(content)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
