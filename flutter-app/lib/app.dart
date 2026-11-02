import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/warehouse_controller.dart';

class WarehouseApp extends StatefulWidget {
  const WarehouseApp({super.key, required this.controller});
  final WarehouseController controller;
  @override
  State<WarehouseApp> createState() => _WarehouseAppState();
}

class _WarehouseAppState extends State<WarehouseApp> {
  final _navigator = GlobalKey<NavigatorState>();
  bool _signedIn = false;
  @override
  void initState() {
    super.initState();
    _signedIn = widget.controller.user != null;
    widget.controller.addListener(_onSession);
  }

  void _onSession() {
    final signedIn = widget.controller.user != null;
    if (_signedIn && !signedIn) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    _signedIn = signedIn;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSession);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Warehouse',
    debugShowCheckedModeBanner: false,
    theme: warehouseTheme(),
    navigatorKey: _navigator,
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => widget.controller.user == null
          ? AuthScreen(controller: widget.controller)
          : InventoryScreen(controller: widget.controller),
    ),
  );
}
