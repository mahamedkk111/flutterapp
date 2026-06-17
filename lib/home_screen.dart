import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';
import 'export_helper.dart';
import 'customer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MapEntry<String, double>> _customers = [];
  double _totalBalance = 0;
  String? _selected;
  String _search = '';
  bool _loading = true;

  final _addCtrl    = TextEditingController();
  final _amtCtrl    = TextEditingController();
  final _noteCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _fmt        = NumberFormat('#,##0.00');

  String _fmtAmt(double v) => _fmt.format(v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final customers = await DBHelper.getSortedCustomersByBalance();
    final total     = await DBHelper.getTotalBalance();
    setState(() {
      _customers    = customers;
      _totalBalance = total;
      _loading      = false;
      // keep selection valid
      if (_selected != null &&
          !customers.any((e) => e.key == _selected)) {
        _selected = null;
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  // ── Add customer ───────────────────────────────────────────────────────────

  Future<void> _addCustomer() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) { _snack('Enter a name'); return; }
    final ok = await DBHelper.addCustomer(name);
    if (ok) {
      _addCtrl.clear();
      _snack("'$name' added.");
      _load();
    } else {
      _snack("'$name' already exists.");
    }
  }

  // ── Transaction ────────────────────────────────────────────────────────────

  Future<void> _addTx(String type) async {
    if (_selected == null) { _snack('Tap a customer first'); return; }
    final amt = double.tryParse(_amtCtrl.text);
    if (amt == null || amt <= 0) { _snack('Enter a valid amount'); return; }
    await DBHelper.addTransaction(
        _selected!, type, amt, _noteCtrl.text.trim());
    _amtCtrl.clear();
    _noteCtrl.clear();
    _snack('$type ${_fmtAmt(amt)} added for $_selected');
    _load();
  }

  // ── Customer tap menu ──────────────────────────────────────────────────────

  void _openMenu(String name, double bal) {
    setState(() => _selected = name);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      Text(_fmtAmt(bal),
                          style: TextStyle(
                              color: bal >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ]),
              ),
              const Divider(color: Colors.white12),

              _menuItem(ctx, Icons.account_circle, Colors.blue,
                  'View Details', () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            CustomerScreen(customerName: name))).then((_) => _load());
              }),

              _menuItem(ctx, Icons.add_circle, Colors.green,
                  'C IN (Cash In)', () {
                Navigator.pop(ctx);
                _addTx('Deposit');
              }),

              _menuItem(ctx, Icons.remove_circle, Colors.orange,
                  'C OUT (Cash Out)', () {
                Navigator.pop(ctx);
                _addTx('Withdraw');
              }),

              _menuItem(ctx, Icons.picture_as_pdf, Colors.red,
                  'Export PDF Statement', () async {
                Navigator.pop(ctx);
                try {
                  final path = await exportCustomerPdf(name);
                  _snack('PDF saved: $path');
                } catch (e) { _snack('Error: $e'); }
              }),

              _menuItem(ctx, Icons.share, Colors.lightBlue,
                  'Share PDF Statement', () async {
                Navigator.pop(ctx);
                try {
                  final path = await exportCustomerPdf(name);
                  await shareFile(path);
                } catch (e) { _snack('Error: $e'); }
              }),

              _menuItem(ctx, Icons.table_chart, Colors.teal,
                  'Export CSV', () async {
                Navigator.pop(ctx);
                try {
                  final path = await exportCustomerCsv(name);
                  _snack('CSV saved: $path');
                } catch (e) { _snack('Error: $e'); }
              }),

              _menuItem(ctx, Icons.grid_on, Colors.purple,
                  'Export Excel', () async {
                Navigator.pop(ctx);
                try {
                  final path = await exportCustomerExcel(name);
                  _snack('Excel saved: $path');
                } catch (e) { _snack('Error: $e'); }
              }),

              _menuItem(ctx, Icons.edit, Colors.amber,
                  'Rename Customer', () {
                Navigator.pop(ctx);
                _renameDialog(name);
              }),

              _menuItem(ctx, Icons.delete, Colors.red.shade700,
                  'Delete Customer', () {
                Navigator.pop(ctx);
                _deleteDialog(name);
              }),
            ]),
          ),
        );
      },
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, Color color,
      String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      onTap: onTap,
    );
  }

  // ── Rename dialog ──────────────────────────────────────────────────────────

  Future<void> _renameDialog(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Rename Customer',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2196F3))),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              final ok = await DBHelper.renameCustomer(oldName, newName);
              Navigator.pop(ctx);
              _snack(ok ? 'Renamed to $newName' : 'Name already exists');
              _load();
            },
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
  }

  // ── Delete dialog ──────────────────────────────────────────────────────────

  Future<void> _deleteDialog(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Customer',
            style: TextStyle(color: Colors.white)),
        content: Text("Delete '$name' and all their transactions?",
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DBHelper.deleteCustomer(name);
      if (_selected == name) setState(() => _selected = null);
      _snack("'$name' deleted.");
      _load();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _customers
        .where((e) =>
            _search.isEmpty ||
            e.key.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: const Text('Point of Sale',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            color: const Color(0xFF1E1E2E),
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              try {
                if (v == 'all_csv') {
                  final p = await exportAllBalancesCsv();
                  _snack('Saved: $p');
                } else if (v == 'all_excel') {
                  final p = await exportAllBalancesExcel();
                  _snack('Saved: $p');
                } else if (v == 'all_share_csv') {
                  final p = await exportAllBalancesCsv();
                  await shareFile(p);
                } else if (v == 'all_share_excel') {
                  final p = await exportAllBalancesExcel();
                  await shareFile(p);
                }
              } catch (e) {
                _snack('Error: $e');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all_csv',
                  child: Text('Export All Balances CSV',
                      style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'all_excel',
                  child: Text('Export All Balances Excel',
                      style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'all_share_csv',
                  child: Text('Share All Balances CSV',
                      style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'all_share_excel',
                  child: Text('Share All Balances Excel',
                      style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),

      body: Column(children: [
        // Total balance
        Container(
          width: double.infinity,
          color: _totalBalance >= 0
              ? const Color(0xFF1B5E20)
              : const Color(0xFFB71C1C),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Total Balance: ${_fmtAmt(_totalBalance)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
        ),

        // Selected banner
        if (_selected != null)
          Container(
            width: double.infinity,
            color: const Color(0xFF0D47A1),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text('Selected: $_selected',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),

        // Input area
        Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            // Add customer row
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDec('New customer name'),
                  onSubmitted: (_) => _addCustomer(),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13)),
                onPressed: _addCustomer,
                child: const Text('ADD',
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 6),
            // Search
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _inputDec('Search customer…').copyWith(
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                        child: const Icon(Icons.clear,
                            color: Colors.white38, size: 18))
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 6),
            // Amount + note + C IN / C OUT
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDec('Amount'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _noteCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDec('Note (optional)'),
                ),
              ),
              const SizedBox(width: 6),
              _txBtn('C IN', Colors.green.shade700,
                  () => _addTx('Deposit')),
              const SizedBox(width: 4),
              _txBtn('C OUT', Colors.orange.shade700,
                  () => _addTx('Withdraw')),
            ]),
          ]),
        ),

        // Customer list header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Customers',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Text('${filtered.length} found',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ]),
        ),

        // Customer list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(
                      child: Text('No customers.',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final name = filtered[i].key;
                        final bal  = filtered[i].value;
                        final isSelected = _selected == name;

                        return GestureDetector(
                          onTap: () => _openMenu(name, bal),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0D3B6E)
                                  : const Color(0xFF1E1E2E),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(
                                      color: const Color(0xFF2196F3),
                                      width: 1.5)
                                  : null,
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                _fmtAmt(bal),
                                style: TextStyle(
                                    color: bal >= 0
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  Widget _txBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13)),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white38, fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: Color(0xFF2196F3))),
      );
}
