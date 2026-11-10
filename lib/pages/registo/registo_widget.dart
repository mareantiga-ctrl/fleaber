import '/auth/supabase_auth/auth_util.dart';
import '/auth/supabase_auth/ensure_own_profile.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/marketplace_feed_refresh.dart';
import '/hub/hub_actions.dart';
import '/hub/hub_navigation.dart';
import '/hub/widgets/fleahub_auth_context_header.dart';
import '/pages/login/login_responsive_shell.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_legal_links_row.dart';
import '/widgets/fleaber_primary_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import 'phone_verify_sheet.dart';
import 'registo_model.dart';
export 'registo_model.dart';

/// Página de registo P09 — shell visual alinhado à P08 Login.
/// Lógica de autenticação / perfil / returnTo preservada.
class RegistoWidget extends StatefulWidget {
  const RegistoWidget({super.key});

  static String routeName = 'Registo';
  static String routePath = '/registo';

  @override
  State<RegistoWidget> createState() => _RegistoWidgetState();
}

class _RegistoWidgetState extends State<RegistoWidget> {
  late RegistoModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _creatingAccount = false;
  late final DateTime _formOpenedAt;
  final TextEditingController _honeypotController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _formOpenedAt = DateTime.now();
    _model = createModel(context, () => RegistoModel());

    _model.txtNomeTextController ??= TextEditingController();
    _model.txtNomeFocusNode ??= FocusNode();

    _model.txtEmailTextController ??= TextEditingController();
    _model.txtEmailFocusNode ??= FocusNode();

    _model.txtSenhaTextController ??= TextEditingController();
    _model.txtSenhaFocusNode ??= FocusNode();

    _model.txtTelefoneTextController ??= TextEditingController();
    _model.txtTelefoneFocusNode ??= FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureReturnToFromRoute();
      safeSetState(() {});
    });
  }

  void _captureReturnToFromRoute() {
    final returnTo =
        GoRouterState.of(context).uri.queryParameters['returnTo']?.trim();
    if (returnTo != null && returnTo.isNotEmpty) {
      HubActions.captureReturnTo(returnTo);
    }
  }

  @override
  void dispose() {
    _honeypotController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<String?> _solveAdaptiveChallenge() async {
    try {
      final issued = await SupaFlow.client.rpc(
        'signup_issue_challenge',
        params: {'p_ip_hint': null},
      );
      if (issued is! Map) return null;
      final challengeId = issued['challenge_id']?.toString();
      final question = issued['question']?.toString() ?? 'Quanto é 2 + 2?';
      if (challengeId == null || challengeId.isEmpty) return null;
      if (!mounted) return null;
      final answerCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Verificação rápida'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(question),
              const SizedBox(height: 12),
              TextField(
                controller: answerCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Resposta',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      final answer = answerCtrl.text.trim();
      answerCtrl.dispose();
      if (ok != true || answer.isEmpty) return null;
      final verified = await SupaFlow.client.rpc(
        'signup_verify_challenge',
        params: {
          'p_challenge_id': challengeId,
          'p_answer': answer,
        },
      );
      if (verified is Map && verified['ok'] == true) {
        return verified['challenge_token']?.toString();
      }
    } catch (e) {
      debugPrint('signup_challenge_err: $e');
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required BuildContext context,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: FlutterFlowTheme.of(context).bodyMedium.override(
            font: GoogleFonts.inter(
              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
            ),
            color: const Color(0xFF6B7280),
            fontSize: 15.0,
            letterSpacing: 0.0,
            fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
            fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
          ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF007782), width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: FlutterFlowTheme.of(context).error,
          width: 1.5,
        ),
        borderRadius: FleaberRadius.circularMd,
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: FlutterFlowTheme.of(context).error,
          width: 1.5,
        ),
        borderRadius: FleaberRadius.circularMd,
      ),
      filled: true,
      fillColor: const Color(0xFFF8F8F8),
      contentPadding:
          const EdgeInsetsDirectional.fromSTEB(20.0, 18.0, 20.0, 18.0),
      prefixIcon: Icon(icon, color: const Color(0xFF007782), size: 20.0),
      suffixIcon: suffix,
    );
  }

  TextStyle _fieldTextStyle(BuildContext context) {
    return FlutterFlowTheme.of(context).bodyMedium.override(
          font: GoogleFonts.inter(
            fontWeight: FontWeight.normal,
            fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
          ),
          fontSize: 15.0,
          letterSpacing: 0.0,
          fontWeight: FontWeight.normal,
          fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
          color: const Color(0xFF101518),
        );
  }

  Future<void> _submitCreateAccount() async {
    if (_model.formKey.currentState == null ||
        !_model.formKey.currentState!.validate()) {
      return;
    }
    setState(() => _creatingAccount = true);
    try {
      final returnTo = HubActions.resolvePendingReturnTo(context);
      GoRouter.of(context).prepareAuthEvent(true);

      final email = _model.txtEmailTextController.text.trim();
      final password = _model.txtSenhaTextController.text;
      final fullName = _model.txtNomeTextController.text.trim();
      final phoneRaw = _model.txtTelefoneTextController.text.trim();

      final formMs =
          DateTime.now().difference(_formOpenedAt).inMilliseconds;
      var result = await authManager.createEmailAccount(
        context,
        email: email,
        password: password,
        fullName: fullName,
        phone: phoneRaw,
        formMs: formMs,
        honeypot: _honeypotController.text,
      );

      // Desafio adaptativo só quando o servidor pede (IP partilhado em pico).
      final needsChallenge = result.status == EmailAccountCreateStatus.failed &&
          (result.errorMessage ?? '').toLowerCase().contains('verificação');
      if (needsChallenge && mounted) {
        final token = await _solveAdaptiveChallenge();
        if (token != null && token.isNotEmpty && mounted) {
          result = await authManager.createEmailAccount(
            context,
            email: email,
            password: password,
            fullName: fullName,
            phone: phoneRaw,
            formMs: formMs,
            honeypot: _honeypotController.text,
            challengeToken: token,
          );
        }
      }

      if (result.status == EmailAccountCreateStatus.failed) {
        // SnackBar já mostrado em createEmailAccount.
        return;
      }

      // Conta criada; falta confirmar e-mail — não é erro.
      if (result.status ==
          EmailAccountCreateStatus.pendingEmailConfirmation) {
        if (!context.mounted) return;
        final pendingMsg =
            'Conta criada. Enviámos um e-mail para $email — '
            'abre o link para activar e depois entra.';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pendingMsg),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirma o teu e-mail'),
            content: Text(pendingMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (returnTo != null && returnTo.isNotEmpty) {
          HubActions.openLoginForReturn(context, returnTo: returnTo);
        } else {
          context.goNamed(LoginWidget.routeName);
        }
        return;
      }

      // Sessão activa — garantir perfil (trigger + insert/update).
      await ensureOwnProfileRow(
        fullName: fullName,
        phone: phoneRaw,
      );
      try {
        await ProfilesTable().update(
          data: {
            'full_name': fullName,
            'phone': phoneRaw,
            'user_type': 'vendedor',
          },
          matchingRows: (q) => q.eq('id', currentUserUid),
        );
      } on PostgrestException catch (e) {
        debugPrint('registo profile update: ${e.message}');
      }

      if (phoneRaw.length >= 9 && context.mounted) {
        await showPhoneVerificationSheet(
          context,
          phoneRaw: phoneRaw,
        );
      }

      requestMarketplaceFeedRefresh();

      if (!context.mounted) return;
      if (returnTo != null && returnTo.isNotEmpty) {
        await HubActions.finishAuthWithHubWelcome(
          context,
          returnTo: returnTo,
        );
        return;
      }
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      HubNavigation.goAppHome(context);
    } finally {
      if (mounted) {
        setState(() => _creatingAccount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleaHubContext = HubActions.isFleaHubAuthContext(context);
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final split = width >= LoginResponsiveShell.splitBreakpoint;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.light,
          colorScheme: Theme.of(context).colorScheme.copyWith(
                brightness: Brightness.light,
                onSurface: const Color(0xFF101518),
              ),
        ),
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FleaberColors.bgTint,
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              SafeArea(
                top: true,
                bottom: false,
                child: ValueListenableBuilder<bool>(
                  valueListenable: FleaberCookieConsentBanner.consentAccepted,
                  builder: (context, cookiesOk, _) {
                    final keyboardInset =
                        MediaQuery.viewInsetsOf(context).bottom;
                    final cookiePad = (!kIsWeb || cookiesOk)
                        ? 0.0
                        : FleaberCookieConsentBanner.scrollReserveForViewport(
                            width: width,
                            height: size.height,
                          );
                    // Teclado + cookies: espaço extra para CTAs/links no fundo.
                    final bottomPad = cookiePad +
                        (keyboardInset > 0 ? 28.0 : 0.0) +
                        (size.height <= 700 ? 24.0 : 0.0);
                    return LoginResponsiveShell(
                      fleaHubContext: fleaHubContext,
                      cookieBottomPad: bottomPad,
                      // Mesmo estado de registo: copy uniforme (sem texto de login).
                      brandHeadline: 'Cria a tua conta.',
                      brandBody: fleaHubContext
                          ? 'Regista-te para reservas, compras, gravados e '
                              'marketplace — no mesmo sítio do directo.'
                          : 'Cria a tua conta gratuita em poucos minutos.',
                      form: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FleahubAuthContextHeader(
                            fleaHubContext: fleaHubContext,
                            defaultSubtitle: 'Cria a tua conta gratuitamente',
                            compact: split || size.height <= 700,
                            // Evita copy de login («Entra para…») no registo.
                            suppressFleaHubBodyCopy: true,
                          ),
                          Form(
                            key: _model.formKey,
                            autovalidateMode: AutovalidateMode.disabled,
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                TextFormField(
                                  controller: _model.txtNomeTextController,
                                  focusNode: _model.txtNomeFocusNode,
                                  autofocus: false,
                                  autofillHints: const [AutofillHints.name],
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  obscureText: false,
                                  decoration: _fieldDecoration(
                                    context: context,
                                    hint: 'Nome',
                                    icon: Icons.person_outline_rounded,
                                  ),
                                  style: _fieldTextStyle(context),
                                  cursorColor: const Color(0xFF007782),
                                  validator: _model
                                      .txtNomeTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller: _model.txtEmailTextController,
                                  focusNode: _model.txtEmailFocusNode,
                                  autofocus: false,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  obscureText: false,
                                  decoration: _fieldDecoration(
                                    context: context,
                                    hint: 'E-mail',
                                    icon: Icons.email_outlined,
                                  ),
                                  style: _fieldTextStyle(context),
                                  keyboardType: TextInputType.emailAddress,
                                  cursorColor: const Color(0xFF007782),
                                  validator: _model
                                      .txtEmailTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller: _model.txtSenhaTextController,
                                  focusNode: _model.txtSenhaFocusNode,
                                  autofocus: false,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  textInputAction: TextInputAction.next,
                                  obscureText: !_model.txtSenhaVisibility,
                                  decoration: _fieldDecoration(
                                    context: context,
                                    hint: 'Palavra-passe',
                                    icon: Icons.lock_outline_rounded,
                                    suffix: InkWell(
                                      onTap: () async {
                                        safeSetState(() =>
                                            _model.txtSenhaVisibility =
                                                !_model.txtSenhaVisibility);
                                      },
                                      focusNode:
                                          FocusNode(skipTraversal: true),
                                      child: Icon(
                                        _model.txtSenhaVisibility
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: const Color(0xFFAAAAAA),
                                        size: 20.0,
                                      ),
                                    ),
                                  ),
                                  style: _fieldTextStyle(context),
                                  keyboardType: TextInputType.visiblePassword,
                                  cursorColor: const Color(0xFF007782),
                                  validator: _model
                                      .txtSenhaTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller: _model.txtTelefoneTextController,
                                  focusNode: _model.txtTelefoneFocusNode,
                                  autofocus: false,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  obscureText: false,
                                  decoration: _fieldDecoration(
                                    context: context,
                                    hint: 'Telemóvel (opcional)',
                                    icon: Icons.phone_outlined,
                                  ),
                                  style: _fieldTextStyle(context),
                                  keyboardType: TextInputType.phone,
                                  cursorColor: const Color(0xFF007782),
                                  validator: _model
                                      .txtTelefoneTextControllerValidator
                                      .asValidator(context),
                                ),
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                          // Honeypot anti-bot (invisível; bots preenchem → rejeitado no servidor)
                          Offstage(
                            offstage: true,
                            child: TextField(
                              controller: _honeypotController,
                              autofillHints: const [],
                              decoration: const InputDecoration(
                                labelText: 'Website',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Criar conta',
                            fontWeight: FontWeight.w600,
                            loading: _creatingAccount,
                            onPressed: _creatingAccount
                                ? null
                                : () async => _submitCreateAccount(),
                          ),
                          // Google OAuth sem handler — oculto (igual P08 login).
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Já tens conta?',
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      color: const Color(0xFF888888),
                                      fontSize: 14.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                              ),
                              InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  final dest =
                                      HubActions.resolvePendingReturnTo(
                                          context);
                                  if (dest != null &&
                                      HubActions.isFleaHubReturnPath(dest)) {
                                    HubActions.openLoginForReturn(
                                      context,
                                      returnTo: dest,
                                    );
                                  } else {
                                    context.pushNamed(LoginWidget.routeName);
                                  }
                                },
                                child: Text(
                                  'Entrar',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: const Color(0xFF007782),
                                        fontSize: 14.0,
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ].divide(const SizedBox(width: 4.0)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Center(
                              child: TextButton(
                                onPressed: () =>
                                    HubActions.openFleaHubLanding(context),
                                child: Text(
                                  'Explorar FleaHub',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF007782),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: FleaberLegalLinksRow(compact: false),
                          ),
                        ].divide(const SizedBox(height: 16.0)),
                      ),
                    );
                  },
                ),
              ),
              if (fleaHubContext && HubNavigation.hasInternalBack(context))
                HubBackButton.topLeftOverlay(context),
            ],
          ),
        ),
      ),
    );
  }
}
