import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'data/api_warehouse_repository.dart';
import 'data/demo_warehouse_repository.dart';
import 'features/warehouse_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const demo = bool.fromEnvironment('DEMO_MODE');
  runApp(
    WarehouseApp(
      controller: WarehouseController(
        demo ? DemoWarehouseRepository() : ApiWarehouseRepository(ApiClient()),
      ),
    ),
  );
}
