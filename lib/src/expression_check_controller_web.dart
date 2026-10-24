import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'expression_check_state.dart';

export 'expression_check_state.dart';

final expressionCheckControllerProvider =
    NotifierProvider<ExpressionCheckController, ExpressionCheckState>(
      ExpressionCheckController.new,
    );

class ExpressionCheckController extends Notifier<ExpressionCheckState> {
  @override
  ExpressionCheckState build() => const ExpressionCheckState();

  Future<void> check(ProjectConfig config) async {
    state = const ExpressionCheckState(
      activity: ExpressionCheckActivity.unsupported,
      message: 'Web 版仅做表达式语法检查，不做编译检查；请在桌面版完成最终校验',
    );
  }
}
