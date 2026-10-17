import 'package:flutter/material.dart';

import '../../ds/ds.dart';
import 'export/file_saver_stub.dart'
    if (dart.library.js_interop) 'export/file_saver_web.dart'
    as saver;

/// A table ready to download: a file name, a header and rows of cells.
class CsvExport {
  const CsvExport({required this.fileName, required this.header, required this.rows, this.detail});

  final String fileName;
  final List<String> header;
  final List<List<Object?>> rows;

  /// After the file name in the pill: "2 periods", "first isolates only".
  final String? detail;

  /// RFC 4180 text: commas, CRLF, quotes doubled; null cells are empty.
  String toCsv() {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return [header, ...rows].map((r) => r.map(cell).join(',')).join('\r\n');
  }
}

/// Where downloads go. The web build hands the file to the browser; elsewhere it is a no-op,
/// and tests can pass their own.
abstract interface class FileSaver {
  void save(String name, String text, {String mimeType});
}

class BrowserFileSaver implements FileSaver {
  const BrowserFileSaver();

  @override
  void save(String name, String text, {String mimeType = 'text/csv;charset=utf-8'}) =>
      saver.saveTextFile(name, text, mimeType);
}

/// Downloads [export] as CSV.
void downloadCsv(CsvExport export, {FileSaver saver = const BrowserFileSaver()}) =>
    saver.save(export.fileName, export.toCsv());

/// "ecoli_tmp_by_sex.csv · 2 periods [Download]": the white action pill.
class ExportReadyPill extends StatelessWidget {
  const ExportReadyPill({super.key, required this.export, this.saver = const BrowserFileSaver()});

  final CsvExport export;
  final FileSaver saver;

  @override
  Widget build(BuildContext context) => ActionPill(
    dark: false,
    message: [export.fileName, ?export.detail].join(' · '),
    actionLabel: 'Download',
    onAction: () => downloadCsv(export, saver: saver),
  );
}
