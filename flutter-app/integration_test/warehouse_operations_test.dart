import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:warehouse_mobile/app.dart';
import 'package:warehouse_mobile/core/api_client.dart';
import 'package:warehouse_mobile/data/api_warehouse_repository.dart';
import 'package:warehouse_mobile/data/operations_store.dart';
import 'package:warehouse_mobile/domain/models.dart';
import 'package:warehouse_mobile/domain/operations.dart';
import 'package:warehouse_mobile/features/warehouse_controller.dart';

import 'fixtures/sku_qr.dart';

const baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8081/api',
);
const account = String.fromEnvironment(
  'E2E_ACCOUNT',
  defaultValue: 'emulator.operator@example.test',
);
const password = 'EmulatorTestOnly123!';
const phase = String.fromEnvironment('E2E_PHASE', defaultValue: 'workflows');
const networkControl = bool.fromEnvironment('E2E_NETWORK_CONTROL');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android warehouse operations ($phase)', (tester) async {
    if (phase == 'decoder') {
      final image = File('${await getDatabasesPath()}/e2e-sku-qr.png');
      await image.parent.create(recursive: true);
      await image.writeAsBytes(base64Decode(skuQrPngBase64));
      final decoder = MobileScannerController(autoStart: false);
      final decoded = await decoder.analyzeImage(
        image.path,
        formats: [BarcodeFormat.qrCode],
      );
      expect(
        decoded?.barcodes.any((barcode) => barcode.rawValue == 'EMU-BOX'),
        isTrue,
        reason: 'Real Android ML Kit must decode the SKU QR fixture',
      );
      await decoder.dispose();
      await image.delete();
      binding.reportData = {'phase': phase, 'decodedSku': 'EMU-BOX'};
      return;
    }
    final fixture = ApiWarehouseRepository(ApiClient(baseUrl: baseUrl));
    if (phase == 'workflows') {
      await fixture.authenticate(
        email: account,
        password: password,
        name: 'Emulator Operator',
      );
      await fixture.save(
        const ItemDraft(
          name: 'Emulator packing box',
          sku: 'EMU-BOX',
          category: 'Emulator QA',
          quantity: 10,
          reorderLevel: 3,
          priceCents: 250,
          notes: 'Isolated emulator fixture',
        ),
      );
      await fixture.save(
        const ItemDraft(
          name: 'Emulator empty bin',
          sku: 'EMU-ZERO',
          category: 'Emulator QA',
          quantity: 2,
          reorderLevel: 3,
          priceCents: 500,
          notes: 'Isolated emulator fixture',
        ),
      );
    } else {
      await fixture.authenticate(email: account, password: password);
    }
    final controller = WarehouseController(
      ApiWarehouseRepository(ApiClient(baseUrl: baseUrl)),
      operationsStore: SqliteOperationsStore(),
    );
    await tester.pumpWidget(WarehouseApp(controller: controller));
    Future<void> settle() async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 45),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      // Offscreen progress indicators schedule no frames, so also wait for
      // real HTTP and native SQLite work rather than just frame settlement.
      while (controller.operations.busy ||
          controller.loading ||
          controller.authenticating) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Native operation did not finish');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> reveal(Finder finder, {bool up = false}) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          up ? -350 : 350,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 35,
        );
      } else {
        await tester.ensureVisible(finder);
      }
      await settle();
    }

    Future<void> tapText(String text) async {
      final finder = find.text(text);
      await reveal(finder);
      await tester.tap(finder);
      await settle();
    }

    Future<void> fill(String label, String value) async {
      final finder = find.widgetWithText(TextFormField, label);
      await reveal(finder);
      await tester.showKeyboard(finder);
      await settle();
      await tester.enterText(finder, value);
      await settle();
    }

    Future<void> login(String email) async {
      await fill('Email address', email);
      await fill('Password', password);
      await tapText('Sign in');
      expect(find.text('Inventory, in view.'), findsOneWidget);
    }

    Future<void> openOperations() async {
      await tester.tap(find.byTooltip('Warehouse operations'));
      await settle();
    }

    Future<void> mode(String label) async {
      final finder = find.widgetWithText(ChoiceChip, label);
      await reveal(finder, up: true);
      await tester.tap(finder);
      await settle();
      expect(
        tester.widget<ChoiceChip>(finder).selected,
        isTrue,
        reason: 'Task selection must be active: $label',
      );
    }

    Future<void> lookup(String sku) async {
      final finder = find.widgetWithText(TextField, 'Scan or enter SKU');
      await reveal(finder);
      await tester.showKeyboard(finder);
      await settle();
      await tester.enterText(finder, sku);
      await settle();
      expect(tester.widget<TextField>(finder).controller!.text, sku);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle();
    }

    Future<void> record(
      MovementType type,
      String sku,
      int quantity,
      String reference,
    ) async {
      await mode(type.label);
      await lookup(sku);
      // ignore: avoid_print
      print(
        'E2E_ENTRY ${type.apiValue}: ${find.byType(TextField).evaluate().map((element) => (element.widget as TextField).decoration?.labelText).toList()}',
      );
      if (networkControl && controller.operations.movements.isEmpty) {
        // ignore: avoid_print
        print('E2E_FORM_READY');
        final gate = File('${await getDatabasesPath()}/e2e-form');
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!await gate.exists() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (await gate.exists()) await gate.delete();
      }
      await fill(
        type == MovementType.stockCount
            ? 'Actual counted quantity'
            : 'Movement quantity',
        '$quantity',
      );
      await fill('Document / count reference', reference);
      await tapText('Save to transaction queue');
      await tapText('Add to queue');
    }

    Future<void> queueScreen() =>
        mode('Transactions (${controller.operations.pendingCount})');
    Future<void> upload() async {
      await queueScreen();
      await tapText('Upload inventory transactions');
      await tapText('Upload');
    }

    Future<InventoryItem> remote(String sku) async {
      final rows = await fixture.list(InventoryQuery(search: sku));
      return rows.items.singleWhere((item) => item.sku == sku);
    }

    Future<void> waitForHost(String marker) async {
      final file = File('${await getDatabasesPath()}/$marker');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!await file.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Host handshake timed out: $marker');
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await file.delete();
    }

    Future<void> exitOperations() async {
      await tester.tap(find.byTooltip('Back').first);
      await settle();
      if (find.text('Discard unsaved entry?').evaluate().isNotEmpty) {
        await tapText('Discard');
      }
    }

    await login(account);
    await openOperations();
    final op = controller.operations;
    if (phase == 'resume') {
      expect(
        op.master,
        isNotNull,
        reason: 'Native SQLite master must survive a process restart',
      );
      expect(op.pendingCount, 1);
      final saved = op.movements.singleWhere((m) => m.pending);
      expect(saved.reference, 'PROCESS-RESTART');
      const expectedId = String.fromEnvironment('E2E_EXPECT_ID');
      if (expectedId.isNotEmpty) expect(saved.clientId, expectedId);
      final before = (await remote('EMU-BOX')).quantity;
      await upload();
      expect(op.pendingCount, 0);
      expect((await remote('EMU-BOX')).quantity, before + 2);
      expect(op.movements.last.receipt, isNotNull);
      final journal = await fixture.client.request(
        'GET',
        '/operations/transactions',
      ) as List;
      expect(
        journal.length,
        6,
        reason: 'Six physical movements, including retries, must yield exactly six server receipts',
      );
      binding.reportData = {
        'phase': phase,
        'restoredTransactionId': saved.clientId,
        'serverQuantity': (await remote('EMU-BOX')).quantity,
      };
      fixture.dispose();
      return;
    }

    await tapText('Download master');
    expect(op.master!.items.length, 2);
    await lookup('EMU-BOX');
    expect(find.text('Last known server stock: 10 units'), findsOneWidget);
    await lookup('NO-SUCH-SKU');
    expect(
      find.textContaining('SKU not found in the downloaded master'),
      findsOneWidget,
    );
    await lookup('EMU-BOX');

    // Exercise the actual Android camera plugin, permissions and preview pipeline.
    if (networkControl) {
      // ignore: avoid_print
      print('E2E_CAMERA_PERMISSION_READY');
      await waitForHost('e2e-camera-permission');
    }
    await tapText('Scan with camera');
    final cameraDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(Texture).evaluate().isEmpty &&
        DateTime.now().isBefore(cameraDeadline)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(
      find.byType(Texture),
      findsWidgets,
      reason: 'Android camera must produce a preview texture',
    );
    expect(find.text('Use manual entry'), findsNothing);
    await tester.tap(find.byTooltip('Back').first);
    await settle();

    await record(MovementType.stockCount, 'EMU-BOX', 8, 'COUNT-001');
    await record(MovementType.goodsIn, 'EMU-BOX', 5, 'GRN-001');
    await record(MovementType.goodsOut, 'EMU-BOX', 3, 'GDN-001');
    expect(op.pendingCount, 3);
    expect(
      (await remote('EMU-BOX')).quantity,
      10,
      reason: 'Queue must not change server before upload',
    );
    await upload();
    expect(op.pendingCount, 0);
    expect((await remote('EMU-BOX')).quantity, 10);
    expect(op.movements.map((m) => m.receipt!.after).toList(), [8, 13, 10]);

    // A saved count must reject a later server change, leaving dependent rows unsent.
    await record(MovementType.stockCount, 'EMU-BOX', 9, 'STALE-COUNT');
    final changed = await remote('EMU-BOX');
    await fixture.save(
      ItemDraft(
        name: changed.name,
        sku: changed.sku,
        category: changed.category,
        quantity: 11,
        reorderLevel: changed.reorderLevel,
        priceCents: changed.priceCents,
        notes: changed.notes,
      ),
      original: changed,
    );
    await upload();
    final stale = op.movements.last;
    expect(stale.rejected, isTrue);
    expect(stale.error, contains('Stock changed'));
    expect((await remote('EMU-BOX')).quantity, 11);
    // Cancellation uses the real UI, preserving the rejected entry in history.
    final cancel = find.text('Cancel transaction');
    await reveal(cancel);
    await tester.tap(cancel);
    await settle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel transaction'));
    await settle();
    expect(op.pendingCount, 0);
    await reveal(find.text('Download master'), up: true);
    await tapText('Download master');

    await record(MovementType.stockCount, 'EMU-ZERO', 0, 'ZERO-COUNT');
    await upload();
    expect((await remote('EMU-ZERO')).quantity, 0);

    // Idempotent receipt replay against the live API must not apply stock twice.
    final sent = op.movements.first;
    final replay = await fixture.uploadMovement(sent);
    expect(replay.id, sent.receipt!.id);
    expect((await remote('EMU-BOX')).quantity, 11);

    if (networkControl) {
      // The host disables emulator Wi-Fi/data before creating the native file marker.
      // ignore: avoid_print
      print('E2E_OFFLINE_READY');
      await waitForHost('e2e-offline');
      expect(
        await op.download(),
        isFalse,
        reason: 'Real network must be unavailable',
      );
      expect(op.master, isNotNull);
      await record(MovementType.goodsIn, 'EMU-BOX', 1, 'OFFLINE-RECEIPT');
      expect(op.pendingCount, 1);
      await upload();
      expect(op.pendingCount, 1);
      expect(op.movements.last.attempted, isTrue);
      expect(op.movements.last.canCancel, isFalse);
      // ignore: avoid_print
      print('E2E_ONLINE_READY');
      await waitForHost('e2e-online');
      await upload();
      expect(op.pendingCount, 0);
      expect((await remote('EMU-BOX')).quantity, 12);
    }

    // Native SQLite must restore the queue after signing out and signing in.
    await record(MovementType.goodsIn, 'EMU-BOX', 2, 'PROCESS-RESTART');
    final restartId = op.movements.last.clientId;
    await exitOperations();
    await tester.tap(find.byTooltip('Account and sign out'));
    await settle();
    await tapText('Sign out');
    await login(account);
    await openOperations();
    expect(op.pendingCount, 1);
    expect(op.movements.last.clientId, restartId);
    // Leave one unuploaded entry for the separate process-restart invocation.
    // ignore: avoid_print
    print('E2E_RESTART_CLIENT_ID=$restartId');
    binding.reportData = {
      'phase': phase,
      'pendingTransactionId': restartId,
      'confirmedReceipts': op.movements.where((m) => m.receipt != null).length,
      'cameraPreview': true,
      'nativeSqliteRestore': true,
    };
    expect(tester.takeException(), isNull);
    fixture.dispose();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
