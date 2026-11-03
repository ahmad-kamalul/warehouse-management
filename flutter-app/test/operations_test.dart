import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_mobile/core/api_client.dart';
import 'package:warehouse_mobile/data/demo_warehouse_repository.dart';
import 'package:warehouse_mobile/data/operations_store.dart';
import 'package:warehouse_mobile/domain/models.dart';
import 'package:warehouse_mobile/domain/operations.dart';
import 'package:warehouse_mobile/features/operations/operations_controller.dart';

class RemoteDemo extends DemoWarehouseRepository {
  @override
  bool get isDemo => false;
  @override
  String get storageNamespace => 'test-server';
  bool loseNextReply = false;
  int uploads = 0;
  @override
  Future<MovementReceipt> uploadMovement(StockMovement movement) async {
    uploads++;
    final result = await super.uploadMovement(movement);
    if (loseNextReply) {
      loseNextReply = false;
      throw const ApiException('Connection lost after server commit.');
    }
    return result;
  }
}

class FailingStore extends MemoryOperationsStore {
  bool fail = false;
  @override
  Future<void> write(String scope, String value) async {
    if (fail) throw StateError('Disk full');
    await super.write(scope, value);
  }
}

void main() {
  late RemoteDemo repo;
  late MemoryOperationsStore store;
  late OperationsController op;
  setUp(() async {
    repo = RemoteDemo();
    store = MemoryOperationsStore();
    op = OperationsController(repo, store);
    await op.open('account-a');
    await op.download();
  });
  tearDown(() => op.dispose());
  Future<bool> queue(MovementType type, int quantity, {InventoryItem? item}) =>
      op.enqueue(
        item: item ?? op.findSku('PPE-001')!,
        type: type,
        quantity: quantity,
        reference: 'DOC-001',
        notes: '',
      );

  test(
    'master download includes every item and exact case-insensitive SKU lookup',
    () {
      expect(op.master!.items.length, 8);
      expect(op.findSku(' ppe-001 ')!.quantity, 124);
      expect(op.findSku('PPE'), isNull);
    },
  );
  test(
    'goods in and out stay local until upload and receive server receipts',
    () async {
      expect(await queue(MovementType.goodsIn, 10), isTrue);
      expect(await queue(MovementType.goodsOut, 4), isTrue);
      expect(op.projected(op.findSku('PPE-001')!), 130);
      expect((await repo.get('0')).quantity, 124);
      expect(await op.uploadAll(), isTrue);
      expect((await repo.get('0')).quantity, 130);
      expect(op.pendingCount, 0);
      expect(op.movements.every((m) => m.receipt != null), isTrue);
    },
  );
  test(
    'zero stock count is valid and count variance is applied on upload',
    () async {
      expect(await queue(MovementType.stockCount, 0), isTrue);
      expect(await op.uploadAll(), isTrue);
      expect(op.findSku('PPE-001')!.quantity, 0);
      expect(op.movements.single.receipt!.before, 124);
      expect(op.movements.single.receipt!.after, 0);
    },
  );
  test(
    'pending work survives reopen and stays isolated by account and server',
    () async {
      await queue(MovementType.goodsIn, 2);
      final id = op.movements.single.clientId;
      await op.open('account-b');
      expect(op.master, isNull);
      expect(op.movements, isEmpty);
      await op.open('account-a');
      expect(op.movements.single.clientId, id);
      expect(op.master!.items.length, 8);
      final stored = await store.read('test-server|account-a');
      expect((jsonDecode(stored!) as Map)['schema'], 1);
    },
  );
  test(
    'lost acknowledgement survives restart and retry applies stock once',
    () async {
      await queue(MovementType.goodsIn, 10);
      final id = op.movements.single.clientId;
      repo.loseNextReply = true;
      expect(await op.uploadAll(), isFalse);
      expect((await repo.get('0')).quantity, 134);
      expect(op.movements.single.canCancel, isFalse);
      final restored = OperationsController(repo, store);
      await restored.open('account-a');
      expect(restored.movements.single.clientId, id);
      expect(restored.movements.single.attempted, isTrue);
      expect(await restored.uploadAll(), isTrue);
      expect((await repo.get('0')).quantity, 134);
      expect(restored.movements.single.receipt, isNotNull);
      restored.dispose();
    },
  );
  test(
    'counts conflict after intervening stock changes and stop later uploads',
    () async {
      await queue(MovementType.stockCount, 100);
      await queue(MovementType.goodsIn, 2);
      final item = await repo.get('0');
      await repo.save(
        ItemDraft(
          name: item.name,
          sku: item.sku,
          category: item.category,
          quantity: 125,
          reorderLevel: item.reorderLevel,
          priceCents: item.priceCents,
          notes: item.notes,
        ),
        original: item,
      );
      expect(await op.uploadAll(), isFalse);
      expect(op.movements.first.rejected, isTrue);
      expect(op.movements.last.attempted, isFalse);
      expect(op.movements.first.canCancel, isTrue);
      await op.cancel(op.movements.first);
      expect(await op.uploadAll(), isTrue);
      expect((await repo.get('0')).quantity, 127);
    },
  );
  test(
    'unsent work can be cancelled, unresolved attempted work cannot',
    () async {
      await queue(MovementType.goodsOut, 1);
      expect(await op.cancel(op.movements.single), isTrue);
      expect(op.movements.single.cancelled, isTrue);
      expect(op.pendingCount, 0);
      await queue(MovementType.goodsIn, 1);
      repo.loseNextReply = true;
      await op.uploadAll();
      expect(await op.cancel(op.movements.last), isFalse);
      expect(op.movements.last.pending, isTrue);
    },
  );
  test(
    'validation rejects zero movements, negative stock, and competing counts',
    () async {
      expect(await queue(MovementType.goodsIn, 0), isFalse);
      expect(await queue(MovementType.goodsOut, 125), isFalse);
      expect(await queue(MovementType.goodsOut, 120), isTrue);
      expect(await queue(MovementType.goodsOut, 5), isFalse);
      expect(await queue(MovementType.stockCount, 4), isFalse);
      expect(op.pendingCount, 1);
    },
  );
  test(
    'failed local save never becomes a queued success or a network write',
    () async {
      final failing = FailingStore();
      final controller = OperationsController(repo, failing);
      await controller.open('account-a');
      await controller.download();
      failing.fail = true;
      expect(
        await controller.enqueue(
          item: controller.findSku('PPE-001')!,
          type: MovementType.goodsIn,
          quantity: 1,
          reference: 'DOC',
          notes: '',
        ),
        isFalse,
      );
      expect(controller.pendingCount, 0);
      expect(repo.uploads, 0);
      controller.dispose();
    },
  );
  test(
    'refresh preserves pending payloads and does not rebase a count silently',
    () async {
      await queue(MovementType.stockCount, 3);
      final original = op.movements.single.toRequest();
      await op.download();
      expect(op.movements.single.toRequest(), original);
    },
  );
  test(
    'uploaded receipt cannot roll a freshly downloaded item backwards',
    () async {
      await queue(MovementType.goodsIn, 10);
      repo.loseNextReply = true;
      await op.uploadAll();
      final item = await repo.get('0');
      await repo.save(
        ItemDraft(
          name: item.name,
          sku: item.sku,
          category: item.category,
          quantity: 200,
          reorderLevel: item.reorderLevel,
          priceCents: item.priceCents,
          notes: item.notes,
        ),
        original: item,
      );
      await op.download();
      expect(await op.uploadAll(), isTrue);
      expect(op.findSku('PPE-001')!.quantity, 200);
    },
  );
}
