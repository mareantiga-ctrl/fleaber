import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/hub/hub_live_reservation_ui.dart';
import '/hub/theme/hub_theme.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/utils/live_bag_copy.dart';
import '/widgets/fleaber_primary_button.dart';

/// Catálogo visual H14 — Saco e Reservas (só UI, sem BD / sem pagamentos).
///
/// Gate: `--dart-define=FLEABER_H14_VISUAL_CATALOG=true` ou debug/profile.
/// Reutiliza chips e tokens já aprovados (108.1 / Hub light chrome).
class HubBagVisualCatalogPage extends StatelessWidget {
  const HubBagVisualCatalogPage({super.key});

  static const routeName = 'H14SacoReservasCatalog';
  static const routePath = '/h14SacoReservasCatalog';

  static bool get isEnabled {
    const viaDefine = bool.fromEnvironment(
      'FLEABER_H14_VISUAL_CATALOG',
      defaultValue: false,
    );
    return viaDefine || kDebugMode || kProfileMode;
  }

  @override
  Widget build(BuildContext context) {
    if (!isEnabled) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7F8),
        body: Center(
          child: Text(
            'Catálogo H14 indisponível neste build.',
            style: GoogleFonts.inter(color: const Color(0xFF57636C)),
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;

    return FleaHubSiteScaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 32 : 16,
          24,
          wide ? 32 : 16,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'H14 — Saco e Reservas (catálogo visual)',
              style: GoogleFonts.interTight(
                color: const Color(0xFF101518),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Estados de referência sobre fundo claro FleaHub. Sem pedidos reais '
              'nem alterações de stock.',
              style: GoogleFonts.inter(
                color: const Color(0xFF57636C),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle('1 · Estado vazio'),
            const SizedBox(height: 12),
            _BagPanelPreview(
              wide: wide,
              child: _EmptyBagPreview(
                onContinue: () {},
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle('2 · Resumo com estados mistos'),
            const SizedBox(height: 12),
            _BagPanelPreview(
              wide: wide,
              child: const _FilledBagPreview(),
            ),
            const SizedBox(height: 28),
            _sectionTitle('3 · Chips de estado (contraste)'),
            const SizedBox(height: 12),
            const _ChipsGrid(),
            const SizedBox(height: 28),
            _sectionTitle('4 · Cartão «O teu saco» (landing)'),
            const SizedBox(height: 12),
            const _LandingBagCardPreview(),
          ],
        ),
      ),
    );
  }

  static Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.inter(
          color: const Color(0xFF101518),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      );
}

class _BagPanelPreview extends StatelessWidget {
  const _BagPanelPreview({required this.wide, required this.child});

  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: wide ? 460 : double.infinity,
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD5DDE3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _EmptyBagPreview extends StatelessWidget {
  const _EmptyBagPreview({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O teu saco',
            style: GoogleFonts.interTight(
              color: const Color(0xFF101518),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Ainda não tens artigos no saco desta vendedora.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onContinue,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF007782),
              side: const BorderSide(color: Color(0xFF007782)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'Continuar a explorar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledBagPreview extends StatelessWidget {
  const _FilledBagPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O teu saco',
            style: GoogleFonts.interTight(
              color: const Color(0xFF101518),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tens 3 reservas',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '1 confirmada · 2 pendentes',
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip('1 confirm.', HubReservationStatusUi.green),
              _chip('2 pend.', HubReservationStatusUi.orange),
            ],
          ),
          const SizedBox(height: 14),
          _demoTile(
            status: 'accepted',
            requestKind: 'guaranteed',
            title: 'Casaco leve bege — tamanho S',
            price: '28,50 €',
            qty: 1,
            expires: 'Reservado até às 18:30',
          ),
          _demoTile(
            status: 'pending',
            requestKind: 'approval_pending',
            title: 'Calças de ganga vintage — 40',
            price: '18,00 €',
            qty: 2,
          ),
          _demoTile(
            status: 'pending',
            requestKind: 'bag_hold_none',
            title: 'Camisola azul clara — M',
            price: '12,50 €',
            qty: 1,
          ),
          const SizedBox(height: 8),
          FleaberPrimaryButton(
            label: 'Pagar',
            height: 44,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  static Widget _chip(String label, Color color) {
    final text = color == HubReservationStatusUi.green
        ? const Color(0xFF1B5E20)
        : const Color(0xFF7A4E00);
    final bg = color == HubReservationStatusUi.green
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFF3E0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static Widget _demoTile({
    required String status,
    required String requestKind,
    required String title,
    required String price,
    required int qty,
    String? expires,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5DDE3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEF1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.checkroom_outlined,
              color: Color(0xFF57636C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HubReservationStatusUi.statusChip(
                  status,
                  requestKind: requestKind,
                  expiresAt: expires != null
                      ? DateTime.now().add(const Duration(hours: 2))
                      : null,
                  lightChrome: true,
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF101518),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF007782),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (expires != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          expires,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF7A4E00),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            '×$qty',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipsGrid extends StatelessWidget {
  const _ChipsGrid();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5DDE3)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          HubReservationStatusUi.statusChip(
            'pending',
            requestKind: 'approval_pending',
            lightChrome: true,
          ),
          HubReservationStatusUi.statusChip(
            'pending',
            requestKind: 'bag_hold_none',
            lightChrome: true,
          ),
          HubReservationStatusUi.statusChip(
            'accepted',
            requestKind: 'guaranteed',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            lightChrome: true,
          ),
          HubReservationStatusUi.statusChip(
            'rejected',
            lightChrome: true,
          ),
          HubReservationStatusUi.statusChip(
            'expired',
            lightChrome: true,
          ),
          LiveBagBuyerStateChip(
            label: LiveBagBuyerStateCopy.unavailable,
            color: HubReservationStatusUi.red,
            onLightBackground: true,
            fontSize: 10,
          ),
        ],
      ),
    );
  }
}

class _LandingBagCardPreview extends StatelessWidget {
  const _LandingBagCardPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E6EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'O teu saco',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tens 3 reservas por concluir',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '2 por confirmar · 1 por pagar',
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: HubTheme.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Ver saco e pagar',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
