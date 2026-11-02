import '../core/api_client.dart';
import '../domain/models.dart';
import '../domain/warehouse_repository.dart';

class ApiWarehouseRepository implements WarehouseRepository {
  ApiWarehouseRepository(this.client);
  final ApiClient client;
  @override
  bool get isDemo => false;
  @override
  Future<WarehouseUser> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    final json = await client.request(
      'POST',
      '/auth/${name == null ? 'login' : 'register'}',
      body: {
        'email': email.trim(),
        'password': password,
        if (name != null) 'name': name.trim(),
      },
    ) as Map<String, dynamic>;
    client.token = json['accessToken'] as String;
    return WarehouseUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  @override
  Future<InventoryPage> list(InventoryQuery query) async =>
      InventoryPage.fromJson(
        await client.request('GET', '/items', query: query.toParams())
            as Map<String, dynamic>,
      );
  @override
  Future<InventoryItem> get(String id) async => InventoryItem.fromJson(
    await client.request('GET', '/items/${Uri.encodeComponent(id)}')
        as Map<String, dynamic>,
  );
  @override
  Future<InventoryItem> save(
    ItemDraft draft, {
    InventoryItem? original,
  }) async => InventoryItem.fromJson(
    await client.request(
      original == null ? 'POST' : 'PUT',
      original == null
          ? '/items'
          : '/items/${Uri.encodeComponent(original.id)}',
      body: draft.toJson(version: original?.version),
    ) as Map<String, dynamic>,
  );
  @override
  Future<void> delete(String id) async {
    await client.request('DELETE', '/items/${Uri.encodeComponent(id)}');
  }

  @override
  void signOut() => client.token = null;
  @override
  void dispose() => client.close();
}
