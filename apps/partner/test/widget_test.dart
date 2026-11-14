import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_core/speedy_core.dart';
import 'package:speedy_partner/main.dart';

void main() {
  testWidgets('Partner auth screen renders 8SpeedyService PARTNER badge and phone input', (WidgetTester tester) async {
    final session = SessionController(storagePrefix: 'test_partner');
    await tester.pumpWidget(SpeedyPartnerApp(session: session));
    expect(find.text('8SpeedyService'), findsOneWidget);
    expect(find.text('PARTNER'), findsOneWidget);
    expect(find.text('Get OTP'), findsOneWidget);
  });
}
