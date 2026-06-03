import 'package:livekit_client/livekit_client.dart';

import 'live_publish_config.dart';

/// Parâmetros de captura para diretos mobile (9:16, câmara frontal).
/// Alinhado com Facebook Live mobile: 720×1280, 30 fps, bitrate alto de teste.
///
/// Em TCL/MTK com [kLivekitMuxLandscapeEncode], pedimos 1280×720 e egress
/// landscape (preset 0); o player roda 90° quando `width > height`.
abstract final class FleaberLiveCapture {
  /// 720×1280 portrait — resolução típica FB Live no telemóvel.
  static const VideoParameters portrait720 = VideoParameters(
    dimensions: VideoDimensions(720, 1280),
    encoding: VideoEncoding(
      // Modo de teste: aproxima qualidade visual ao FB Live em boa rede.
      maxBitrate: 8000000,
      maxFramerate: 30,
    ),
  );

  /// 1280×720 landscape — buffer nativo MTK antes do egress (Android experiment).
  static const VideoParameters landscape720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(
      maxBitrate: 8000000,
      maxFramerate: 30,
    ),
  );

  static const AudioCaptureOptions audioOptions = AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
  );

  /// Opções base portrait — usar [resolveMuxCameraOptions] no fluxo LiveKit.
  static const CameraCaptureOptions cameraOptions = CameraCaptureOptions(
    cameraPosition: CameraPosition.front,
    params: portrait720,
    maxFrameRate: 30,
    focusMode: CameraFocusMode.auto,
    exposureMode: CameraExposureMode.auto,
  );

  static const CameraCaptureOptions landscapeCameraOptions = CameraCaptureOptions(
    cameraPosition: CameraPosition.front,
    params: landscape720,
    maxFrameRate: 30,
    // TCL/MTK: auto → NPE em CameraUtils.setFocusPoint (app_logs).
    focusMode: CameraFocusMode.locked,
    exposureMode: CameraExposureMode.locked,
  );

  static VideoParameters get muxVideoParams =>
      kLivekitMuxLandscapeEncode ? landscape720 : portrait720;

  static CameraCaptureOptions get muxCameraOptions =>
      kLivekitMuxLandscapeEncode ? landscapeCameraOptions : cameraOptions;

  /// Câmara frontal + params do pipeline Mux activo (portrait ou landscape).
  static Future<CameraCaptureOptions> resolveMuxCameraOptions() async {
    if (kLivekitMuxLandscapeEncode) {
      return _resolveCameraOptionsWithDevice(landscapeCameraOptions);
    }
    return resolvePortraitCameraOptions();
  }

  /// Câmara frontal explícita + 720×1280 (melhor que só facingMode em OEMs).
  static Future<CameraCaptureOptions> resolvePortraitCameraOptions() async {
    return _resolveCameraOptionsWithDevice(cameraOptions);
  }

  static Future<CameraCaptureOptions> _resolveCameraOptionsWithDevice(
    CameraCaptureOptions base,
  ) async {
    try {
      final inputs = await Hardware.instance.videoInputs();
      MediaDevice? front;
      for (final d in inputs) {
        final label = d.label.toLowerCase();
        if (label.contains('front') ||
            label.contains('frente') ||
            label.contains('user')) {
          front = d;
          break;
        }
      }
      front ??= inputs.isNotEmpty ? inputs.first : null;
      if (front != null && front.deviceId.isNotEmpty) {
        return base.copyWith(deviceId: front.deviceId);
      }
    } catch (_) {}
    return base;
  }

  /// Lê dimensões reais do WebRTC (pode diferir dos params pedidos).
  static ({int? width, int? height, bool portrait}) readWebRtcDimensions(
    LocalVideoTrack track,
  ) {
    try {
      final settings = track.mediaStreamTrack.getSettings();
      final w = settings['width'];
      final h = settings['height'];
      if (w is num && h is num && w > 0 && h > 0) {
        final wi = w.toInt();
        final hi = h.toInt();
        return (width: wi, height: hi, portrait: hi > wi);
      }
    } catch (_) {}
    final dims = track.currentOptions.params.dimensions;
    return (
      width: dims.width,
      height: dims.height,
      portrait: dims.height > dims.width,
    );
  }

  static const VideoPublishOptions publishOptions = VideoPublishOptions(
    videoEncoding: VideoEncoding(
      maxBitrate: 8000000,
      maxFramerate: 30,
    ),
    simulcast: false,
  );

  static const RoomOptions roomOptions = RoomOptions(
    adaptiveStream: false,
    dynacast: false,
    defaultCameraCaptureOptions: cameraOptions,
    defaultVideoPublishOptions: publishOptions,
  );
}
