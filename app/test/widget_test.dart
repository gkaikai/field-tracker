import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/main.dart';

void main() {
  testWidgets('App launches smoke test - login page', (WidgetTester tester) async {
    await tester.pumpWidget(const FieldTrackerApp(isLoggedIn: false));
    // 应该显示登录页面
    expect(find.text('外勤定位'), findsOneWidget);
    expect(find.text('登 录'), findsOneWidget);
  });

  testWidgets('App launches smoke test - home page (logged in)', (WidgetTester tester) async {
    await tester.pumpWidget(const FieldTrackerApp(isLoggedIn: true));
    // 应该显示首页
    expect(find.text('外勤定位'), findsOneWidget);
  });
}
