import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '/backend/supabase/supabase.dart';

enum FleaberLogLevel { debug, info, warning, error }

/// Logger global — erros vão para Supabase `app_logs` (sem cabo USB).
class FleaberLogger {
  FleaberLogger._();
  static final FleaberLogger instance = FleaberLogger._();

  static const int maxMemoryEntries = 300;
  static const int maxMessageChars = 8000;
  static const int maxStackChars = 16000;

  static bool _installed = false;
  static bool _supabaseReady = false;
  static FlutterExceptionHandler? _previousFlutterErrorHandler;
  static DateTime? _lastPublishStepUploadUtc;

  Map<String, dynamic>? _cachedDeviceInfo;
  final List<FleaberLogEntry> _entries = [];
  final List<Map<String, dynamic>> _pendingSupabaseRows = [];

  String Function()? routeProvider;

  /// Último erro ao gravar no Supabase (ver no DEBUG se a tabela estiver vazia).
  String? lastRemoteLogError;

  List<FleaberLogEntry> get recentEntries => List.unmodifiable(_entries);

  static void install() {
    if (_installed) return;
    _installed = true;

    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      instance._handleFlutterError(details);
      _previousFlutterErrorHandler?.call(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      instance._handleUncaught(error, stack, category: 'PlatformDispatcher');
      if (previousPlatformError != null) {
        return previousPlatformError(error, stack);
      }
      return false;
    };

    instance.info('bootstrap', 'FleaberLogger instalado (Supabase app_logs)');
  }

  static void markSupabaseReady() {
    _supabaseReady = true;
    unawaited(instance._flushPendingToSupabase());
    unawaited(
      instance.uploadStep(
        'app.startup',
        detail: 'Supabase pronto — logger remoto activo',
      ),
    );
    // Bundle pesado só sob pedido (uploadDiagnosticBundle), não no arranque.
  }

  /// Evento estruturado → memória + ficheiro local + Supabase (não bloqueia UI).
  ///
  /// Uploads remotos são agregados (~1.5s) para não saturar a rede em polls.
  Future<void> event(String category, Map<String, dynamic> data) async {
    final payload = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      ...data,
    };
    final message = jsonEncode(payload);
    _record(
      level: FleaberLogLevel.info,
      category: category,
      message: message,
      uploadToSupabase: false,
    );
    _enqueueAppLog(
      category: category,
      errorMessage: _truncate(message, maxMessageChars),
    );
  }

  Timer? _appLogFlushTimer;

  void _enqueueAppLog({
    required String category,
    required String errorMessage,
    String? stackTrace,
  }) {
    unawaited(() async {
      final deviceInfo = await _deviceInfo();
      if (routeProvider != null) {
        deviceInfo['route'] = routeProvider!.call();
      }
      _pendingSupabaseRows.add({
        'category': _truncate(category, 200),
        'error_message': _truncate(errorMessage, maxMessageChars),
        'stack_trace':
            stackTrace != null ? _truncate(stackTrace, maxStackChars) : null,
        'device_info': deviceInfo,
      });
      _appLogFlushTimer?.cancel();
      _appLogFlushTimer = Timer(const Duration(milliseconds: 1500), () {
        unawaited(_flushPendingToSupabase());
      });
    }());
  }

  /// Pacote com últimos logs (para análise no Supabase + ficheiro no telemóvel).
  Future<String?> uploadDiagnosticBundle({String? note}) async {
    final path = await _localLogPath();
    final bundlePath = path == null
        ? null
        : path.replaceAll('fleaber_app.log', 'fleaber_diagnostic_bundle.json');

    final bundle = <String, dynamic>{
      if (note != null) 'note': note,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'local_log': path,
      'bundle_file': bundlePath,
      'entries': _entries.map((e) => e.toJson()).toList(growable: false),
    };

    try {
      final user = SupaFlow.client.auth.currentUser;
      if (user != null) {
        bundle['user_id'] = user.id;
        bundle['user_email'] = user.email;
      }
    } catch (_) {}

    if (bundlePath != null) {
      try {
        await File(bundlePath).writeAsString(
          jsonEncode(bundle),
          flush: true,
        );
      } catch (_) {}
    }

    unawaited(
      _uploadToSupabase(
        category: 'diagnostic.bundle',
        errorMessage: _truncate(jsonEncode(bundle), maxMessageChars),
      ),
    );
    unawaited(_flushPendingToSupabase());
    return bundlePath ?? path;
  }

  /// Grava um passo no Supabase (com rate-limit para não bloquear o projecto).
  Future<void> uploadStep(String step, {String? detail}) async {
    if (!_shouldUploadPublishStep(step)) return;
    final message = detail != null ? '$step | $detail' : step;
    unawaited(
      _uploadToSupabase(
        category: 'live_publish.step',
        errorMessage: message,
      ),
    );
  }

  static bool _shouldUploadPublishStep(String step) {
    if (!kReleaseMode) return true;
    final critical = step.contains('fail') ||
        step.contains('error') ||
        step.contains('egress') ||
        step.contains('startLive') ||
        step.contains('stopLive');
    if (critical) return true;
    final now = DateTime.now().toUtc();
    final last = _lastPublishStepUploadUtc;
    if (last != null && now.difference(last) < const Duration(seconds: 4)) {
      return false;
    }
    _lastPublishStepUploadUtc = now;
    return true;
  }

  void info(String category, String message) =>
      _record(level: FleaberLogLevel.info, category: category, message: message);

  void warning(String category, String message) => _record(
        level: FleaberLogLevel.warning,
        category: category,
        message: message,
      );

  void debug(String category, String message) {
    if (kReleaseMode) return;
    _record(level: FleaberLogLevel.debug, category: category, message: message);
  }

  void error(
    String category,
    Object error, [
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
  ]) {
    if (error is PlatformException) {
      platformException(category, error, stackTrace, extra);
      return;
    }
    _record(
      level: FleaberLogLevel.error,
      category: category,
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
      details: extra != null ? jsonEncode(extra) : null,
      uploadToSupabase: true,
    );
  }

  void platformException(
    String category,
    PlatformException exception, [
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
  ]) {
    final details = <String, dynamic>{
      if (exception.code.isNotEmpty) 'code': exception.code,
      if (exception.details != null) 'details': exception.details.toString(),
      if (extra != null) ...extra,
    };
    _record(
      level: FleaberLogLevel.error,
      category: category,
      message: exception.message ?? exception.toString(),
      stackTrace: stackTrace?.toString(),
      details: details.isEmpty ? null : jsonEncode(details),
      uploadToSupabase: true,
    );
  }

  void recordZoneError(Object error, StackTrace stackTrace) {
    if (error is PlatformException) {
      platformException('Zone.uncaught', error, stackTrace);
    } else {
      this.error('Zone.uncaught', error, stackTrace);
    }
  }

  /// Antes da app fechar / após falha em «Iniciar Direto» — envia tudo ao Supabase.
  Future<void> reportFailure({
    required String category,
    required Object error,
    StackTrace? stackTrace,
    List<String>? contextLines,
  }) async {
    final buffer = StringBuffer()..writeln(error.toString());
    if (contextLines != null && contextLines.isNotEmpty) {
      buffer.writeln('--- contexto ---');
      buffer.writeln(contextLines.join('\n'));
    }
    await _uploadToSupabase(
      category: category,
      errorMessage: buffer.toString(),
      stackTrace: stackTrace?.toString(),
    );
    await _flushPendingToSupabase();
  }

  Future<void> flush() async {
    await _flushPendingToSupabase();
  }

  Future<String> logPathForUser() async {
    final path = await _localLogPath();
    return path ?? 'Supabase → tabela app_logs';
  }

  /// Stripe/checkout → `app_logs` (category stripe.*) + tentativa em `stripe_checkout_events`.
  Future<void> logStripe(
    String step, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final payload = <String, dynamic>{
      'step': step,
      if (data != null) ...data,
      if (error != null) 'error': error.toString(),
    };
    if (error != null) {
      this.error('stripe.checkout', error, stackTrace, payload);
    } else {
      await event('stripe.checkout', payload);
    }
    if (!_supabaseReady) return;
    try {
      final user = SupaFlow.client.auth.currentUser;
      await SupaFlow.client.from('stripe_checkout_events').insert({
        'session_id': data?['session_id']?.toString(),
        'order_id': data?['order_id']?.toString(),
        'product_id': data?['product_id']?.toString(),
        'live_id': data?['live_id']?.toString(),
        'buyer_id': user?.id,
        'event': step,
        'detail': payload,
      });
    } catch (_) {
      // Tabela ainda não migrada — app_logs chega na mesma.
    }
  }

  /// Painel vendedor/helper em directo → `app_logs` + `live_vendor_studio_logs`.
  Future<void> logLiveVendorStudio(
    String step, {
    String? liveId,
    String? sellerId,
    String? liveItemId,
    String? requestId,
    String status = 'ok',
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final payload = <String, dynamic>{
      'step': step,
      'status': status,
      if (liveId != null && liveId.trim().isNotEmpty) 'live_id': liveId.trim(),
      if (sellerId != null && sellerId.trim().isNotEmpty)
        'seller_id': sellerId.trim(),
      if (liveItemId != null && liveItemId.trim().isNotEmpty)
        'live_item_id': liveItemId.trim(),
      if (requestId != null && requestId.trim().isNotEmpty)
        'request_id': requestId.trim(),
      if (data != null) ...data,
      if (error != null) 'error': error.toString(),
    };
    if (error != null) {
      this.error('live.vendor.studio', error, stackTrace, payload);
    } else {
      await this.event('live.vendor.studio', payload);
    }
    if (!_supabaseReady) return;
    try {
      final user = SupaFlow.client.auth.currentUser;
      await SupaFlow.client.from('live_vendor_studio_logs').insert({
        'live_id': (liveId == null || liveId.trim().isEmpty) ? null : liveId.trim(),
        'seller_id':
            (sellerId == null || sellerId.trim().isEmpty) ? null : sellerId.trim(),
        'actor_id': user?.id,
        'live_item_id': (liveItemId == null || liveItemId.trim().isEmpty)
            ? null
            : liveItemId.trim(),
        'request_id': (requestId == null || requestId.trim().isEmpty)
            ? null
            : requestId.trim(),
        'event': step,
        'status': status,
        'detail': payload,
        'error_message': error?.toString(),
      });
    } catch (_) {
      // Tabela ainda não migrada — app_logs chega na mesma.
    }
  }

  /// Convites helper → `app_logs` (staff.helper.*) + `staff_helper_events`.
  Future<void> logStaffHelper(
    String step, {
    String? sellerId,
    String? helperUserId,
    String? sellerHelpersId,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final payload = <String, dynamic>{
      'step': step,
      if (sellerId != null) 'seller_id': sellerId,
      if (helperUserId != null) 'helper_user_id': helperUserId,
      if (sellerHelpersId != null) 'seller_helpers_id': sellerHelpersId,
      if (data != null) ...data,
      if (error != null) 'error': error.toString(),
    };
    if (error != null) {
      this.error('staff.helper', error, stackTrace, payload);
    } else {
      await event('staff.helper', payload);
    }
    if (!_supabaseReady) return;
    try {
      final user = SupaFlow.client.auth.currentUser;
      await SupaFlow.client.from('staff_helper_events').insert({
        'seller_id': sellerId,
        'helper_user_id': helperUserId,
        'seller_helpers_id': sellerHelpersId,
        'actor_id': user?.id,
        'event': step,
        'detail': payload,
      });
    } catch (_) {}
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack;
    final library = details.library ?? '';
    final context = details.context?.toString();

    final message = StringBuffer()
      ..writeln(exception.toString())
      ..writeln('library: $library');
    if (context != null && context.isNotEmpty) {
      message.writeln('context: $context');
    }

    if (exception is PlatformException) {
      unawaited(
        _uploadToSupabase(
          category: 'FlutterError.PlatformException',
          errorMessage: message.toString(),
          stackTrace: stack?.toString(),
          extra: {
            'code': exception.code,
            if (exception.details != null)
              'details': exception.details.toString(),
          },
        ),
      );
    } else {
      unawaited(
        _uploadToSupabase(
          category: 'FlutterError',
          errorMessage: message.toString(),
          stackTrace: stack?.toString(),
        ),
      );
    }

    _record(
      level: FleaberLogLevel.error,
      category: 'FlutterError',
      message: exception.toString(),
      stackTrace: stack?.toString(),
      uploadToSupabase: false,
    );
  }

  void _handleUncaught(
    Object error,
    StackTrace stack, {
    required String category,
  }) {
    if (error is PlatformException) {
      unawaited(
        _uploadToSupabase(
          category: '$category.PlatformException',
          errorMessage: error.message ?? error.toString(),
          stackTrace: stack.toString(),
          extra: {
            'code': error.code,
            if (error.details != null) 'details': error.details.toString(),
          },
        ),
      );
    } else {
      unawaited(
        _uploadToSupabase(
          category: category,
          errorMessage: error.toString(),
          stackTrace: stack.toString(),
        ),
      );
    }
  }

  void _record({
    required FleaberLogLevel level,
    required String category,
    required String message,
    String? stackTrace,
    String? details,
    bool uploadToSupabase = false,
  }) {
    final entry = FleaberLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      route: routeProvider?.call(),
      stackTrace: stackTrace,
      details: details,
    );

    _entries.add(entry);
    if (_entries.length > maxMemoryEntries) {
      _entries.removeAt(0);
    }

    debugPrint('FleaberLog ${entry.toDisplayLine()}');
    if (stackTrace != null && stackTrace.isNotEmpty) {
      debugPrint(stackTrace);
    }

    unawaited(_appendLocal(entry));

    if (uploadToSupabase) {
      unawaited(
        _uploadToSupabase(
          category: category,
          errorMessage: details != null ? '$message\n$details' : message,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> _uploadToSupabase({
    required String category,
    required String errorMessage,
    String? stackTrace,
    Map<String, dynamic>? extra,
  }) async {
    final deviceInfo = await _deviceInfo();
    if (routeProvider != null) {
      deviceInfo['route'] = routeProvider!.call();
    }
    if (extra != null) {
      deviceInfo['extra'] = extra;
    }

    final row = <String, dynamic>{
      'category': _truncate(category, 200),
      'error_message': _truncate(errorMessage, maxMessageChars),
      'stack_trace': stackTrace != null
          ? _truncate(stackTrace, maxStackChars)
          : null,
      'device_info': deviceInfo,
    };

    if (!_supabaseReady) {
      _pendingSupabaseRows.add(row);
      return;
    }

    try {
      await SupaFlow.client
          .from('app_logs')
          .insert(row)
          .timeout(const Duration(seconds: 10));
      lastRemoteLogError = null;
    } catch (e, st) {
      lastRemoteLogError = e.toString();
      debugPrint('FleaberLogger Supabase insert falhou: $e\n$st');
      _pendingSupabaseRows.add(row);
    }
  }

  Future<void> _flushPendingToSupabase() async {
    if (!_supabaseReady || _pendingSupabaseRows.isEmpty) return;

    final copy = List<Map<String, dynamic>>.from(_pendingSupabaseRows);
    _pendingSupabaseRows.clear();

    for (final row in copy) {
      try {
        await SupaFlow.client.from('app_logs').insert(row);
      } catch (e) {
        debugPrint('FleaberLogger pending insert falhou: $e');
        _pendingSupabaseRows.add(row);
        break;
      }
    }
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    if (_cachedDeviceInfo != null) return Map.of(_cachedDeviceInfo!);

    final info = <String, dynamic>{
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      if (!kIsWeb) 'os_version': Platform.operatingSystemVersion,
      if (!kIsWeb) 'locale': Platform.localeName,
      'release_mode': kReleaseMode,
    };

    try {
      final user = SupaFlow.client.auth.currentUser;
      if (user != null) {
        info['user_id'] = user.id;
        info['user_email'] = user.email;
      }
    } catch (_) {}

    _cachedDeviceInfo = info;
    return info;
  }

  String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}…[truncated]';
  }

  Future<void> _appendLocal(FleaberLogEntry entry) async {
    if (kIsWeb) return;
    try {
      final path = await _localLogPath();
      if (path == null) return;
      await File(path).writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  Future<String?> _localLogPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/fleaber_app.log';
    } catch (_) {
      return null;
    }
  }
}

/// Entrada em memória (debug local).
class FleaberLogEntry {
  FleaberLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.route,
    this.stackTrace,
    this.details,
  });

  final DateTime timestamp;
  final FleaberLogLevel level;
  final String category;
  final String message;
  final String? route;
  final String? stackTrace;
  final String? details;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'level': level.name,
        'category': category,
        'message': message,
        if (route != null) 'route': route,
        if (details != null) 'details': details,
        if (stackTrace != null) 'stack': stackTrace,
      };

  String toDisplayLine() {
    final ts = timestamp.toIso8601String().substring(11, 23);
    final routeBit = route != null ? ' @$route' : '';
    return '[$ts] ${level.name.toUpperCase()} $category$routeBit: $message';
  }
}
