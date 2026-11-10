import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

/// Chrome visual partilhado do Checkout marketplace (FleaHub Web + app).
///
/// Só apresentação — sem Stripe, stock, RPCs ou regras de negócio.
abstract final class FleaberCheckoutUi {
  /// E86: dialog centrado também em mid-width (antes só ≥900).
  static const double desktopBreakpoint = 768;
  static const double sheetMaxWidth = 640;
  static const Color ink = Color(0xFF101518);
  static const Color muted = Color(0xFF57636C);
  static const Color line = Color(0xFFD5E4E6);
  static const Color cardBg = FleaberColors.bgTint;
  static const Color teal = FleaberColors.teal;

  static bool isDesktopLayout(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  /// Desktop web: diálogo centrado. Mobile/app: bottom sheet.
  static Future<T?> showHost<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double maxWidth = sheetMaxWidth,
    Color backgroundColor = Colors.white,
  }) {
    final wide = isDesktopLayout(context);
    if (wide) {
      return showDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (ctx) {
          final size = MediaQuery.sizeOf(ctx);
          final h = size.height;
          final w = size.width;
          final dialogW = maxWidth.clamp(320.0, w - 48);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: w >= 900 ? 40 : 24,
              vertical: w >= 900 ? 32 : 20,
            ),
            child: SizedBox(
              width: dialogW,
              height: (h * 0.90).clamp(440.0, h - 48),
              child: Material(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                elevation: 10,
                shadowColor: Colors.black26,
                child: builder(ctx),
              ),
            ),
          );
        },
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SizedBox(
          height: (h * 0.92).clamp(360.0, h),
          child: builder(ctx),
        );
      },
    );
  }
}

class FleaberCheckoutHandle extends StatelessWidget {
  const FleaberCheckoutHandle({super.key});

  @override
  Widget build(BuildContext context) {
    if (FleaberCheckoutUi.isDesktopLayout(context)) {
      return const SizedBox(height: 4);
    }
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD0D5D8),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class FleaberCheckoutTitleBar extends StatelessWidget {
  const FleaberCheckoutTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.2,
                  color: FleaberCheckoutUi.ink,
                ),
              ),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    color: FleaberCheckoutUi.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: 'Fechar',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: FleaberCheckoutUi.muted),
          ),
      ],
    );
  }
}

class FleaberCheckoutSectionLabel extends StatelessWidget {
  const FleaberCheckoutSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
        color: FleaberCheckoutUi.ink,
      ),
    );
  }
}

/// Resumo do artigo (imagem + título + vendedor + quantidade).
class FleaberCheckoutProductSummary extends StatelessWidget {
  const FleaberCheckoutProductSummary({
    super.key,
    required this.title,
    this.imageUrl,
    this.sellerName,
    this.quantityLabel,
    this.priceLabel,
  });

  final String title;
  final String? imageUrl;
  final String? sellerName;
  final String? quantityLabel;
  final String? priceLabel;

  @override
  Widget build(BuildContext context) {
    final img = (imageUrl ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberCheckoutUi.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: FleaberRadius.circularSm,
            child: SizedBox(
              width: 72,
              height: 72,
              child: img.isEmpty
                  ? Container(
                      color: const Color(0xFFE8EEF0),
                      child: const Icon(
                        Icons.image_outlined,
                        color: FleaberCheckoutUi.muted,
                      ),
                    )
                  : BatataCachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      placeholderColor: const Color(0xFFE8EEF0),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FleaberCheckoutUi.ink,
                  ),
                ),
                if ((sellerName ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Vendedor: ${sellerName!.trim()}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: FleaberCheckoutUi.muted,
                    ),
                  ),
                ],
                if ((quantityLabel ?? '').trim().isNotEmpty ||
                    (priceLabel ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if ((quantityLabel ?? '').trim().isNotEmpty)
                        quantityLabel!.trim(),
                      if ((priceLabel ?? '').trim().isNotEmpty)
                        priceLabel!.trim(),
                    ].join(' · '),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FleaberCheckoutUi.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FleaberCheckoutAddressCard extends StatelessWidget {
  const FleaberCheckoutAddressCard({
    super.key,
    required this.lines,
    this.complete = true,
    this.onEdit,
  });

  final List<String> lines;
  final bool complete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FleaberCheckoutUi.cardBg,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberCheckoutUi.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            complete ? Icons.location_on_outlined : Icons.warning_amber_rounded,
            size: 20,
            color: complete ? FleaberCheckoutUi.teal : const Color(0xFFC28A00),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete ? 'Morada de entrega' : 'Morada incompleta',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FleaberCheckoutUi.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  complete
                      ? lines.where((l) => l.trim().isNotEmpty).join('\n')
                      : 'Completa o nome legal e a morada nas definições '
                          'antes de pagar com Seguro Fleaber ou envio.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: FleaberCheckoutUi.muted,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: FleaberCheckoutUi.teal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                complete ? 'Alterar' : 'Completar',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FleaberCheckoutChoiceCard<T> extends StatelessWidget {
  const FleaberCheckoutChoiceCard({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    this.subtitle,
    this.onChanged,
    this.enabled = true,
  });

  final T value;
  final T groupValue;
  final String title;
  final String? subtitle;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected
            ? FleaberCheckoutUi.teal.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: FleaberRadius.circularMd,
        child: InkWell(
          borderRadius: FleaberRadius.circularMd,
          onTap: !enabled || onChanged == null
              ? null
              : () => onChanged!(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(
                color: selected ? FleaberCheckoutUi.teal : FleaberCheckoutUi.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 22,
                  color: selected
                      ? FleaberCheckoutUi.teal
                      : FleaberCheckoutUi.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: FleaberCheckoutUi.ink,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!.trim(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: FleaberCheckoutUi.muted,
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

class FleaberCheckoutPriceLine extends StatelessWidget {
  const FleaberCheckoutPriceLine({
    super.key,
    required this.label,
    required this.value,
    this.isTotal = false,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool isTotal;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
              color: emphasis
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF3D4A55),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isTotal ? 17 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            color: isTotal ? FleaberCheckoutUi.teal : FleaberCheckoutUi.ink,
          ),
        ),
      ],
    );
  }
}

class FleaberCheckoutTotalsCard extends StatelessWidget {
  const FleaberCheckoutTotalsCard({
    super.key,
    required this.lines,
  });

  final List<FleaberCheckoutPriceLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FleaberCheckoutUi.cardBg,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberCheckoutUi.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            if (lines[i].isTotal) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, color: FleaberCheckoutUi.line),
              ),
            ],
            lines[i],
          ],
        ],
      ),
    );
  }
}

/// Corpo scrollável + CTA sticky no fundo (desktop e mobile).
class FleaberCheckoutBody extends StatelessWidget {
  const FleaberCheckoutBody({
    super.key,
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryLoading = false,
    this.primaryEnabled = true,
    this.footerNote,
  });

  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;
  final bool primaryEnabled;
  final String? footerNote;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            16 + bottomInset + (padBottom > 0 ? padBottom : 8),
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: FleaberCheckoutUi.line),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((footerNote ?? '').trim().isNotEmpty) ...[
                Text(
                  footerNote!.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.35,
                    color: FleaberCheckoutUi.muted,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FleaberPrimaryButton(
                width: double.infinity,
                label: primaryLabel,
                loading: primaryLoading,
                onPressed: primaryEnabled ? onPrimary : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
