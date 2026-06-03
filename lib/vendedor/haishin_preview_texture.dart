import 'dart:async';
import 'dart:convert' as convert;

import 'package:flutter/material.dart';
import 'package:haishin_kit/haishin_kit.dart';
import 'package:haishin_kit/src/haishin_kit/video_gravity.dart';
import 'package:haishin_kit/src/stream_session/stream_session_view_texture_snapshot.dart';

/// Android: [registerTexture] devolve `null` até [updateTexture] com tamanho.
/// Este widget faz register → update (com retries) antes de mostrar [Texture].
class HaishinPreviewTexture extends StatefulWidget {
  const HaishinPreviewTexture({
    super.key,
    required this.session,
    this.videoGravity = VideoGravity.resizeAspectFill,
    this.onTextureReady,
    this.onTextureFailed,
  });

  final StreamSession session;
  final VideoGravity videoGravity;
  final void Function(int textureId)? onTextureReady;
  final void Function()? onTextureFailed;

  @override
  State<HaishinPreviewTexture> createState() => _HaishinPreviewTextureState();
}

class _HaishinPreviewTextureState extends State<HaishinPreviewTexture> {
  int? _textureId;
  Size? _lastSize;
  bool _initDone = false;
  int _initGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleInit(Size(640, 360));
  }

  @override
  void dispose() {
    // Não chamar unregisterTexture aqui — a sessão pode já estar disposed
    // (crash nativo ao preparar Mux). O plugin limpa no session.dispose().
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HaishinPreviewTexture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.memory != widget.session.memory) {
      _textureId = null;
      _lastSize = null;
      _initDone = false;
      _initGeneration++;
      _scheduleInit(Size(640, 360));
    }
  }

  void _scheduleInit(Size fallbackSize) {
    final gen = _initGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _initGeneration) return;
      unawaited(_initTexturePipeline(fallbackSize, gen));
    });
  }

  Future<void> _initTexturePipeline(Size size, int gen) async {
    if (_initDone && _textureId != null) return;

    await widget.session.registerTexture({});

    for (var attempt = 0; attempt < 25; attempt++) {
      if (!mounted || gen != _initGeneration) return;

      final id = await _updateTextureSize(size, force: true);
      if (id != null) {
        if (!mounted || gen != _initGeneration) return;
        setState(() {
          _textureId = id;
          _initDone = true;
        });
        widget.onTextureReady?.call(id);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted || gen != _initGeneration) return;
    widget.onTextureFailed?.call();
  }

  Future<int?> _updateTextureSize(Size size, {bool force = false}) async {
    if (size.width < 2 || size.height < 2) return null;
    if (!force && _lastSize == size && _textureId != null) return _textureId;
    _lastSize = size;

    final snapshot = StreamSessionViewTextureSnapshot(
      width: size.width,
      height: size.height,
      videoGravity: widget.videoGravity,
    );
    return widget.session.updateTexture({
      'value': convert.jsonEncode(snapshot.toJson()),
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth;
        var h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w < 2 || h < 2) {
          final screen = MediaQuery.sizeOf(context);
          w = screen.width;
          h = screen.height;
        }
        final size = Size(w, h);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_textureId == null) {
            unawaited(_initTexturePipeline(size, _initGeneration));
          } else {
            unawaited(_updateTextureSize(size));
          }
        });

        if (_textureId == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white54),
                const SizedBox(height: 12),
                Text(
                  'A criar Surface…',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }
        return Texture(textureId: _textureId!);
      },
    );
  }
}
