import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_mobile/core/api_client.dart';
import 'package:warehouse_mobile/data/demo_warehouse_repository.dart';
import 'package:warehouse_mobile/domain/models.dart';
import 'package:warehouse_mobile/features/warehouse_controller.dart';

class ControlledRepository extends DemoWarehouseRepository {
  final pending = <Completer<InventoryPage>>[];
  bool controlled = false;
  @override
  Future<InventoryPage> list(InventoryQuery query) {
    if (!controlled) return super.list(query);
    final completer = Completer<InventoryPage>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  test(
    'demo creates, updates, filters, detects conflicts, deletes, and resets',
    () async {
      final repo = DemoWarehouseRepository();
      const draft = ItemDraft(
        name: 'Test box',
        sku: 'test-1',
        category: 'Test',
        quantity: 5,
        reorderLevel: 5,
        priceCents: 10,
        notes: '',
      );
      final item = await repo.save(draft);
      expect(item.lowStock, isTrue);
      expect(
        (await repo.list(
          const InventoryQuery(search: 'test-1', lowStock: true),
        )).total,
        1,
      );
      final updated = await repo.save(draft, original: item);
      expect(updated.version, 1);
      await expectLater(
        repo.save(draft, original: item),
        throwsA(isA<ApiException>()),
      );
      await expectLater(repo.save(draft), throwsA(isA<ApiException>()));
      await repo.delete(item.id);
      expect(
        (await repo.list(const InventoryQuery(search: 'test-1'))).total,
        0,
      );
      repo.signOut();
      expect((await repo.list(const InventoryQuery())).total, 8);
    },
  );
  test('old search responses cannot overwrite newer results', () async {
    final repo = ControlledRepository();
    final c = WarehouseController(repo);
    await c.authenticate(email: '', password: '');
    repo.controlled = true;
    final first = c.load(const InventoryQuery(search: 'old'));
    final second = c.load(const InventoryQuery(search: 'new'));
    repo.pending[1].complete(
      const InventoryPage(items: [], total: 2, pages: 1),
    );
    await second;
    repo.pending[0].complete(
      const InventoryPage(items: [], total: 99, pages: 5),
    );
    await first;
    expect(c.inventory!.total, 2);
    expect(c.query.search, 'new');
    c.dispose();
  });
  test(
    '401 clears private data and outstanding responses cannot restore it',
    () async {
      final repo = ControlledRepository();
      final c = WarehouseController(repo);
      await c.authenticate(email: '', password: '');
      repo.controlled = true;
      final request = c.load();
      repo.pending.last.completeError(
        const ApiException('Expired', status: 401),
      );
      await request;
      expect(c.user, isNull);
      expect(c.inventory, isNull);
      expect(c.sessionMessage, contains('expired'));
      c.dispose();
    },
  );
  test(
    'deleting the only row on the last page returns to the previous page',
    () async {
      final repo = ControlledRepository();
      final c = WarehouseController(repo);
      await c.authenticate(email: '', password: '');
      repo.controlled = true;
      final loading = c.load(const InventoryQuery(page: 1));
      repo.pending[0].complete(
        const InventoryPage(items: [], total: 20, pages: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.pending.length, 2);
      repo.pending[1].complete(
        const InventoryPage(items: [], total: 20, pages: 1),
      );
      await loading;
      expect(c.query.page, 0);
      c.dispose();
    },
  );
}
