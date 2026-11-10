import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_elevation.dart';

import '../hub_actions.dart';
import '../data/hub_models.dart';
import '../hub_urls.dart';
import '../theme/hub_theme.dart';

class HubSectionHeader extends StatelessWidget {
  const HubSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: HubTheme.titleMd),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class HubEmptyState extends StatelessWidget {
  const HubEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, color: HubTheme.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: HubTheme.body,
          ),
        ],
      ),
    );
  }
}

class HubErrorState extends StatelessWidget {
  const HubErrorState({
    super.key,
    this.onRetry,
  });

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: HubTheme.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar.',
              style: HubTheme.titleMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Tenta novamente dentro de momentos.',
              style: HubTheme.body,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
            ],
          ],
        ),
      ),
    );
  }
}

class HubLiveBadge extends StatelessWidget {
  const HubLiveBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return HubLiveStatusBadge(
      status: HubLiveDisplayStatus.live,
      compact: compact,
    );
  }
}

/// AO VIVO / GRAVADO / GRAVAÇÃO A PREPARAR — Hub + cards relacionados (B12).
class HubLiveStatusBadge extends StatelessWidget {
  const HubLiveStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  factory HubLiveStatusBadge.forLive(
    HubLive live, {
    bool compact = false,
  }) {
    return HubLiveStatusBadge(
      status: hubLiveDisplayStatus(live),
      compact: compact,
    );
  }

  final HubLiveDisplayStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, decoration, showDot) = switch (status) {
      HubLiveDisplayStatus.live => (
          'AO VIVO',
          HubTheme.liveBadgeDecoration,
          true,
        ),
      HubLiveDisplayStatus.recorded => (
          'GRAVADO',
          BoxDecoration(
            color: HubTheme.teal,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [FleaberElevation.smAccent(HubTheme.teal)],
          ),
          false,
        ),
      HubLiveDisplayStatus.preparing => (
          'GRAVAÇÃO A PREPARAR',
          BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          false,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class HubVerifiedBadge extends StatelessWidget {
  const HubVerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HubTheme.teal.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HubTheme.teal.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, color: HubTheme.accent, size: 14),
          const SizedBox(width: 4),
          Text(
            'Seller verificada',
            style: GoogleFonts.inter(
              color: HubTheme.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class HubInstallBanner extends StatelessWidget {
  const HubInstallBanner({super.key, this.compact = false});

  /// Layout horizontal secundário (perfil desktop). Default = cartão empilhado.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final published = HubUrls.installAndroidPublished;
    final title = Text('Leva a Fleaber contigo', style: HubTheme.titleMd);
    final body = Text(
      published
          ? 'Reserva mais rápido, recebe notificações de diretos e compra com proteção.'
          : 'A app Fleaber chega em breve à Google Play. Entretanto usa o FleaHub no browser.',
      style: HubTheme.body,
    );
    final button = OutlinedButton(
      onPressed: published ? () => HubActions.openInstallApp() : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: HubTheme.accent,
        side: const BorderSide(color: HubTheme.teal),
      ),
      child: Text(published ? 'Instalar app' : 'Em breve'),
    );

    if (compact) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: HubTheme.cardDecoration.copyWith(
          border: Border.all(color: HubTheme.teal.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 4),
                  body,
                ],
              ),
            ),
            const SizedBox(width: 16),
            button,
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: HubTheme.cardDecoration.copyWith(
        border: Border.all(color: HubTheme.teal.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 6),
          body,
          const SizedBox(height: 12),
          Row(children: [Expanded(child: button)]),
        ],
      ),
    );
  }
}
