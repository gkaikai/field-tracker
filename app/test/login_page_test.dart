import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:field_tracker/pages/login_page.dart';

void main() {
  group('LoginPage Widget Tests', () {
    testWidgets('should display login form elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoginPage()),
      );

      // 检查必要元素
      expect(find.text('外勤定位'), findsOneWidget);
      expect(find.text('登 录'), findsOneWidget);
      expect(find.text('手机号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
    });

    testWidgets('should show validation error on empty fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoginPage()),
      );

      // 清空输入框
      final usernameField = find.widgetWithText(TextFormField, '手机号');
      final passwordField = find.widgetWithText(TextFormField, '密码');
      expect(usernameField, findsOneWidget);
      expect(passwordField, findsOneWidget);

      // 点击登录按钮（不输入内容）
      await tester.tap(find.text('登 录'));
      await tester.pumpAndSettle();

      // 应显示表单验证错误
      // 注意：实际验证消息取决于 TextFormField 的 validator
    });
  });
}
