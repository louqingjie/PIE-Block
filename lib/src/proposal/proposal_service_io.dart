/// 提案服务：轮询工程旁边的 `<工程>.proposed`，把结果交给 UI 展示。
///
/// 应用是工程文件的唯一写者：这里只读取和删除提案文件，真正写入由
/// [AppController.applyProposal] 完成。轮询而不是文件监听，是为了避开
/// Windows 上原子替换产生的事件抖动，并且逻辑更容易测试。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../controller.dart';
import 'proposal_types.dart';

export 'proposal_types.dart';

final proposalServiceProvider =
    NotifierProvider<ProposalService, ProposalInspection>(ProposalService.new);

/// 读取并评估工程旁边的提案文件；不依赖 Riverpod，便于单测。
ProposalInspection inspectProposalFile(
  String projectPath,
  ProjectDocument current,
) {
  final path = proposalPathFor(projectPath);
  final file = File(path);
  if (!file.existsSync()) return const ProposalInspection.none();
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return ProposalInspection.invalid('提案不是 JSON 对象', path: path);
    }
    final proposal = ProjectProposal.fromJson(
      Map<String, Object?>.from(decoded),
    );
    if (proposal.document.kind != current.kind) {
      return ProposalInspection.invalid('提案的工程类型与当前工程不一致', path: path);
    }
    // 工程可能本来就没配置完：只拒绝候选**新增**的校验错误。
    final newErrors = newValidationErrors(
      base: current.config,
      candidate: proposal.document.config,
    );
    if (newErrors.isNotEmpty) {
      return ProposalInspection.invalid(
        '提案引入了 ${newErrors.length} 个新的校验错误：${newErrors.first.message}',
        path: path,
      );
    }
    final remainingErrors = ProjectValidator.validate(proposal.document.config)
        .where((issue) => issue.severity == IssueSeverity.error)
        .length;
    return ProposalInspection(
      status: ProposalStatus.pending,
      proposal: proposal,
      stale: _isStale(projectPath, proposal.baseSha256),
      dirty: _isDirty(projectPath, current),
      remainingErrors: remainingErrors,
      proposalPath: path,
    );
  } on ProposalException catch (error) {
    return ProposalInspection.invalid(error.message, path: path);
  } on FormatException catch (error) {
    return ProposalInspection.invalid('提案格式错误：${error.message}', path: path);
  } catch (error) {
    return ProposalInspection.invalid('提案无法读取：$error', path: path);
  }
}

class ProposalService extends Notifier<ProposalInspection> {
  Timer? _timer;
  String? _projectPath;
  String? _signature;
  String? _dismissedSignature;
  bool _disposed = false;

  @override
  ProposalInspection build() {
    ref.listen<String?>(
      appControllerProvider.select((state) => state.path),
      (_, path) => _scheduleWatch(path),
    );
    // build 期间不能改 state，初始检查推到微任务里。
    _scheduleWatch(ref.read(appControllerProvider).path);
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    return const ProposalInspection.none();
  }

  /// 应用当前提案；成功后清理提案文件并写结果文件。
  Future<ProposalApplyResult> accept() async {
    final proposal = state.proposal;
    final projectPath = _projectPath;
    if (proposal == null || projectPath == null) {
      return ProposalApplyResult.unavailable;
    }
    final applied = await ref
        .read(appControllerProvider.notifier)
        .applyProposal(proposal.document.config);
    if (!applied) return ProposalApplyResult.failed;
    _writeResult(projectPath, 'applied');
    _deleteProposal(projectPath);
    _signature = null;
    if (!_disposed) state = const ProposalInspection.none();
    return ProposalApplyResult.applied;
  }

  /// 丢弃当前提案（包括无法读取的提案）。
  Future<void> discard() async {
    final projectPath = _projectPath;
    if (projectPath == null) return;
    _dismissedSignature = _signature;
    _writeResult(projectPath, 'discarded');
    _deleteProposal(projectPath);
    _signature = null;
    if (!_disposed) state = const ProposalInspection.none();
  }

  void _scheduleWatch(String? path) {
    scheduleMicrotask(() {
      if (_disposed) return;
      _watch(path);
    });
  }

  void _watch(String? path) {
    _timer?.cancel();
    _timer = null;
    _projectPath = path;
    _signature = null;
    if (state.status != ProposalStatus.none) {
      state = const ProposalInspection.none();
    }
    if (path == null || !_supportsProposals(path)) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(_check()),
    );
    unawaited(_check());
  }

  bool _supportsProposals(String path) {
    if (kIsWeb) return false;
    if (path.startsWith('content://')) return false;
    return path.toLowerCase().endsWith('.pieproj');
  }

  Future<void> _check() async {
    if (_disposed) return;
    final projectPath = _projectPath;
    if (projectPath == null) return;
    final document = ref.read(appControllerProvider).document;
    if (document == null) return;

    final file = File(proposalPathFor(projectPath));
    if (!file.existsSync()) {
      _signature = null;
      if (state.status != ProposalStatus.none) {
        state = const ProposalInspection.none();
      }
      return;
    }

    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      return;
    }
    final signature = '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
    if (signature == _dismissedSignature) return;
    if (signature == _signature) {
      // 提案没变，但工程可能被保存过，刷新「基于旧版本 / 有未保存改动」标记。
      if (state.hasPending) {
        final refreshed = inspectProposalFile(projectPath, document);
        if (_disposed) return;
        if (refreshed.status == ProposalStatus.pending) {
          if (refreshed.stale != state.stale ||
              refreshed.dirty != state.dirty) {
            state = refreshed;
          }
        } else if (refreshed.status == ProposalStatus.none) {
          _signature = null;
          state = const ProposalInspection.none();
        }
      }
      return;
    }

    _signature = signature;
    final inspection = inspectProposalFile(projectPath, document);
    if (_disposed) return;
    state = inspection;
  }

  void _writeResult(String projectPath, String status) {
    try {
      File(proposalResultPathFor(projectPath)).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'schema': 1, 'status': status, 'at': DateTime.now().toUtc().toIso8601String()})}\n',
      );
    } catch (_) {
      // 结果文件只是给 Agent 的可选反馈，写失败不影响应用逻辑。
    }
  }

  void _deleteProposal(String projectPath) {
    try {
      final file = File(proposalPathFor(projectPath));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 删除失败时保留 _dismissedSignature，不会反复提示同一份提案。
    }
  }
}

bool _isStale(String projectPath, String baseSha256) {
  try {
    return sha256Hex(File(projectPath).readAsBytesSync()) != baseSha256;
  } catch (_) {
    return false;
  }
}

bool _isDirty(String projectPath, ProjectDocument current) {
  try {
    final decoded = jsonDecode(File(projectPath).readAsStringSync());
    if (decoded is! Map) return false;
    final disk = ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
    return jsonEncode(disk.config.toJson()) !=
        jsonEncode(current.config.toJson());
  } catch (_) {
    return false;
  }
}
