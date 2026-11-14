import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_core/speedy_core.dart';

void main() {
  test('Indian phone normalization accepts valid 10-digit numbers and rejects invalid ones', () {
    expect(SessionController.normalizeIndianPhone('9876543210'), '+919876543210');
    expect(SessionController.normalizeIndianPhone('+91 98765-43210'), '+919876543210');
    expect(SessionController.normalizeIndianPhone('09876543210'), '+919876543210');
    expect(SessionController.normalizeIndianPhone('1234567890'), isNull);
    expect(SessionController.normalizeIndianPhone('98765'), isNull);
  });

  test('Catalog fallback contains all 5 vehicles and 5 issues with integer paise pricing', () {
    expect(Catalog.fallback.vehicles.length, 5);
    expect(Catalog.fallback.issues.length, 5);
    expect(formatRupeesFromPaise(Catalog.fallback.vehicles.first.visitFeePaise), '₹149');
  });
}
