import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_mobile/core/validators.dart';
import 'package:warehouse_mobile/domain/models.dart';

void main() {
  test('money preserves API decimal values without rounding errors', () {
    expect(parseCents('9999999999.99'), 999999999999);
    expect(parseCents(12.5), 1250);
    expect(parseCents(0), 0);
    expect(decimalPrice(parseCents('0.01')), '0.01');
  });
  test(
    'validation covers integer, decimal, SKU and BCrypt byte boundaries',
    () {
      expect(Validators.wholeNumber('2147483647'), isNull);
      for (final v in ['2147483648', '-1', '1.2', 'abc']) {
        expect(Validators.wholeNumber(v), isNotNull);
      }
      expect(Validators.price('9999999999.99'), isNull);
      for (final v in ['10000000000', '-1', '1.001', '1e3']) {
        expect(Validators.price(v), isNotNull);
      }
      expect(Validators.sku('BOX_001-A'), isNull);
      expect(Validators.sku('BOX 001'), isNotNull);
      expect(Validators.password('é' * 37, registration: true), isNotNull);
      expect(Validators.password('é' * 36, registration: true), isNull);
    },
  );
  test('update sends all required fields and the exact observed version', () {
    const draft = ItemDraft(
      name: ' Tape ',
      sku: 'pkg-1',
      category: ' Packing ',
      quantity: 1,
      reorderLevel: 1,
      priceCents: 650,
      notes: ' note ',
    );
    expect(draft.toJson(version: 7), {
      'name': 'Tape',
      'sku': 'PKG-1',
      'category': 'Packing',
      'quantity': 1,
      'reorderLevel': 1,
      'price': '6.50',
      'notes': 'note',
      'version': 7,
    });
    expect(draft.toJson().containsKey('version'), isFalse);
  });
}
