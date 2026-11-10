import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Câmara a ecrã cheio — fora de ListView (evita erros CameraX / «Snapshot»).
///
/// Padrão alinhado ao exemplo oficial do `mobile_scanner` 7.x:
/// o widget monta o controller e faz `autoStart` (sem `start()` manual).
class AmazonImporterCameraScanPage extends StatefulWidget {
  const AmazonImporterCameraScanPage({super.key});

  @override
  State<AmazonImporterCameraScanPage> createState() =>
      _AmazonImporterCameraScanPageState();
}

class _AmazonImporterCameraScanPageState
    extends State<AmazonImporterCameraScanPage> {
  /// Resolução mais alta que o default Android 640×480 (melhor EAN/LPN).
  /// Formatos vazios = todos (incl. Data Matrix / ITF das etiquetas Amazon).
  final MobileScannerController _controller = MobileScannerController(
    // unrestricted + resolução alta; autoZoom OFF (em alguns TCL o zoom
    // suggestion do ML Kit parte o pipeline de análise).
    detectionSpeed: DetectionSpeed.unrestricted,
    facing: CameraFacing.back,
    cameraResolution: const Size(1280, 720),
    autoZoom: false,
    formats: const <BarcodeFormat>[],
  );

  StreamSubscription<BarcodeCapture>? _sub;
  bool _permissionOk = false;
  bool _starting = true;
  bool _busyGallery = false;
  String? _error;
  String? _status;
  String? _lastCode;
  DateTime? _lastAt;
  bool _torchOn = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _sub = _controller.barcodes.listen(
      _onDetect,
      onError: (Object e, StackTrace st) {
        debugPrint('AmazonImporterCamera barcodes error: $e\n$st');
        if (!mounted) return;
        setState(() => _status = 'Erro de leitura. Tenta de novo ou usa fotografia.');
      },
    );
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _starting = true;
      _error = null;
      _permissionOk = false;
      _status = null;
      _handled = false;
    });
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() {
        _starting = false;
        _error = status.isPermanentlyDenied
            ? 'Permissão de câmara negada. Abre as definições da app.'
            : 'É necessária a câmara para ler códigos.';
      });
      return;
    }
    setState(() {
      _permissionOk = true;
      _starting = false;
      _error = null;
      _status =
          'Aponta ao código (bem iluminado, a ~15 cm). Podes usar a lanterna ou «Ler da fotografia».';
    });
  }

  static String _friendlyCameraError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('permission')) return 'Sem permissão de câmara.';
    if (raw.contains('already') || raw.contains('started')) {
      return 'A câmara já estava em uso. Fecha outras apps e tenta de novo.';
    }
    return 'Não foi possível abrir a câmara. Tenta fechar e abrir de novo.';
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = (b.rawValue ?? b.displayValue ?? '').trim();
      if (raw.isEmpty) continue;
      final now = DateTime.now();
      if (_lastCode == raw &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastCode = raw;
      _lastAt = now;
      _handled = true;
      debugPrint('AmazonImporterCamera detected: $raw format=${b.format}');
      if (!mounted) return;
      setState(() => _status = 'Lido: $raw');
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busyGallery || _handled) return;
    setState(() {
      _busyGallery = true;
      _status = 'A abrir fotografia…';
    });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _busyGallery = false;
          _status = 'Aponta ao código…';
        });
        return;
      }
      setState(() => _status = 'A ler fotografia…');
      final capture = await _controller.analyzeImage(file.path);
      if (!mounted) return;
      final raw = capture?.barcodes
          .map((b) => (b.rawValue ?? b.displayValue ?? '').trim())
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      if (raw == null || raw.isEmpty) {
        setState(() {
          _busyGallery = false;
          _status = 'Nenhum código na fotografia. Tenta outra ou a câmara.';
        });
        return;
      }
      _handled = true;
      debugPrint('AmazonImporterCamera gallery: $raw');
      Navigator.of(context).pop(raw);
    } catch (e, st) {
      debugPrint('AmazonImporterCamera gallery failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _busyGallery = false;
        _status = 'Falha ao ler fotografia. Tenta outro ficheiro.';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Ler código',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_permissionOk)
            IconButton(
              tooltip: _torchOn ? 'Desligar luz' : 'Ligar luz',
              onPressed: () async {
                await _controller.toggleTorch();
                if (!mounted) return;
                setState(() => _torchOn = !_torchOn);
              },
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            ),
          if (_permissionOk)
            IconButton(
              tooltip: 'Ler fotografia',
              onPressed: _busyGallery ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
            ),
        ],
      ),
      body: _starting
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _ErrorPane(
                  message: _error!,
                  onSettings: openAppSettings,
                  onRetry: _boot,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      fit: BoxFit.cover,
                      tapToFocus: true,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) {
                        return _ErrorPane(
                          message: _friendlyCameraError(
                            error.errorDetails?.message ?? error,
                          ),
                          onSettings: openAppSettings,
                          onRetry: _boot,
                        );
                      },
                    ),
                    IgnorePointer(
                      child: CustomPaint(painter: _ScanFramePainter()),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _status ??
                                    'Aponta ao EAN ou LPN. A leitura fecha automaticamente.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.35,
                                  shadows: const [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed:
                                    _busyGallery ? null : _pickFromGallery,
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  _busyGallery
                                      ? 'A ler…'
                                      : 'Ler da fotografia',
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white70),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.78,
      height: size.height * 0.28,
    );
    final paint = Paint()
      ..color = const Color(0xFF00A3AD)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(r, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    required this.onSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<bool> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007782),
                minimumSize: const Size(200, 48),
              ),
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => onSettings(),
              child: Text(
                'Abrir definições',
                style: GoogleFonts.inter(color: const Color(0xFF00A3AD)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
