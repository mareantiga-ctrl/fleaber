import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_publish_config.dart';
import '/utils/mux_urls.dart';
import '/widgets/mux_web_hls_stub.dart'
    if (dart.library.html) '/widgets/mux_web_hls_web.dart';

/// Player HLS Mux — leve, ecrã cheio com [BoxFit.cover].
class MuxHlsPlayer extends StatefulWidget {
  const MuxHlsPlayer({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.liveId,
    this.fit = BoxFit.cover,
    this.looping = true,
    this.isRecording = false,
    this.onLivePlaybackFailed,
    this.muxLandscapePlayback = false,
    this.vodControlsBottomInset = 0,
    this.vodControlsAtTop = false,
    this.vodControlsTopInset = 0,
    this.onPlaybackTick,
  });

  final String url;
  final String? thumbnailUrl;
  final String? liveId;
  final BoxFit fit;
  final bool looping;
  /// false = direto ao vivo (Mux demora 15–45 s após egress).
  final bool isRecording;
  /// Se o HLS live falhar, tenta obter URL VOD (gravação).
  final Future<String?> Function()? onLivePlaybackFailed;

  /// Lives `livekit_mux_landscape` — rotação HLS oposta ao preview local.
  final bool muxLandscapePlayback;

  /// Espaço reservado em baixo (ex.: carrossel) para a barra VOD não ficar tapada.
  final double vodControlsBottomInset;

  /// Barra de tempo VOD no topo (por baixo do header do directo).
  final bool vodControlsAtTop;

  /// Offset desde o topo do ecrã até à barra (safe area + header).
  final double vodControlsTopInset;

  /// Posição do vídeo (gravação) — sincronizar chat replay.
  final void Function(Duration position, Duration duration)? onPlaybackTick;

  @override
  State<MuxHlsPlayer> createState() => _MuxHlsPlayerState();
}

class _MuxHlsPlayerState extends State<MuxHlsPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _waiting = true;
  String? _statusMessage;
  int _attempt = 0;
  bool _loggedMeta = false;
  bool _vodFallbackTried = false;
  bool _codecFailureSeen = false;
  String? _activeUrl;
  bool _activeIsRecording = false;
  bool _vodControlsVisible = false;
  Timer? _vodControlsHideTimer;
  bool _vodDragging = false;

  bool get _isLive => !_activeIsRecording;

  int get _maxAttempts => _isLive ? 12 : 15;

  Duration get _initTimeout => Duration(seconds: _isLive ? 12 : 14);

  Duration _retryDelay(int attempt) {
    if (widget.isRecording) return Duration(seconds: attempt.clamp(1, 3));
    if (attempt <= 2) return const Duration(seconds: 2);
    if (attempt <= 5) return const Duration(seconds: 4);
    return const Duration(seconds: 5);
  }

  bool get _androidCompat =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _isCodecError(Object e) {
    final s = e.toString();
    return s.contains('MediaCodecVideoRenderer') ||
        s.contains('MediaCodec') ||
        s.contains('Decoder failed');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeUrl = widget.url;
    _activeIsRecording = widget.isRecording;
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // Lab/web: pausar HLS quando o separador/iframe não está activo — evita
    // queimar minutos Mux com o player «escondido» noutro ecrã do Fleaber.
    if (state == AppLifecycleState.resumed) {
      if (_isLive || widget.looping) {
        unawaited(c.play());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(c.pause());
    }
  }

  @override
  void didUpdateWidget(covariant MuxHlsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.isRecording != widget.isRecording) {
      _activeUrl = widget.url;
      _activeIsRecording = widget.isRecording;
      _vodFallbackTried = false;
      _codecFailureSeen = false;
      _disposeController();
      _ready = false;
      _waiting = true;
      _statusMessage = null;
      _attempt = 0;
      _loggedMeta = false;
      _init();
    }
  }

  Future<void> _init() async {
    final url = (_activeUrl ?? widget.url).trim();
    if (url.isEmpty) return;

    // Chrome/Edge desktop: video_player não toca HLS — player Mux (web).
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _ready = true;
          _waiting = false;
          _statusMessage = null;
        });
      }
      unawaited(
        FleaberLogger.instance.event('video.playback.ready', {
          'url': url,
          'live_id': widget.liveId,
          'is_recording': widget.isRecording,
          'is_live': _isLive,
          'web_mux_player': true,
        }),
      );
      return;
    }

    if (_isLive) {
      if (mounted) {
        setState(() {
          _waiting = true;
          _statusMessage = 'A preparar sinal do direto…';
        });
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
    }

    // MERDA.md: qualidade vem do encode Mux; no player tentamos sempre alta
    // qualidade primeiro — caps 480/360 só após falha de codec/dispositivo.
    final urlsToTry = MuxUrls.playbackUrlsForDevice(
      primaryUrl: url,
      isRecording: widget.isRecording,
      androidLowEndCompat: _androidCompat && _codecFailureSeen,
    );

    for (var urlIndex = 0; urlIndex < urlsToTry.length && mounted; urlIndex++) {
      final tryUrl = urlsToTry[urlIndex];
      final perUrlAttempts = urlIndex == 0 ? 3 : 2;

      for (var i = 0; i < perUrlAttempts && _attempt < _maxAttempts && mounted; i++) {
        _attempt++;
        if (mounted) {
          setState(() {
            _waiting = true;
            _statusMessage = _attempt > 1 || _isLive
                ? _isLive
                    ? 'A ligar ao direto… (${_attempt}/$_maxAttempts)'
                    : 'A preparar gravação… (${_attempt}/$_maxAttempts)'
                : null;
          });
        }

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(tryUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
        _controller = controller;

        try {
          await controller.initialize().timeout(
            _initTimeout,
            onTimeout: () => throw TimeoutException('playback timeout'),
          );
          await controller.setVolume(1.0);
          await controller.setLooping(widget.looping);
          await controller.play();
          _activeUrl = tryUrl;
          _logPlaybackMetaOnce(controller);
          controller.addListener(_onVideoTick);
          if (!mounted) return;
          setState(() {
            _ready = true;
            _waiting = false;
            _statusMessage = null;
            if (widget.isRecording) {
              _vodControlsVisible = true;
            }
          });
          if (widget.isRecording) {
            _scheduleHideVodControls();
          }
          if (urlIndex > 0) {
            unawaited(
              FleaberLogger.instance.event('video.playback.fallback.success', {
                'live_id': widget.liveId,
                'url': tryUrl,
                'primary_url': url,
              }),
            );
          }
          return;
        } catch (e) {
          if (_isCodecError(e)) _codecFailureSeen = true;
          unawaited(
            FleaberLogger.instance.event('video.playback.init_error', {
              'live_id': widget.liveId,
              'url': tryUrl,
              'attempt': _attempt,
              'codec_error': _isCodecError(e),
              'error': e.toString(),
            }),
          );
          await controller.dispose();
          _controller = null;
          if (_isCodecError(e)) break;
          if (_attempt < _maxAttempts && mounted) {
            await Future<void>.delayed(_retryDelay(_attempt));
          }
        }
      }
    }

    if (!mounted) return;
    if (!_vodFallbackTried && widget.onLivePlaybackFailed != null) {
      _vodFallbackTried = true;
      unawaited(
        FleaberLogger.instance.event('video.playback.fallback.begin', {
          'live_id': widget.liveId,
          'failed_url': url,
          'was_live_mode': _isLive,
        }),
      );
      final vodUrl = await widget.onLivePlaybackFailed!();
      if (vodUrl != null && vodUrl.trim().isNotEmpty && mounted) {
        unawaited(
          FleaberLogger.instance.event('video.playback.fallback.done', {
            'live_id': widget.liveId,
            'vod_url': vodUrl,
          }),
        );
        _activeUrl = vodUrl.trim();
        _activeIsRecording = true;
        _attempt = 0;
        _loggedMeta = false;
        await _init();
        return;
      }
      unawaited(
        FleaberLogger.instance.event('video.playback.fallback.empty', {
          'live_id': widget.liveId,
          'failed_url': url,
        }),
      );
    }
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _ready = false;
      _statusMessage = _codecFailureSeen
          ? 'Não foi possível reproduzir neste telemóvel. '
              'Liberta espaço de armazenamento (telefone cheio bloqueia o vídeo) '
              'e toca «Tentar outra vez».'
          : widget.isRecording
              ? 'Gravação indisponível. Tenta daqui a um minuto.'
              : 'Sinal ainda a chegar. Toca «Tentar outra vez».';
    });
    unawaited(
      FleaberLogger.instance.event(
        'video.playback.failed',
        {
          'url': url,
          'live_id': widget.liveId,
          'is_recording': widget.isRecording,
          'is_live': _isLive,
          'attempts': _attempt,
        },
      ),
    );
  }

  void _retry() {
    _disposeController();
    _ready = false;
    _waiting = true;
    _statusMessage = null;
    _attempt = 0;
    _loggedMeta = false;
    _vodFallbackTried = false;
    _codecFailureSeen = false;
    _activeUrl = widget.url;
    _activeIsRecording = widget.isRecording;
    _init();
  }

  void _logPlaybackMetaOnce(VideoPlayerController controller) {
    if (_loggedMeta) return;
    _loggedMeta = true;
    final size = controller.value.size;
    final rot = controller.value.rotationCorrection;
    unawaited(
      FleaberLogger.instance.event(
        'video.playback.ready',
        {
          'url': widget.url,
          'live_id': widget.liveId,
          'is_recording': widget.isRecording,
          'is_live': _isLive,
          'width': size.width,
          'height': size.height,
          'aspect': size.height > 0 ? size.width / size.height : null,
          'portrait_meta': size.height > size.width,
          'rotation_correction': rot,
          'aspect_ratio': controller.value.aspectRatio,
          'manual_quarter_turns': _manualQuarterTurns(controller),
        },
      ),
    );
  }

  /// Dimensões do decoder; valores por defeito portrait 9:16.
  (double w, double h) _videoDimensions(VideoPlayerController controller) {
    var w = controller.value.size.width;
    var h = controller.value.size.height;
    if (w <= 0 || h <= 0) {
      w = 720;
      h = 1280;
    }
    return (w, h);
  }

  /// Rotação manual só quando o decoder não traz tag e os pixels vêm em landscape.
  /// O widget [VideoPlayer] já aplica [VideoPlayerValue.rotationCorrection].
  int _manualQuarterTurns(VideoPlayerController controller) {
    final (w, h) = _videoDimensions(controller);
    if (w <= 0 || h <= 0) return 0;
    final rot = controller.value.rotationCorrection % 360;
    // Stream landscape (egress 1280×720) → portrait; sentido depende do pipeline.
    if (w > h && (rot == 0 || rot == 180)) {
      return widget.muxLandscapePlayback
          ? kMuxLandscapePlaybackQuarterTurns
          : 1;
    }
    return 0;
  }

  /// Ecrã cheio 9:16 — rotação se landscape; sem zoom artificial.
  Widget _buildFullScreenVideo(VideoPlayerController controller) {
    final manualTurns = _manualQuarterTurns(controller);
    final (w, h) = _videoDimensions(controller);
    final swapDims = manualTurns == 1 || manualTurns == 3;
    final boxW = swapDims ? h : w;
    final boxH = swapDims ? w : h;

    Widget video = VideoPlayer(controller);
    if (manualTurns != 0) {
      video = RotatedBox(
        quarterTurns: manualTurns,
        child: SizedBox(width: boxW, height: boxH, child: video),
      );
    } else {
      video = SizedBox(width: boxW, height: boxH, child: video);
    }

    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          alignment: Alignment.center,
          child: video,
        ),
      ),
    );
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.isRecording && widget.onPlaybackTick != null) {
      widget.onPlaybackTick!(c.value.position, c.value.duration);
    }
    if (!mounted || _vodDragging) return;
    if (_vodControlsVisible) setState(() {});
  }

  void _toggleVodControls() {
    if (!widget.isRecording) return;
    setState(() => _vodControlsVisible = !_vodControlsVisible);
    _scheduleHideVodControls();
  }

  void _scheduleHideVodControls() {
    _vodControlsHideTimer?.cancel();
    if (!_vodControlsVisible) return;
    _vodControlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_vodDragging) {
        setState(() => _vodControlsVisible = false);
      }
    });
  }

  Future<void> _seekRelative(Duration delta) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration;
    var target = c.value.position + delta;
    if (target.isNegative) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    await c.seekTo(target);
    _scheduleHideVodControls();
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    _scheduleHideVodControls();
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Widget _buildVodControls(VideoPlayerController controller) {
    final pos = controller.value.position;
    final dur = controller.value.duration;
    final totalMs = dur.inMilliseconds.clamp(1, 1 << 31);
    final value = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final mq = MediaQuery.paddingOf(context);
    final atTop = widget.vodControlsAtTop;
    final edge = atTop
        ? widget.vodControlsTopInset + mq.top
        : widget.vodControlsBottomInset + mq.bottom;

    return Positioned(
      left: 0,
      right: 0,
      top: atTop ? edge + 4 : null,
      bottom: atTop ? null : edge + 8,
      child: AnimatedOpacity(
        opacity: _vodControlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_vodControlsVisible,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: const Color(0xFF00A3AD),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    onChangeStart: (_) {
                      _vodDragging = true;
                      _vodControlsHideTimer?.cancel();
                    },
                    onChanged: (v) {
                      final ms = (v * totalMs).round();
                      controller.seekTo(Duration(milliseconds: ms));
                      setState(() {});
                    },
                    onChangeEnd: (_) {
                      _vodDragging = false;
                      _scheduleHideVodControls();
                    },
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(pos),
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' / ${_formatDuration(dur)}',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_seekRelative(const Duration(seconds: -10))),
                      icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 26),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_togglePlayPause()),
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_seekRelative(const Duration(seconds: 10))),
                      icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _disposeController() {
    _controller?.removeListener(_onVideoTick);
    _vodControlsHideTimer?.cancel();
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vodControlsHideTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  Widget _thumb() {
    final thumb = widget.thumbnailUrl?.trim();
    if (thumb == null || thumb.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(
      thumb,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playUrl = (_activeUrl ?? widget.url).trim();

    // Web (Chrome/Edge): iframe Mux — HLS nativo do browser não chega.
    if (kIsWeb && _ready && playUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          buildMuxWebHlsPlayer(
            url: playUrl,
            isRecording: _activeIsRecording,
            fit: widget.fit,
            onRetry: _retry,
          ),
        ],
      );
    }

    if (_ready && controller != null && controller.value.isInitialized) {
      return GestureDetector(
        onTap: widget.isRecording ? _toggleVodControls : null,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fill(child: _buildFullScreenVideo(controller)),
            if (widget.isRecording) _buildVodControls(controller),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _thumb(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_waiting)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                )
              else
                Icon(
                  Icons.sensors_rounded,
                  size: 40,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (!_waiting && (_isLive || widget.isRecording)) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _retry,
                  style: TextButton.styleFrom(
                    foregroundColor: FleaberColors.tealHighlight,
                  ),
                  child: const Text('Tentar outra vez'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
