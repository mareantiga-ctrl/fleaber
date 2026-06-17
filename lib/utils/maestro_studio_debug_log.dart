import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Log em ficheiro para o harness Maestro / debug do painel vendedor.
///
/// Ficheiro no dispositivo (Android):
/// `Android/data/com.mycompany.fleaber/files/maestro_studio_debug.log`
///
/// Pull: `powershell -File tool/pull_maestro_studio_logs.ps1`
abstract final class MaestroStudioDebugLog {
  static const _fileName = 'maestro_studio_debug.log';
  static const _maxBytes = 512 * 1024;

  static File? _file;
  static bool _enabled = false;
  static final List<String> _pending = [];

  static bool get enabled => _enabled;

  static Future<void> enable({String session = 'maestro'}) async {
    if (!kDebugMode) return;
    _enabled = true;
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      await _file!.writeAsString('', mode: FileMode.write);
      await log('session.start', data: {'session': session, 'path': _file!.path});
    } catch (e, st) {
      debugPrint('[MaestroStudioLog] enable failed: $e\n$st');
      _enabled = false;
    }
  }

  static Future<void> log(
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stack,
  }) async {
    if (!_enabled) return;
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('[$ts] $event');
    if (data.isNotEmpty) {
      buf.write(' ${data.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
    }
    if (error != null) buf.write(' error=$error');
    if (stack != null) buf.write('\n$stack');
    final line = buf.toString();
    debugPrint('[MaestroStudioLog] $line');
    _pending.add(line);
    unawaited(_flush());
  }

  static Future<void> _flush() async {
    final file = _file;
    if (file == null || _pending.isEmpty) return;
    final batch = List<String>.from(_pending);
    _pending.clear();
    try {
      if (await file.exists() && await file.length() > _maxBytes) {
        final text = await file.readAsString();
        final trimmed = text.substring(text.length ~/ 2);
        await file.writeAsString(trimmed, mode: FileMode.write);
      }
      await file.writeAsString('${batch.join('\n')}\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('[MaestroStudioLog] flush failed: $e');
    }
  }

  static void installFlutterErrorHandler() {
    if (!kDebugMode) return;
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        log(
          'flutter.error',
          data: {
            'library': details.library ?? '',
            'context': details.context?.toDescription() ?? '',
          },
          error: details.exceptionAsString(),
          stack: details.stack,
        ),
      );
      prev?.call(details);
    };
  }

  static Future<String?> deviceLogPath() async {
    final file = _file;
    return file?.path;
  }
}
