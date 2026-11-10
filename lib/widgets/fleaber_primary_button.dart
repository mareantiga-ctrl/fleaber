import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_radius.dart';

/// CTA principal Fleaber — altura ~48, radius 16, teal, loading inline.
class FleaberPrimaryButton extends StatelessWidget {
  const FleaberPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.width,
    this.height = kDefaultHeight, // null = altura intrínseca
    this.borderRadius = kDefaultRadius,
    this.backgroundColor = kTeal,
    this.foregroundColor = Colors.white,
    this.disabledBackgroundColor,
    this.textStyle,
    this.icon,
    this.padding,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w700,
    this.letterSpacing,
    this.maxLines,
    this.softWrap,
    this.textAlign,
  });

  /// Chip compacto (ex. «Seguir» no live player) — mantém padding/radius menores.
  const FleaberPrimaryButton.compact({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.backgroundColor = kTeal,
    this.foregroundColor = Colors.white,
    this.disabledBackgroundColor,
    this.textStyle,
    this.icon,
  })  : width = null,
        height = null,
        borderRadius = 14,
        padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        fontSize = 11,
        fontWeight = FontWeight.w700,
        letterSpacing = null,
        maxLines = null,
        softWrap = null,
        textAlign = null;

  static const Color kTeal = Color(0xFF007782);
  static const double kDefaultHeight = 48;
  static const double kDefaultRadius = FleaberRadius.md;

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? disabledBackgroundColor;
  final TextStyle? textStyle;
  final Widget? icon;
  final EdgeInsetsGeometry? padding;
  final double fontSize;
  final FontWeight fontWeight;
  final double? letterSpacing;
  final int? maxLines;
  final bool? softWrap;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final disabledColor =
        disabledBackgroundColor ?? backgroundColor.withValues(alpha: 0.5);
    final labelStyle = textStyle ??
        GoogleFonts.inter(
          fontWeight: fontWeight,
          fontSize: fontSize,
          letterSpacing: letterSpacing,
          color: foregroundColor,
        );

    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: foregroundColor,
            ),
          )
        : (icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon!,
                  const SizedBox(width: 8),
                  Text(label, style: labelStyle),
                ],
              )
            : Text(
                label,
                style: labelStyle,
                textAlign: textAlign,
                softWrap: softWrap ?? true,
                maxLines: maxLines ?? (softWrap == false ? 1 : null),
                overflow: softWrap == false
                    ? TextOverflow.visible
                    : (maxLines != null ? TextOverflow.ellipsis : null),
              ));

    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: disabledColor,
        disabledForegroundColor: foregroundColor.withValues(alpha: 0.85),
        elevation: 0,
        padding: padding ??
            (height != null
                ? const EdgeInsets.symmetric(horizontal: 20)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
        // Evita CTA «Continuar» apertado: min. largura quando só há altura.
        minimumSize: height != null
            ? Size(width ?? (padding != null ? 0 : 88), height!)
            : Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      child: child,
    );

    if (width == double.infinity) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: button,
      );
    }
    if (width != null) {
      return SizedBox(width: width, height: height, child: button);
    }
    if (height != null) {
      return SizedBox(height: height, child: button);
    }
    return button;
  }
}
