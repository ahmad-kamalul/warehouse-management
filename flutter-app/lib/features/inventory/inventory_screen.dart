import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../warehouse_controller.dart';
import 'item_editor.dart';
import '../operations/operations_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller});
  final WarehouseController controller;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  WarehouseController get c => widget.controller;
  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      c.load(c.query.copyWith(search: value.trim(), page: 0));
    });
  }

  Future<void> _open([InventoryItem? item]) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ItemEditor(controller: c, item: item),
      ),
    );
    if (mounted && result != null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result)));
    }
  }

  Future<void> _filters() async {
    _debounce?.cancel();
    final category = TextEditingController(text: c.query.category);
    var sort = c.query.sort;
    var ascending = c.query.ascending;
    final result = await showModalBottomSheet<InventoryQuery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Refine inventory',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: category,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    helperText: 'Exact category; leave blank for all.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sort,
                  decoration: const InputDecoration(labelText: 'Sort by'),
                  items: const [
                    DropdownMenuItem(
                      value: 'updatedAt',
                      child: Text('Last updated'),
                    ),
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                    DropdownMenuItem(value: 'sku', child: Text('SKU')),
                    DropdownMenuItem(
                      value: 'quantity',
                      child: Text('Quantity'),
                    ),
                    DropdownMenuItem(value: 'price', child: Text('Unit price')),
                  ],
                  onChanged: (value) => setSheetState(() => sort = value!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ascending order'),
                  value: ascending,
                  onChanged: (value) => setSheetState(() => ascending = value),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    c.query.copyWith(
                      category: category.text.trim(),
                      sort: sort,
                      ascending: ascending,
                      search: _search.text.trim(),
                      page: 0,
                    ),
                  ),
                  child: const Text('Apply filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Wait for the closing sheet animation before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    category.dispose();
    if (result != null && mounted) await c.load(result);
  }

  void _account() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.user!.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(c.user!.email),
              const SizedBox(height: 20),
              Notice(
                c.repository.isDemo
                    ? 'Demo mode · No server connection. Sample data resets on sign-out.'
                    : 'Your inventory belongs to your account. Sign in again after restarting the app or when your session expires.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  c.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = c.inventory;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.warehouse_outlined, color: teal),
            SizedBox(width: 10),
            Text('Warehouse', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Warehouse operations',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OperationsScreen(controller: c),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Account and sign out',
            onPressed: _account,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => c.load(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            c.repository.isDemo
                                ? 'DEMO WORKSPACE'
                                : 'YOUR WORKSPACE',
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                              color: teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Inventory, in view.',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Know what you have. Keep work moving.',
                            style: TextStyle(color: Color(0xFF61716F)),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: ink,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'MATCHING ITEMS',
                                        style: TextStyle(
                                          color: Color(0xFFB4D9CB),
                                          fontSize: 11,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        page == null ? '—' : '${page.total}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        c.query.lowStock
                                            ? 'At or below reorder level'
                                            : 'Across your current filters',
                                        style: const TextStyle(
                                          color: Color(0xFFCCDAD5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 54,
                                  color: Color(0xFF8FC7B3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _search,
                            onChanged: _searchChanged,
                            maxLength: 100,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (value) {
                              _debounce?.cancel();
                              c.load(
                                c.query.copyWith(search: value.trim(), page: 0),
                              );
                            },
                            decoration: InputDecoration(
                              hintText: 'Search name, SKU or category',
                              counterText: '',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _debounce?.cancel();
                                  _search.clear();
                                  c.load(c.query.copyWith(search: '', page: 0));
                                },
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                label: const Text('All stock'),
                                selected: !c.query.lowStock,
                                onSelected: (_) {
                                  _debounce?.cancel();
                                  c.load(
                                    c.query.copyWith(
                                      search: _search.text.trim(),
                                      lowStock: false,
                                      page: 0,
                                    ),
                                  );
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Low stock'),
                                selected: c.query.lowStock,
                                onSelected: (_) {
                                  _debounce?.cancel();
                                  c.load(
                                    c.query.copyWith(
                                      search: _search.text.trim(),
                                      lowStock: true,
                                      page: 0,
                                    ),
                                  );
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.tune, size: 18),
                                label: const Text('Filters'),
                                onPressed: _filters,
                              ),
                              if (c.query.category.isNotEmpty)
                                InputChip(
                                  label: Text(c.query.category),
                                  onDeleted: () => c.load(
                                    c.query.copyWith(category: '', page: 0),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Stock list',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh inventory',
                                onPressed: c.loading ? null : () => c.load(),
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                          if (c.loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 60),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (c.error != null)
                            Notice(
                              c.error!,
                              error: true,
                              action: TextButton(
                                onPressed: () => c.load(),
                                child: const Text('Try again'),
                              ),
                            ),
                          if (page != null && page.items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 48,
                                    color: teal,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No items found',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Try another search or add your first item.',
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _debounce?.cancel();
                                      _search.clear();
                                      c.load(const InventoryQuery());
                                    },
                                    child: const Text(
                                      'Reset search and filters',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (page != null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _ItemCard(
                          item: page.items[index],
                          onTap: () => _open(page.items[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              if (page != null && page.pages > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: c.query.page == 0
                              ? null
                              : () => c.load(
                                  c.query.copyWith(page: c.query.page - 1),
                                ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page ${c.query.page + 1} of ${page.pages}'),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: c.query.page + 1 >= page.pages
                              ? null
                              : () => c.load(
                                  c.query.copyWith(page: c.query.page + 1),
                                ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});
  final InventoryItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF3F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: teal,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.sku} · ${item.category}',
                        style: const TextStyle(
                          color: Color(0xFF61716F),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF72847B)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${item.quantity} units',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${money(item.priceCents)} / unit',
                  style: const TextStyle(fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item.lowStock
                        ? const Color(0xFFFFECDC)
                        : const Color(0xFFE4F2EC),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    item.quantity == 0
                        ? 'Out of stock'
                        : item.lowStock
                        ? 'Low stock'
                        : 'In stock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: item.lowStock
                          ? const Color(0xFF904517)
                          : const Color(0xFF25664C),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
