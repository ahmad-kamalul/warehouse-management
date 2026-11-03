import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_mobile/app.dart';
import 'package:warehouse_mobile/data/demo_warehouse_repository.dart';
import 'package:warehouse_mobile/features/warehouse_controller.dart';

void main() {
  setUpAll(() async {
    // Use SDK fonts so visual checks show readable text instead of Ahem blocks.
    final configFile = File('.dart_tool/package_config.json');
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'flutter');
    final root = Directory.fromUri(
      configFile.absolute.uri.resolve(flutter['rootUri'] as String),
    ).uri.resolve('../../');
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File.fromUri(
          root.resolve('bin/cache/artifacts/material_fonts/${entry.value}'),
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
    }
  });
  Future<void> openDemo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      WarehouseApp(controller: WarehouseController(DemoWarehouseRepository())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore demo workspace'));
    await tester.pumpAndSettle();
  }

  testWidgets('phone inventory renders and low-stock filter works', (
    tester,
  ) async {
    await openDemo(tester);
    expect(find.text('Inventory, in view.'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/inventory.png'),
      skip: !Platform.isWindows,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('create, search, open and delete an inventory item', (
    tester,
  ) async {
    await openDemo(tester);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String text) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    await fill('Item name', 'Test carton');
    await fill('SKU', 'TEST-BOX');
    await fill('Category', 'Packaging');
    final save = find.text('Save item');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Item created.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'TEST-BOX');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Test carton'));
    await tester.tap(find.text('Test carton'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete item'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Delete item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Item deleted.'), findsOneWidget);
    expect(find.text('No items found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'warehouse operations downloads, scans with keyboard and uploads goods in',
    (tester) async {
      await openDemo(tester);
      final controller = tester
          .widget<WarehouseApp>(find.byType(WarehouseApp))
          .controller;
      await tester.tap(find.byTooltip('Warehouse operations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download master'));
      await tester.pumpAndSettle();
      expect(find.textContaining('8 master items downloaded'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Goods in'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Goods in'));
      await tester.pumpAndSettle();
      final sku = find.widgetWithText(TextField, 'Scan or enter SKU');
      await tester.ensureVisible(sku);
      await tester.enterText(sku, 'PPE-001');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      // A second hardware scan of the same SKU adds one unit.
      await tester.enterText(sku, 'PPE-001');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final quantity = find.widgetWithText(TextFormField, 'Movement quantity');
      expect(tester.widget<TextFormField>(quantity).controller!.text, '2');
      final reference = find.widgetWithText(
        TextFormField,
        'Document / count reference',
      );
      await tester.ensureVisible(reference);
      await tester.enterText(reference, 'GRN-001');
      final save = find.text('Save to transaction queue');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(controller.operations.pendingCount, 1);
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Transactions (1)'),
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Transactions (1)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Upload inventory transactions'));
      await tester.tap(find.text('Upload inventory transactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload').last);
      await tester.pumpAndSettle();
      expect(controller.operations.pendingCount, 0);
      expect((await controller.repository.get('0')).quantity, 126);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsaved changes require confirmation before leaving', (
    tester,
  ) async {
    await openDemo(tester);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Item name'),
      'Unsaved',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory, in view.'), findsOneWidget);
  });
}
