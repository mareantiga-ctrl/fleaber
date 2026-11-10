import '/auth/supabase_auth/auth_util.dart';
import '/auth/supabase_auth/ensure_own_profile.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import '/utils/login_remember_storage.dart';
import '/hub/hub_actions.dart';
import '/hub/hub_navigation.dart';
import '/hub/routing/hub_route_paths.dart';
import '/hub/widgets/fleahub_auth_context_header.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_legal_links_row.dart';
import '/widgets/fleaber_primary_button.dart';
import '/hub/hub_qa_diag.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_model.dart';
import 'login_responsive_shell.dart';
export 'login_model.dart';

/// Create a clean and elegant login page for a mobile app called Fleaber.
///
/// The background should be white. Include a space for a circular logo at the
/// top. Add two large, rounded text fields: one for Email and one for
/// Password. Add a large primary button with the color #007782 that says
/// "Entrar". Below, add a "Sign in with Google" button. Use a friendly font
/// and ensure plenty of whitespace so it's easy to read for people aged 45+.
class LoginWidget extends StatefulWidget {
  const LoginWidget({super.key});

  static String routeName = 'Login';
  static String routePath = '/login';

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

class _LoginWidgetState extends State<LoginWidget> {
  late LoginModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  int _d1EmailLen = 0;
  int _d1PassLen = 0;
  bool _facebookBusy = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LoginModel());

    _model.emailLoginTextController ??= TextEditingController();
    _model.emailLoginFocusNode ??= FocusNode();

    _model.senhaLoginTextController ??= TextEditingController();
    _model.senhaLoginFocusNode ??= FocusNode();

    if (kIsWeb) {
      HubQaDiag.logD1ScreenOpen();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _captureReturnToFromRoute();
      // C1: limpar passwords legadas; só pré-preencher e-mail.
      await LoginRememberStorage.purgeLegacyPasswords();
      final savedEmail = await LoginRememberStorage.loadRememberedEmail();
      if (!mounted || savedEmail == null) return;
      _model.rememberOnDevice = true;
      _model.emailLoginTextController?.text = savedEmail;
      // Nunca autofill da password a partir de storage local.
      if (kIsWeb) {
        _d1EmailLen = savedEmail.length;
        _d1PassLen = 0;
        HubQaDiag.logD1RememberAutofill(
          emailLen: _d1EmailLen,
          passLen: _d1PassLen,
        );
      }
      safeSetState(() {});
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  void _captureReturnToFromRoute() {
    final returnTo =
        GoRouterState.of(context).uri.queryParameters['returnTo']?.trim();
    if (returnTo != null && returnTo.isNotEmpty) {
      HubActions.captureReturnTo(returnTo);
    }
  }

  Future<void> _submitLogin() async {
    if (kIsWeb) {
      HubQaDiag.logD1Submit(
        emailLen: _model.emailLoginTextController.text.length,
        passLen: _model.senhaLoginTextController.text.length,
      );
    }
    if (kDebugMode) {
      debugPrint(
        'MAESTRO_LOGIN len email=${_model.emailLoginTextController.text.length} '
        'pass=${_model.senhaLoginTextController.text.length}',
      );
    }
    if (!functions.checkLoginFields(
      _model.emailLoginTextController.text,
      _model.senhaLoginTextController.text,
    )) {
      await showDialog(
        context: context,
        builder: (alertDialogContext) {
          return AlertDialog(
            title: Text('Erro'),
            content: Text('E-mail inválido ou campo vazio'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(alertDialogContext),
                child: Text('Ok'),
              ),
            ],
          );
        },
      );
      return;
    }

    final returnTo = HubActions.resolvePendingReturnTo(context);
    GoRouter.of(context).prepareAuthEvent(true);

    final user = await authManager.signInWithEmail(
      context,
      _model.emailLoginTextController.text,
      _model.senhaLoginTextController.text,
    );
    if (user == null) {
      return;
    }

    final email = _model.emailLoginTextController.text.trim();
    if (_model.rememberOnDevice) {
      await LoginRememberStorage.saveRememberedEmail(email);
    } else {
      await LoginRememberStorage.clearCredentials();
    }

    // Perfil pode faltar se o registo ficou só em Auth (confirmação de e-mail).
    await ensureOwnProfileRow();

    if (!mounted) return;
    if (currentUserUid != '') {
      if (returnTo != null && returnTo.isNotEmpty) {
        await HubActions.finishAuthWithHubWelcome(
          context,
          returnTo: returnTo,
        );
        return;
      }
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      HubNavigation.goAppHome(context);
      return;
    }

    await showDialog(
      context: context,
      builder: (alertDialogContext) {
        return AlertDialog(
          title: Text('Erro no Login'),
          content: Text(
            'Utilizador não encontrado ou palavra-passe errada. Verifica os teus dados ou regista-te!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(alertDialogContext),
              child: Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitFacebookLogin() async {
    if (_facebookBusy) return;
    _facebookBusy = true;
    safeSetState(() {});

    final returnTo = HubActions.resolvePendingReturnTo(context);
    GoRouter.of(context).prepareAuthEvent(true);

    try {
      await authManager.signInWithFacebook(
        context,
        returnTo: returnTo,
      );

      if (!mounted) return;
      // Web: redirect completo para Facebook — não continuar neste ecrã.
      if (kIsWeb) return;
      if (currentUserUid != '') {
        if (returnTo != null && returnTo.isNotEmpty) {
          await HubActions.finishAuthWithHubWelcome(
            context,
            returnTo: returnTo,
          );
          return;
        }
        AppStateNotifier.instance.updateNotifyOnAuthChange(true);
        HubNavigation.goAppHome(context);
        return;
      }

      final fbDetail = lastFacebookLoginFailureMessage?.trim();
      await showDialog<void>(
        context: context,
        builder: (alertDialogContext) {
          return AlertDialog(
            title: Text('Erro no Login'),
            content: Text(
              fbDetail?.isNotEmpty == true
                  ? fbDetail!
                  : 'Não foi possível iniciar sessão com Facebook. Tenta novamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(alertDialogContext),
                child: Text('Ok'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        _facebookBusy = false;
        safeSetState(() {});
      }
    }
  }

  /// Maestro usa `identifier` nativo; no web o Semantics bloqueia teclado/colar.
  Widget _loginMaestroField({
    required String identifier,
    required String label,
    required Widget field,
  }) {
    if (kIsWeb) return field;
    return Semantics(
      identifier: identifier,
      textField: true,
      label: label,
      child: ExcludeSemantics(child: field),
    );
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
              final cookiePad = (!kIsWeb || cookiesOk)
                  ? 0.0
                  : FleaberCookieConsentBanner.scrollReserveForViewport(
                      width: width,
                      height: size.height,
                    );
              return LoginResponsiveShell(
                fleaHubContext: fleaHubContext,
                cookieBottomPad: cookiePad,
                form: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FleahubAuthContextHeader(
                        fleaHubContext: fleaHubContext,
                        defaultSubtitle: 'Bem-vindo de volta!',
                        compact: split,
                        suppressFleaHubBodyCopy: split && fleaHubContext,
                      ),
                      Form(
                        key: _model.formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            _loginMaestroField(
                              identifier: 'login_email',
                              label: 'E-mail',
                              field: TextFormField(
                              controller: _model.emailLoginTextController,
                              focusNode: _model.emailLoginFocusNode,
                              autofocus: false,
                              autofillHints: const [AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              obscureText: false,
                              enableInteractiveSelection: true,
                              decoration: InputDecoration(
                                hintText: 'E-mail',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyLarge
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyLarge
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyLarge
                                            .fontStyle,
                                      ),
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 18.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontStyle,
                                      lineHeight: 1.4,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFDDDDDD),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF007782),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                    24.0, 20.0, 24.0, 20.0),
                                prefixIcon: Icon(
                                  Icons.mail_outline_rounded,
                                  color: Color(0xFF007782),
                                  size: 22.0,
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontStyle,
                                    ),
                                    color: Color(0xFF222222),
                                    fontSize: 18.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .fontStyle,
                                    lineHeight: 1.4,
                                  ),
                              cursorColor: Color(0xFF007782),
                              onChanged: (v) {
                                if (kIsWeb) {
                                  final len = v.length;
                                  HubQaDiag.logD1FieldChange(
                                    field: 'email',
                                    prevLen: _d1EmailLen,
                                    newLen: len,
                                  );
                                  _d1EmailLen = len;
                                }
                                safeSetState(() {});
                              },
                              validator: _model
                                  .emailLoginTextControllerValidator
                                  .asValidator(context),
                            ),
                            ),
                            _loginMaestroField(
                              identifier: 'login_password',
                              label: 'Palavra-passe',
                              field: TextFormField(
                              controller: _model.senhaLoginTextController,
                              focusNode: _model.senhaLoginFocusNode,
                              autofocus: false,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              obscureText: !_model.senhaLoginVisibility,
                              enableInteractiveSelection: true,
                              decoration: InputDecoration(
                                hintText: 'Palavra-passe',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyLarge
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyLarge
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyLarge
                                            .fontStyle,
                                      ),
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 18.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontStyle,
                                      lineHeight: 1.4,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFDDDDDD),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF007782),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                    24.0, 20.0, 24.0, 20.0),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF007782),
                                  size: 22.0,
                                ),
                                suffixIcon: InkWell(
                                  onTap: () async {
                                    safeSetState(() =>
                                        _model.senhaLoginVisibility =
                                            !_model.senhaLoginVisibility);
                                  },
                                  focusNode: FocusNode(skipTraversal: true),
                                  child: Icon(
                                    _model.senhaLoginVisibility
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 22,
                                  ),
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .fontStyle,
                                    ),
                                    color: Color(0xFF222222),
                                    fontSize: 18.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .fontStyle,
                                    lineHeight: 1.4,
                                  ),
                              cursorColor: Color(0xFF007782),
                              onFieldSubmitted: (_) {
                                unawaited(_submitLogin());
                              },
                              onChanged: (v) {
                                if (kIsWeb) {
                                  final len = v.length;
                                  HubQaDiag.logD1FieldChange(
                                    field: 'password',
                                    prevLen: _d1PassLen,
                                    newLen: len,
                                  );
                                  _d1PassLen = len;
                                }
                                safeSetState(() {});
                              },
                              validator: _model
                                  .senhaLoginTextControllerValidator
                                  .asValidator(context),
                            ),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _model.rememberOnDevice,
                                  activeColor: const Color(0xFF007782),
                                  onChanged: (v) => safeSetState(
                                    () => _model.rememberOnDevice = v ?? false,
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => safeSetState(
                                      () => _model.rememberOnDevice =
                                          !_model.rememberOnDevice,
                                    ),
                                    child: Text(
                                      'Memorizar e-mail neste dispositivo',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF444444),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    context.pushNamed(
                                        EsqueciSenhaWidget.routeName);
                                  },
                                  child: Text(
                                    'Esqueceste a palavra-passe?',
                                    style: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w500,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                    .fontStyle,
                                          ),
                                          color: Color(0xFF007782),
                                          fontSize: 15.0,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w500,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            Semantics(
                              identifier: 'login_entrar',
                              button: true,
                              label: 'Entrar',
                              onTap: () => unawaited(_submitLogin()),
                              child: ExcludeSemantics(
                                child: FleaberPrimaryButton(
                              width: double.infinity,
                              label: 'Entrar',
                              onPressed: () => unawaited(_submitLogin()),
                            ),
                              ),
                            ),
                            // Google OAuth sem handler — oculto até existir fluxo real.
                            Semantics(
                              identifier: 'login_facebook',
                              button: true,
                              label: 'Entrar com Facebook',
                              child: ExcludeSemantics(
                                child: Opacity(
                                  opacity: _facebookBusy ? 0.65 : 1.0,
                                  child: InkWell(
                                    onTap: _facebookBusy
                                        ? null
                                        : () => unawaited(_submitFacebookLogin()),
                                    splashColor: Colors.transparent,
                                    focusColor: Colors.transparent,
                                    hoverColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    child: Container(
                                      width: double.infinity,
                                      height: 60.0,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: FleaberRadius.circularMd,
                                        border: Border.all(
                                          color: Color(0xFFDDDDDD),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.facebook,
                                              size: 24.0,
                                            ),
                                            const SizedBox(width: 12.0),
                                            Flexible(
                                              child: Text(
                                                'Entrar com Facebook',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: FlutterFlowTheme.of(context)
                                                    .titleMedium
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleMedium
                                                                .fontStyle,
                                                      ),
                                                      color: Color(0xFF333333),
                                                      fontSize: 17.0,
                                                      letterSpacing: 0.0,
                                                      fontWeight: FontWeight.w600,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleMedium
                                                              .fontStyle,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ].divide(SizedBox(height: 20.0)),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding:
                        EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 24.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Ainda não tens conta? ',
                          style:
                              FlutterFlowTheme.of(context).bodyMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    color: Color(0xFF888888),
                                    fontSize: 16.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                        ),
                        InkWell(
                          splashColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: () async {
                            // Sempre o mesmo funil Hub (returnTo preservado).
                            // Antes: com returnTo FleaHub + registo OFF →
                            // openRegistoForReturn reabria o login (loop).
                            final dest =
                                HubActions.resolvePendingReturnTo(context) ??
                                    HubRoutePaths.landing;
                            HubActions.openRegistoForReturn(
                              context,
                              returnTo: dest,
                            );
                          },
                          child: Text(
                            'Registar-se',
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                                  color: Color(0xFF007782),
                                  fontSize: 16.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Center(
                      child: TextButton(
                        onPressed: () => HubActions.openFleaHubLanding(context),
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
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: FleaberLegalLinksRow(compact: false),
                  ),
                ],
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
    );
  }
}
