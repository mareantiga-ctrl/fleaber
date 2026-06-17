import 'dart:ui';

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

enum _CreateAction { novoAnuncio, novoDirecto }

/// Bottom sheet glass «Criar» (Novo Anúncio / Novo Direto) — Home, Mensagens, Perfil.
class FleaberCreateSheet extends StatelessWidget {
  const FleaberCreateSheet._({
    required this.onNovoAnuncio,
    required this.onNovoDirecto,
  });

  final VoidCallback onNovoAnuncio;
  final VoidCallback onNovoDirecto;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<_CreateAction>(
      context: context,
      backgroundColor: Colors.transparent,
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
    ).then((action) {
      if (!context.mounted || action == null) return;
      switch (action) {
        case _CreateAction.novoAnuncio:
          context.pushNamed(SellerProductFormWidget.routeName);
        case _CreateAction.novoDirecto:
          context.pushNamed(PrepararDirectoPageWidget.routeName);
      }
    });
  }

  static const _sheetPadding = EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0);
  static const _innerPadding = EdgeInsets.fromLTRB(14.0, 10.0, 14.0, 18.0);
  static const _radius = FleaberRadius.lg;
  static const _blurSigma = 14.0;
  static const _sheetColor = Color(0xCC101518);
  static const _accent = FleaberColors.teal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _sheetPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          child: Container(
            padding: _innerPadding,
            decoration: BoxDecoration(
              color: _sheetColor,
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
                Semantics(
                  identifier: 'prep_sheet_novo_anuncio',
                  button: true,
                  onTap: onNovoAnuncio,
                  child: ExcludeSemantics(
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
                ),
                Semantics(
                  identifier: 'prep_sheet_novo_direto',
                  button: true,
                  onTap: onNovoDirecto,
                  child: ExcludeSemantics(
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
