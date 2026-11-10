import '/auth/supabase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/widgets/fleahub_auth_context_header.dart';
import '/index.dart';
import '/pages/login/login_responsive_shell.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_oauth_redirect.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_primary_button.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'esqueci_senha_model.dart';
export 'esqueci_senha_model.dart';

/// Recuperação de palavra-passe — mesmo shell desktop do Login/Registo.
class EsqueciSenhaWidget extends StatefulWidget {
  const EsqueciSenhaWidget({super.key});

  static String routeName = 'EsqueciSenha';
  static String routePath = '/esqueciSenha';

  @override
  State<EsqueciSenhaWidget> createState() => _EsqueciSenhaWidgetState();
}

class _EsqueciSenhaWidgetState extends State<EsqueciSenhaWidget> {
  late EsqueciSenhaModel _model;
  bool _sending = false;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EsqueciSenhaModel());
    _model.emailTextController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  InputDecoration _emailDecoration(BuildContext context) {
    return InputDecoration(
      hintText: 'E-mail',
      hintStyle: FlutterFlowTheme.of(context).bodyLarge.override(
            font: GoogleFonts.inter(),
            color: const Color(0xFFAAAAAA),
            fontSize: 18.0,
            lineHeight: 1.4,
          ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: FleaberColors.teal, width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFCC0000), width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFCC0000), width: 1.5),
        borderRadius: FleaberRadius.circularMd,
      ),
      contentPadding:
          const EdgeInsetsDirectional.fromSTEB(16.0, 18.0, 16.0, 18.0),
      prefixIcon: const Icon(
        Icons.mail_outline_rounded,
        color: FleaberColors.teal,
        size: 22.0,
      ),
    );
  }

  Future<void> _submit() async {
    final email = _model.emailTextController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Indica o teu e-mail para recuperares a palavra-passe.',
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await authManager.resetPassword(
        email: email,
        context: context,
        redirectTo: FleaberOAuthRedirect.passwordRecoveryRedirectTo(),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        body: SafeArea(
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
                fleaHubContext: false,
                cookieBottomPad: cookiePad,
                brandHeadline: 'Recupera o acesso à tua conta.',
                brandBody:
                    'Enviamos-te um link para o teu e-mail para definires '
                    'uma nova palavra-passe.',
                form: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FlutterFlowIconButton(
                        borderColor: Colors.transparent,
                        borderRadius: 20.0,
                        borderWidth: 1.0,
                        buttonSize: 40.0,
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: FleaberColors.teal,
                          size: 24.0,
                        ),
                        onPressed: () async {
                          context.safePop();
                        },
                      ),
                    ),
                    FleahubAuthContextHeader(
                      fleaHubContext: false,
                      defaultSubtitle: 'Esqueceste a palavra-passe?',
                      compact: split,
                    ),
                    Text(
                      'Introduz o e-mail da tua conta e enviamos-te um link '
                      'para definires uma nova palavra-passe.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: FleaberColors.muted,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _model.formKey,
                      autovalidateMode: AutovalidateMode.disabled,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _model.emailTextController,
                            focusNode: _model.textFieldFocusNode,
                            autofocus: false,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: _emailDecoration(context),
                            style: GoogleFonts.inter(
                              color: FleaberColors.text,
                              fontSize: 16,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            cursorColor: FleaberColors.teal,
                            validator: _model.emailTextControllerValidator
                                .asValidator(context),
                          ),
                          const SizedBox(height: 20),
                          FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Enviar link de recuperação',
                            loading: _sending,
                            fontWeight: FontWeight.bold,
                            onPressed: _sending ? null : _submit,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Se o e-mail existir na Fleaber, recebes o link '
                            'em poucos minutos. Verifica também a pasta de spam.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF777777),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Lembraste-te da palavra-passe?',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF888888),
                            fontSize: 15,
                          ),
                        ),
                        InkWell(
                          splashColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: () async {
                            context.pushNamed(LoginWidget.routeName);
                          },
                          child: Text(
                            ' Entrar',
                            style: GoogleFonts.inter(
                              color: FleaberColors.teal,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
