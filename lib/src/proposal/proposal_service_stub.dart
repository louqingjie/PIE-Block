/// 提案服务的非 IO 平台桩（Web）：没有文件系统，永远没有提案。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proposal_types.dart';

export 'proposal_types.dart';

final proposalServiceProvider =
    NotifierProvider<ProposalService, ProposalInspection>(ProposalService.new);

class ProposalService extends Notifier<ProposalInspection> {
  @override
  ProposalInspection build() => const ProposalInspection.none();

  Future<ProposalApplyResult> accept() async => ProposalApplyResult.unavailable;

  Future<void> discard() async {}
}
