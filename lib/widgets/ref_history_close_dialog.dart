import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/ref_history_service.dart';

/// Diálogo em 2 passos para encerrar histórico.
abstract final class RefHistoryCloseDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String sellerId,
    required String historyId,
    required String displayTitle,
  }) async {
    final preview = await RefHistoryService.closePreview(
      sellerId: sellerId,
      historyId: historyId,
    );
    if (!context.mounted) return false;
    if (!preview.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(preview.error)),
        ),
      );
      return false;
    }

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2329),
        title: Text(
          'Encerrar histórico?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Vais encerrar «$displayTitle». '
          '${preview.willCancelTotal > 0 ? 'Serão canceladas ${preview.willCancelTotal} reservas/pedidos não pagos. ' : ''}'
          'Compras já pagas mantêm-se.',
          style: GoogleFonts.inter(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Continuar',
              style: GoogleFonts.inter(
                color: const Color(0xFF80DEEA),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return false;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmCloseDialog(
        sellerId: sellerId,
        historyId: historyId,
      ),
    );
    return step2 == true;
  }

  static String _errorMessage(String? code) {
    switch (code) {
      case 'history_not_active':
        return 'Este histórico já está encerrado.';
      case 'history_not_found':
        return 'Histórico não encontrado.';
      case 'not_allowed':
        return 'Sem permissão para encerrar.';
      default:
        return 'Não foi possível preparar o encerramento.';
    }
  }
}

class _ConfirmCloseDialog extends StatefulWidget {
  const _ConfirmCloseDialog({
    required this.sellerId,
    required this.historyId,
  });

  final String sellerId;
  final String historyId;

  @override
  State<_ConfirmCloseDialog> createState() => _ConfirmCloseDialogState();
}

class _ConfirmCloseDialogState extends State<_ConfirmCloseDialog> {
  bool _loading = false;

  Future<void> _confirm() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await RefHistoryService.closeWithMeta(
        sellerId: widget.sellerId,
        historyId: widget.historyId,
        reason: 'seller_closed',
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            RefHistoryCloseDialog._errorMessage(result.error) !=
                    'Não foi possível preparar o encerramento.'
                ? RefHistoryCloseDialog._errorMessage(result.error)
                : 'Não foi possível encerrar o histórico.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A2329),
      title: Text(
        'Confirmar encerramento',
        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      content: Text(
        'Esta ação não pode ser desfeita. O histórico deixa de aparecer '
        'nas sugestões «Continuar histórico».',
        style: GoogleFonts.inter(color: Colors.white70, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text('Voltar', style: GoogleFonts.inter(color: Colors.white60)),
        ),
        FilledButton(
          onPressed: _loading ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007782),
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Encerrar',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}
