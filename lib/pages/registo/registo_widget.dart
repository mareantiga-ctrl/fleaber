import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import '/marketplace_feed_refresh.dart';
import '/widgets/fleaber_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import 'phone_verify_sheet.dart';
import 'registo_model.dart';
export 'registo_model.dart';

/// Create a professional and clean Sign Up page for a mobile app called
/// Fleaber.
///
/// The background must be solid white. At the top, include a circular
/// placeholder for a logo. Below the logo, add four large, rounded text
/// fields in this order: 1. Full Name, 2. Email, 3. Phone Number, 4.
/// Password. Under the fields, add a large primary button with the color
/// #007782 that says "Criar Conta". Below the button, add a "Sign in with
/// Google" option. At the bottom, add a small text that says "Já tem conta?
/// Entrar". Use a clean, friendly font and ensure there is a lot of
/// whitespace to make it very easy to read.
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

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => RegistoModel());

    _model.txtNomeTextController ??= TextEditingController();
    _model.txtNomeFocusNode ??= FocusNode();

    _model.txtEmailTextController ??= TextEditingController();
    _model.txtEmailFocusNode ??= FocusNode();

    _model.txtSenhaTextController ??= TextEditingController();
    _model.txtSenhaFocusNode ??= FocusNode();

    _model.txtTelefoneTextController ??= TextEditingController();
    _model.txtTelefoneFocusNode ??= FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Padding(
                  padding:
                      EdgeInsetsDirectional.fromSTEB(32.0, 40.0, 32.0, 40.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 90.0,
                        height: 90.0,
                        decoration: BoxDecoration(
                          color: Color(0xFFF0F8F9),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(0xFF007782),
                            width: 2.0,
                          ),
                        ),
                        child: Align(
                          alignment: AlignmentDirectional(0.0, 0.0),
                          child: Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF007782),
                            size: 40.0,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Fleaber',
                            style: FlutterFlowTheme.of(context)
                                .headlineMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .headlineMedium
                                        .fontStyle,
                                  ),
                                  color: Color(0xFF007782),
                                  fontSize: 28.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .fontStyle,
                                ),
                          ),
                          Text(
                            'Crie sua conta gratuitamente',
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                                  color: Color(0xFF888888),
                                  fontSize: 14.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.normal,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                          ),
                        ].divide(SizedBox(height: 4.0)),
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
                              decoration: InputDecoration(
                                hintText: 'Nome',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: const Color(0xFF6B7280),
                                      fontSize: 15.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE0E0E0),
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
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                    20.0, 18.0, 20.0, 18.0),
                                prefixIcon: Icon(
                                  Icons.person_outline_rounded,
                                  color: Color(0xFF007782),
                                  size: 20.0,
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    fontSize: 15.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                    color: const Color(0xFF101518),
                                  ),
                              cursorColor: Color(0xFF007782),
                              validator: _model.txtNomeTextControllerValidator
                                  .asValidator(context),
                            ),
                            TextFormField(
                              controller: _model.txtEmailTextController,
                              focusNode: _model.txtEmailFocusNode,
                              autofocus: false,
                              autofillHints: [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              obscureText: false,
                              decoration: InputDecoration(
                                hintText: 'Endereço de Email',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 15.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE0E0E0),
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
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                    20.0, 18.0, 20.0, 18.0),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: Color(0xFF007782),
                                  size: 20.0,
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    fontSize: 15.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                    color: const Color(0xFF101518),
                                  ),
                              keyboardType: TextInputType.emailAddress,
                              cursorColor: Color(0xFF007782),
                              validator: _model.txtEmailTextControllerValidator
                                  .asValidator(context),
                            ),
                            TextFormField(
                              controller: _model.txtSenhaTextController,
                              focusNode: _model.txtSenhaFocusNode,
                              autofocus: false,
                              autofillHints: [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              obscureText: !_model.txtSenhaVisibility,
                              decoration: InputDecoration(
                                hintText: 'Senha',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 15.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE0E0E0),
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
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                    20.0, 18.0, 20.0, 18.0),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF007782),
                                  size: 20.0,
                                ),
                                suffixIcon: InkWell(
                                  onTap: () async {
                                    safeSetState(() =>
                                        _model.txtSenhaVisibility =
                                            !_model.txtSenhaVisibility);
                                  },
                                  focusNode: FocusNode(skipTraversal: true),
                                  child: Icon(
                                    _model.txtSenhaVisibility
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Color(0xFFAAAAAA),
                                    size: 20.0,
                                  ),
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    fontSize: 15.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                    color: const Color(0xFF101518),
                                  ),
                              keyboardType: TextInputType.visiblePassword,
                              cursorColor: Color(0xFF007782),
                              validator: _model.txtSenhaTextControllerValidator
                                  .asValidator(context),
                            ),
                            TextFormField(
                              controller: _model.txtTelefoneTextController,
                              focusNode: _model.txtTelefoneFocusNode,
                              autofocus: false,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              textInputAction: TextInputAction.next,
                              obscureText: false,
                              decoration: InputDecoration(
                                hintText: 'Número de Telefone',
                                hintStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: const Color(0xFF6B7280),
                                      fontSize: 15.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE0E0E0),
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
                                fillColor: Color(0xFFF8F8F8),
                                contentPadding:
                                    EdgeInsetsDirectional.fromSTEB(
                                        20.0, 18.0, 20.0, 18.0),
                                prefixIcon: Icon(
                                  Icons.phone_outlined,
                                  color: Color(0xFF007782),
                                  size: 20.0,
                                ),
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    fontSize: 15.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.normal,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                    color: const Color(0xFF101518),
                                  ),
                              keyboardType: TextInputType.phone,
                              cursorColor: Color(0xFF007782),
                              validator: _model
                                  .txtTelefoneTextControllerValidator
                                  .asValidator(context),
                            ),
                          ].divide(SizedBox(height: 14.0)),
                        ),
                      ),
                      FleaberPrimaryButton(
                        width: double.infinity,
                        label: 'Criar Conta',
                        fontWeight: FontWeight.w600,
                        onPressed: () async {
                          if (_model.formKey.currentState == null ||
                              !_model.formKey.currentState!.validate()) {
                            return;
                          }
                          GoRouter.of(context).prepareAuthEvent();

                          final user = await authManager.createAccountWithEmail(
                            context,
                            _model.txtEmailTextController.text,
                            _model.txtSenhaTextController.text,
                          );
                          if (user == null) {
                            return;
                          }

                          final phoneRaw =
                              _model.txtTelefoneTextController.text.trim();

                          await ProfilesTable().insert({
                            'id': currentUserUid,
                            'full_name':
                                _model.txtNomeTextController.text.trim(),
                            'phone': phoneRaw,
                            'user_type': 'vendedor',
                          });

                          if (phoneRaw.length >= 9 && context.mounted) {
                            await showPhoneVerificationSheet(
                              context,
                              phoneRaw: phoneRaw,
                            );
                          }

                          requestMarketplaceFeedRefresh();

                          if (!context.mounted) return;
                          context.goNamedAuth(
                              HomePageWidget.routeName, context.mounted);
                        },
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 60.0,
                            height: 1.0,
                            decoration: BoxDecoration(
                              color: Color(0xFFE0E0E0),
                            ),
                          ),
                          Text(
                            'ou continue com',
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 13.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                          ),
                          Container(
                            width: 60.0,
                            height: 1.0,
                            decoration: BoxDecoration(
                              color: Color(0xFFE0E0E0),
                            ),
                          ),
                        ].divide(SizedBox(width: 16.0)),
                      ),
                      FFButtonWidget(
                        onPressed: () {
                          print('Button pressed ...');
                        },
                        text: 'Entrar com Google',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 56.0,
                          padding: EdgeInsetsDirectional.fromSTEB(
                              24.0, 0.0, 24.0, 0.0),
                          iconPadding: EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: Colors.white,
                          textStyle:
                              FlutterFlowTheme.of(context).titleSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                                    color: Color(0xFF333333),
                                    fontSize: 15.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                          elevation: 0.0,
                          borderSide: BorderSide(
                            color: Color(0xFFE0E0E0),
                            width: 1.5,
                          ),
                          borderRadius: FleaberRadius.circularMd,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Já tem conta?',
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      color: Color(0xFF888888),
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
                              context.pushNamed(LoginWidget.routeName);
                            },
                            child: Text(
                              'Entrar',
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: Color(0xFF007782),
                                    fontSize: 14.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .fontStyle,
                                  ),
                            ),
                          ),
                        ].divide(SizedBox(width: 4.0)),
                      ),
                    ].divide(SizedBox(height: 20.0)),
                  ),
                ),
              ].divide(SizedBox(height: 0.0)),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
