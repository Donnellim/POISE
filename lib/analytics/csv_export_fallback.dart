import 'dart:io';
import 'package:flutter/services.dart';

const csvActionLabel = 'Download CSV';

Future<String> exportCsv(String csv, String filename) async {
  // Always copy to clipboard for quick paste & background test safety
  await Clipboard.setData(ClipboardData(text: csv));

  try {
    Directory? targetDir;
    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        targetDir = androidDownload;
      } else {
        final sdcardDownload = Directory('/sdcard/Download');
        if (await sdcardDownload.exists()) {
          targetDir = sdcardDownload;
        }
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final winDownload = Directory('$userProfile\\Downloads');
        if (await winDownload.exists()) {
          targetDir = winDownload;
        }
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final unixDownload = Directory('$home/Downloads');
        if (await unixDownload.exists()) {
          targetDir = unixDownload;
        }
      }
    }

    targetDir ??= Directory.current;

    final file = File('${targetDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsString(csv, flush: true);
    return 'CSV downloaded to Downloads (${file.path.split(Platform.pathSeparator).last}).';
  } catch (e) {
    // If saving file fails due to permissions or environment, clipboard was already set
    return 'CSV copied to clipboard (file download notice: $e).';
  }
}
