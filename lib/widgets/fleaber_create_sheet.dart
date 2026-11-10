import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

enum _CreateAction { novoAnuncio, novoDirecto }

/// Menu «Criar» (Novo Anúncio / Novo Direto) — Home, Mensagens, Perfil.
///
/// - Mobile / web estreito: bottom sheet glass original.
/// - Desktop web (≥768): menu compacto ancorado ao botão que o abriu.
class FleaberCreateSheet extends StatelessWidget {
  const FleaberCreateSheet._({
    required this.onNovoAnuncio,
    required this.onNovoDirecto,
  });

  final VoidCallback onNovoAnuncio;
  final VoidCallback onNovoDirecto;

  static const _sheetPadding = EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0);
  static const _innerPadding = EdgeInsets.fromLTRB(14.0, 10.0, 14.0, 18.0);
  static const _radius = FleaberRadius.lg;
  static const _blurSigma = 14.0;
  /// Mobile: glass semi-transparente. Web estreito: sólido.
  static const _sheetColor = Color(0xCC101518);
  static const _sheetColorWeb = Color(0xFF101518);
  static const _accent = FleaberColors.teal;
  static const _menuBg = Color(0xFF101518);

  static bool _isWideDesktop(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 768;

  /// [anchorContext] deve ser o contexto do botão «+ Criar» (desktop).
  /// Se omitido, tenta [context]; em último caso ancora ao canto superior direito.
  static Future<void> show(
    BuildContext context, {
    BuildContext? anchorContext,
  }) {
    final wide = _isWideDesktop(context);

    final Future<_CreateAction?> future;
    if (wide) {
      future = _showAnchoredMenu(
        context,
        anchorContext: anchorContext ?? context,
      );
    } else {
      future = showModalBottomSheet<_CreateAction>(
        context: context,
        backgroundColor: kIsWeb ? _sheetColorWeb : Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          return FleaberCreateSheet._(
            onNovoAnuncio: () {
              Navigator.of(sheetContext).pop(_CreateAction.novoAnuncio);
            },
            onNovoDirecto: () {
              Navigator.of(sheetContext).pop(_CreateAction.novoDirecto);
            },
          );
        },
      );
    }

    return future.then((action) {
      if (!context.mounted || action == null) return;
      switch (action) {
        case _CreateAction.novoAnuncio:
          context.pushNamed(SellerProductFormWidget.routeName);
        case _CreateAction.novoDirecto:
          context.pushNamed(PrepararDirectoPageWidget.routeName);
      }
    });
  }

  static RelativeRect _menuPosition(
    BuildContext overlayContext,
    BuildContext anchorContext,
  ) {
    final overlay =
        Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize || !overlay.hasSize) {
      final size = MediaQuery.sizeOf(overlayContext);
      return RelativeRect.fromLTRB(size.width - 280, 56, 16, size.height - 200);
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    // Preferir abrir por baixo do botão; se não couber, alinhar à direita.
    return RelativeRect.fromRect(
      Rect.fromPoints(
        Offset(topLeft.dx, bottomRight.dy + 6),
        Offset(bottomRight.dx, bottomRight.dy + 6),
      ),
      Offset.zero & overlay.size,
    );
  }

  static Future<_CreateAction?> _showAnchoredMenu(
    BuildContext context, {
    required BuildContext anchorContext,
  }) {
    final position = _menuPosition(context, anchorContext);
    return showMenu<_CreateAction>(
      context: context,
      position: position,
      color: _menuBg,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      items: [
        PopupMenuItem<_CreateAction>(
          value: _CreateAction.novoAnuncio,
          height: 48,
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Novo An\u00fancio',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_CreateAction>(
          value: _CreateAction.novoDirecto,
          height: 48,
          child: Row(
            children: [
              const Icon(Icons.videocam_outlined, color: _accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Novo Direto',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = kIsWeb ? _sheetColorWeb : _sheetColor;
    final sheetBody = Container(
      padding: _innerPadding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44.0,
            height: 4.0,
            margin: const EdgeInsets.only(bottom: 10.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: FleaberRadius.circularPill,
            ),
          ),
          // Sem ExcludeSemantics: Maestro/a11y têm de ver «Novo Anúncio» / «Novo Direto».
          Semantics(
            identifier: 'prep_sheet_novo_anuncio',
            button: true,
            label: 'Novo Anúncio',
            onTap: onNovoAnuncio,
            child: ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: _accent,
              ),
              title: const Text('Novo Anúncio'),
              textColor: Colors.white,
              onTap: onNovoAnuncio,
            ),
          ),
          Semantics(
            identifier: 'prep_sheet_novo_direto',
            button: true,
            label: 'Novo Direto',
            onTap: onNovoDirecto,
            child: ListTile(
              leading: const Icon(
                Icons.videocam_outlined,
                color: _accent,
              ),
              title: const Text('Novo Direto'),
              textColor: Colors.white,
              onTap: onNovoDirecto,
            ),
          ),
        ],
      ),
    );

    // Web: BackdropFilter/blur no modal costuma pintar ecrã cinza opaco.
    // Mobile mantém o glass blur (BATATA — só desligar blur em kIsWeb).
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: kIsWeb
          ? sheetBody
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _blurSigma,
                sigmaY: _blurSigma,
              ),
              child: sheetBody,
            ),
    );

    return Padding(
      padding: _sheetPadding,
      child: clipped,
    );
  }
}
