import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '/utils/fleaber_logger.dart';

/// Diagnóstico em-app do pipeline HaishinKit (sem logcat USB).
class LivePublishDebug extends ChangeNotifier {
  LivePublishDebug._();
  static final LivePublishDebug instance = LivePublishDebug._();

  static const int maxLogLines = 80;

  final List<String> _lines = [];
  String? lastError;
  String? lastStackTrace;

  bool cameraPermission = false;
  bool micPermission = false;
  bool cameraAttached = false;
  bool surfaceCreated = false;
  bool encoderStarted = false;
  bool firstFrameHint = false;
  bool previewFramesBeforeConnect = false;
  bool rtmpConnectAttempted = false;
  bool rtmpConnected = false;
  String? rtmpConnectResult;

  String cameraState = 'idle';
  String encoderState = 'idle';
  String previewState = 'idle';
  String activeResolution = '-';
  String activeBitrate = '-';
  String activeFps = '-';
  String activeProfile = 'H264 Baseline (pedido)';
  String encoderBackend = 'hardware (HaishinKit default)';

  /// Modo teste: não chama [StreamSession.connect] — só preview local.
  bool previewOnlyMode = false;

  List<String> get lines => List.unmodifiable(_lines);

  void clear() {
    _lines.clear();
    lastError = null;
    lastStackTrace = null;
    cameraPermission = false;
    micPermission = false;
    cameraAttached = false;
    surfaceCreated = false;
    encoderStarted = false;
    firstFrameHint = false;
    previewFramesBeforeConnect = false;
    rtmpConnectAttempted = false;
    rtmpConnected = false;
    rtmpConnectResult = null;
    cameraState = 'idle';
    encoderState = 'idle';
    previewState = 'idle';
    activeResolution = '-';
    activeBitrate = '-';
    activeFps = '-';
    notifyListeners();
  }

  void log(String message) {
    final line =
        '[${DateTime.now().toIso8601String().substring(11, 19)}] $message';
    _lines.add(line);
    if (_lines.length > maxLogLines) {
      _lines.removeAt(0);
    }
    debugPrint('LivePublishDebug: $message');
    unawaited(_appendToFile(line));
    notifyListeners();
  }

  void error(
    String step,
    Object e, [
    StackTrace? stackTrace,
  ]) {
    FleaberLogger.instance.error('live_publish.$step', e, stackTrace);
    lastError = '$step: $e';
    lastStackTrace = stackTrace?.toString();
    log('ERROR [$step] $e');
    if (stackTrace != null) {
      log('STACK: $stackTrace');
    }
    notifyListeners();
  }

  Future<T?> guard<T>(
    String step,
    Future<T> Function() action, {
    bool rethrowError = false,
  }) async {
    log('▶ $step');
    try {
      final result = await action();
      log('✓ $step');
      return result;
    } catch (e, st) {
      error(step, e, st);
      if (rethrowError) rethrow;
      return null;
    }
  }

  void markCameraAttached(String sourceId) {
    cameraAttached = true;
    cameraState = 'attached ($sourceId)';
    log('camera attached: $sourceId');
    notifyListeners();
  }

  void markSurfaceCreated(int? textureId) {
    if (textureId == null) {
      surfaceCreated = false;
      previewState = 'texture id=null (ERRO Surface)';
      log('ERRO: Flutter Texture id=null após updateTexture');
      notifyListeners();
      return;
    }
    surfaceCreated = true;
    previewState = 'texture id=$textureId';
    log('surface OK (Flutter Texture id=$textureId)');
    notifyListeners();
  }

  void markEncoderStarted() {
    encoderStarted = true;
    encoderState = 'startRunning OK';
    log('encoder started (mixer.startRunning)');
    notifyListeners();
  }

  void markFirstFrameHint(String reason) {
    if (firstFrameHint) return;
    firstFrameHint = true;
    previewFramesBeforeConnect = !rtmpConnected;
    previewState = 'frame hint: $reason';
    log('first video frame (hint): $reason');
    notifyListeners();
  }

  void markRtmpResult({required bool success, String? detail}) {
    rtmpConnectAttempted = true;
    rtmpConnected = success;
    rtmpConnectResult = detail ?? (success ? 'OK' : 'FAIL');
    log('RTMP connect ${success ? 'SUCCESS' : 'FAIL'}${detail != null ? ': $detail' : ''}');
    notifyListeners();
  }

  Future<String?> logFilePath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/live_publish_debug.log';
    } catch (_) {
      return null;
    }
  }

  Future<void> _appendToFile(String line) async {
    if (kIsWeb) return;
    try {
      final path = await logFilePath();
      if (path == null) return;
      final file = File(path);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> exportSnapshot() async {
    final path = await logFilePath();
    log('log file: ${path ?? 'n/a'}');
  }

  /// Grava no disco antes de operações nativas (útil se a app rebentar).
  Future<void> flush() async {
    if (kIsWeb) return;
    try {
      final path = await logFilePath();
      if (path == null) return;
      final file = File(path);
      final body = StringBuffer()
        ..writeln('--- flush ${DateTime.now().toIso8601String()} ---')
        ..writeln('lastError: $lastError')
        ..writeln('rtmpAttempted=$rtmpConnectAttempted connected=$rtmpConnected')
        ..writeln('--- lines ---');
      for (final line in _lines) {
        body.writeln(line);
      }
      await file.writeAsString('$body\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
