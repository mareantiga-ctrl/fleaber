import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/flutter_flow/nav/nav.dart';
import '/legal/legal_document_page_widget.dart';
import '/legal/legal_texts.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';

import '../routing/hub_route_paths.dart';
import '../seo/hub_seo_meta.dart';
import '../widgets/fleahub_site_chrome.dart';
import '../widgets/hub_seo_scope.dart';
import 'how_it_works_body.dart';

/// Páginas públicas H15–H19.
///
/// H15 = [HowItWorksBody] (fonte única com o Perfil).
/// H16–H19 = [LegalTexts] (mesma fonte do Perfil).
/// Sem CTAs «Explorar FleaHub» — o utilizador já está no FleaHub.

class FleaHubHowItWorksPage extends StatelessWidget {
  const FleaHubHowItWorksPage({super.key});

  static const routePath = HubRoutePaths.howItWorks;
  static const routeName = 'FleaHubHowItWorks';

  @override
  Widget build(BuildContext context) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubInfo(
        title: 'Como funciona · FleaHub',
        description:
            'Descobre, reserva, junta no saco e compra — o percurso no FleaHub.',
        path: routePath,
      ),
      child: FleaHubSiteScaffold(
        body: Padding(
          padding: EdgeInsets.fromLTRB(pad.left, 18, pad.right, 0),
          child: HowItWorksBody(
            onBuySafe: () => context.push(HubRoutePaths.buySafe),
            onSell: () => context.push(HubRoutePaths.sell),
            onFaq: () => context.push(HubRoutePaths.help),
          ),
        ),
      ),
    );
  }
}

class FleaHubBuySafePage extends StatelessWidget {
  const FleaHubBuySafePage({super.key});

  static const routePath = HubRoutePaths.buySafe;
  static const routeName = 'FleaHubBuySafe';

  @override
  Widget build(BuildContext context) {
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubInfo(
        title: 'Comprar com segurança · FleaHub',
        description:
            'Pagamentos Stripe, Protecção Fleaber, envios DPD e disputas.',
        path: routePath,
      ),
      child: FleaHubSiteScaffold(
        body: _InfoPageShell(
          title: LegalTexts.buySafeTitle,
          subtitle:
              'O que está efectivamente disponível — sem inventar métodos '
              'ou prazos.',
          children: [
            for (var i = 0; i < LegalTexts.buySafe.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _InfoBlock(
                icon: _buySafeIcon(LegalTexts.buySafe[i].title),
                title: LegalTexts.buySafe[i].title,
                body: LegalTexts.buySafe[i].body,
                trailing: _buySafeTrailing(LegalTexts.buySafe[i].title),
              ),
            ],
            const SizedBox(height: 20),
            _SecondaryButton(
              label: 'Perguntas Frequentes',
              onPressed: () => context.push(HubRoutePaths.help),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _buySafeIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('pagamento directo')) return Icons.swap_horiz_rounded;
    if (t.contains('pagamento')) return Icons.credit_card_rounded;
    if (t.contains('protec')) return Icons.verified_user_outlined;
    if (t.contains('envio') || t.contains('dpd')) {
      return Icons.local_shipping_outlined;
    }
    return Icons.inventory_2_outlined;
  }

  static Widget? _buySafeTrailing(String title) {
    final t = title.toLowerCase();
    if (t.contains('pagamento') && !t.contains('directo')) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: _PaymentOnlyRow(),
      );
    }
    if (t.contains('envio') || t.contains('dpd')) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: _ShippingOnlyRow(),
      );
    }
    return null;
  }
}

class FleaHubSellPage extends StatelessWidget {
  const FleaHubSellPage({super.key});

  static const routePath = HubRoutePaths.sell;
  static const routeName = 'FleaHubSell';

  @override
  Widget build(BuildContext context) {
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubInfo(
        title: 'Vender na Fleaber · FleaHub',
        description:
            'Sem comissões Fleaber. Marketplace, directos, reservas e envios.',
        path: routePath,
      ),
      child: FleaHubSiteScaffold(
        body: _InfoPageShell(
          title: LegalTexts.sellTitle,
          subtitle:
              'Como publicar, vender e receber — com a política sem comissões '
              'da Fleaber separada dos custos externos.',
          children: [
            const _NoCommissionBanner(),
            const SizedBox(height: 16),
            for (var i = 0; i < LegalTexts.sell.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _InfoBlock(
                icon: Icons.storefront_outlined,
                title: LegalTexts.sell[i].title,
                body: LegalTexts.sell[i].body,
              ),
            ],
            const SizedBox(height: 20),
            _SecondaryButton(
              label: 'Contactos',
              onPressed: () => context.push(HubRoutePaths.contacts),
            ),
          ],
        ),
      ),
    );
  }
}

class FleaHubContactsPage extends StatelessWidget {
  const FleaHubContactsPage({super.key});

  static const routePath = HubRoutePaths.contacts;
  static const routeName = 'FleaHubContacts';

  @override
  Widget build(BuildContext context) {
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubInfo(
        title: 'Contactos e identificação legal · FleaHub',
        description:
            'Identificação da Mare Antiga Unipessoal Lda e contactos Fleaber.',
        path: routePath,
      ),
      child: FleaHubSiteScaffold(
        body: _InfoPageShell(
          title: LegalTexts.contactsTitle,
          subtitle:
              'Dados da empresa responsável pela plataforma — não contactos '
              'pessoais de vendedores.',
          children: [
            for (var i = 0; i < LegalTexts.contactsInfo.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _InfoBlock(
                icon: Icons.apartment_outlined,
                title: LegalTexts.contactsInfo[i].title,
                body: LegalTexts.contactsInfo[i].body,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MailtoChip(
                  label: LegalTexts.supportEmail,
                  email: LegalTexts.supportEmail,
                ),
                _MailtoChip(
                  label: LegalTexts.legalEmail,
                  email: LegalTexts.legalEmail,
                ),
                _TelChip(
                  label: LegalTexts.supportPhoneDisplay,
                  tel: LegalTexts.supportPhoneTel,
                ),
                _SecondaryButton(
                  label: 'Informação legal',
                  onPressed: () {
                    context.pushNamed(
                      LegalDocumentPageWidget.routeName,
                      queryParameters: {'kind': 'privacy'},
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FleaHubHelpPage extends StatelessWidget {
  const FleaHubHelpPage({super.key});

  static const routePath = HubRoutePaths.help;
  static const routeName = 'FleaHubHelp';

  @override
  Widget build(BuildContext context) {
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubInfo(
        title: 'Ajuda · FleaHub',
        description: 'Perguntas frequentes sobre a Fleaber e o FleaHub.',
        path: routePath,
      ),
      child: FleaHubSiteScaffold(
        body: _InfoPageShell(
          title: LegalTexts.faqTitle,
          subtitle:
              'Uma só FAQ — a mesma do Perfil — organizada por temas.',
          children: [
            for (final s in LegalTexts.faq) _FaqOrCategory(section: s),
            const SizedBox(height: 20),
            _SecondaryButton(
              label: 'Como funciona',
              onPressed: () => context.push(HubRoutePaths.howItWorks),
            ),
          ],
        ),
      ),
    );
  }
}

// ——— shells / blocks ———

class _InfoPageShell extends StatelessWidget {
  const _InfoPageShell({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 18, pad.right, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            LegalTexts.updatedLabelInfoOct2026,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NoCommissionBanner extends StatelessWidget {
  const _NoCommissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(
          color: FleaberColors.teal.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FleaberColors.teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.savings_outlined,
              color: FleaberColors.teal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sem comissões, taxas ou subscrições cobradas pela Fleaber '
              'aos vendedores. Custos externos (pagamentos, portes) são à parte.',
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOnlyRow extends StatelessWidget {
  const _PaymentOnlyRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _LogoPill(
          child: FleaHubBrandMark(
            asset: 'assets/images/hub_landing/brands/visa.png',
            semanticLabel: 'Visa',
            height: 16,
            maxWidth: 44,
          ),
        ),
        _LogoPill(
          child: FleaHubBrandMark(
            asset: 'assets/images/hub_landing/brands/mastercard.png',
            semanticLabel: 'Mastercard',
            height: 22,
            maxWidth: 36,
          ),
        ),
      ],
    );
  }
}

class _ShippingOnlyRow extends StatelessWidget {
  const _ShippingOnlyRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _LogoPill(
          child: FleaHubBrandMark(
            asset: 'assets/images/hub_landing/brands/dpd.png',
            semanticLabel: 'DPD',
            height: 18,
            maxWidth: 48,
          ),
        ),
      ],
    );
  }
}

class _LogoPill extends StatelessWidget {
  const _LogoPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FleaberColors.bgTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FleaberColors.alternate),
      ),
      child: child,
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: FleaberColors.teal, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: FleaberColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LegalLinkedText(
            text: body,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _FaqOrCategory extends StatelessWidget {
  const _FaqOrCategory({required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    if (section.body.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text(
          section.title,
          style: GoogleFonts.inter(
            color: FleaberColors.teal,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: FleaberColors.surface,
          borderRadius: BorderRadius.circular(FleaberRadius.md),
          border: Border.all(color: FleaberColors.alternate),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              section.title,
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: LegalLinkedText(
                  text: section.body,
                  style: GoogleFonts.inter(
                    color: FleaberColors.muted,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (section.linkUrl != null && section.linkLabel != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final uri = Uri.tryParse(section.linkUrl!);
                      if (uri == null) return;
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: FleaberColors.teal,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      section.linkLabel!,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: FleaberColors.teal, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FleaberRadius.md),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: FleaberColors.teal,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _MailtoChip extends StatelessWidget {
  const _MailtoChip({required this.label, required this.email});

  final String label;
  final String email;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final uri = Uri.parse('mailto:$email');
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: FleaberColors.teal),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: FleaberColors.teal,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TelChip extends StatelessWidget {
  const _TelChip({required this.label, required this.tel});

  final String label;
  final String tel;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final uri = Uri.parse(tel);
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: FleaberColors.teal),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: FleaberColors.teal,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
