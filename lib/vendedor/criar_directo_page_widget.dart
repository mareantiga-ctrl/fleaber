import 'dart:async';
import 'dart:io';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/marketplace_feed_refresh.dart';
import '/vendedor/haishin_preview_texture.dart';
import '/vendedor/livekit_preview_texture.dart';
import '/vendedor/livekit_publish_controller.dart';
import '/utils/live_catalog_cache.dart';
import '/utils/live_catalog_sync.dart';
import '/utils/live_catalog_prep_service.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_screen_wake.dart';
import '/utils/fleaber_colors.dart';
import '/utils/live_publish_config.dart';
import '/vendedor/live_publish_debug.dart';
import '/utils/live_publish_cleanup.dart';
import '/utils/live_start_open_reservations_service.dart';
import '/widgets/live_start_reservations_warning_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/live_vendor_studio_panel.dart';
import '/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haishin_kit/haishin_kit.dart';
import 'package:haishin_kit/src/haishin_kit/video_gravity.dart';
import 'package:permission_handler/permission_handler.dart';

/// Publicar direto: LiveKit WebRTC (POC MTK) ou HaishinKit RTMP → Mux.
/// Viewers mantêm Mux HLS (regra BATATA).
class CriarDirectoPageWidget extends StatefulWidget {
  const CriarDirectoPageWidget({super.key});

  static String routeName = 'CriarDirecto';
  static String routePath = '/criarDirecto';

  @override
  State<CriarDirectoPageWidget> createState() => _CriarDirectoPageWidgetState();
}

class _CriarDirectoPageWidgetState extends State<CriarDirectoPageWidget>
    with FleaberScreenWakeMixin, WidgetsBindingObserver {
  static const Color _kTeal = Color(0xFF007782);
  // Preset conservador para Android MTK/TCL (encoder + Camera2).
  static const int _kDefaultW = 720;
  static const int _kDefaultH = 1280;
  static const int _kDefaultBitrate = 450000;
  static const int _kDefaultFps = 15;

  final _titleController = TextEditingController();
  final _dbg = LivePublishDebug.instance;

  MediaMixer? _mixer;
  StreamSession? _session;
  StreamSubscription<StreamSessionReadyState>? _sessionStateSub;
  StreamSubscription<dynamic>? _nativeDiagSub;
  Timer? _nativeFrameWatchdog;
  Timer? _frameHintTimer;

  int _textureGeneration = 0;
  int _surfaceLoggedForGen = -1;
  bool _initInProgress = false;
  bool _pipelineReady = false;
  bool _starting = false;
  bool _stopping = false;
  bool _isLive = false;
  bool _publishConnected = false;
  bool _showSessionTexture = true;
  bool _diagnosticMode = false;
  bool _purePreviewMode = false;
  String? _liveId;
  String? _streamKey;
  String? _sessionUrlHost;
  /// URL usada na última [StreamSession.create] (para alternar em falha de connect).
  bool _muxPublishUsesRtmps = true;
  /// Override manual escondido para testes:
  /// null = AUTO (RTMPS), true = força RTMPS, false = força RTMP.
  bool? _forceRtmpsOverride;
  bool _debugPanelExpanded = true;
  int _videoW = _kDefaultW;
  int _videoH = _kDefaultH;
  int _videoBitrate = _kDefaultBitrate;
  int _videoFps = _kDefaultFps;
  bool _nativeEncoderFramesSeen = false;

  LivekitPublishController? _lk;
  String? _livekitUrl;
  String? _livekitToken;
  String? _livekitRoomName;
  bool _livekitEgressStarted = false;
  bool _livekitLocalPreviewOnly = false;
  bool _teardownComplete = false;
  DateTime? _liveStartedAt;
  int _catalogItemCount = 0;
  bool _sellerPrivateChatMode = false;
  int _sellerPrivateUnread = 0;
  int _opsQueueBadge = 0;
  SellerLiveActivePanel _activeSellerPanel = SellerLiveActivePanel.none;
  final _studioPanelKey = GlobalKey<LiveVendorStudioPanelState>();
  DateTime? _livekitEgressStartedAt;
  Completer<void>? _livekitPipelineCompleter;
  bool _livekitPipelineWantsEgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    _dbg.clear();
    _dbg.previewOnlyMode = false;
    _dbg.log(
      'página aberta — backend=$kLivePublishBackendLabel',
    );
    _dbg.addListener(_onDebugChanged);
    unawaited(_logPathsForUser());
    unawaited(
      FleaberLogger.instance.uploadStep(
        'criar_directo.page_open',
        detail: 'backend=$kLivePublishBackendLabel',
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoStartCameraPreview());
    });
  }

  Future<void> _autoStartCameraPreview() async {
    if (!mounted || _pipelineReady || _initInProgress || _isLive || _stopping) {
      return;
    }
    if (_titleController.text.trim().length < 3) {
      _titleController.text = 'O meu direto';
    }
    await _prepareCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Best-effort: alguns Android chamam detached ao remover dos recentes.
    if (state != AppLifecycleState.detached) return;
    final id = _liveId?.trim() ?? '';
    if (!_teardownComplete &&
        id.isNotEmpty &&
        (_isLive || _livekitEgressStarted)) {
      unawaited(LivePublishCleanup.finalizeEnded(id));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    _dbg.removeListener(_onDebugChanged);
    _frameHintTimer?.cancel();
    _nativeFrameWatchdog?.cancel();
    _titleController.dispose();
    _sessionStateSub?.cancel();
    _nativeDiagSub?.cancel();
    final session = _session;
    final mixer = _mixer;
    _session = null;
    _mixer = null;
    unawaited(_shutdownHaishin(session, mixer));
    if (!_teardownComplete && kPublishUsesLiveKit) {
      unawaited(
        FleaberLogger.instance.event('livekit.teardown.missed_dispose', {
          'live_id': _liveId,
          'local_preview_only': _livekitLocalPreviewOnly,
          'egress_started': _livekitEgressStarted,
          'room_connected': _lk?.isConnected ?? false,
        }),
      );
    }
    final orphanLiveId = _liveId?.trim() ?? '';
    if (!_teardownComplete && orphanLiveId.isNotEmpty) {
      unawaited(LivePublishCleanup.finalizeEnded(orphanLiveId));
    }
    super.dispose();
  }

  void _onDebugChanged() {
    if (mounted) setState(() {});
  }

  void _detachNativeHandlesForStability() {
    _sessionStateSub?.cancel();
    _sessionStateSub = null;
    _nativeDiagSub?.cancel();
    _nativeDiagSub = null;
    _nativeFrameWatchdog?.cancel();
    _nativeFrameWatchdog = null;
    _nativeEncoderFramesSeen = false;
    _session = null;
    _mixer = null;
    _pipelineReady = false;
    _showSessionTexture = false;
  }

  Future<void> _logPathsForUser() async {
    await _dbg.exportSnapshot();
    final global = await FleaberLogger.instance.logPathForUser();
    _dbg.log('logs Supabase: tabela app_logs');
    _dbg.log('backup local: $global');
  }

  Future<void> _applySessionFrameRate(StreamSession session) async {
    final memory = session.memory;
    if (memory == null) return;
    await const MethodChannel('com.haishinkit').invokeMethod<void>(
      'StreamSession#setFrameRate',
      {'memory': memory, 'value': _videoFps},
    );
  }

  void _listenNativeDiagnostics(StreamSession session) {
    _nativeDiagSub?.cancel();
    final memory = session.memory;
    if (memory == null) return;
    final channel = EventChannel('com.haishinkit.diagnostic/$memory');
    _nativeDiagSub = channel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final name = event['event']?.toString() ?? '';
      if (name.isEmpty) return;
      final detail = event['detail']?.toString();
      if (name == 'encoder_producing_frames' ||
          (name == 'encoder_video_fps' && detail != null && detail != 'fps=0')) {
        _nativeEncoderFramesSeen = true;
        _nativeFrameWatchdog?.cancel();
      }
      _dbg.log('native.$name${detail != null ? ' | $detail' : ''}');
      final important = <String>{
        'rtmp_session_open',
        'encoder_producing_frames',
        'encoder_video_fps',
      };
      if (!kReleaseMode && important.contains(name)) {
        unawaited(
          FleaberLogger.instance.uploadStep(
            'native.$name',
            detail: detail,
          ),
        );
      }
    });
  }

  void _startEncoderWatchdog() {
    _nativeFrameWatchdog?.cancel();
    _nativeEncoderFramesSeen = false;
    _nativeFrameWatchdog = Timer(const Duration(seconds: 6), () {
      if (_nativeEncoderFramesSeen) return;
      _dbg.log('native: sem encoder_video_fps > 0 após 6s de publish');
      unawaited(
        FleaberLogger.instance.uploadStep(
          'native.no_encoder_fps_after_publish',
          detail: '6s timeout',
        ),
      );
    });
  }

  Future<void> _logLivekit(String event, [Map<String, dynamic>? extra]) async {
    final detail = <String, dynamic>{
      'live_id': _liveId,
      if (_livekitRoomName != null) 'room': _livekitRoomName,
      ...?extra,
    };
    _dbg.log('[livekit] $event ${extra ?? ''}');
    await FleaberLogger.instance.event('livekit.$event', detail);
  }

  // ignore: unused_element — teardown usa _runLivekitTeardownInBackground
  Future<void> _disconnectLivekitRoom() async {
    final lk = _lk;
    if (lk == null) return;
    final durationSec = lk.connectedDuration?.inSeconds;
    await _logLivekit('room.disconnect.begin', {
      if (durationSec != null) 'duration_sec': durationSec,
    });
    await _dbg.guard('livekit.disconnect', () => lk.disconnect());
    _livekitUrl = null;
    _livekitToken = null;
    _livekitRoomName = null;
    _lk = null;
    await _logLivekit('room.disconnect.done', {
      if (durationSec != null) 'duration_sec': durationSec,
    });
  }

  String _livekitApiErrorMessage(Object e) {
    if (e is FunctionException) {
      final details = e.details;
      if (details is Map) {
        final err = details['error']?.toString();
        final step = details['step']?.toString();
        if (err != null && err.isNotEmpty) {
          if (e.status == 429 ||
              err.contains('429') ||
              err.toLowerCase().contains('egress minutes')) {
            return 'Limite de transmissão LiveKit atingido (minutos de egress). '
                'Sai desta página para libertar o directo anterior, aguarda alguns '
                'minutos ou actualiza o plano LiveKit.';
          }
          return step != null ? '$err ($step)' : err;
        }
      }
      if (e.status == 429) {
        return 'Limite de transmissão LiveKit atingido. Tenta outra vez mais tarde.';
      }
      return 'livekit-mux-publish HTTP ${e.status}: ${e.reasonPhrase ?? "erro"}';
    }
    final s = e.toString();
    if (s.contains('429') || s.toLowerCase().contains('egress minutes')) {
      return 'Limite de transmissão LiveKit atingido (minutos de egress).';
    }
    return s;
  }

  Future<void> _stopLivekitEgress({bool silent = true}) async {
    final liveId = _liveId;
    if (liveId == null || liveId.isEmpty) return;
    final egressDurationSec = _livekitEgressStartedAt == null
        ? null
        : DateTime.now().difference(_livekitEgressStartedAt!).inSeconds;
    await _logLivekit('egress.stop.begin', {
      if (egressDurationSec != null) 'duration_sec': egressDurationSec,
    });
    try {
      final response = await _dbg.guard(
        'livekit-mux-publish stop_egress',
        () => SupaFlow.client.functions.invoke(
          'livekit-mux-publish',
          body: {'step': 'stop_egress', 'live_id': liveId},
        ),
      );
      final data = response?.data;
      if (data is Map) {
        await _logLivekit('egress.stop.done', {
          'active_egress_before': data['active_egress_before'],
          'active_egress_stopped': data['active_egress_stopped'],
          if (egressDurationSec != null) 'duration_sec': egressDurationSec,
        });
      }
    } catch (e) {
      if (!silent) rethrow;
      await _logLivekit('egress.stop.failed', {'error': e.toString()});
    }
    _livekitEgressStarted = false;
    _livekitEgressStartedAt = null;
  }

  Future<void> _fetchLivekitToken(String liveId) async {
    final response = await _dbg.guard(
      'livekit-mux-publish token',
      () => SupaFlow.client.functions.invoke(
        'livekit-mux-publish',
        body: {'step': 'token', 'live_id': liveId},
      ),
      rethrowError: true,
    );
    final data = response?.data;
    if (data is! Map) throw Exception('Resposta LiveKit inválida.');
    final error = data['error']?.toString();
    if (error != null && error.isNotEmpty) throw Exception(error);

    _livekitUrl = data['livekit_url']?.toString();
    _livekitToken = data['token']?.toString();
    _livekitRoomName = data['room_name']?.toString();
    if (_livekitUrl == null ||
        _livekitUrl!.isEmpty ||
        _livekitToken == null ||
        _livekitToken!.isEmpty) {
      throw Exception('token/url LiveKit em falta.');
    }
  }

  Future<void> _startLivekitMuxEgress() async {
    final liveId = _liveId;
    final streamKey = _streamKey;
    if (liveId == null || liveId.isEmpty || streamKey == null || streamKey.isEmpty) {
      throw Exception('live_id/stream_key em falta para egress.');
    }
    if (_livekitEgressStarted) {
      _dbg.log('egress já activo — reutilizar');
      return;
    }
    await _stopLivekitEgress();
    final useRtmps = _forceRtmpsOverride ?? true;
    final trackSids = _lk?.publishedTrackSids;
    final response = await _dbg.guard(
      'livekit-mux-publish egress',
      () => SupaFlow.client.functions
          .invoke(
            'livekit-mux-publish',
            body: {
              'step': 'egress',
              'live_id': liveId,
              'stream_key': streamKey,
              'use_rtmps': useRtmps,
              'mux_encode_landscape': kLivekitMuxLandscapeEncode,
              if (trackSids?.videoTrackId != null)
                'video_track_id': trackSids!.videoTrackId,
              if (trackSids?.audioTrackId != null)
                'audio_track_id': trackSids!.audioTrackId,
            },
          )
          .timeout(const Duration(seconds: 90)),
      rethrowError: true,
    );
    final data = response?.data;
    if (data is! Map) throw Exception('Resposta egress inválida.');
    final error = data['error']?.toString();
    if (error != null && error.isNotEmpty) throw Exception(error);
    _livekitEgressStarted = true;
    _livekitEgressStartedAt = DateTime.now();
    await _logLivekit('egress.start.done', {
      'egress_id': data['egress_id'],
      'egress_mode': data['egress_mode'] ?? 'track_composite',
      'egress_layout': data['egress_layout'],
      'egress_video_track_id': data['egress_video_track_id'],
      'egress_preset': data['egress_preset'],
      'active_egress_before': data['active_egress_before'],
      'active_egress_after_start': data['active_egress_after_start'],
      'room': data['room_name'] ?? _livekitRoomName,
    });
    _dbg.log('egress Mux iniciado room=$_livekitRoomName');
  }

  Future<void> _prepareLocalPreviewOnly() async {
    await FleaberLogger.instance.uploadStep('livekit.pre_permissions');
    await _ensurePermissions();
    _lk ??= LivekitPublishController();
    await _dbg.guard(
      'livekit.local_preview',
      () => _lk!.startLocalPreview(),
      rethrowError: true,
    );
    _livekitLocalPreviewOnly = true;
    if (!mounted) return;
    setState(() => _pipelineReady = true);
    _dbg.previewState = 'Local preview (sem room)';
    _dbg.markCameraAttached('livekit_local');
    await _logLivekit('local_preview.ready');
  }

  Future<void> _ensureLivekitPipeline({required bool startEgress}) async {
    if (_livekitPipelineCompleter != null) {
      _livekitPipelineWantsEgress |= startEgress;
      await _livekitPipelineCompleter!.future;
      if (_livekitPipelineWantsEgress &&
          !_dbg.previewOnlyMode &&
          !_livekitEgressStarted) {
        await _startLivekitMuxEgressOnly();
      }
      return;
    }

    _livekitPipelineCompleter = Completer<void>();
    _livekitPipelineWantsEgress = startEgress;
    _initInProgress = true;
    _dbg.previewState = 'LiveKit…';
    try {
      await FleaberLogger.instance.uploadStep('livekit.pre_permissions');
      await _ensurePermissions();

      final liveId = _liveId;
      if (liveId == null || liveId.isEmpty) {
        throw Exception('live_id em falta — cria Mux primeiro.');
      }

      _lk ??= LivekitPublishController();

      if (!_lk!.isConnected) {
        await FleaberLogger.instance.uploadStep('livekit.pre_token');
        await _fetchLivekitToken(liveId);
        await FleaberLogger.instance.uploadStep('livekit.pre_connect');
        await _logLivekit('room.connect.begin');
        await _dbg.guard(
          'livekit.connect',
          () => _lk!.connect(
            url: _livekitUrl!,
            token: _livekitToken!,
          ),
          rethrowError: true,
        );
        _livekitLocalPreviewOnly = false;
        await FleaberLogger.instance.uploadStep('livekit.post_connect');
        await _logLivekit('room.connect.done');
      }

      await _dbg.guard(
        'livekit.camera_mic',
        () => _lk!.enableCameraAndMic(),
        rethrowError: true,
      );
      // Dar tempo ao publish das tracks antes do egress (Chrome/track composite).
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      if (_livekitPipelineWantsEgress &&
          !_dbg.previewOnlyMode &&
          !_livekitEgressStarted) {
        await _startLivekitMuxEgressOnly();
      }

      if (!mounted) return;
      setState(() {
        _pipelineReady = true;
        _publishConnected = _livekitEgressStarted;
      });
      _dbg.previewState =
          _livekitEgressStarted ? 'LiveKit LIVE' : 'LiveKit preview';
      _dbg.markCameraAttached('livekit');
      _dbg.markEncoderStarted();
      if (mounted) setState(() {});
      // TCL: textura WebRTC pode precisar de um frame extra após publish.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() {});
      _livekitPipelineCompleter!.complete();
    } catch (e, st) {
      _dbg.error('ensureLivekitPipeline', e, st);
      _dbg.previewState = 'erro';
      if (!(_livekitPipelineCompleter?.isCompleted ?? true)) {
        _livekitPipelineCompleter!.completeError(e, st);
      }
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.livekit_pipeline',
        error: e,
        stackTrace: st,
        contextLines: _dbg.lines,
      );
      rethrow;
    } finally {
      _livekitPipelineCompleter = null;
      _initInProgress = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startLivekitMuxEgressOnly() async {
    await FleaberLogger.instance.uploadStep('livekit.pre_egress');
    await _startLivekitMuxEgress();
    await FleaberLogger.instance.uploadStep('livekit.post_egress');
    if (!mounted) return;
    setState(() {
      _publishConnected = _livekitEgressStarted;
      if (_livekitEgressStarted) {
        _isLive = true;
        _liveStartedAt ??= DateTime.now();
      }
    });
  }

  Future<void> _syncLiveCatalog({bool forceFull = false}) async {
    final id = _liveId;
    final sid = currentUserUid;
    if (id == null || id.isEmpty || sid.isEmpty) return;
    try {
      if (!forceFull) {
        final existing = await LiveItemsTable().queryRows(
          queryFn: (q) => q.eqOrNull('live_id', id),
          limit: 1,
        );
        if (existing.isNotEmpty) {
          await LiveCatalogSync.mergeForLive(liveId: id, sellerId: sid);
          final rows = await LiveItemsTable().queryRows(
            queryFn: (q) => q
                .eqOrNull('live_id', id)
                .order('created_at', ascending: true),
          );
          if (rows.isNotEmpty) {
            await LiveCatalogCache.write(id, rows);
            if (mounted) setState(() => _catalogItemCount = rows.length);
          }
          return;
        }
      }
      final sync = await LiveCatalogSync.syncForLive(liveId: id, sellerId: sid);
      try {
        final rows = await LiveItemsTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('live_id', id)
              .order('created_at', ascending: true),
        );
        if (rows.isNotEmpty) {
          await LiveCatalogCache.write(id, rows);
          if (mounted) setState(() => _catalogItemCount = rows.length);
        }
      } catch (_) {}
      unawaited(
        FleaberLogger.instance.uploadStep(
          'live.catalog.sync.done',
          detail:
              'liveId=$id items=${sync.inserted} '
              'refs=${sync.schemeItems} products=${sync.productItems} '
              'schemes_prefs=${sync.schemesInPrefs}',
        ),
      );
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'live.catalog.sync',
          error: e,
          stackTrace: st,
          contextLines: ['liveId=$id'],
        ),
      );
    }
  }

  /// V1: aviso de reservas em aberto — após catálogo sincronizado, antes de emitir.
  Future<bool> _confirmOpenReservationsBeforeGoLive() async {
    final liveId = _liveId?.trim() ?? '';
    if (liveId.isEmpty) return true;

    final report = await LiveStartOpenReservationsService.fetch(liveId);
    if (report == null || !report.summary.hasOpen) return true;
    if (!mounted) return false;

    final proceed = await LiveStartReservationsWarningSheet.show(
      context,
      report: report,
    );
    if (!proceed && mounted) {
      context.pop();
    }
    return proceed;
  }

  Future<void> _markLiveActiveInDb() async {
    final id = _liveId;
    if (id == null || id.isEmpty) return;
    try {
      final existing = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      final patch = <String, dynamic>{
        'status': 'live',
        'is_active': true,
        'publish_backend': kPublishUsesLiveKit
            ? (kLivekitMuxLandscapeEncode
                ? 'livekit_mux_landscape'
                : 'livekit_mux')
            : 'mux_rtmp',
      };
      if (existing.isEmpty || existing.first.wentLiveAt == null) {
        patch['went_live_at'] = DateTime.now().toUtc().toIso8601String();
      }
      await LivesTable().update(
        data: patch,
        matchingRows: (rows) => rows.eqOrNull('id', id),
      );
      await LivePublishCleanup.registerActiveBroadcast(id);
      await _syncLiveCatalog();
    } catch (_) {}
  }

  /// Grava `ended` de imediato — evita cards LIVE fantasmas se a app fechar
  /// antes do teardown em background (Mux/LiveKit).
  Future<void> _markLiveEndedInDb(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return;
    try {
      await LivesTable().update(
        data: {'status': 'ended', 'is_active': false},
        matchingRows: (rows) => rows.eqOrNull('id', id),
      );
      await LivePublishCleanup.clearActiveBroadcast();
      requestLiveFeedRefresh();
      await FleaberLogger.instance.uploadStep(
        'live.status.ended',
        detail: 'liveId=$id',
      );
    } catch (e, st) {
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.mark_ended',
        error: e,
        stackTrace: st,
        contextLines: ['live_id=$id'],
      );
    }
  }

  Future<void> _shutdownHaishin(
    StreamSession? session,
    MediaMixer? mixer,
  ) async {
    await _dbg.guard('session.close', () async {
      await session?.close();
    });
    await _dbg.guard('session.dispose', () async {
      await session?.dispose();
    });
    await _dbg.guard('mixer.stopRunning', () async {
      await mixer?.stopRunning();
    });
    await _dbg.guard('mixer.dispose', () async {
      await mixer?.dispose();
    });
  }

  String _muxRtmpUrl(String streamKey) =>
      'rtmp://global-live.mux.com:5222/app/$streamKey';

  String _muxRtmpsUrl(String streamKey) =>
      'rtmps://global-live.mux.com:443/app/$streamKey';

  VideoCodecSettings get _currentVideoSettings => VideoCodecSettings(
    width: _videoW,
    height: _videoH,
    bitrate: _videoBitrate,
    frameInterval: 2,
    profileLevel: ProfileLevel.h264Baseline31,
  );

  String _protocolModeLabel() {
    final v = _forceRtmpsOverride;
    if (v == null) return 'AUTO→RTMPS';
    return v ? 'FORCE RTMPS' : 'FORCE RTMP';
  }

  Future<void> _toggleProtocolOverride() async {
    setState(() {
      if (_forceRtmpsOverride == null) {
        _forceRtmpsOverride = true;
      } else if (_forceRtmpsOverride == true) {
        _forceRtmpsOverride = false;
      } else {
        _forceRtmpsOverride = null;
      }
    });
    final mode = _protocolModeLabel();
    _dbg.log('protocolo publish: $mode');
    await FleaberLogger.instance.uploadStep(
      'protocol.override',
      detail: mode,
    );
    _showSnack('Modo protocolo: $mode');
  }

  Future<void> _toggleDiagnosticMode() async {
    final toEnable = !_diagnosticMode;
    setState(() {
      _diagnosticMode = toEnable;
      _purePreviewMode = toEnable;
      if (toEnable) {
        // 480p landscape, Baseline, baixo bitrate para reduzir stress no encoder.
        _videoW = 854;
        _videoH = 480;
        _videoBitrate = 400000;
        _videoFps = 15;
        _dbg.previewOnlyMode = true;
      } else {
        _videoW = _kDefaultW;
        _videoH = _kDefaultH;
        _videoBitrate = _kDefaultBitrate;
        _videoFps = _kDefaultFps;
      }
    });
    _dbg.log(
      'diagMode=${_diagnosticMode ? 'ON' : 'OFF'} '
      'preset=${_videoW}x$_videoH ${_videoFps}fps ${(_videoBitrate / 1000).round()}kbps',
    );
    await FleaberLogger.instance.uploadStep(
      'diagnostic.mode',
      detail: _diagnosticMode ? 'on 854x480@15 400kbps' : 'off default',
    );
    // Recriar pipeline para aplicar preset sem estado antigo.
    final oldSession = _session;
    final oldMixer = _mixer;
    _session = null;
    _mixer = null;
    _pipelineReady = false;
    _sessionStateSub?.cancel();
    _textureGeneration++;
    _surfaceLoggedForGen = -1;
    unawaited(_shutdownHaishin(oldSession, oldMixer));
    _showSnack(_diagnosticMode
        ? 'Diagnóstico ON: preview puro + 480p.'
        : 'Diagnóstico OFF: preset normal.');
  }

  void _applyDebugVideoLabels() {
    _dbg.activeResolution = '${_videoW}x$_videoH';
    _dbg.activeBitrate = '${(_videoBitrate / 1000).round()} kbps';
    _dbg.activeFps = '$_videoFps';
    _dbg.activeProfile = ProfileLevel.h264Baseline31.profileLevelName;
    if (mounted) setState(() {});
  }

  void _listenSessionReady(StreamSession session) {
    _sessionStateSub?.cancel();
    _sessionStateSub = session.readyState.listen((state) {
      _dbg.log('readyState: $state');
      if (!mounted) return;
      if (state == StreamSessionReadyState.open) {
        _dbg.markRtmpResult(success: true);
        setState(() {
          _publishConnected = true;
        });
        _showSnack('RTMP ligado (Mux).');
      } else if (state == StreamSessionReadyState.closed) {
        if (_dbg.rtmpConnectAttempted && !_dbg.rtmpConnected) {
          _dbg.markRtmpResult(success: false, detail: 'closed');
        }
      }
    });
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    _dbg.cameraPermission = cam.isGranted;
    _dbg.micPermission = mic.isGranted;
    _dbg.log(
      'permissões: CAMERA=${_dbg.cameraPermission} MIC=${_dbg.micPermission}',
    );
    if (!_dbg.cameraPermission || !_dbg.micPermission) {
      throw Exception('Permissões CAMERA / RECORD_AUDIO em falta.');
    }
  }

  Future<void> _ensureMixerRunning() async {
    if (_mixer != null) return;

    final sources = await HaishinKitPlatformInterface.instance.videoSources;
    if (sources.isEmpty) {
      throw Exception('videoSources vazio (Camera2).');
    }
    final videoSource = sources.firstWhere(
      (s) => s.position == CameraPosition.back,
      orElse: () => sources.first,
    );

    final mixer = await _dbg.guard(
      'MediaMixer.create',
      () => MediaMixer.create(
        options: const MediaMixerOptions(
          captureSessionMode: CaptureSessionMode.single,
        ),
      ),
      rethrowError: true,
    );
    if (mixer == null) throw Exception('MediaMixer.create falhou.');

    mixer.frameRate = _videoFps;
    mixer.videoMixerSettings = const VideoMixerSettings(isMuted: false);
    mixer.screen?.size = ScreenObjectSize(width: _videoW, height: _videoH);
    _applyDebugVideoLabels();

    await _dbg.guard(
      'attachAudio',
      () => mixer.attachAudio(0, AudioSource()),
      rethrowError: true,
    );
    await _dbg.guard(
      'attachVideo',
      () => mixer.attachVideo(0, videoSource),
      rethrowError: true,
    );
    _dbg.markCameraAttached(videoSource.id);

    await _dbg.guard(
      'startRunning',
      () => mixer.startRunning(),
      rethrowError: true,
    );
    _dbg.markEncoderStarted();

    await Future<void>.delayed(const Duration(milliseconds: 1000));
    _mixer = mixer;
  }

  /// Nova sessão com URL Mux real (obrigatório antes de connect).
  /// [useRtmps] null → RTMPS (443), costuma ser mais estável que RTMP:5222 em Android MTK.
  Future<void> _createSessionForStreamKey(
    String streamKey, {
    bool? useRtmps,
    bool showTexture = true,
  }) async {
    final rtmps = useRtmps ?? _forceRtmpsOverride ?? true;
    _muxPublishUsesRtmps = rtmps;
    final url = rtmps ? _muxRtmpsUrl(streamKey) : _muxRtmpUrl(streamKey);
    _sessionUrlHost = rtmps ? 'rtmps:443' : 'rtmp:5222';
    _dbg.log('StreamSession.create → $_sessionUrlHost/app/[stream_key]');
    FleaberLogger.instance.info(
      'live_publish',
      'a criar StreamSession ($_sessionUrlHost)',
    );

    final old = _session;
    if (old != null && _streamKey == streamKey) {
      _dbg.log('sessão já existe para esta stream key — reutilizar');
      await FleaberLogger.instance.uploadStep('streamSession.reuse_existing');
      return;
    }
    _sessionStateSub?.cancel();
    if (old != null) {
      await FleaberLogger.instance.uploadStep('streamSession.old_exists_skip_recreate');
      _dbg.log('sessão antiga ignorada (sem unregister/dispose — evita crash MTK)');
    }

    await FleaberLogger.instance.uploadStep(
      'streamSession.pre_create',
      detail: _sessionUrlHost,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final session = await _dbg.guard(
      'StreamSession.create',
      () => StreamSession.create(url, StreamSessionMode.publish),
      rethrowError: true,
    );
    if (session == null) throw Exception('StreamSession.create falhou.');

    await FleaberLogger.instance.uploadStep(
      'streamSession.post_create',
      detail: 'memory=${session.memory}',
    );

    await _dbg.guard('setVideoSettings', () async {
      session.videoSettings = _currentVideoSettings;
    });
    await _dbg.guard('setSessionFrameRate', () async {
      await _applySessionFrameRate(session);
    });
    await FleaberLogger.instance.uploadStep('streamSession.post_video_settings');

    _listenSessionReady(session);
    _listenNativeDiagnostics(session);

    if (!mounted) return;
    setState(() {
      _session = session;
      _pipelineReady = true;
      _showSessionTexture = showTexture;
      if (showTexture) {
        _textureGeneration++;
        _surfaceLoggedForGen = -1;
      }
    });

    _dbg.previewState = 'textura (updateTexture explícito)';
    _startFrameHintPolling();

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _buildPipelineWithStreamKey(
    String streamKey, {
    bool createSession = true,
  }) async {
    if (_initInProgress) return;

    if (_pipelineReady &&
        _mixer != null &&
        _streamKey == streamKey &&
        (!createSession || _session != null)) {
      _dbg.log('pipeline já ativo — mesma stream key, sem recriar');
      return;
    }

    _initInProgress = true;
    _dbg.previewState = 'a preparar…';

    try {
      await FleaberLogger.instance.uploadStep(
        'pipeline.pre_permissions',
      );
      await _ensurePermissions();

      await FleaberLogger.instance.uploadStep('pipeline.pre_mixer');
      await _ensureMixerRunning();

      if (createSession) {
        await FleaberLogger.instance.uploadStep('pipeline.pre_session');
        await _createSessionForStreamKey(streamKey);
        await FleaberLogger.instance.uploadStep('pipeline.post_session');
        _dbg.log('pipeline pronto — sessão Mux + preview');
      } else {
        if (mounted) {
          setState(() => _pipelineReady = true);
        }
        _dbg.previewState = 'mixer OK — sessão RTMP só no Iniciar';
        await FleaberLogger.instance.uploadStep(
          'pipeline.mixer_only_ok',
          detail: 'liveId=$_liveId',
        );
        _dbg.log('Mux + câmara OK — sem StreamSession (evita crash)');
      }
      await FleaberLogger.instance.flush();
    } catch (e, st) {
      _dbg.error('buildPipelineWithStreamKey', e, st);
      _dbg.previewState = 'erro';
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.buildPipeline',
        error: e,
        stackTrace: st,
        contextLines: _dbg.lines,
      );
    } finally {
      _initInProgress = false;
      if (mounted) setState(() {});
    }
  }

  void _startFrameHintPolling() {
    _frameHintTimer?.cancel();
    var ticks = 0;
    _frameHintTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      ticks++;
      if (!mounted || ticks > 15) {
        t.cancel();
        return;
      }
      if (_pipelineReady && _session != null && !_dbg.firstFrameHint) {
        _dbg.markFirstFrameHint('t+${ticks}s (heurística, não confirma frame real)');
        if (!kReleaseMode) {
          unawaited(
            FleaberLogger.instance.uploadStep(
              'video.heuristic_tick',
              detail: 't+${ticks}s (nao confirma frame real)',
            ),
          );
        }
      }
    });
  }

  Future<void> _connectRtmp() async {
    var session = _session;
    final key = _streamKey;
    if (session == null || key == null || key.isEmpty) {
      throw Exception('Sem sessão ou stream key. Prepara primeiro.');
    }
    if (_dbg.previewOnlyMode) {
      _dbg.log('connect ignorado (previewOnly)');
      return;
    }

    // TCL/MTK: texture activa durante connect() costuma rebentar no nativo.
    if (mounted) {
      setState(() => _showSessionTexture = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    _dbg.rtmpConnectAttempted = true;
    await _dbg.flush();
    await FleaberLogger.instance.flush();
    _dbg.log(
      'pre-connect: sessão memory=${session.memory} urlHost=$_sessionUrlHost',
    );
    FleaberLogger.instance.info(
      'live_publish',
      'RTMP connect memory=${session.memory}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));

    session = _session;
    if (session == null) {
      throw Exception('Sessão perdida antes do connect.');
    }

    try {
      await _dbg.guard(
        'connect RTMP',
        () => session!.connect(),
        rethrowError: true,
      );
    } on StreamSessionConnectFailedException catch (e) {
      final altRtmps = !_muxPublishUsesRtmps;
      _dbg.log(
        'connect falhou ($e) — recriar sessão (${altRtmps ? 'RTMPS' : 'RTMP'})…',
      );
      await _createSessionForStreamKey(
        key,
        useRtmps: altRtmps,
        showTexture: false,
      );
      final session2 = _session;
      if (session2 == null) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _dbg.flush();
      await _dbg.guard(
        'connect retry',
        () => session2.connect(),
        rethrowError: true,
      );
    }

  }

  String _muxApiErrorMessage(Object e) {
    if (e is FunctionException) {
      final details = e.details;
      if (details is Map) {
        final err = details['error']?.toString();
        final step = details['step']?.toString();
        if (err != null && err.isNotEmpty) {
          return step != null ? '$err ($step)' : err;
        }
      }
      return 'create-mux-live HTTP ${e.status}: ${e.reasonPhrase ?? "erro"}';
    }
    return e.toString();
  }

  Future<String> _fetchMuxStreamKey(String title) async {
    try {
      final response = await _dbg.guard(
        'create-mux-live',
        () => SupaFlow.client.functions.invoke(
          'create-mux-live',
          body: {'title': title},
        ),
        rethrowError: true,
      );
      final data = response?.data;
      if (data is! Map) throw Exception('Resposta Mux inválida.');
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty) throw Exception(error);

      final streamKey = data['stream_key']?.toString() ?? '';
      final live = data['live'];
      _liveId = live is Map ? live['id']?.toString() : null;
      if (streamKey.isEmpty) throw Exception('stream_key em falta.');
      _dbg.log('Mux OK live=$_liveId');
      final newLiveId = _liveId?.trim() ?? '';
      final sid = currentUserUid.trim();
      if (newLiveId.isNotEmpty && sid.isNotEmpty) {
        await LiveCatalogPrepService.onMuxLiveCreated(
          newLiveId: newLiveId,
          sellerId: sid,
        );
      }
      await _syncLiveCatalog();
      return streamKey;
    } catch (e, st) {
      final msg = _muxApiErrorMessage(e);
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.create_mux_live',
        error: e,
        stackTrace: st,
        contextLines: _dbg.lines,
      );
      throw Exception(msg);
    }
  }

  Future<void> _prepareCamera() async {
    final title = _titleController.text.trim();
    if (title.length < 3) {
      _showSnack('Título mínimo 3 caracteres.');
      return;
    }
    if (_initInProgress || _starting || _stopping) return;
    setState(() => _starting = true);
    _dbg.lastError = null;
    _dbg.lastStackTrace = null;
    try {
      if (_streamKey != null &&
          _streamKey!.isNotEmpty &&
          _liveId != null &&
          _liveId!.isNotEmpty) {
        await FleaberLogger.instance.uploadStep(
          'prepare.reuse_mux_key',
          detail: 'liveId=$_liveId',
        );
        _dbg.log('reutilizar stream key Mux já criada nesta sessão');
      } else {
        await FleaberLogger.instance.uploadStep('prepare.pre_mux_api');
        _streamKey = await _fetchMuxStreamKey(title);
        await FleaberLogger.instance.uploadStep(
          'prepare.post_mux_api',
          detail: 'liveId=$_liveId',
        );
      }

      if (kPublishUsesLiveKit) {
        await _prepareLocalPreviewOnly();
        await FleaberLogger.instance.uploadStep(
          'prepare.complete',
          detail: 'local_preview_only liveId=$_liveId',
        );
        _showSnack(
          'Câmara OK (preview local). Toca «Iniciar Direto» para emitir.',
        );
        return;
      }

      // Só mixer + Mux — sem StreamSession/textura (evita crash MTK no botão 1).
      await _buildPipelineWithStreamKey(
        _streamKey!,
        createSession: false,
      );
      await FleaberLogger.instance.uploadStep(
        'prepare.complete',
        detail: 'mixer_only liveId=$_liveId',
      );
      _showSnack(
        'Câmara OK (sem RTMP). Toca «Iniciar Direto» para emitir.',
      );
    } catch (e, st) {
      final msg = kPublishUsesLiveKit
          ? _livekitApiErrorMessage(e)
          : _muxApiErrorMessage(e);
      _dbg.error('prepareCamera', e, st);
      _dbg.lastError = msg;
      _showSnack('Falha: $msg');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startLive() async {
    final title = _titleController.text.trim();
    if (title.length < 3) {
      _showSnack('Título mínimo 3 caracteres.');
      return;
    }
    if (_starting || _stopping || _initInProgress) return;

    setState(() => _starting = true);
    _dbg.lastError = null;
    _dbg.lastStackTrace = null;
    try {
      await FleaberLogger.instance.uploadStep('startLive.begin');

      // Botão 2 funciona sozinho: Mux + publish (não depende do 1).
      if (_streamKey == null || _streamKey!.isEmpty) {
        await FleaberLogger.instance.uploadStep('startLive.pre_mux_api');
        _streamKey = await _fetchMuxStreamKey(title);
        await FleaberLogger.instance.uploadStep('startLive.post_mux_api');
      }

      await _syncLiveCatalog();
      if (!await _confirmOpenReservationsBeforeGoLive()) return;

      if (kPublishUsesLiveKit) {
        if (!_dbg.previewOnlyMode) {
          await FleaberLogger.instance.uploadStep('startLive.pre_livekit_publish');
          await _ensureLivekitPipeline(startEgress: true);
          await FleaberLogger.instance.uploadStep('startLive.post_livekit_publish');
          if (!_livekitEgressStarted) {
            throw Exception(
              'Egress Mux não arrancou. Verifica LiveKit no servidor ou tenta outra vez.',
            );
          }
          await _markLiveActiveInDb();
          if (mounted) {
            setState(() {
              _isLive = true;
              _liveStartedAt ??= DateTime.now();
              _publishConnected = true;
            });
          }
          requestLiveFeedRefresh();
          _showSnack('Direto no ar (WebRTC → Mux).');
        } else {
          await _ensureLivekitPipeline(startEgress: false);
          _showSnack('Preview only — egress não iniciado.');
        }
        return;
      }

      if (!_pipelineReady || _mixer == null) {
        await _buildPipelineWithStreamKey(
          _streamKey!,
          createSession: false,
        );
      }

      if (_session == null) {
        await FleaberLogger.instance.uploadStep('startLive.pre_session');
        await _createSessionForStreamKey(
          _streamKey!,
          showTexture: false,
        );
        await FleaberLogger.instance.uploadStep('startLive.post_session');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        _dbg.log(
          'sessão já preparada — a ligar RTMP sem recriar (evita crash)',
        );
        await FleaberLogger.instance.uploadStep('startLive.reuse_session');
      }

      if (!_dbg.previewOnlyMode) {
        await FleaberLogger.instance.uploadStep('startLive.pre_rtmp_connect');
        _startEncoderWatchdog();
        await _connectRtmp();
        await FleaberLogger.instance.uploadStep('startLive.post_rtmp_connect');
        await _markLiveActiveInDb();
        if (mounted) {
          setState(() {
            _isLive = true;
            _liveStartedAt ??= DateTime.now();
          });
        }
        requestLiveFeedRefresh();
        _showSnack('Direto no ar.');
      } else {
        _showSnack('Preview only — RTMP não ligado.');
      }
    } catch (e, st) {
      final msg = kPublishUsesLiveKit
          ? _livekitApiErrorMessage(e)
          : _muxApiErrorMessage(e);
      _dbg.error('startLive', e, st);
      _dbg.lastError = msg;
      _dbg.markRtmpResult(success: false, detail: msg);
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.startLive',
        error: e,
        stackTrace: st,
        contextLines: _dbg.lines,
      );
      _showSnack('Não foi possível iniciar: $msg');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _connectOnly() async {
    if (_streamKey == null || _streamKey!.isEmpty) {
      _showSnack('Aguarda a câmara ou define um título (mín. 3 caracteres).');
      return;
    }
    setState(() => _starting = true);
    try {
      if (_session == null) {
        await _createSessionForStreamKey(_streamKey!);
      }
      await _connectRtmp();
      if (mounted) {
        setState(() {
          _isLive = true;
          _liveStartedAt ??= DateTime.now();
        });
      }
      requestLiveFeedRefresh();
    } catch (e, st) {
      _dbg.error('connectOnly', e, st);
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.connectOnly',
        error: e,
        stackTrace: st,
        contextLines: _dbg.lines,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _requestExitPage() {
    if (_starting || _stopping) return;
    unawaited(_teardownLiveSession(popNavigator: true));
  }

  Future<void> _runLivekitTeardownInBackground({
    required String? liveId,
    required bool wasBroadcasting,
    required LivekitPublishController? lk,
    required bool lkWasConnected,
    required bool localPreviewOnly,
  }) async {
    try {
      await FleaberLogger.instance.uploadStep(
        'live.teardown.background',
        detail: 'liveId=$liveId',
      );

      if (kPublishUsesLiveKit) {
        if (lk != null) {
          await lk.releaseFast(
            wasConnected: lkWasConnected,
            localPreviewOnly: localPreviewOnly,
          );
        }

        if (liveId != null && liveId.isNotEmpty) {
          try {
            await SupaFlow.client.functions.invoke(
              'livekit-mux-publish',
              body: {'step': 'stop_egress', 'live_id': liveId},
            ).timeout(const Duration(seconds: 15));
          } catch (_) {}

          try {
            final completeRes = await SupaFlow.client.functions
                .invoke(
                  'complete-mux-live',
                  body: {'live_id': liveId},
                )
                .timeout(const Duration(seconds: 25));
            final data = completeRes.data;
            await FleaberLogger.instance.event('livekit.mux.complete.response', {
              'live_id': liveId,
              'status': completeRes.status,
              if (data is Map) ...{
                'ok': data['ok'],
                'vod_playback_id': data['vod_playback_id'],
                'mux_asset_id': data['mux_asset_id'],
                'error': data['error'],
                'step': data['step'],
              },
            });
          } catch (e, st) {
            await FleaberLogger.instance.reportFailure(
              category: 'livekit.mux.complete.failed',
              error: e,
              stackTrace: st,
              contextLines: ['live_id=$liveId'],
            );
          }
        }
      }

      if (liveId != null && liveId.isNotEmpty) {
        await _markLiveEndedInDb(liveId);
      }

      await LiveCatalogSync.clearPrepAfterLiveEnd();
      requestLiveFeedRefresh();
      await FleaberLogger.instance.uploadStep('live.teardown.background.done');
    } catch (e, st) {
      await FleaberLogger.instance.reportFailure(
        category: 'live_publish.teardown_background',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _exitPublishScreen(bool popNavigator) {
    if (!popNavigator || !mounted) return;
    requestLiveFeedRefresh();
    context.goNamed(HomePageWidget.routeName);
  }

  void _openArenaAfterLiveEnd(String liveId) {
    if (!mounted) return;
    final id = liveId.trim();
    if (id.isNotEmpty) {
      unawaited(LivePublishCleanup.finalizeEnded(id, runBackendTeardown: false));
    }
    requestLiveFeedRefresh();
    context.pushReplacementNamed(
      FleaberLivePlayerWidget.routeName,
      queryParameters: {
        'liveId': serializeParam(liveId, ParamType.String),
        'isLive': serializeParam(false, ParamType.bool),
        'sellerId': serializeParam(currentUserUid, ParamType.String),
      }.withoutNulls,
    );
  }

  Future<void> _teardownLiveSession({required bool popNavigator}) async {
    final liveId = _liveId?.trim();

    if (_teardownComplete) {
      if (liveId != null && liveId.isNotEmpty) {
        await _markLiveEndedInDb(liveId);
      }
      _exitPublishScreen(popNavigator);
      return;
    }
    if (_stopping) return;

    if (liveId != null && liveId.isNotEmpty) {
      await _markLiveEndedInDb(liveId);
    }
    final wasBroadcasting =
        _isLive || _livekitEgressStarted || _dbg.rtmpConnectAttempted;
    final lk = _lk;
    final lkWasConnected = lk?.isConnected == true;
    final localPreviewOnly = _livekitLocalPreviewOnly;

    _teardownComplete = true;
    _isLive = false;
    _publishConnected = false;
    _livekitEgressStarted = false;
    _livekitLocalPreviewOnly = false;
    _lk = null;

    if (mounted) setState(() {});

    final endedLiveId = liveId ?? '';
    if (!popNavigator && endedLiveId.isNotEmpty) {
      _openArenaAfterLiveEnd(endedLiveId);
    } else {
      _exitPublishScreen(popNavigator);
    }

    unawaited(
      FleaberLogger.instance.uploadStep(
        'live.teardown.begin',
        detail: 'liveId=$liveId pop_first=true',
      ),
    );

    if (kPublishUsesLiveKit) {
      unawaited(
        _runLivekitTeardownInBackground(
          liveId: liveId,
          wasBroadcasting: wasBroadcasting,
          lk: lk,
          lkWasConnected: lkWasConnected,
          localPreviewOnly: localPreviewOnly,
        ),
      );
      return;
    }

    try {
      final id = liveId;
      if (id != null && id.isNotEmpty) {
        try {
          await SupaFlow.client.functions
              .invoke(
                'complete-mux-live',
                body: {'live_id': id},
              )
              .timeout(const Duration(seconds: 25));
        } catch (_) {}
        await _markLiveEndedInDb(id);
      }
      _detachNativeHandlesForStability();
      await LiveCatalogSync.clearPrepAfterLiveEnd();
      requestLiveFeedRefresh();
    } catch (e, st) {
      _dbg.error('teardownLiveSession', e, st);
    }
  }

  void _stopLive() {
    if (!_isLive &&
        !_dbg.rtmpConnectAttempted &&
        !(kPublishUsesLiveKit &&
            (_livekitEgressStarted || _livekitLocalPreviewOnly)) &&
        _liveId == null) {
      return;
    }
    unawaited(_teardownLiveSession(popNavigator: false));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ignore: unused_element — painel debug opcional (não montado no build actual)
  Widget _buildDebugOverlay() {
    final d = _dbg;
    final keyHint = _streamKey != null && _streamKey!.length > 8
        ? '${_streamKey!.substring(0, 4)}…'
        : '—';
    return Positioned(
      left: 8,
      right: 8,
      bottom: 100,
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _debugPanelExpanded = !_debugPanelExpanded),
              onLongPress: () => unawaited(_toggleProtocolOverride()),
              onDoubleTap: () => unawaited(_toggleDiagnosticMode()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'DEBUG PIPELINE',
                      style: GoogleFonts.robotoMono(
                        color: Colors.amber,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _debugPanelExpanded
                          ? Icons.expand_more
                          : Icons.expand_less,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_debugPanelExpanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip('cam', d.cameraState),
                    _chip('enc', d.encoderState),
                    _chip('prev', d.previewState),
                    _chip('key', keyHint),
                    _chip('url', _sessionUrlHost ?? _livekitRoomName ?? '—'),
                    _chip(
                      'pub',
                      kPublishUsesLiveKit ? 'LiveKit' : 'Haishin',
                    ),
                    _chip('proto', _protocolModeLabel()),
                    _chip('diag', _diagnosticMode ? 'ON' : 'OFF'),
                    _chip(
                      'RTMP',
                      d.rtmpConnectAttempted
                          ? (d.rtmpConnected ? 'OK' : 'FAIL')
                          : '—',
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                title: Text(
                  'Só preview (sem RTMP)',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                ),
                value: d.previewOnlyMode,
                activeThumbColor: _kTeal,
                onChanged: (v) {
                  d.previewOnlyMode = v;
                  d.log('previewOnlyMode=$v');
                  setState(() {});
                },
              ),
              if (_diagnosticMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                  child: Text(
                    'Diag ativo: preview puro, 854x480, 15fps, 400kbps, Baseline.',
                    style: GoogleFonts.robotoMono(
                      color: Colors.orange.shade200,
                      fontSize: 9,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'surface=${d.surfaceCreated} encoder=${d.encoderStarted} '
                  'frameHint=${d.firstFrameHint}',
                  style: GoogleFonts.robotoMono(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  itemCount: d.lines.length,
                  itemBuilder: (_, i) => Text(
                    d.lines[d.lines.length - 1 - i],
                    style: GoogleFonts.robotoMono(
                      color: Colors.white60,
                      fontSize: 9,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 9),
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (kPublishUsesLiveKit) {
      final lkTrack = _lk?.localVideoTrack;
      if (_initInProgress && !_pipelineReady) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      if (_pipelineReady && lkTrack != null) {
        return LivekitPreviewTexture(
          key: ValueKey(lkTrack.mediaStreamTrack.id),
          track: lkTrack,
        );
      }
      if (_pipelineReady) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF007782), size: 56),
                const SizedBox(height: 16),
                Text(
                  'Mux + LiveKit prontos',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A aguardar vídeo da câmara…\nToca «Iniciar Direto» para emitir.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'A preparar a câmara…\nToca «Iniciar Direto» quando estiveres pronto.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
          ),
        ),
      );
    }

    if (_initInProgress && !_pipelineReady) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_pipelineReady && _mixer != null && _session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF007782), size: 56),
              const SizedBox(height: 16),
              Text(
                'Mux + câmara prontos',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Câmara + Mux prontos.\nToca «Iniciar Direto» para emitir.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final session = _session;
    if (_pipelineReady && session != null) {
      if (!_showSessionTexture) {
        return const SizedBox.shrink();
      }
      return HaishinPreviewTexture(
        key: ValueKey<int>(_textureGeneration),
        session: session,
        videoGravity: VideoGravity.resizeAspectFill,
        onTextureReady: (id) {
          if (_surfaceLoggedForGen == _textureGeneration) return;
          _surfaceLoggedForGen = _textureGeneration;
          _dbg.markSurfaceCreated(id);
        },
        onTextureFailed: () {
          _dbg.log(
            'texture falhou após retries — RTMP pode ter vídeo mesmo com preview preto',
          );
          _dbg.previewState = 'texture FAILED';
        },
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:               Text(
                'Toca «Iniciar Direto» para começar.\n'
                'A câmara arranca ao abrir esta página.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final err = _dbg.lastError;

    if (_purePreviewMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _requestExitPage();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoLayer(),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => unawaited(_toggleDiagnosticMode()),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestExitPage();
      },
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildVideoLayer(),
              if (err != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                    ),
                    color: Colors.red.shade900.withValues(alpha: 0.92),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        err,
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              // O painel abaixo já mostra “LIVE” com duração; este chip só faz sentido sem painel.
              if (_isLive && (_liveId == null || _liveId!.trim().isEmpty))
                Positioned(
                  top: err != null ? 100 : 72,
                  left: 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: FleaberColors.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _publishConnected
                          ? 'LIVE'
                          : (kPublishUsesLiveKit ? 'WebRTC…' : 'RTMP…'),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              if (!_isLive)
                Positioned(
                  top: err != null ? 48 : 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _starting || _stopping
                            ? null
                            : _requestExitPage,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          enabled: !_starting,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Título do Direto',
                            hintStyle: GoogleFonts.inter(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.45),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_stopping)
                const Positioned.fill(
                  child: ColoredBox(color: Colors.transparent),
                ),
              if (_isLive &&
                  _liveId != null &&
                  _liveId!.trim().isNotEmpty) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: err != null ? 200 : 140,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.black.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                          child: LiveVendorBroadcastHeader(
                            liveId: _liveId!.trim(),
                            sellerId: currentUserUid,
                            startedAt: _liveStartedAt,
                            leading: IconButton(
                              onPressed:
                                  _stopping ? null : _requestExitPage,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            title: _titleController.text.trim().isEmpty
                                ? 'O meu direto'
                                : _titleController.text.trim(),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                            child: LiveVendorStudioPanel(
                              key: _studioPanelKey,
                              liveId: _liveId!.trim(),
                              sellerId: currentUserUid,
                              startedAt: _liveStartedAt,
                              catalogItemCount: _catalogItemCount,
                              hideTopChrome: true,
                              viewerStyleLayout: true,
                              sellerOverlayLayout: true,
                              showTopNav: true,
                              privateChatMode: _sellerPrivateChatMode,
                              onPrivateChatModeChanged: (v) {
                                if (_sellerPrivateChatMode == v) return;
                                setState(() => _sellerPrivateChatMode = v);
                              },
                              onPrivateUnreadChanged: (n) {
                                if (_sellerPrivateUnread == n) return;
                                setState(() => _sellerPrivateUnread = n);
                              },
                              onOpsTotalsChanged: (totals) {
                                if (_opsQueueBadge == totals.queuePending) {
                                  return;
                                }
                                setState(
                                  () => _opsQueueBadge = totals.queuePending,
                                );
                              },
                              activePanel: _activeSellerPanel,
                              onActivePanelChanged: (panel) {
                                if (_activeSellerPanel == panel) return;
                                setState(() => _activeSellerPanel = panel);
                              },
                              onMoreTap: () =>
                                  _studioPanelKey.currentState?.showMoreMenu(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: _stopping ? null : () => _stopLive(),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Colors.white.withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                'Terminar directo',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isLive)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _starting || _stopping
                              ? null
                              : () => unawaited(_startLive()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FleaberColors.danger,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            _dbg.previewOnlyMode
                                ? 'Iniciar (só preview)'
                                : 'Iniciar Direto',
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    if (_pipelineReady && !_isLive) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: TextButton(
                          onPressed: _starting
                              ? null
                              : () => unawaited(_connectOnly()),
                          child: const Text(
                            'Ligar RTMP (sessão já preparada)',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
