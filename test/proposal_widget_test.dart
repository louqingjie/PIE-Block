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

  @override
  ProposalInspection build() => _initial;
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
    expect(find.text('查看'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('丢弃'), findsOneWidget);
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
          ),
        ),
      ),
    );

    expect(find.text('AI 改动提案'), findsOneWidget);
    expect(find.textContaining('chassis.normal_speed'), findsOneWidget);
    expect(find.textContaining('基于旧版本'), findsOneWidget);
    expect(find.textContaining('未保存'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });
}
