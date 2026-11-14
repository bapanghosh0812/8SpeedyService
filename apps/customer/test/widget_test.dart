import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_core/speedy_core.dart';
import 'package:speedy_customer/main.dart';

void main() {
  testWidgets('Customer auth screen renders 8SpeedyService brand and phone input', (WidgetTester tester) async {
    final session = SessionController(storagePrefix: 'test_cust');
    await tester.pumpWidget(SpeedyCustomerApp(session: session));
    expect(find.text('8SpeedyService'), findsOneWidget);
    expect(find.text('Get OTP'), findsOneWidget);
  });
}
