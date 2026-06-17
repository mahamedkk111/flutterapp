import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';
import 'export_helper.dart';

class CustomerScreen extends StatefulWidget {
  final String customerName;
  const CustomerScreen({super.key, required this.customerName});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  List<Map<String, dynamic>> _txs = [];
  double _balance = 0;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _loading = true;

  final _fmt = NumberFormat('#,##0.00');
  String _fmtAmt(double v) => _fmt.format(v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txs = await DBHelper.getTransactions(widget.customerName,
        dateFrom: _dateFrom, dateTo: _dateTo);
    final bal = await DBHelper.getBalance(widget.customerName,
        dateFrom: _dateFrom, dateTo: _dateTo);
    setState(() {
      _txs = txs;
      _balance = bal;
      _loading = false;
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF2196F3),
            surface: Color(0xFF1E1E2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    _load();
  }

  void _clearFilter() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _load();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _editTx(Map<String, dynamic> t) async {
    final amtCtrl  = TextEditingController(text: t['amount'].toString());
    final noteCtrl = TextEditingController(text: t['note'] as String);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Edit Transaction',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amtCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('Amount'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('Note'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text);
              if (amt == null || amt <= 0) {
                _snack('Invalid amount');
                return;
              }
              await DBHelper.editTransaction(
                  t['id'] as int, amt, noteCtrl.text);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTx(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Transaction',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure?',
            style: TextStyle(color: Colors.white70)),
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
      await DBHelper.deleteTransaction(id);
      _load();
    }
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2196F3))),
      );

  Widget _dateBtn(String label, DateTime? date, bool isFrom) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _pickDate(isFrom),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              date != null
                  ? DateFormat('yyyy-MM-dd').format(date)
                  : label,
              style: TextStyle(
                  fontSize: 12,
                  color: date != null ? Colors.white : Colors.white38),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balColor = _balance >= 0 ? Colors.greenAccent : Colors.redAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(widget.customerName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            color: const Color(0xFF1E1E2E),
            icon: const Icon(Icons.download, color: Colors.white),
            onSelected: (v) async {
              String? path;
              try {
                if (v == 'csv') {
                  path = await exportCustomerCsv(widget.customerName);
                } else if (v == 'excel') {
                  path = await exportCustomerExcel(widget.customerName);
                } else if (v == 'pdf') {
                  path = await exportCustomerPdf(widget.customerName,
                      dateFrom: _dateFrom, dateTo: _dateTo);
                } else if (v == 'share_pdf') {
                  path = await exportCustomerPdf(widget.customerName,
                      dateFrom: _dateFrom, dateTo: _dateTo);
                  if (path != null) await shareFile(path);
                  return;
                }
                if (path != null) {
                  _snack('Saved: $path');
                }
              } catch (e) {
                _snack('Error: $e');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Export PDF', style: TextStyle(color: Colors.white)),
                  ])),
              const PopupMenuItem(value: 'share_pdf',
                  child: Row(children: [
                    Icon(Icons.share, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Share PDF', style: TextStyle(color: Colors.white)),
                  ])),
              const PopupMenuItem(value: 'csv',
                  child: Row(children: [
                    Icon(Icons.table_chart, color: Colors.teal, size: 18),
                    SizedBox(width: 8),
                    Text('Export CSV', style: TextStyle(color: Colors.white)),
                  ])),
              const PopupMenuItem(value: 'excel',
                  child: Row(children: [
                    Icon(Icons.grid_on, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text('Export Excel', style: TextStyle(color: Colors.white)),
                  ])),
            ],
          ),
        ],
      ),
      body: Column(children: [
        // Balance bar
        Container(
          width: double.infinity,
          color: _balance >= 0
              ? const Color(0xFF1B5E20)
              : const Color(0xFFB71C1C),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Balance: ${_fmtAmt(_balance)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ),

        // Date filter
        Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            _dateBtn('From', _dateFrom, true),
            const SizedBox(width: 6),
            _dateBtn('To', _dateTo, false),
            const SizedBox(width: 6),
            if (_dateFrom != null || _dateTo != null)
              GestureDetector(
                onTap: _clearFilter,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.clear,
                      size: 18, color: Colors.white70),
                ),
              ),
          ]),
        ),

        // Transactions
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _txs.isEmpty
                  ? const Center(
                      child: Text('No transactions.',
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _txs.length,
                      itemBuilder: (ctx, i) {
                        double running = 0;
                        for (int j = 0; j <= i; j++) {
                          running += _txs[j]['type'] == 'Deposit'
                              ? _txs[j]['amount'] as double
                              : -(_txs[j]['amount'] as double);
                        }
                        final t = _txs[i];
                        final isDeposit = t['type'] == 'Deposit';
                        final dt = t['dt'] as DateTime;

                        return Card(
                          color: const Color(0xFF1E1E2E),
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('yyyy-MM-dd  HH:mm')
                                            .format(dt),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white54),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${t['type']}: ${_fmtAmt(t['amount'] as double)}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isDeposit
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent),
                                      ),
                                      if ((t['note'] as String).isNotEmpty)
                                        Text(t['note'] as String,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white54)),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Running: ${_fmtAmt(running)}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: running >= 0
                                                ? Colors.greenAccent.shade100
                                                : Colors.redAccent.shade100),
                                      ),
                                    ]),
                              ),
                              Column(children: [
                                SizedBox(
                                  height: 30,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Colors.orange.shade700,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10)),
                                    onPressed: () => _editTx(t),
                                    child: const Text('EDIT',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 30,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10)),
                                    onPressed: () =>
                                        _deleteTx(t['id'] as int),
                                    child: const Text('DEL',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
