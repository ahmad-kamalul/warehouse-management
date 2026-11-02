import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../domain/models.dart';
import '../warehouse_controller.dart';

class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, required this.controller, this.item});
  final WarehouseController controller;
  final InventoryItem? item;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final _form = GlobalKey<FormState>();
  final _inputs = <String, TextEditingController>{};
  InventoryItem? _original;
  bool _busy = false, _dirty = false, _conflict = false;
  String? _error;
  Map<String, String> _fields = {};
  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'sku',
      'category',
      'quantity',
      'reorderLevel',
      'price',
      'notes',
    ]) {
      _inputs[key] = TextEditingController();
    }
    _fill(widget.item);
  }

  void _fill(InventoryItem? item) {
    _original = item;
    final values = {
      'name': item?.name ?? '',
      'sku': item?.sku ?? '',
      'category': item?.category ?? '',
      'quantity': '${item?.quantity ?? 0}',
      'reorderLevel': '${item?.reorderLevel ?? 5}',
      'price': decimalPrice(item?.priceCents ?? 0),
      'notes': item?.notes ?? '',
    };
    for (final entry in values.entries) {
      _inputs[entry.key]!.text = entry.value;
    }
    _dirty = false;
  }

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _leave() async {
    if (_busy) return;
    if (!_dirty ||
        await _confirm(
          'Discard changes?',
          'Your unsaved changes will be lost.',
          'Discard',
        )) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _handleError(Object e) {
    setState(() {
      _error = e is ApiException
          ? e.message
          : 'Unable to complete the request. Please retry.';
      _fields = e is ApiException ? e.fields : {};
      _conflict = e is ApiException && e.status == 409 && _original != null;
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _fields = {};
      _error = null;
      _conflict = false;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.controller.save(
        ItemDraft(
          name: _inputs['name']!.text,
          sku: _inputs['sku']!.text,
          category: _inputs['category']!.text,
          quantity: int.parse(_inputs['quantity']!.text.trim()),
          reorderLevel: int.parse(_inputs['reorderLevel']!.text.trim()),
          priceCents: parseCents(_inputs['price']!.text.trim()),
          notes: _inputs['notes']!.text,
        ),
        original: _original,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
      });
      Navigator.pop(
        context,
        _original == null ? 'Item created.' : 'Item updated.',
      );
    } catch (e) {
      if (mounted) _handleError(e);
    }
  }

  Future<void> _reload() async {
    if (!await _confirm(
      'Reload latest item?',
      'This replaces your unsaved changes with the server version.',
      'Reload',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final item = await widget.controller.reloadItem(_original!.id);
      if (!mounted) return;
      setState(() {
        _fill(item);
        _error = null;
        _fields = {};
        _conflict = false;
        _busy = false;
      });
    } catch (e) {
      if (mounted) _handleError(e);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm(
      'Delete item?',
      'Permanently delete ${_original!.name}? This cannot be undone.',
      'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.delete(_original!.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
      });
      Navigator.pop(context, 'Item deleted.');
    } catch (e) {
      if (mounted) _handleError(e);
    }
  }

  Widget _field(
    String key,
    String label,
    String? Function(String?) validator, {
    TextInputType? keyboard,
    int? max,
    int lines = 1,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: _inputs[key],
      enabled: !_busy,
      validator: validator,
      onChanged: (_) {
        if (!_dirty) setState(() => _dirty = true);
      },
      keyboardType: keyboard,
      maxLength: max,
      maxLines: lines,
      textCapitalization: key == 'name' || key == 'category'
          ? TextCapitalization.words
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: _fields[key],
        counterText: max == null ? null : '',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_original == null ? 'Add item' : 'Item details'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _original == null
                        ? 'Make room for something new.'
                        : _original!.sku,
                    style: const TextStyle(
                      color: teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _original == null ? 'New inventory item' : _original!.name,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _original == null
                        ? 'Add the details your team needs.'
                        : 'Updated ${_original!.updatedAt.toLocal().toString().split('.').first} · Version ${_original!.version}',
                    style: const TextStyle(color: Color(0xFF61716F)),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Notice(
                        _error!,
                        error: true,
                        action: _conflict
                            ? TextButton(
                                onPressed: _busy ? null : _reload,
                                child: const Text('Reload latest item'),
                              )
                            : null,
                      ),
                    ),
                  _field(
                    'name',
                    'Item name',
                    (v) => Validators.requiredText(v, 120),
                    max: 120,
                  ),
                  _field(
                    'sku',
                    'SKU',
                    Validators.sku,
                    max: 40,
                    helper: 'Unique within your inventory.',
                  ),
                  _field(
                    'category',
                    'Category',
                    (v) => Validators.requiredText(v, 80),
                    max: 80,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text(
                      'STOCK & PRICING',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _field(
                    'quantity',
                    'Quantity on hand',
                    Validators.wholeNumber,
                    keyboard: TextInputType.number,
                  ),
                  _field(
                    'reorderLevel',
                    'Reorder level',
                    Validators.wholeNumber,
                    keyboard: TextInputType.number,
                    helper:
                        'Low stock when quantity is at or below this level.',
                  ),
                  _field(
                    'price',
                    'Unit price (MYR)',
                    Validators.price,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _field(
                    'notes',
                    'Notes (optional)',
                    (v) => (v?.length ?? 0) > 2000
                        ? 'Use at most 2000 characters.'
                        : null,
                    max: 2000,
                    lines: 4,
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Working…' : 'Save item'),
                  ),
                  if (_original != null) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete item'),
                    ),
                  ],
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
