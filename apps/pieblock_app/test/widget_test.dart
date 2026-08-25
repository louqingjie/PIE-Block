import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/main.dart';

void main() {
  testWidgets('启动页展示两个项目入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PieBlockApp()));
    await tester.pumpAndSettle();
    expect(find.text('新建机器人项目'), findsOneWidget);
    expect(find.text('打开已有项目'), findsOneWidget);
    expect(find.text('PIE-Block'), findsOneWidget);
  });
}
