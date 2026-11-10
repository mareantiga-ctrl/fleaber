import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_elevation.dart';
import '/widgets/fleaber_primary_button.dart';

import '../hub_public_access.dart';
import '../hub_urls.dart';
import '../routing/hub_route_paths.dart';
import '../theme/hub_theme.dart';
import '../widgets/hub_seo_scope.dart';
import '../seo/hub_seo_meta.dart';

/// Launcher QA — abrir FleaHub / handle no browser.
/// URL: `/hub-dev` (mesmo código Flutter que app + fleaber.pt).
///
/// Página 07 — redesign visual responsivo (sem alterar lógica de navegação).
class HubDevLauncherPage extends StatefulWidget {
  const HubDevLauncherPage({super.key});

  static const routePath = '/hub-dev';
  static const routeName = 'HubDevLauncher';

  /// Largura útil desktop — só esta página.
  static const double desktopMaxWidth = 1080;
  static const double desktopBreakpoint = 900;

  @override
  State<HubDevLauncherPage> createState() => _HubDevLauncherPageState();
}

class _HubDevLauncherPageState extends State<HubDevLauncherPage> {
  final _handleCtrl = TextEditingController(text: 'claudia');
  final _handleFocus = FocusNode();

  @override
  void dispose() {
    _handleCtrl.dispose();
    _handleFocus.dispose();
    super.dispose();
  }

  String get _handle => _handleCtrl.text.trim().toLowerCase();

  void _open(String path) {
    if (!mounted) return;
    context.go(path);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copiado',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: HubTheme.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: HubTheme.surfaceElevated,
      labelStyle: GoogleFonts.inter(color: HubTheme.textSecondary, fontSize: 13),
      hintStyle: GoogleFonts.inter(color: HubTheme.textMuted, fontSize: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HubTheme.accent, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !HubPublicAccess.devHubLauncherEnabled) {
      return Scaffold(
        backgroundColor: HubTheme.bg,
        body: Center(
          child: Text(
            'Hub dev launcher só disponível na web.',
            style: HubTheme.body,
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= HubDevLauncherPage.desktopBreakpoint;
    final handle = _handle;

    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubLanding(indexable: false),
      child: Scaffold(
        backgroundColor: HubTheme.bg,
        body: Column(
          children: [
            _TopBar(desktop: desktop),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: HubDevLauncherPage.desktopMaxWidth,
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 32 : 20,
                      desktop ? 28 : 20,
                      desktop ? 32 : 20,
                      40,
                    ),
                    children: [
                      _HeroHeader(desktop: desktop),
                      if (!HubPublicAccess.registrationEnabled) ...[
                        const SizedBox(height: 16),
                        const _RegistrationNotice(),
                      ],
                      const SizedBox(height: 28),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _HandlePanel(
                                handleCtrl: _handleCtrl,
                                handleFocus: _handleFocus,
                                fieldDecoration: _fieldDecoration,
                                handle: handle,
                                onOpenProfile: handle.isEmpty
                                    ? null
                                    : () => _open(
                                          HubRoutePaths.profileFor(handle),
                                        ),
                                onOpenLive: handle.isEmpty
                                    ? null
                                    : () => _open(
                                          HubRoutePaths.liveFor(handle),
                                        ),
                                onOpenShop: handle.isEmpty
                                    ? null
                                    : () => _open(
                                          HubRoutePaths.shopFor(handle),
                                        ),
                                onOpenReviews: handle.isEmpty
                                    ? null
                                    : () => _open(
                                          HubRoutePaths.reviewsFor(handle),
                                        ),
                                onHandleChanged: () => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 4,
                              child: _ShortcutsAndUrls(
                                handle: handle,
                                onOpenLanding: () =>
                                    _open(HubRoutePaths.landing),
                                onOpenNotFound: () =>
                                    _open('/handle-inexistente-qa'),
                                onCopy: _copy,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _HandlePanel(
                          handleCtrl: _handleCtrl,
                          handleFocus: _handleFocus,
                          fieldDecoration: _fieldDecoration,
                          handle: handle,
                          onOpenProfile: handle.isEmpty
                              ? null
                              : () =>
                                  _open(HubRoutePaths.profileFor(handle)),
                          onOpenLive: handle.isEmpty
                              ? null
                              : () => _open(HubRoutePaths.liveFor(handle)),
                          onOpenShop: handle.isEmpty
                              ? null
                              : () => _open(HubRoutePaths.shopFor(handle)),
                          onOpenReviews: handle.isEmpty
                              ? null
                              : () =>
                                  _open(HubRoutePaths.reviewsFor(handle)),
                          onHandleChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 20),
                        _ShortcutsAndUrls(
                          handle: handle,
                          onOpenLanding: () => _open(HubRoutePaths.landing),
                          onOpenNotFound: () =>
                              _open('/handle-inexistente-qa'),
                          onCopy: _copy,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HubTheme.surface,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: desktop ? 28 : 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          boxShadow: const [FleaberElevation.sm],
        ),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HubDevLauncherPage.desktopMaxWidth,
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'FleaHub',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: HubTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: HubTheme.teal.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      desktop ? 'QA · hub-dev' : 'QA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: HubTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (desktop) ...[
                  const Spacer(),
                  Text(
                    'Ferramenta interna',
                    style: GoogleFonts.inter(
                      color: HubTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hub — testes browser',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: desktop ? 28 : 22,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'O mesmo código Hub da app. Alterações em lib/hub/ reflectem aqui '
          'e em fleaber.pt após publicação.',
          style: HubTheme.body.copyWith(fontSize: desktop ? 15 : 14),
        ),
      ],
    );
  }
}

class _RegistrationNotice extends StatelessWidget {
  const _RegistrationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2118),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF5D4037)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFFCC80), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Registo público desactivado (fase de testes). '
              'Só «Entrar» visível no FleaHub.',
              style: GoogleFonts.inter(
                color: const Color(0xFFFFE0B2),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandlePanel extends StatelessWidget {
  const _HandlePanel({
    required this.handleCtrl,
    required this.handleFocus,
    required this.fieldDecoration,
    required this.handle,
    required this.onOpenProfile,
    required this.onOpenLive,
    required this.onOpenShop,
    required this.onOpenReviews,
    required this.onHandleChanged,
  });

  final TextEditingController handleCtrl;
  final FocusNode handleFocus;
  final InputDecoration Function({required String label, String? hint})
      fieldDecoration;
  final String handle;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenLive;
  final VoidCallback? onOpenShop;
  final VoidCallback? onOpenReviews;
  final VoidCallback onHandleChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Vendedor', style: HubTheme.titleMd),
          const SizedBox(height: 6),
          Text(
            'Indica o handle e abre o perfil, live, loja ou avaliações.',
            style: HubTheme.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: handleCtrl,
            focusNode: handleFocus,
            onChanged: (_) => onHandleChanged(),
            textInputAction: TextInputAction.done,
            decoration: fieldDecoration(
              label: 'Handle vendedor',
              hint: 'ex. claudia',
            ),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 14),
          FleaberPrimaryButton(
            label: 'Abrir perfil Hub',
            onPressed: onOpenProfile,
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'Abrir live Hub',
            icon: Icons.videocam_outlined,
            onPressed: onOpenLive,
          ),
          const SizedBox(height: 8),
          _SecondaryButton(
            label: 'Abrir marketplace',
            icon: Icons.storefront_outlined,
            onPressed: onOpenShop,
          ),
          const SizedBox(height: 8),
          _SecondaryButton(
            label: 'Abrir avaliações',
            icon: Icons.star_outline_rounded,
            onPressed: onOpenReviews,
          ),
        ],
      ),
    );
  }
}

class _ShortcutsAndUrls extends StatelessWidget {
  const _ShortcutsAndUrls({
    required this.handle,
    required this.onOpenLanding,
    required this.onOpenNotFound,
    required this.onCopy,
  });

  final String handle;
  final VoidCallback onOpenLanding;
  final VoidCallback onOpenNotFound;
  final Future<void> Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final profileUrl = handle.isEmpty
        ? HubUrls.displayHost
        : HubUrls.profile(handle);
    final landing = HubUrls.fleahubLanding();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Atalhos', style: HubTheme.titleMd),
              const SizedBox(height: 12),
              FleaberPrimaryButton(
                label: 'Abrir FleaHub landing',
                onPressed: onOpenLanding,
              ),
              const SizedBox(height: 8),
              _SecondaryButton(
                label: 'Abrir página não encontrada',
                icon: Icons.search_off_outlined,
                onPressed: onOpenNotFound,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('URLs canónicas', style: HubTheme.titleMd),
              const SizedBox(height: 10),
              _UrlRow(label: 'Landing', value: landing, onCopy: onCopy),
              const SizedBox(height: 10),
              _UrlRow(label: 'Perfil', value: profileUrl, onCopy: onCopy),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final Future<void> Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: HubTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: HubTheme.body.copyWith(fontSize: 12, color: Colors.white),
              ),
            ),
            IconButton(
              tooltip: 'Copiar',
              onPressed: () => onCopy(value),
              icon: const Icon(Icons.copy_rounded, size: 18),
              color: HubTheme.accent,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: HubTheme.surfaceElevated,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: HubTheme.accent),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HubTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: const [FleaberElevation.md],
      ),
      child: child,
    );
  }
}
