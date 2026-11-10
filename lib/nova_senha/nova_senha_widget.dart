import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/widgets/fleahub_auth_context_header.dart';
import '/index.dart';
import '/pages/login/login_responsive_shell.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_password_recovery.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_primary_button.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nova_senha_model.dart';
export 'nova_senha_model.dart';

/// Nova palavra-passe — mesmo shell desktop do Login/Registo.
class NovaSenhaWidget extends StatefulWidget {
  const NovaSenhaWidget({super.key});

  static String routeName = 'NovaSenha';
  static String routePath = '/novaSenha';

  @override
  State<NovaSenhaWidget> createState() => _NovaSenhaWidgetState();
}

class _NovaSenhaWidgetState extends State<NovaSenhaWidget> {
  late NovaSenhaModel _model;
  bool _submitting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NovaSenhaModel());
    _model.newPasswordTextController ??= TextEditingController();
    _model.confirmPasswordTextController ??= TextEditingController();
    _model.newPasswordFocusNode ??= FocusNode();
    _model.confirmPasswordFocusNode ??= FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  bool get _hasRecoverySession => loggedIn;

  InputDecoration _fieldDecoration(
    BuildContext context,
    String hint, {
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      hintText: hint,
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
        Icons.lock_outline_rounded,
        color: FleaberColors.teal,
        size: 22.0,
      ),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(
          obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: const Color(0xFF888888),
          size: 22,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final newPwd = _model.newPasswordTextController!.text;
    final confirmPwd = _model.confirmPasswordTextController!.text;

    if (newPwd.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A nova palavra-passe deve ter pelo menos 6 caracteres.',
          ),
        ),
      );
      return;
    }
    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A confirmação não coincide com a nova palavra-passe.',
          ),
        ),
      );
      return;
    }
    if (!_hasRecoverySession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Link inválido ou expirado. Pede um novo link para recuperares a palavra-passe.',
          ),
        ),
      );
      if (mounted) context.goNamed(EsqueciSenhaWidget.routeName);
      return;
    }

    setState(() => _submitting = true);
    try {
      FleaberPasswordRecovery.markCompleted();
      AppStateNotifier.instance.clearRedirectLocation();
      await SupaFlow.client.auth.updateUser(UserAttributes(password: newPwd));
      await authManager.refreshUser();
      await authManager.signOut();
      AppStateNotifier.instance.clearRedirectLocation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Palavra-passe actualizada. Entra com a nova palavra-passe.',
          ),
        ),
      );
      context.goNamed(LoginWidget.routeName);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível actualizar: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionOk = _hasRecoverySession;
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final split = width >= LoginResponsiveShell.splitBreakpoint;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
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
                brandHeadline: 'Define uma nova palavra-passe.',
                brandBody:
                    'Escolhe uma palavra-passe segura para continuares a '
                    'utilizar a Fleaber.',
                form: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FleahubAuthContextHeader(
                      fleaHubContext: false,
                      defaultSubtitle: 'Define a tua nova palavra-passe',
                      compact: split,
                    ),
                    if (!sessionOk) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: FleaberRadius.circularMd,
                          border: Border.all(color: const Color(0xFFE0A86A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Link inválido ou expirado',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF7A4E00),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Este ecrã abre depois de clicares no link do e-mail. '
                              'Se o link já não for válido, pede um novo.',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF7A4E00),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => context
                                    .goNamed(EsqueciSenhaWidget.routeName),
                                child: Text(
                                  'Pedir novo link',
                                  style: GoogleFonts.inter(
                                    color: FleaberColors.teal,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'Escolhe uma palavra-passe com pelo menos 6 caracteres.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: FleaberColors.muted,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _model.formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _model.newPasswordTextController,
                            focusNode: _model.newPasswordFocusNode,
                            obscureText: _obscureNew,
                            enabled: sessionOk,
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration(
                              context,
                              'Nova palavra-passe',
                              obscure: _obscureNew,
                              onToggle: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                            ),
                            cursorColor: FleaberColors.teal,
                            style: GoogleFonts.inter(
                              color: FleaberColors.text,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _model.confirmPasswordTextController,
                            focusNode: _model.confirmPasswordFocusNode,
                            obscureText: _obscureConfirm,
                            enabled: sessionOk,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (sessionOk) _submit();
                            },
                            decoration: _fieldDecoration(
                              context,
                              'Confirmar palavra-passe',
                              obscure: _obscureConfirm,
                              onToggle: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                            cursorColor: FleaberColors.teal,
                            style: GoogleFonts.inter(
                              color: FleaberColors.text,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Guardar nova palavra-passe',
                            loading: _submitting,
                            fontWeight: FontWeight.bold,
                            onPressed:
                                (!sessionOk || _submitting) ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            context.goNamed(LoginWidget.routeName),
                        child: Text(
                          'Voltar ao login',
                          style: GoogleFonts.inter(
                            color: FleaberColors.teal,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
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
