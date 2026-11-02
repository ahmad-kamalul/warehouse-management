import 'models.dart';

abstract class WarehouseRepository {
  bool get isDemo;
  Future<WarehouseUser> authenticate({
    required String email,
    required String password,
    String? name,
  });
  Future<InventoryPage> list(InventoryQuery query);
  Future<InventoryItem> get(String id);
  Future<InventoryItem> save(ItemDraft draft, {InventoryItem? original});
  Future<void> delete(String id);
  void signOut();
  void dispose();
}
