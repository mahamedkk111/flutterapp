import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pos_data.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id   INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER,
            type        TEXT,
            amount      REAL,
            note        TEXT,
            dt          TEXT,
            FOREIGN KEY(customer_id) REFERENCES customers(id)
          )
        ''');
      },
    );
  }

  // ── Customers ──────────────────────────────────────────────────────────────

  static Future<List<String>> getCustomers() async {
    final d = await db;
    final rows = await d.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<bool> addCustomer(String name) async {
    try {
      final d = await db;
      await d.insert('customers', {'name': name});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteCustomer(String name) async {
    final d = await db;
    final rows = await d.query('customers', where: 'name=?', whereArgs: [name]);
    if (rows.isEmpty) return;
    final id = rows.first['id'] as int;
    await d.delete('transactions', where: 'customer_id=?', whereArgs: [id]);
    await d.delete('customers', where: 'id=?', whereArgs: [id]);
  }

  static Future<bool> renameCustomer(String oldName, String newName) async {
    try {
      final d = await db;
      await d.update('customers', {'name': newName},
          where: 'name=?', whereArgs: [oldName]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Transactions ───────────────────────────────────────────────────────────

  static Future<void> addTransaction(
      String customerName, String type, double amount, String note) async {
    final d = await db;
    final rows = await d
        .query('customers', where: 'name=?', whereArgs: [customerName]);
    if (rows.isEmpty) return;
    final id = rows.first['id'] as int;
    final dt = DateTime.now().toIso8601String();
    await d.insert('transactions', {
      'customer_id': id,
      'type': type,
      'amount': amount,
      'note': note,
      'dt': dt,
    });
  }

  static Future<void> editTransaction(
      int transId, double amount, String note) async {
    final d = await db;
    await d.update(
      'transactions',
      {'amount': amount, 'note': note},
      where: 'id=?',
      whereArgs: [transId],
    );
  }

  static Future<void> deleteTransaction(int transId) async {
    final d = await db;
    await d.delete('transactions', where: 'id=?', whereArgs: [transId]);
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
    String customerName, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final d = await db;
    final rows = await d
        .query('customers', where: 'name=?', whereArgs: [customerName]);
    if (rows.isEmpty) return [];
    final cid = rows.first['id'] as int;

    String where = 'customer_id=?';
    List<dynamic> args = [cid];

    if (dateFrom != null) {
      where += ' AND dt >= ?';
      args.add(DateTime(dateFrom.year, dateFrom.month, dateFrom.day)
          .toIso8601String());
    }
    if (dateTo != null) {
      where += ' AND dt <= ?';
      args.add(DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59)
          .toIso8601String());
    }

    final txRows = await d.query(
      'transactions',
      where: where,
      whereArgs: args,
      orderBy: 'dt ASC, id ASC',
    );

    return txRows.map((r) {
      return {
        'id': r['id'],
        'type': r['type'],
        'amount': (r['amount'] as num).toDouble(),
        'note': r['note'] ?? '',
        'dt': DateTime.parse(r['dt'] as String),
      };
    }).toList();
  }

  static Future<double> getBalance(String customerName,
      {DateTime? dateFrom, DateTime? dateTo}) async {
    final txs = await getTransactions(customerName,
        dateFrom: dateFrom, dateTo: dateTo);
    double bal = 0;
    for (final t in txs) {
      bal += t['type'] == 'Deposit' ? t['amount'] : -t['amount'];
    }
    return bal;
  }

  static Future<List<MapEntry<String, double>>>
      getSortedCustomersByBalance() async {
    final customers = await getCustomers();
    final List<MapEntry<String, double>> entries = [];
    for (final name in customers) {
      final bal = await getBalance(name);
      entries.add(MapEntry(name, bal));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  static Future<double> getTotalBalance() async {
    final customers = await getCustomers();
    double total = 0;
    for (final name in customers) {
      total += await getBalance(name);
    }
    return total;
  }
}
