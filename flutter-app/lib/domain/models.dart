/// Money uses integer minor units to avoid floating-point arithmetic.
int parseCents(Object value) {
  final parts = value.toString().split('.');
  return int.parse(parts[0]) * 100 +
      int.parse(
        (parts.length == 1 ? '' : parts[1]).padRight(2, '0').substring(0, 2),
      );
}

String decimalPrice(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
String money(int cents) => 'RM ${decimalPrice(cents)}';

class WarehouseUser {
  const WarehouseUser({required this.name, required this.email, this.id = ''});
  final String id;
  final String name;
  final String email;
  factory WarehouseUser.fromJson(Map<String, dynamic> json) => WarehouseUser(
    id: json['id'] as String? ?? '',
    name: json['name'] as String,
    email: json['email'] as String,
  );
}

class ItemDraft {
  const ItemDraft({
    required this.name,
    required this.sku,
    required this.category,
    required this.quantity,
    required this.reorderLevel,
    required this.priceCents,
    required this.notes,
  });
  final String name, sku, category, notes;
  final int quantity, reorderLevel, priceCents;
  Map<String, Object?> toJson({int? version}) => {
    'name': name.trim(),
    'sku': sku.trim().toUpperCase(),
    'category': category.trim(),
    'quantity': quantity,
    'reorderLevel': reorderLevel,
    'price': decimalPrice(priceCents),
    'notes': notes.trim(),
    'version': ?version,
  };
}

class InventoryItem extends ItemDraft {
  const InventoryItem({
    required this.id,
    required this.version,
    required this.updatedAt,
    required super.name,
    required super.sku,
    required super.category,
    required super.quantity,
    required super.reorderLevel,
    required super.priceCents,
    required super.notes,
  });
  final String id;
  final int version;
  final DateTime updatedAt;
  bool get lowStock => quantity <= reorderLevel;
  Map<String, Object?> toStoredJson() => {
    ...toJson(version: version),
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
  };
  int get stockValueCents => quantity * priceCents;
  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as String,
    version: json['version'] as int,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    name: json['name'] as String,
    sku: json['sku'] as String,
    category: json['category'] as String,
    quantity: json['quantity'] as int,
    reorderLevel: json['reorderLevel'] as int,
    priceCents: parseCents(json['price']!),
    notes: json['notes'] as String? ?? '',
  );
}

class InventoryQuery {
  const InventoryQuery({
    this.search = '',
    this.category = '',
    this.lowStock = false,
    this.page = 0,
    this.sort = 'updatedAt',
    this.ascending = false,
  });
  final String search, category, sort;
  final bool lowStock, ascending;
  final int page;
  static const pageSize = 20;
  InventoryQuery copyWith({
    String? search,
    String? category,
    bool? lowStock,
    int? page,
    String? sort,
    bool? ascending,
  }) => InventoryQuery(
    search: search ?? this.search,
    category: category ?? this.category,
    lowStock: lowStock ?? this.lowStock,
    page: page ?? this.page,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
  );
  Map<String, String> toParams() => {
    'q': search,
    'category': category,
    'lowStock': '$lowStock',
    'page': '$page',
    'size': '$pageSize',
    'sortBy': sort,
    'direction': ascending ? 'asc' : 'desc',
  };
}

class InventoryPage {
  const InventoryPage({
    required this.items,
    required this.total,
    required this.pages,
  });
  final List<InventoryItem> items;
  final int total, pages;
  factory InventoryPage.fromJson(Map<String, dynamic> json) => InventoryPage(
    items: (json['content'] as List)
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    total: json['totalElements'] as int,
    pages: json['totalPages'] as int,
  );
}
