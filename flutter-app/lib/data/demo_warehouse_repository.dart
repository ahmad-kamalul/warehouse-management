import 'dart:math';

import '../core/api_client.dart';
import '../domain/models.dart';
import '../domain/operations.dart';
import '../domain/warehouse_repository.dart';

/// Explicit, ephemeral sandbox; never a fallback for failed network requests.
class DemoWarehouseRepository implements WarehouseRepository {
  DemoWarehouseRepository() {
    _seed();
  }
  final Map<String, InventoryItem> _items = {};
  int _nextId = 100;
  @override
  bool get isDemo => true;
  final _receipts = <String, MovementReceipt>{};
  @override
  String get storageNamespace => 'demo';
  @override
  Future<MasterData> downloadMaster() async => MasterData(
    downloadedAt: DateTime.now().toUtc(),
    items: _items.values.toList(),
  );
  @override
  Future<MovementReceipt> uploadMovement(StockMovement movement) async {
    if (_receipts[movement.clientId] case final receipt?) return receipt;
    final item = await get(movement.itemId);
    if (movement.type == MovementType.stockCount &&
        item.version != movement.expectedVersion) {
      throw const ApiException(
        'Stock changed after download. Download master and recount.',
        status: 409,
      );
    }
    final after = switch (movement.type) {
      MovementType.stockCount => movement.quantity,
      MovementType.goodsIn => item.quantity + movement.quantity,
      MovementType.goodsOut => item.quantity - movement.quantity,
    };
    if (after < 0 || after > 2147483647) {
      throw const ApiException(
        'Insufficient stock or quantity exceeds limit.',
        status: 409,
      );
    }
    final updated = await save(
      ItemDraft(
        name: item.name,
        sku: item.sku,
        category: item.category,
        quantity: after,
        reorderLevel: item.reorderLevel,
        priceCents: item.priceCents,
        notes: item.notes,
      ),
      original: item,
    );
    final receipt = MovementReceipt(
      id: newTransactionId(),
      before: item.quantity,
      after: after,
      version: updated.version,
      uploadedAt: DateTime.now().toUtc(),
    );
    _receipts[movement.clientId] = receipt;
    return receipt;
  }

  void _seed() {
    _items.clear();
    const rows = [
      ('Industrial safety gloves', 'PPE-001', 'Safety', 124, 30, 1850),
      ('Heavy-duty storage bin', 'STR-014', 'Storage', 8, 15, 4590),
      ('Packing tape · 48 mm', 'PKG-028', 'Packaging', 260, 50, 650),
      ('Steel shelving unit', 'STR-006', 'Storage', 0, 5, 38900),
      ('Barcode label roll', 'PKG-032', 'Packaging', 42, 20, 2490),
      ('Digital weighing scale', 'EQP-009', 'Equipment', 6, 3, 17900),
      ('High-visibility vest', 'PPE-012', 'Safety', 12, 20, 2200),
      ('Pallet stretch wrap', 'PKG-041', 'Packaging', 85, 25, 3200),
    ];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      _items['$i'] = InventoryItem(
        id: '$i',
        version: 0,
        updatedAt: DateTime.utc(2026, 10, 20 + i),
        name: r.$1,
        sku: r.$2,
        category: r.$3,
        quantity: r.$4,
        reorderLevel: r.$5,
        priceCents: r.$6,
        notes: 'Check packaging condition before dispatch.',
      );
    }
  }

  @override
  Future<WarehouseUser> authenticate({
    required String email,
    required String password,
    String? name,
  }) async =>
      const WarehouseUser(name: 'Alex Morgan', email: 'alex@demo.warehouse');
  @override
  Future<InventoryPage> list(InventoryQuery query) async {
    final search = query.search.toLowerCase();
    final rows = _items.values
        .where(
          (item) =>
              (search.isEmpty ||
                  [
                    item.name,
                    item.sku,
                    item.category,
                  ].any((text) => text.toLowerCase().contains(search))) &&
              (query.category.isEmpty ||
                  item.category.toLowerCase() ==
                      query.category.toLowerCase()) &&
              (!query.lowStock || item.lowStock),
        )
        .toList();
    rows.sort((a, b) {
      final result = switch (query.sort) {
        'name' => a.name.compareTo(b.name),
        'sku' => a.sku.compareTo(b.sku),
        'quantity' => a.quantity.compareTo(b.quantity),
        'price' => a.priceCents.compareTo(b.priceCents),
        _ => a.updatedAt.compareTo(b.updatedAt),
      };
      return query.ascending ? result : -result;
    });
    final start = min(query.page * InventoryQuery.pageSize, rows.length);
    return InventoryPage(
      items: rows.sublist(
        start,
        min(start + InventoryQuery.pageSize, rows.length),
      ),
      total: rows.length,
      pages: (rows.length / InventoryQuery.pageSize).ceil(),
    );
  }

  @override
  Future<InventoryItem> get(String id) async =>
      _items[id] ??
      (throw const ApiException('This item no longer exists.', status: 404));
  @override
  Future<InventoryItem> save(ItemDraft draft, {InventoryItem? original}) async {
    if (original != null &&
        (await get(original.id)).version != original.version) {
      throw const ApiException(
        'This item changed. Reload before saving.',
        status: 409,
      );
    }
    if (_items.values.any(
      (i) => i.sku == draft.sku.trim().toUpperCase() && i.id != original?.id,
    )) {
      throw const ApiException(
        'An item with this SKU already exists.',
        status: 409,
        fields: {'sku': 'Choose a unique SKU.'},
      );
    }
    final item = InventoryItem(
      id: original?.id ?? '${_nextId++}',
      version: (original?.version ?? -1) + 1,
      updatedAt: DateTime.now().toUtc(),
      name: draft.name.trim(),
      sku: draft.sku.trim().toUpperCase(),
      category: draft.category.trim(),
      quantity: draft.quantity,
      reorderLevel: draft.reorderLevel,
      priceCents: draft.priceCents,
      notes: draft.notes.trim(),
    );
    _items[item.id] = item;
    return item;
  }

  @override
  Future<void> delete(String id) async {
    await get(id);
    _items.remove(id);
  }

  @override
  void signOut() {
    _receipts.clear();
    _seed();
  }

  @override
  void dispose() {}
}
