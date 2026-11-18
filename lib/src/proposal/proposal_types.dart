import 'package:pieblock_core/pieblock_core.dart';

/// 当前工程是否有待处理的 AI 提案。
enum ProposalStatus {
  /// 没有提案。
  none,

  /// 有一份可应用的提案。
  pending,

  /// 有提案文件，但读取/校验失败。
  invalid,
}

/// 一份提案的评估结果（应用侧状态）。
class ProposalInspection {
  const ProposalInspection({
    required this.status,
    this.proposal,
    this.error,
    this.stale = false,
    this.dirty = false,
    this.remainingErrors = 0,
    this.proposalPath,
  });

  const ProposalInspection.none() : this(status: ProposalStatus.none);

  factory ProposalInspection.invalid(String error, {String? path}) =>
      ProposalInspection(
        status: ProposalStatus.invalid,
        error: error,
        proposalPath: path,
      );

  final ProposalStatus status;
  final ProjectProposal? proposal;

  /// 读取或校验失败的说明。
  final String? error;

  /// 提案基于旧版本工程（生成后工程又被保存过）。
  final bool stale;

  /// 应用内存里有未保存的改动，应用提案会覆盖它们。
  final bool dirty;

  /// 应用后工程仍会剩下的 error 级问题数（提案没有新增，只是工程本来没配完）。
  final int remainingErrors;

  final String? proposalPath;

  bool get hasPending => status == ProposalStatus.pending;
  bool get isInvalid => status == ProposalStatus.invalid;
}

/// 应用提案的结果。
enum ProposalApplyResult {
  /// 已写入并清理提案。
  applied,

  /// 写盘失败，提案仍在。
  failed,

  /// 当前没有可应用的提案。
  unavailable,
}
