// Browser-only implementation, excluded from native builds.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

const csvActionLabel = 'Export CSV';
Future<String> exportCsv(String csv, String filename) async {
  final blob = html.Blob([utf8.encode('\ufeff$csv')], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Keep the object URL alive until the browser has begun the download.
  Future<void>.delayed(
      const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
  return 'CSV download started.';
}
