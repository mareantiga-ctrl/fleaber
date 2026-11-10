import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '/legal/legal_texts.dart';

/// Banner de cookies (web). Essenciais + link para política.
class FleaberCookieConsentBanner extends StatefulWidget {
  const FleaberCookieConsentBanner({super.key, required this.child});

  final Widget child;

  /// Preferência partilhada (web).
  static const prefsKey = 'fleaber_cookie_consent_v1';

  /// `true` = consentimento aceite ou banner não aplicável (nativo).
  /// Páginas podem ouvir para reservar padding e não tapar CTAs.
  static final ValueNotifier<bool> consentAccepted = ValueNotifier<bool>(true);

  /// Largura a partir da qual o cartão compacto (desktop) é seguro:
  /// abaixo disto a app ainda mostra bottom nav (~80 px).
  static const double compactBannerMinWidth = 1024;

  /// Altura do slot do banner (incl. margem) — eleva a app sem sobrepor a nav.
  static double bannerSlotExtent(double width) {
    // ≥1024: cartão compacto + margem 18 (sem bottom nav).
    if (width >= compactBannerMinWidth) return 96;
    // <1024: altura pintada do banner mobile (~106) + folga para a barra de
    // compra no detalhe (Stack). 168 era curto demais; 208 deixava vão excessivo.
    return 128;
  }

  /// Altura aproximada a reservar no scroll enquanto o banner está visível.
  static double scrollReserveForWidth(double width) {
    return scrollReserveForViewport(width: width, height: 900);
  }

  /// Padding extra no scroll (forms/landing) — o slot já eleva a shell;
  /// só respiração leve para não colar CTAs ao aviso.
  static double scrollReserveForViewport({
    required double width,
    required double height,
  }) {
    if (width >= 768) return 24;
    return 16;
  }

  @override
  State<FleaberCookieConsentBanner> createState() =>
      _FleaberCookieConsentBannerState();
}

class _FleaberCookieConsentBannerState
    extends State<FleaberCookieConsentBanner> {
  bool _ready = false;
  bool _accepted = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _ready = true;
      _accepted = true;
      FleaberCookieConsentBanner.consentAccepted.value = true;
      return;
    }
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final accepted =
          prefs.getBool(FleaberCookieConsentBanner.prefsKey) ?? false;
      setState(() {
        _accepted = accepted;
        _ready = true;
      });
      FleaberCookieConsentBanner.consentAccepted.value = accepted;
    });
  }

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FleaberCookieConsentBanner.prefsKey, true);
    if (!mounted) return;
    setState(() => _accepted = true);
    FleaberCookieConsentBanner.consentAccepted.value = true;
  }

  Future<void> _openPolicy() async {
    final uri = Uri.parse(LegalTexts.publicCookiesUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eleva a app (padding inferior = slot). Páginas com bottomNavigationBar
    // crítica (ex. detalhe de produto) acrescentam ainda um espaçador local
    // porque no Flutter web a barra do Scaffold pode continuar a pintar sobre
    // o aviso apesar deste Padding.
    if (!_ready || _accepted) {
      return widget.child;
    }
    final width = MediaQuery.sizeOf(context).width;
    final compact =
        width >= FleaberCookieConsentBanner.compactBannerMinWidth;
    final slot = FleaberCookieConsentBanner.bannerSlotExtent(width);
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: slot),
          child: widget.child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: compact
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SafeArea(top: false, child: _desktopBanner()),
                )
              : SafeArea(top: false, child: _mobileBanner()),
        ),
      ],
    );
  }

  /// Visual desktop alinhado à landing 2027 — mesma lógica de consentimento.
  Widget _desktopBanner() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            elevation: 12,
            color: const Color(0xFF161C20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                          height: 1.35,
                        ),
                        children: [
                          const TextSpan(
                            text:
                                'Utilizamos cookies essenciais para sessão e segurança. '
                                'Ao continuar, aceita a nossa política de cookies. ',
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: _openPolicy,
                              child: Text(
                                'Saber mais',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF00A3AD),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007782),
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Aceitar',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileBanner() {
    return Material(
      elevation: 8,
      color: const Color(0xFF101518),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Utilizamos cookies essenciais para sessão e segurança. '
              'Ao continuar, aceita a nossa política de cookies.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: _openPolicy,
                  child: Text(
                    'Saber mais',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF00A3AD),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _accept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007782),
                  ),
                  child: Text(
                    'Aceitar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
