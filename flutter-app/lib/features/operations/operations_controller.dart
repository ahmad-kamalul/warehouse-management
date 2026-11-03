import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../data/operations_store.dart';
import '../../domain/models.dart';
import '../../domain/operations.dart';
import '../../domain/warehouse_repository.dart';

class _SessionChanged implements Exception {}

class OperationsController extends ChangeNotifier {
  OperationsController(this.repository, this.store);
  final WarehouseRepository repository;
  final OperationsStore store;
  VoidCallback? onExpired;
  MasterData? master;
  List<StockMovement> movements = const [];
  bool busy = false, ready = false;
  String? error, message;
  String _scope = '';
  int _epoch = 0;
  bool _disposed = false;
  int get pendingCount => movements.where((e) => e.pending).length;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (epoch != _epoch || _disposed || _scope.isEmpty) throw _SessionChanged();
  }

  void clearSession() {
    _epoch++;
    _scope = '';
    master = null;
    movements = const [];
    busy = false;
    ready = false;
    error = null;
    message = null;
    _emit();
  }

  Future<void> open(String account) async {
    clearSession();
    _scope = '${repository.storageNamespace}|$account';
    final epoch = _epoch;
    busy = true;
    _emit();
    try {
      final value = repository.isDemo ? null : await store.read(_scope);
      _check(epoch);
      if (value != null) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        if (json['schema'] != 1) {
          throw const FormatException('Unsupported workspace schema');
        }
        master = json['master'] == null
            ? null
            : MasterData.fromJson(json['master'] as Map<String, dynamic>);
        movements = (json['movements'] as List)
            .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      ready = true;
    } on _SessionChanged {
      return;
    } catch (_) {
      error = 'Cannot read saved warehouse work. Reopen the app or restore your device backup; saved data has not been overwritten.';
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> _commit(
    MasterData? nextMaster,
    List<StockMovement> next,
    int epoch,
  ) async {
    _check(epoch);
    final scope = _scope;
    await store.write(
      scope,
      jsonEncode({
        'schema': 1,
        'master': nextMaster?.toJson(),
        'movements': next.map((e) => e.toJson()).toList(),
      }),
    );
    _check(epoch);
    master = nextMaster;
    movements = List.unmodifiable(next);
    _emit();
  }

  Future<bool> _run(Future<void> Function(int epoch) work) async {
    if (busy || !ready) return false;
    final epoch = _epoch;
    busy = true;
    error = null;
    message = null;
    _emit();
    try {
      await work(epoch);
      _check(epoch);
      return true;
    } on _SessionChanged {
      return false;
    } catch (e) {
      if (epoch == _epoch) {
        error = e is ApiException ? e.message : 'Unable to save or complete this operation. Your previous saved work is retained. Retry when storage and network are available.';
        if (e is ApiException && e.status == 401) onExpired?.call();
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> download() => _run((epoch) async {
    final downloaded = await repository.downloadMaster();
    await _commit(downloaded, movements, epoch);
    message =
        '${downloaded.items.length} master items downloaded. Pending work retained.';
  });
  InventoryItem? findSku(String code) {
    final sku = code.trim().toUpperCase();
    for (final item in master?.items ?? <InventoryItem>[]) {
      if (item.sku.toUpperCase() == sku) return item;
    }
    return null;
  }

  int projected(InventoryItem item) {
    var quantity = item.quantity;
    for (final m in movements.where((m) => m.pending && m.itemId == item.id)) {
      quantity = switch (m.type) {
        MovementType.stockCount => m.quantity,
        MovementType.goodsIn => quantity + m.quantity,
        MovementType.goodsOut => quantity - m.quantity,
      };
    }
    return quantity;
  }

  Future<bool> enqueue({
    required InventoryItem item,
    required MovementType type,
    required int quantity,
    required String reference,
    required String notes,
  }) => _run((epoch) async {
    if (findSku(item.sku)?.id != item.id) {
      throw const ApiException('Download master and select the item again.');
    }
    if (quantity < 0 ||
        quantity > 2147483647 ||
        (type != MovementType.stockCount && quantity == 0)) {
      throw const ApiException(
        'Enter a valid quantity. Goods in/out must be greater than zero.',
      );
    }
    if (reference.trim().isEmpty ||
        reference.trim().length > 100 ||
        notes.length > 2000) {
      throw const ApiException(
        'Reference is required (up to 100 characters); notes allow 2000 characters.',
      );
    }
    if (type == MovementType.stockCount &&
        movements.any((m) => m.pending && m.itemId == item.id)) {
      throw const ApiException(
        'Upload or resolve existing work for this SKU before starting a new count.',
      );
    }
    final expected = switch (type) {
      MovementType.stockCount => quantity,
      MovementType.goodsIn => projected(item) + quantity,
      MovementType.goodsOut => projected(item) - quantity,
    };
    if (expected < 0 || expected > 2147483647) {
      throw const ApiException(
        'Quantity would exceed available stock or the supported limit.',
      );
    }
    final m = StockMovement(
      clientId: newTransactionId(),
      itemId: item.id,
      sku: item.sku,
      type: type,
      quantity: quantity,
      expectedVersion: item.version,
      reference: reference.trim(),
      notes: notes.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    await _commit(master, [...movements, m], epoch);
    message =
        '${type.label} saved on this device. Upload to apply it to server stock.';
  });
  Future<bool> cancel(StockMovement movement) => _run((epoch) async {
    if (!movement.canCancel) {
      throw const ApiException(
        'Retry this transaction to confirm its server outcome before cancelling.',
      );
    }
    final next = movements
        .map(
          (m) =>
              m.clientId == movement.clientId ? m.copyWith(cancelled: true) : m,
        )
        .toList();
    await _commit(master, next, epoch);
    message = 'Transaction cancelled locally.';
  });
  MasterData? _apply(StockMovement m, MovementReceipt receipt) {
    if (master == null) return null;
    return MasterData(
      downloadedAt: master!.downloadedAt,
      items: master!.items.map((item) {
        if (item.id != m.itemId || item.version > receipt.version) return item;
        return InventoryItem(
          id: item.id,
          version: receipt.version,
          updatedAt: receipt.uploadedAt,
          name: item.name,
          sku: item.sku,
          category: item.category,
          quantity: receipt.after,
          reorderLevel: item.reorderLevel,
          priceCents: item.priceCents,
          notes: item.notes,
        );
      }).toList(),
    );
  }

  Future<bool> uploadAll() => _run((epoch) async {
    var uploaded = 0;
    for (var i = 0; i < movements.length; i++) {
      _check(epoch);
      if (!movements[i].pending) continue;
      // Save the original ID before sending. A retry always has the same payload.
      var current = movements[i].copyWith(attempted: true, rejected: false);
      var next = [...movements];
      next[i] = current;
      await _commit(master, next, epoch);
      try {
        final receipt = await repository.uploadMovement(current);
        _check(epoch);
        next = [...movements];
        next[i] = current.copyWith(receipt: receipt);
        await _commit(_apply(current, receipt), next, epoch);
        uploaded++;
      } catch (e) {
        _check(epoch);
        final rejected =
            e is ApiException && [400, 404, 409].contains(e.status);
        current = current.copyWith(
          rejected: rejected,
          error: e is ApiException
              ? e.message
              : 'Outcome unconfirmed. Retry the same transaction.',
        );
        next = [...movements];
        next[i] = current;
        await _commit(master, next, epoch);
        rethrow; // Stop in order; later rows may depend on this item's quantity.
      }
    }
    message = '$uploaded transactions uploaded and confirmed.';
  });
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    store.close();
    super.dispose();
  }
}
