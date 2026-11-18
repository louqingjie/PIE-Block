import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_app/src/proposal/proposal_banner.dart';
import 'package:pieblock_app/src/proposal/proposal_diff_dialog.dart';
import 'package:pieblock_app/src/proposal/proposal_service_io.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'support/valid_project.dart';

class _FakeProposalService extends ProposalService {
  _FakeProposalService(this._initial);

  final ProposalInspection _initial;
  int accepted = 0;

  @override
  ProposalInspection build() => _initial;

  @override
  Future<ProposalApplyResult> accept() async {
    accepted += 1;
    return ProposalApplyResult.applied;
  }
}

ProjectProposal _proposal() => ProjectProposal.create(
  base: validInfantryDocument(),
  candidateJson: projectJsonWithSpeed(4321),
  baseSha256: 'a' * 64,
);

void main() {
  testWidgets('提案横幅展示摘要、标记与操作', (tester) async {
    final proposal = _proposal();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proposalServiceProvider.overrideWith(
            () => _FakeProposalService(
              ProposalInspection(
                status: ProposalStatus.pending,
                proposal: proposal,
                stale: true,
                dirty: true,
                remainingErrors: 1,
                proposalPath: r'C:\tmp\robot.pieproj.proposed',
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProposalBanner())),
      ),
    );

    expect(find.textContaining('AI 提交了改动提案'), findsOneWidget);
    expect(find.textContaining('基于旧版本'), findsOneWidget);
    expect(find.textContaining('未保存'), findsOneWidget);
    expect(find.textContaining('工程仍有 1 个错误'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('丢弃'), findsOneWidget);
    // 主题把 bannerTheme 统一设成错误色；提案横幅必须显式覆盖，不能是红色。
    final scheme = Theme.of(tester.element(find.byType(ProposalBanner)))
        .colorScheme;
    final banner = tester.widget<MaterialBanner>(find.byType(MaterialBanner));
    expect(banner.backgroundColor, scheme.surfaceContainerHigh);
  });

  testWidgets('无法读取的提案显示错误与丢弃', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proposalServiceProvider.overrideWith(
            () => _FakeProposalService(
              ProposalInspection.invalid('坏文件', path: 'x.proposed'),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProposalBanner())),
      ),
    );

    expect(find.textContaining('AI 提案无法读取'), findsOneWidget);
    expect(find.text('丢弃'), findsOneWidget);
    final scheme = Theme.of(tester.element(find.byType(ProposalBanner)))
        .colorScheme;
    expect(
      tester
          .widget<MaterialBanner>(find.byType(MaterialBanner))
          .backgroundColor,
      scheme.errorContainer,
    );
  });

  testWidgets('改动对话框展示字段差异与警告', (tester) async {
    final proposal = _proposal();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalDiffDialog(
            current: validInfantryConfig(),
            proposal: proposal,
            stale: true,
            dirty: true,
            remainingErrors: 2,
          ),
        ),
      ),
    );

    expect(find.text('AI 改动提案'), findsOneWidget);
    expect(find.textContaining('chassis.normal_speed'), findsOneWidget);
    expect(find.textContaining('基于旧版本'), findsOneWidget);
    expect(find.textContaining('未保存'), findsOneWidget);
    expect(find.textContaining('工程本身还有 2 个校验错误'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('应用后的提示条会自动消失，撤销窗口内仍可点', (tester) async {
    final service = _FakeProposalService(
      ProposalInspection(
        status: ProposalStatus.pending,
        proposal: _proposal(),
        proposalPath: 'x.proposed',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proposalServiceProvider.overrideWith(() => service),
        ],
        child: const MaterialApp(home: Scaffold(body: ProposalBanner())),
      ),
    );

    await tester.tap(find.text('应用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.accepted, 1);
    expect(find.text('已应用 AI 提案'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    // 带 action 的默认值是 persist=true（永不自动消失），这里必须是 false。
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.persist, isFalse);
    expect(snackBar.duration, const Duration(seconds: 6));

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('已应用 AI 提案'), findsNothing);
  });
}
