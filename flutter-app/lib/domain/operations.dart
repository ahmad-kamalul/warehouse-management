import 'dart:math';

import 'models.dart';

enum MovementType {
  stockCount('STOCK_COUNT', 'Stock count'),
  goodsIn('GOODS_IN', 'Goods in'),
  goodsOut('GOODS_OUT', 'Goods out');

  const MovementType(this.apiValue, this.label);
  final String apiValue, label;
  static MovementType parse(String value) =>
      values.singleWhere((e) => e.apiValue == value);
}

String newTransactionId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class MasterData {
  const MasterData({required this.downloadedAt, required this.items});
  final DateTime downloadedAt;
  final List<InventoryItem> items;
  Map<String, Object?> toJson() => {
    'downloadedAt': downloadedAt.toIso8601String(),
    'items': items.map((e) => e.toStoredJson()).toList(),
  };
  factory MasterData.fromJson(Map<String, dynamic> json) => MasterData(
    downloadedAt: DateTime.parse(json['downloadedAt'] as String),
    items: (json['items'] as List)
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class MovementReceipt {
  const MovementReceipt({
    required this.id,
    required this.before,
    required this.after,
    required this.version,
    required this.uploadedAt,
  });
  final String id;
  final int before, after, version;
  final DateTime uploadedAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'beforeQuantity': before,
    'afterQuantity': after,
    'appliedVersion': version,
    'uploadedAt': uploadedAt.toIso8601String(),
  };
  factory MovementReceipt.fromJson(Map<String, dynamic> json) =>
      MovementReceipt(
        id: json['id'] as String,
        before: json['beforeQuantity'] as int,
        after: json['afterQuantity'] as int,
        version: json['appliedVersion'] as int,
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      );
}

class StockMovement {
  const StockMovement({
    required this.clientId,
    required this.itemId,
    required this.sku,
    required this.type,
    required this.quantity,
    required this.expectedVersion,
    required this.reference,
    required this.notes,
    required this.createdAt,
    this.attempted = false,
    this.rejected = false,
    this.error,
    this.receipt,
    this.cancelled = false,
  });
  final String clientId, itemId, sku, reference, notes;
  final MovementType type;
  final int quantity, expectedVersion;
  final DateTime createdAt;
  final bool attempted, rejected, cancelled;
  final String? error;
  final MovementReceipt? receipt;
  bool get pending => receipt == null && !cancelled;
  bool get canCancel => pending && (!attempted || rejected);
  String get status => cancelled
      ? 'Cancelled'
      : receipt != null
      ? 'Uploaded'
      : rejected
      ? 'Needs attention'
      : attempted
      ? 'Awaiting confirmation'
      : 'Queued';
  StockMovement copyWith({
    bool? attempted,
    bool? rejected,
    bool? cancelled,
    String? error,
    MovementReceipt? receipt,
  }) => StockMovement(
    clientId: clientId,
    itemId: itemId,
    sku: sku,
    type: type,
    quantity: quantity,
    expectedVersion: expectedVersion,
    reference: reference,
    notes: notes,
    createdAt: createdAt,
    attempted: attempted ?? this.attempted,
    rejected: rejected ?? this.rejected,
    cancelled: cancelled ?? this.cancelled,
    error: error,
    receipt: receipt ?? this.receipt,
  );
  Map<String, Object?> toRequest() => {
    'clientId': clientId,
    'itemId': itemId,
    'type': type.apiValue,
    'quantity': quantity,
    'expectedVersion': type == MovementType.stockCount ? expectedVersion : null,
    'reference': reference,
    'notes': notes,
  };
  Map<String, Object?> toJson() => {
    ...toRequest(),
    'sku': sku,
    'expectedVersion': expectedVersion,
    'createdAt': createdAt.toIso8601String(),
    'attempted': attempted,
    'rejected': rejected,
    'cancelled': cancelled,
    'error': error,
    'receipt': receipt?.toJson(),
  };
  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    clientId: json['clientId'] as String,
    itemId: json['itemId'] as String,
    sku: json['sku'] as String,
    type: MovementType.parse(json['type'] as String),
    quantity: json['quantity'] as int,
    expectedVersion: json['expectedVersion'] as int,
    reference: json['reference'] as String,
    notes: json['notes'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    attempted: json['attempted'] as bool,
    rejected: json['rejected'] as bool,
    cancelled: json['cancelled'] as bool,
    error: json['error'] as String?,
    receipt: json['receipt'] == null
        ? null
        : MovementReceipt.fromJson(json['receipt'] as Map<String, dynamic>),
  );
}
