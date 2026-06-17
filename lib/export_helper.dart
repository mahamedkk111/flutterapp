import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'db_helper.dart';

const String businessName = 'M KK BIZ HUB';
final _fmt = NumberFormat('#,##0.00');
String fmtAmt(double v) => _fmt.format(v);

Future<String> _downloadsPath() async {
  if (Platform.isAndroid) {
    return '/storage/emulated/0/Download';
  }
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

// ── CSV ───────────────────────────────────────────────────────────────────────

Future<String> exportCustomerCsv(String customerName) async {
  final txs = await DBHelper.getTransactions(customerName);
  double running = 0;
  final rows = <List<dynamic>>[
    ['Date', 'Time', 'Type', 'Amount', 'Note', 'Running Balance'],
  ];
  for (final t in txs) {
    running += t['type'] == 'Deposit' ? t['amount'] : -(t['amount'] as double);
    final dt = t['dt'] as DateTime;
    rows.add([
      DateFormat('yyyy-MM-dd').format(dt),
      DateFormat('HH:mm:ss').format(dt),
      t['type'],
      t['amount'],
      t['note'],
      running,
    ]);
  }
  final csv = const ListToCsvConverter().convert(rows);
  final path =
      '${await _downloadsPath()}/${customerName.replaceAll(' ', '_')}_transactions.csv';
  await File(path).writeAsString(csv);
  return path;
}

Future<String> exportAllBalancesCsv() async {
  final customers = await DBHelper.getSortedCustomersByBalance();
  final rows = <List<dynamic>>[
    ['Customer Name', 'Balance'],
    ...customers.map((e) => [e.key, fmtAmt(e.value)]),
  ];
  final csv = const ListToCsvConverter().convert(rows);
  final path = '${await _downloadsPath()}/all_customers_balances.csv';
  await File(path).writeAsString(csv);
  return path;
}

// ── Excel ─────────────────────────────────────────────────────────────────────

Future<String> exportCustomerExcel(String customerName) async {
  final excel = Excel.createExcel();
  final sheet = excel['Transactions'];
  final headers = [
    'Date', 'Time', 'Type', 'Amount', 'Note', 'Running Balance'
  ];
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

  final txs = await DBHelper.getTransactions(customerName);
  double running = 0;
  for (final t in txs) {
    running += t['type'] == 'Deposit' ? t['amount'] : -(t['amount'] as double);
    final dt = t['dt'] as DateTime;
    sheet.appendRow([
      TextCellValue(DateFormat('yyyy-MM-dd').format(dt)),
      TextCellValue(DateFormat('HH:mm:ss').format(dt)),
      TextCellValue(t['type'] as String),
      DoubleCellValue(t['amount'] as double),
      TextCellValue(t['note'] as String),
      DoubleCellValue(running),
    ]);
  }
  final bytes = excel.encode()!;
  final path =
      '${await _downloadsPath()}/${customerName.replaceAll(' ', '_')}_transactions.xlsx';
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<String> exportAllBalancesExcel() async {
  final excel = Excel.createExcel();
  final sheet = excel['Balances'];
  sheet.appendRow(
      [TextCellValue('Customer Name'), TextCellValue('Balance')]);
  final customers = await DBHelper.getSortedCustomersByBalance();
  for (final e in customers) {
    sheet.appendRow(
        [TextCellValue(e.key), DoubleCellValue(e.value)]);
  }
  final bytes = excel.encode()!;
  final path = '${await _downloadsPath()}/all_customers_balances.xlsx';
  await File(path).writeAsBytes(bytes);
  return path;
}

// ── PDF ───────────────────────────────────────────────────────────────────────

Future<String> exportCustomerPdf(
  String customerName, {
  DateTime? dateFrom,
  DateTime? dateTo,
}) async {
  final txs = await DBHelper.getTransactions(customerName,
      dateFrom: dateFrom, dateTo: dateTo);

  // Opening balance = balance before dateFrom
  double opening = 0;
  if (dateFrom != null) {
    final allTxs = await DBHelper.getTransactions(customerName);
    for (final t in allTxs) {
      final dt = t['dt'] as DateTime;
      if (dt.isBefore(dateFrom)) {
        opening +=
            t['type'] == 'Deposit' ? t['amount'] : -(t['amount'] as double);
      }
    }
  }

  double totalIn = 0, totalOut = 0, running = opening;
  for (final t in txs) {
    if (t['type'] == 'Deposit') {
      totalIn += t['amount'] as double;
    } else {
      totalOut += t['amount'] as double;
    }
  }
  final closing = opening + totalIn - totalOut;

  final now = DateTime.now();
  final generatedStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
  final periodStr = (dateFrom == null && dateTo == null)
      ? 'All Dates'
      : '${dateFrom != null ? DateFormat('yyyy-MM-dd').format(dateFrom) : '—'}'
          '  to  '
          '${dateTo != null ? DateFormat('yyyy-MM-dd').format(dateTo) : '—'}';

  // ── Colors ─────────────────────────────────────────────────────────────
  const darkBlue  = PdfColor.fromInt(0xFF1A237E);
  const midBlue   = PdfColor.fromInt(0xFF283593);
  const lightRow  = PdfColor.fromInt(0xFFE8EAF6);
  const altRow    = PdfColor.fromInt(0xFFF5F5F5);
  const green     = PdfColor.fromInt(0xFF2E7D32);
  const red       = PdfColor.fromInt(0xFFC62828);
  const greyLine  = PdfColor.fromInt(0xFF9E9E9E);
  const white     = PdfColors.white;

  final doc = pw.Document();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(20),
    build: (ctx) {
      final rows = <pw.Widget>[];

      // ── Header ──────────────────────────────────────────────────────
      rows.add(pw.Container(
        width: double.infinity,
        color: darkBlue,
        padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: pw.Column(children: [
          pw.Text(businessName,
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: white)),
          pw.SizedBox(height: 2),
          pw.Container(
            color: midBlue,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Center(
              child: pw.Text('ACCOUNT STATEMENT',
                  style: pw.TextStyle(
                      fontSize: 11,
                      color: PdfColor.fromInt(0xFFB3C2F2),
                      fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ]),
      ));

      rows.add(pw.SizedBox(height: 10));

      // ── Summary box ─────────────────────────────────────────────────
      pw.Widget summaryCell(String label, String value,
          {PdfColor valueColor = PdfColors.black}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColor.fromInt(0xFF616161))),
                pw.SizedBox(height: 2),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: valueColor)),
              ]),
        );
      }

      rows.add(pw.Container(
        decoration: pw.BoxDecoration(
          color: lightRow,
          border: pw.Border.all(color: greyLine, width: 0.5),
        ),
        child: pw.Table(
          children: [
            pw.TableRow(children: [
              summaryCell('Account Holder', customerName),
              summaryCell('Issued By', businessName),
            ]),
            pw.TableRow(children: [
              summaryCell('Period', periodStr),
              summaryCell('Generated', generatedStr),
            ]),
            pw.TableRow(children: [
              summaryCell('Opening Balance', fmtAmt(opening)),
              summaryCell('Closing Balance', fmtAmt(closing),
                  valueColor: closing >= 0 ? green : red),
            ]),
            pw.TableRow(children: [
              summaryCell('Total Deposits', fmtAmt(totalIn),
                  valueColor: green),
              summaryCell('Total Withdrawals', fmtAmt(totalOut),
                  valueColor: red),
            ]),
          ],
        ),
      ));

      rows.add(pw.SizedBox(height: 10));

      // ── Transactions table ───────────────────────────────────────────
      final colWidths = {
        0: const pw.FixedColumnWidth(54),   // Date
        1: const pw.FixedColumnWidth(36),   // Time
        2: const pw.FixedColumnWidth(48),   // Type
        3: const pw.FixedColumnWidth(52),   // Amount
        4: const pw.FlexColumnWidth(1.0),   // Note
        5: const pw.FixedColumnWidth(58),   // Running Bal
        6: const pw.FixedColumnWidth(24),   // Ref#
      };

      pw.Widget th(String text) => pw.Container(
            padding: const pw.EdgeInsets.all(4),
            color: darkBlue,
            child: pw.Text(text,
                style: pw.TextStyle(
                    fontSize: 7,
                    color: white,
                    fontWeight: pw.FontWeight.bold)),
          );

      final tableRows = <pw.TableRow>[
        pw.TableRow(children: [
          th('Date'), th('Time'), th('Type'),
          th('Amount'), th('Note'), th('Running Bal'), th('Ref#'),
        ]),
      ];

      if (txs.isEmpty) {
        tableRows.add(pw.TableRow(children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('No transactions in this period.',
                style: const pw.TextStyle(fontSize: 8)),
          ),
          ...List.generate(6, (_) => pw.Container()),
        ]));
      }

      for (int i = 0; i < txs.length; i++) {
        final t = txs[i];
        running += t['type'] == 'Deposit'
            ? t['amount'] as double
            : -(t['amount'] as double);
        final dt = t['dt'] as DateTime;
        final isDeposit = t['type'] == 'Deposit';
        final bgColor = i % 2 == 0 ? white : altRow;

        pw.Widget td(String text,
                {pw.TextAlign align = pw.TextAlign.left,
                PdfColor color = PdfColors.black,
                bool bold = false}) =>
            pw.Container(
              color: bgColor,
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(text,
                  textAlign: align,
                  style: pw.TextStyle(
                      fontSize: 7,
                      color: color,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            );

        tableRows.add(pw.TableRow(children: [
          td(DateFormat('yyyy-MM-dd').format(dt)),
          td(DateFormat('HH:mm').format(dt)),
          td(t['type'] as String,
              color: isDeposit ? green : PdfColor.fromInt(0xFFE65100)),
          td('${isDeposit ? "+" : "-"}${fmtAmt(t['amount'] as double)}',
              align: pw.TextAlign.right,
              color: isDeposit ? green : red,
              bold: true),
          td(t['note'] as String,
              color: PdfColor.fromInt(0xFF757575)),
          td(fmtAmt(running),
              align: pw.TextAlign.right,
              color: running >= 0 ? green : red,
              bold: true),
          td('${i + 1}',
              align: pw.TextAlign.center,
              color: greyLine),
        ]));
      }

      rows.add(pw.Table(
        columnWidths: colWidths,
        border: pw.TableBorder.all(color: greyLine, width: 0.3),
        children: tableRows,
      ));

      rows.add(pw.SizedBox(height: 10));

      // ── Footer ──────────────────────────────────────────────────────
      rows.add(pw.Divider(color: greyLine, thickness: 0.5));
      rows.add(pw.SizedBox(height: 4));
      rows.add(pw.Center(
        child: pw.Text(
          'This statement was generated by $businessName on $generatedStr. '
          'For queries, contact your account manager.',
          style: pw.TextStyle(
              fontSize: 7,
              color: greyLine,
              fontStyle: pw.FontStyle.italic),
          textAlign: pw.TextAlign.center,
        ),
      ));

      return rows;
    },
  ));

  final bytes = await doc.save();
  final path =
      '${await _downloadsPath()}/${customerName.replaceAll(' ', '_')}_statement.pdf';
  await File(path).writeAsBytes(bytes);
  return path;
}

// ── Share ─────────────────────────────────────────────────────────────────────

Future<void> shareFile(String path) async {
  await Share.shareXFiles([XFile(path)],
      text: 'Exported by $businessName');
}
