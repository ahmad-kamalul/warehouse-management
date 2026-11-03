import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../domain/models.dart';
import '../domain/warehouse_repository.dart';
import '../data/operations_store.dart';
import 'operations/operations_controller.dart';

/// Presentation state. Widgets never call HTTP or own credentials.
class WarehouseController extends ChangeNotifier {
  WarehouseController(this.repository, {OperationsStore? operationsStore})
    : operations = OperationsController(
        repository,
        operationsStore ?? MemoryOperationsStore(),
      ) {
    operations.onExpired = () => signOut(
      message: 'Your session expired. Sign in again; saved warehouse work is retained.',
    );
  }
  final OperationsController operations;
  final WarehouseRepository repository;
  WarehouseUser? user;
  InventoryQuery query = const InventoryQuery();
  InventoryPage? inventory;
  bool loading = false;
  bool authenticating = false;
  String? error, sessionMessage;
  int _generation = 0;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    if (authenticating) return;
    authenticating = true;
    sessionMessage = null;
    _emit();
    try {
      user = await repository.authenticate(
        email: email,
        password: password,
        name: name,
      );
      await operations.open(
        user!.id.isEmpty ? user!.email.toLowerCase() : user!.id,
      );
      await load();
    } finally {
      authenticating = false;
      _emit();
    }
  }

  Future<void> load([InventoryQuery? next]) async {
    if (user == null) return;
    query = next ?? query;
    final generation = ++_generation;
    loading = true;
    error = null;
    inventory = null; // Never display old rows beneath a different query.
    _emit();
    try {
      var result = await repository.list(query);
      if (generation != _generation || _disposed) return;
      if (query.page > 0 && query.page >= result.pages) {
        query = query.copyWith(page: result.pages > 0 ? result.pages - 1 : 0);
        result = await repository.list(query);
      }
      if (generation == _generation && !_disposed) inventory = result;
    } catch (e) {
      if (generation != _generation || _disposed) return;
      if (!_expire(e)) {
        error = e is ApiException
            ? e.message
            : 'Something went wrong. Please retry.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  Future<InventoryItem> save(ItemDraft draft, {InventoryItem? original}) async {
    try {
      final result = await repository.save(draft, original: original);
      await load();
      return result;
    } catch (e) {
      _expire(e);
      rethrow;
    }
  }

  Future<InventoryItem> reloadItem(String id) async {
    try {
      return await repository.get(id);
    } catch (e) {
      _expire(e);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await repository.delete(id);
      await load();
    } catch (e) {
      _expire(e);
      rethrow;
    }
  }

  bool _expire(Object e) {
    if (e is ApiException && e.status == 401) {
      signOut(message: 'Your session expired. Please sign in again.');
      return true;
    }
    return false;
  }

  void signOut({String? message}) {
    _generation++;
    operations.clearSession();
    repository.signOut();
    user = null;
    query = const InventoryQuery();
    inventory = null;
    loading = false;
    error = null;
    sessionMessage = message;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    repository.dispose();
    operations.dispose();
    super.dispose();
  }
}
