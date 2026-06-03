import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fleaber/utils/fleaber_live_capture.dart';
import 'package:fleaber/utils/fleaber_logger.dart';
import 'package:fleaber/utils/live_publish_config.dart';
import 'package:livekit_client/livekit_client.dart';

/// Publicação WebRTC (LiveKit) — preview local sem room; connect só ao ir live.
class LivekitPublishController {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LocalVideoTrack? _preparedVideoTrack;
  LocalAudioTrack? _preparedAudioTrack;
  DateTime? _connectedAt;

  Room? get room => _room;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  bool get hasLocalPreview => _preparedVideoTrack != null;

  Duration? get connectedDuration =>
      _connectedAt == null ? null : DateTime.now().difference(_connectedAt!);

  /// Track da câmara para o ecrã do vendedor — após connect usar a publicada na room.
  LocalVideoTrack? get localVideoTrack {
    final participant = _room?.localParticipant;
    if (participant != null && isConnected) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.source != TrackSource.camera || pub.muted) continue;
        final track = pub.track;
        if (track is LocalVideoTrack) return track;
      }
    }
    return _preparedVideoTrack;
  }

  /// SIDs das tracks publicadas (para TrackComposite egress no servidor).
  ({String? videoTrackId, String? audioTrackId}) get publishedTrackSids {
    final lp = _room?.localParticipant;
    if (lp == null) return (videoTrackId: null, audioTrackId: null);
    String? videoSid;
    String? audioSid;
    for (final pub in lp.videoTrackPublications) {
      if (pub.source != TrackSource.camera || pub.muted || pub.track == null) {
        continue;
      }
      videoSid = pub.sid;
      break;
    }
    for (final pub in lp.audioTrackPublications) {
      if (pub.source != TrackSource.microphone || pub.muted || pub.track == null) {
        continue;
      }
      audioSid = pub.sid;
      break;
    }
    return (videoTrackId: videoSid, audioTrackId: audioSid);
  }

  /// Preview local apenas — sem token, sem Room.connect (zero minutos LiveKit).
  Future<void> startLocalPreview() async {
    if (_preparedVideoTrack != null) return;
    await _createLocalTracks();
    await _logCameraCapture();
    unawaited(
      FleaberLogger.instance.event('livekit.local_preview.start', const {}),
    );
  }

  /// Liga à room — recria tracks se vierem do preview local (evita NegotiationError MTK).
  Future<void> connect({
    required String url,
    required String token,
  }) async {
    if (isConnected) return;

    final hadLocalPreview = _preparedVideoTrack != null;
    if (hadLocalPreview) {
      await _stopPreparedTracks();
    }
    await _createLocalTracks();

    final videoTrack = _preparedVideoTrack!;
    final audioTrack = _preparedAudioTrack!;

    final room = Room(roomOptions: FleaberLiveCapture.roomOptions);
    _listener = room.createListener();
    _listener!.on<RoomDisconnectedEvent>((_) {
      unawaited(
        FleaberLogger.instance.event('livekit.room.disconnected', {
          'duration_sec': connectedDuration?.inSeconds,
        }),
      );
    });

    unawaited(
      FleaberLogger.instance.event('livekit.room.connect.begin', {
        'url_host': Uri.tryParse(url)?.host,
        'recreated_tracks_after_preview': hadLocalPreview,
      }),
    );

    try {
      await room.connect(
        url,
        token,
        connectOptions: const ConnectOptions(
          autoSubscribe: false,
        ),
        fastConnectOptions: FastConnectOptions(
          camera: TrackOption(track: videoTrack),
          microphone: TrackOption(track: audioTrack),
        ),
      );
    } catch (e, st) {
      await _stopPreparedTracks();
      try {
        await room.dispose();
      } catch (_) {}
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'livekit.room.connect',
          error: e,
          stackTrace: st,
        ),
      );
      rethrow;
    }
    _room = room;
    _connectedAt = DateTime.now();

    unawaited(
      FleaberLogger.instance.event('livekit.room.connect.done', const {}),
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _logCameraCapture();
  }

  Future<void> enableCameraAndMic() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;

    // fastConnect já publicou tracks — novo setCameraEnabled gera renegotiation (MTK).
    if (_preparedVideoTrack != null && isConnected) {
      return;
    }
    await lp.setCameraEnabled(false);
    await lp.setCameraEnabled(
      true,
      cameraCaptureOptions: FleaberLiveCapture.muxCameraOptions,
    );
    await lp.setMicrophoneEnabled(true);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _logCameraCapture();
  }

  Future<void> _createLocalTracks() async {
    final cameraOptions = await FleaberLiveCapture.resolveMuxCameraOptions();
    final videoTrack = await LocalVideoTrack.createCameraTrack(cameraOptions);
    await videoTrack.start();
    await _ensureMuxCaptureOrientation(videoTrack, cameraOptions);
    final audioTrack = await LocalAudioTrack.create(
      FleaberLiveCapture.audioOptions,
    );
    await audioTrack.start();
    _preparedVideoTrack = videoTrack;
    _preparedAudioTrack = audioTrack;
  }

  Future<void> _ensureMuxCaptureOrientation(
    LocalVideoTrack videoTrack,
    CameraCaptureOptions options,
  ) async {
    if (kLivekitMuxLandscapeEncode) {
      await _ensureLandscapeCapture(videoTrack, options);
    } else {
      await _ensurePortraitCapture(videoTrack, options);
    }
  }

  /// Se o WebRTC reportar landscape, reinicia a track com a app já em portrait.
  Future<void> _ensurePortraitCapture(
    LocalVideoTrack videoTrack,
    CameraCaptureOptions options,
  ) async {
    var dims = FleaberLiveCapture.readWebRtcDimensions(videoTrack);
    if (dims.portrait) return;

    unawaited(
      FleaberLogger.instance.event('live.publish.camera.restart_portrait', {
        'webrtc_width': dims.width,
        'webrtc_height': dims.height,
        'requested': '720x1280',
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await videoTrack.restartTrack(options);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      dims = FleaberLiveCapture.readWebRtcDimensions(videoTrack);
      if (!dims.portrait) {
        unawaited(
          FleaberLogger.instance.event('live.publish.camera.landscape_buffer', {
            'webrtc_width': dims.width,
            'webrtc_height': dims.height,
            'note':
                'Sensor WebRTC em landscape; egress preset 4 deve aplicar rotação.',
          }),
        );
      }
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'live.publish.camera.restart_portrait',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  /// Pipeline landscape→Mux: manter buffer WebRTC com width >= height.
  Future<void> _ensureLandscapeCapture(
    LocalVideoTrack videoTrack,
    CameraCaptureOptions options,
  ) async {
    var dims = FleaberLiveCapture.readWebRtcDimensions(videoTrack);
    if (!dims.portrait) return;

    unawaited(
      FleaberLogger.instance.event('live.publish.camera.restart_landscape', {
        'webrtc_width': dims.width,
        'webrtc_height': dims.height,
        'requested': '1280x720',
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await videoTrack.restartTrack(options);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      dims = FleaberLiveCapture.readWebRtcDimensions(videoTrack);
      if (dims.portrait) {
        unawaited(
          FleaberLogger.instance.event('live.publish.camera.portrait_buffer', {
            'webrtc_width': dims.width,
            'webrtc_height': dims.height,
            'note':
                'Sensor ainda portrait após pedir 1280×720; testar na mesma.',
          }),
        );
      }
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'live.publish.camera.restart_landscape',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<void> _logCameraCapture() async {
    final track = localVideoTrack;
    final dims = track?.currentOptions.params.dimensions;
    final device = await _deviceSummary();
    final webrtc = track != null
        ? FleaberLiveCapture.readWebRtcDimensions(track)
        : null;
    final lp = _room?.localParticipant;
    VideoDimensions? pubDims;
    if (lp != null) {
      for (final pub in lp.videoTrackPublications) {
        if (pub.source == TrackSource.camera) {
          pubDims = pub.dimensions;
          break;
        }
      }
    }
    final trackSids = publishedTrackSids;
    final payload = <String, dynamic>{
      'mux_pipeline': kLivekitMuxLandscapeEncode
          ? 'landscape_encode'
          : 'portrait_encode',
      if (dims != null) ...{
        'requested_width': dims.width,
        'requested_height': dims.height,
        'portrait_requested': dims.height > dims.width,
      },
      if (webrtc != null) ...{
        'webrtc_width': webrtc.width,
        'webrtc_height': webrtc.height,
        'portrait_webrtc': webrtc.portrait,
      },
      if (pubDims != null) ...{
        'lk_pub_width': pubDims.width,
        'lk_pub_height': pubDims.height,
        'lk_pub_portrait': pubDims.height > pubDims.width,
      },
      if (trackSids.videoTrackId != null)
        'video_track_id': trackSids.videoTrackId,
      if (trackSids.audioTrackId != null)
        'audio_track_id': trackSids.audioTrackId,
      if (device != null) ...device,
      'fast_connect': _preparedVideoTrack != null,
      'room_connected': isConnected,
    };
    if (track != null) {
      try {
        final settings = track.mediaStreamTrack.getSettings();
        if (settings.isNotEmpty) {
          payload['webrtc_settings'] = settings;
        }
      } catch (_) {}
    }
    if (payload.isNotEmpty) {
      unawaited(FleaberLogger.instance.event('live.publish.camera', payload));
    }
  }

  Future<Map<String, String>?> _deviceSummary() async {
    try {
      if (!Platform.isAndroid) return null;
      final info = await DeviceInfoPlugin().androidInfo;
      return {
        'device_brand': info.brand,
        'device_model': info.model,
        'device_manufacturer': info.manufacturer,
        'android_sdk': '${info.version.sdkInt}',
      };
    } catch (_) {
      return null;
    }
  }

  /// Para preview local quando nunca houve connect à room.
  Future<void> stopLocalPreview() async {
    if (isConnected) {
      await disconnect();
      return;
    }
    await _stopPreparedTracks();
    unawaited(
      FleaberLogger.instance.event('livekit.local_preview.stop', const {}),
    );
  }

  Future<void> _stopPreparedTracks() async {
    final video = _preparedVideoTrack;
    final audio = _preparedAudioTrack;
    _preparedVideoTrack = null;
    _preparedAudioTrack = null;
    try {
      await video?.stop();
    } catch (_) {}
    try {
      await audio?.stop();
    } catch (_) {}
  }

  /// Libertação rápida ao sair do directo — não bloqueia a UI à espera do SDK.
  Future<void> releaseFast({
    required bool wasConnected,
    required bool localPreviewOnly,
  }) async {
    final durationSec = connectedDuration?.inSeconds;
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _connectedAt = null;

    try {
      await _stopPreparedTracks().timeout(const Duration(seconds: 2));
    } catch (_) {}

    if (room == null) {
      if (localPreviewOnly) {
        unawaited(
          FleaberLogger.instance.event('livekit.local_preview.stop', const {}),
        );
      }
      return;
    }

    unawaited(
      FleaberLogger.instance.event('livekit.room.disconnect.begin', {
        if (durationSec != null) 'duration_sec': durationSec,
        'fast_release': true,
      }),
    );

    unawaited(() async {
      try {
        if (wasConnected) {
          await room.disconnect().timeout(const Duration(seconds: 2));
        }
      } catch (_) {}
      try {
        await room.dispose().timeout(const Duration(seconds: 1));
      } catch (_) {}
      unawaited(
        FleaberLogger.instance.event('livekit.room.disconnect.done', {
          if (durationSec != null) 'duration_sec': durationSec,
          'fast_release': true,
        }),
      );
    }());
  }

  Future<void> disconnect() async {
    await releaseFast(
      wasConnected: isConnected,
      localPreviewOnly: !isConnected && hasLocalPreview,
    );
  }
}
