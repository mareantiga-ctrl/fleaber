// ignore_for_file: avoid_print
/// Saída em tempo real para corridas Maestro (o que está a correr, pass/fail, motivo).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MaestroLiveLog {
  static String? _currentLabel;

  static void chainStart(String chainId, String description) {
    _println('');
    _println('━━ CHAIN $chainId ━━ $description');
  }

  static void chainEnd(String chainId, {required bool aborted}) {
    _println('━━ CHAIN $chainId ${aborted ? 'ABORT' : 'OK'} ━━');
    _println('');
  }

  static void login(String flowPath) {
    _println('  → login: $flowPath');
  }

  static void nav(String label) {
    _println('  → nav: $label');
  }

  static void testStart({
    required List<String> testIds,
    required String title,
    required String device,
    required String flowPath,
    required String chainId,
    String? extra,
  }) {
    final ids = testIds.isEmpty ? '—' : testIds.join(',');
    _currentLabel = testIds.isEmpty ? flowPath : testIds.join('+');
    _println('');
    _println('▶ [$ids] $title');
    _println('  chain=$chainId  device=$device');
    _println('  flow=$flowPath${extra != null ? '  $extra' : ''}');
  }

  static void adbDeepLink(String uri, String device) {
    _println('  adb deep link → $uri ($device)');
  }

  static void maestroLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return;
    // Evita duplicar banners nossos.
    if (t.startsWith('Maestro ->')) return;
    _println('  │ $t');
  }

  static void testEnd({
    required List<String> testIds,
    required bool ok,
    required int durationMs,
    String? reason,
  }) {
    final ids = testIds.isEmpty ? (_currentLabel ?? '?') : testIds.join(',');
    final icon = ok ? '✓ PASS' : '✗ FAIL';
    final secs = (durationMs / 1000).toStringAsFixed(1);
    _println('$icon [$ids] (${secs}s)');
    if (!ok && reason != null && reason.trim().isNotEmpty) {
      for (final line in reason.trim().split('\n')) {
        final t = line.trim();
        if (t.isNotEmpty) _println('  motivo: $t');
      }
    }
    _currentLabel = null;
  }

  static String parseFailure(String stdout, String stderr) {
    final combined = '$stdout\n$stderr';
    final lines = combined.split(RegExp(r'\r?\n'));

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (lower.contains('assertion') ||
          lower.contains('assertion is false') ||
          lower.contains('element not found') ||
          lower.contains('no visible') ||
          lower.contains('timed out') ||
          lower.contains('timeout') ||
          lower.contains('failed') ||
          lower.contains('error')) {
        return t;
      }
    }

    for (final line in lines.reversed) {
      final t = line.trim();
      if (t.isNotEmpty && !t.startsWith('Maestro')) return t;
    }
    return combined.trim().isEmpty ? 'exit != 0 (sem output Maestro)' : tail(combined);
  }

  static String tail(String text, [int max = 500]) {
    final t = text.trim();
    if (t.length <= max) return t;
    return t.substring(t.length - max);
  }

  /// Corre processo com stdout/stderr em tempo real; devolve buffers completos.
  static Future<ProcessResult> runStreaming({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    bool runInShell = true,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();

    Future<void> drain(Stream<List<int>> stream, StringBuffer buf) async {
      final decoder = Platform.isWindows
          ? systemEncoding.decoder
          : utf8.decoder;
      await stream
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        buf.writeln(line);
        maestroLine(line);
      });
    }

    await Future.wait([
      drain(process.stdout, stdoutBuf),
      drain(process.stderr, stderrBuf),
    ]);

    final code = await process.exitCode;
    return ProcessResult(
      process.pid,
      code,
      stdoutBuf.toString(),
      stderrBuf.toString(),
    );
  }

  static void _println(String msg) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    print('[$hh:$mm:$ss] $msg');
  }
}
