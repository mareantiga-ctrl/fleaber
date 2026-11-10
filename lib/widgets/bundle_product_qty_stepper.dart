import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

/// Selector compacto de quantidade por artigo no fluxo conjunto.
///
/// Com [allowZero] true (Criar/Ver conjunto):
/// - qty 0: `−` inactivo, `+` activo → passa a 1 (sem «Adicionar»);
/// - `+` desactiva só no máximo de stock;
/// - `−` desce até 0.
///
/// [enabled] false = stock esgotado / UI totalmente inactiva.
class BundleProductQtyStepper extends StatelessWidget {
  const BundleProductQtyStepper({
    super.key,
    required this.quantity,
    required this.maxQuantity,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
    this.allowZero = false,
  });

  final int quantity;
  final int maxQuantity;
  final ValueChanged<int> onChanged;
  final bool compact;
  final bool enabled;
  final bool allowZero;

  int get _max {
    if (maxQuantity < 1) return enabled ? 1 : 0;
    return maxQuantity.clamp(1, 999);
  }

  int get _qty {
    if (!enabled) return 0;
    if (allowZero) return quantity.clamp(0, _max);
    return quantity.clamp(1, _max);
  }

  int get _minActive => allowZero ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 18.0 : 20.0;
    final fontSize = compact ? 13.0 : 14.0;
    final side = iconSize + 14;
    final canMinus = enabled && _qty > _minActive;
    // Crítico: com stock, qty 0 ⇒ + activo (não depende de «seleccionado»).
    final canPlus = enabled && _qty < _max;

    // IconButton (não GestureDetector) — no Flutter web cada controlo fica
    // com hit-target e semantics próprios; evita o «botão 0» fundido que
    // engolia o + nos artigos ainda não seleccionados.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: side,
          height: side,
          child: IconButton(
            key: const ValueKey('bundle_qty_minus'),
            tooltip: 'Diminuir quantidade',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: side, height: side),
            style: IconButton.styleFrom(
              backgroundColor:
                  canMinus ? FleaberColors.teal : const Color(0xFFF1F4F8),
              foregroundColor:
                  canMinus ? Colors.white : const Color(0xFFB0B8C0),
              disabledBackgroundColor: const Color(0xFFF1F4F8),
              disabledForegroundColor: const Color(0xFFB0B8C0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: canMinus ? FleaberColors.teal : const Color(0xFFE0E6EB),
                ),
              ),
            ),
            onPressed: canMinus
                ? () => onChanged((_qty - 1).clamp(_minActive, _max))
                : null,
            icon: Icon(Icons.remove_rounded, size: iconSize),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          child: ExcludeSemantics(
            child: SizedBox(
              width: compact ? 18 : 22,
              child: Text(
                '$_qty',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                  color: enabled
                      ? const Color(0xFF101518)
                      : const Color(0xFFB0B8C0),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: side,
          height: side,
          child: IconButton(
            key: const ValueKey('bundle_qty_plus'),
            tooltip: 'Aumentar quantidade',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: side, height: side),
            style: IconButton.styleFrom(
              backgroundColor:
                  canPlus ? FleaberColors.teal : const Color(0xFFF1F4F8),
              foregroundColor:
                  canPlus ? Colors.white : const Color(0xFFB0B8C0),
              disabledBackgroundColor: const Color(0xFFF1F4F8),
              disabledForegroundColor: const Color(0xFFB0B8C0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: canPlus ? FleaberColors.teal : const Color(0xFFE0E6EB),
                ),
              ),
            ),
            onPressed: canPlus
                ? () => onChanged((_qty + 1).clamp(_minActive, _max))
                : null,
            icon: Icon(Icons.add_rounded, size: iconSize),
          ),
        ),
      ],
    );
  }
}
