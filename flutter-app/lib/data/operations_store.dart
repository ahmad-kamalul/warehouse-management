import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

abstract class OperationsStore {
  Future<String?> read(String scope);
  Future<void> write(String scope, String value);
  Future<void> close();
}

class MemoryOperationsStore implements OperationsStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String scope) async => _values[scope];
  @override
  Future<void> write(String scope, String value) async {
    _values[scope] = value;
  }

  @override
  Future<void> close() async {}
}

/// App-private SQLite. Each committed snapshot includes both master and outbox.
class SqliteOperationsStore implements OperationsStore {
  Future<Database>? _opening;
  Future<Database> get _database => _opening ??= _open();
  Future<Database> _open() async => openDatabase(
    path.join(await getDatabasesPath(), 'warehouse_operations.db'),
    version: 1,
    onCreate: (db, _) => db.execute(
      'CREATE TABLE workspaces (scope TEXT PRIMARY KEY, data TEXT NOT NULL)',
    ),
  );
  @override
  Future<String?> read(String scope) async {
    final rows = await (await _database).query(
      'workspaces',
      where: 'scope = ?',
      whereArgs: [scope],
    );
    return rows.isEmpty ? null : rows.first['data'] as String;
  }

  @override
  Future<void> write(String scope, String value) async {
    await (await _database).transaction(
      (txn) => txn.insert('workspaces', {
        'scope': scope,
        'data': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  @override
  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
  }
}
