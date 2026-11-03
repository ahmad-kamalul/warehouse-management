import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../domain/models.dart';
import '../../domain/operations.dart';
import '../warehouse_controller.dart';
import 'operations_controller.dart';
import 'scan_screen.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key, required this.controller});
  final WarehouseController controller;
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  final _form = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _skuFocus = FocusNode();
  MovementType? _type;
  String? _selectedId, _lookupError;
  bool _showQueue = false, _dirty = false;
  OperationsController get op => widget.controller.operations;
  InventoryItem? get _item {
    for (final item in op.master?.items ?? <InventoryItem>[]) {
      if (item.id == _selectedId) return item;
    }
    return null;
  }

  @override
  void dispose() {
    _sku.dispose();
    _quantity.dispose();
    _reference.dispose();
    _notes.dispose();
    _skuFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
    if (op.busy) return;
    if (!_dirty ||
        await _confirm(
          'Discard unsaved entry?',
          'This entry has not been added to the queue. Saved queue entries remain on this device.',
          'Discard',
        )) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _changeMode(MovementType? type, {bool queue = false}) async {
    if (_dirty &&
        !await _confirm(
          'Discard unsaved entry?',
          'Switching tasks clears the current unsaved entry.',
          'Discard',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _type = type;
      _showQueue = queue;
      _selectedId = null;
      _lookupError = null;
      _sku.clear();
      _quantity.text = '1';
      _notes.clear();
      _dirty = false;
    });
  }

  Future<void> _acceptCode(String code) async {
    if (op.busy) return;
    final item = op.findSku(code);
    if (item == null) {
      setState(
        () => _lookupError = 'SKU not found in the downloaded master. Check the code or download master again.',
      );
      return;
    }
    if (_type != null &&
        _dirty &&
        _selectedId != item.id &&
        !await _confirm(
          'Switch item?',
          'The current quantity has not been queued. Discard it and select ${item.sku}?',
          'Switch',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_type != null && _selectedId == item.id) {
        final previous = int.tryParse(_quantity.text) ?? 0;
        if (previous < 2147483647) _quantity.text = '${previous + 1}';
      } else {
        _quantity.text = '1';
      }
      _selectedId = item.id;
      _sku.text = item.sku;
      _lookupError = null;
      if (_type != null) _dirty = true;
    });
    _skuFocus.requestFocus();
    _sku.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _sku.text.length,
    );
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code != null && mounted) await _acceptCode(code);
  }

  Future<void> _save() async {
    if (_item != null &&
        _sku.text.trim().toUpperCase() != _item!.sku.toUpperCase()) {
      setState(
        () => _lookupError = 'Confirm the entered SKU with Enter or the search button before saving.',
      );
      return;
    }
    if (!_form.currentState!.validate() || _item == null) return;
    final quantity = int.parse(_quantity.text.trim());
    if (!await _confirm(
      'Queue ${_type!.label.toLowerCase()}?',
      '${_item!.sku}: ${_type == MovementType.stockCount ? 'set counted quantity to' : 'record'} $quantity units. Server stock changes only after upload.',
      'Add to queue',
    )) {
      return;
    }
    final saved = await op.enqueue(
      item: _item!,
      type: _type!,
      quantity: quantity,
      reference: _reference.text,
      notes: _notes.text,
    );
    if (saved && mounted) {
      setState(() {
        _dirty = false;
        _selectedId = null;
        _sku.clear();
        _quantity.text = '1';
        _notes.clear();
      });
      _skuFocus.requestFocus();
    }
  }

  Future<void> _upload() async {
    if (!await _confirm(
      'Upload inventory transactions?',
      'Upload ${op.pendingCount} pending transactions in order. Confirmed transactions will update server stock. Upload stops at the first unresolved entry.',
      'Upload',
    )) {
      return;
    }
    await op.uploadAll();
    if (widget.controller.user != null) await widget.controller.load();
  }

  Widget _task(
    String title,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) => ChoiceChip(
    label: Text(title),
    avatar: Icon(icon, size: 17),
    selected: selected,
    onSelected: op.busy ? null : (_) => onTap(),
  );
  Widget _queue() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${op.pendingCount} pending transactions',
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Saved locally until confirmed by the server. Uploads use the same transaction ID on every retry.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: op.busy || op.pendingCount == 0 ? null : _upload,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Upload inventory transactions'),
      ),
      const SizedBox(height: 20),
      if (op.movements.isEmpty)
        const Notice(
          'No transactions yet. Record a stock count, goods in, or goods out to begin.',
        ),
      ...op.movements.reversed.map(
        (m) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m.type.label} · ${m.sku}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${m.quantity} units · ${m.status}'),
                  Text('Reference: ${m.reference}'),
                  Text(
                    'Saved: ${m.createdAt.toLocal().toString().split('.').first}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (m.receipt case final receipt?) ...[
                    const SizedBox(height: 8),
                    Text('Server stock: ${receipt.before} → ${receipt.after}'),
                    Text(
                      'Receipt: ${receipt.id}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                  if (m.error != null && m.pending)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Notice(m.error!, error: true),
                    ),
                  if (m.pending && !m.canCancel)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Outcome unconfirmed. Retry upload to reconcile; this entry cannot be cancelled yet.',
                      ),
                    ),
                  if (m.canCancel)
                    TextButton(
                      onPressed: op.busy
                          ? null
                          : () async {
                              if (await _confirm(
                                'Cancel queued transaction?',
                                'This entry will remain in local history as cancelled.',
                                'Cancel transaction',
                              )) {
                                await op.cancel(m);
                              }
                            },
                      child: const Text('Cancel transaction'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _entry() {
    final item = _item;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _type?.label ?? 'Check stock',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _type == MovementType.stockCount
                ? 'Count actual units, including zero. Scanning the same SKU again adds one unit.'
                : _type == MovementType.goodsIn
                ? 'Receive goods into stock. Use the supplier delivery or receipt reference.'
                : _type == MovementType.goodsOut
                ? 'Dispatch goods from stock. Use the delivery or issue reference.'
                : 'Look up an SKU in the downloaded master. Refresh from server when you need current stock.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _sku,
            focusNode: _skuFocus,
            enabled: !op.busy,
            // Keep the scanner input connection alive when a hardware scanner
            // sends Enter; Android's default completion first unfocuses it.
            onEditingComplete: () {},
            onSubmitted: _acceptCode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Scan or enter SKU',
              errorText: _lookupError,
              helperText: 'Hardware scanner: scan the SKU and send Enter.',
              suffixIcon: IconButton(
                tooltip: 'Find SKU',
                onPressed: op.busy ? null : () => _acceptCode(_sku.text),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: op.busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan with camera'),
          ),
          if (item != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${item.sku} · ${item.category}'),
                    const SizedBox(height: 12),
                    Text('Last known server stock: ${item.quantity} units'),
                    Text('With pending work: ${op.projected(item)} units'),
                    Text(
                      'Reorder level: ${item.reorderLevel} · ${money(item.priceCents)} / unit',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Downloaded data can become stale. The server validates stock and count versions on upload.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (_type != null) ...[
              const SizedBox(height: 18),
              TextFormField(
                controller: _quantity,
                enabled: !op.busy,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _dirty = true),
                validator: (value) =>
                    Validators.wholeNumber(value) ??
                    (_type != MovementType.stockCount &&
                            int.parse(value!.trim()) == 0
                        ? 'Enter at least one unit.'
                        : null),
                decoration: InputDecoration(
                  labelText: _type == MovementType.stockCount
                      ? 'Actual counted quantity'
                      : 'Movement quantity',
                ),
              ),
              const SizedBox(height: 16),
              if (_type == MovementType.stockCount &&
                  int.tryParse(_quantity.text.trim()) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Count variance: ${int.parse(_quantity.text.trim()) - item.quantity} units',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              TextFormField(
                controller: _reference,
                enabled: !op.busy,
                maxLength: 100,
                onChanged: (_) => setState(() => _dirty = true),
                validator: (v) => Validators.requiredText(v, 100),
                decoration: const InputDecoration(
                  labelText: 'Document / count reference',
                ),
              ),
              TextFormField(
                controller: _notes,
                enabled: !op.busy,
                maxLength: 2000,
                maxLines: 2,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: op.busy ? null : _save,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Save to transaction queue'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: op.busy ? null : () => op.download(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh stock from server'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: op,
    builder: (context, _) => PopScope(
      canPop: !op.busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Warehouse operations'),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: op.busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Item master',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            op.master == null
                                ? 'Download your item master before checking or recording stock.'
                                : '${op.master!.items.length} items · downloaded ${op.master!.downloadedAt.toLocal().toString().split('.').first}',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: op.busy || !op.ready || _dirty
                                ? null
                                : () => op.download(),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Download master'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (op.busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: LinearProgressIndicator(),
                    ),
                  if (op.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(op.error!, error: true),
                    ),
                  if (op.message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(op.message!),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _task(
                        'Check stock',
                        Icons.search,
                        _type == null && !_showQueue,
                        () => _changeMode(null),
                      ),
                      _task(
                        'Stock count',
                        Icons.fact_check_outlined,
                        _type == MovementType.stockCount && !_showQueue,
                        () => _changeMode(MovementType.stockCount),
                      ),
                      _task(
                        'Goods in',
                        Icons.move_to_inbox_outlined,
                        _type == MovementType.goodsIn && !_showQueue,
                        () => _changeMode(MovementType.goodsIn),
                      ),
                      _task(
                        'Goods out',
                        Icons.outbox_outlined,
                        _type == MovementType.goodsOut && !_showQueue,
                        () => _changeMode(MovementType.goodsOut),
                      ),
                      _task(
                        'Transactions (${op.pendingCount})',
                        Icons.cloud_upload_outlined,
                        _showQueue,
                        () => _changeMode(null, queue: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_showQueue)
                    _queue()
                  else if (op.master != null)
                    _entry()
                  else
                    const Notice(
                      'Your downloaded master and saved transactions are available offline during this session. Sign-in and uploads require a connection.',
                    ),
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
