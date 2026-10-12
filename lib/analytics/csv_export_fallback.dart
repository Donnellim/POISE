import 'package:flutter/services.dart';

const csvActionLabel = 'Copy CSV';
Future<String> exportCsv(String csv, String filename) async {
  await Clipboard.setData(ClipboardData(text: csv));
  return 'CSV copied to clipboard.';
}
