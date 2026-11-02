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
