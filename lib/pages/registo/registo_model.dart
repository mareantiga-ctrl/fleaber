import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'registo_widget.dart' show RegistoWidget;
import 'package:flutter/material.dart';

class RegistoModel extends FlutterFlowModel<RegistoWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for txt_nome widget.
  FocusNode? txtNomeFocusNode;
  TextEditingController? txtNomeTextController;
  String? Function(BuildContext, String?)? txtNomeTextControllerValidator;
  String? _txtNomeTextControllerValidator(BuildContext context, String? val) {
    final t = val?.trim() ?? '';
    if (t.isEmpty) {
      return 'Indica o teu nome.';
    }
    if (t.length < 2) {
      return 'O nome é demasiado curto.';
    }
    if (t.length > 80) {
      return 'O nome é demasiado longo.';
    }
    return null;
  }

  // State field(s) for txt_email widget.
  FocusNode? txtEmailFocusNode;
  TextEditingController? txtEmailTextController;
  String? Function(BuildContext, String?)? txtEmailTextControllerValidator;
  String? _txtEmailTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'O e-mail é obrigatório.';
    }

    if (!RegExp(kTextValidatorEmailRegex).hasMatch(val)) {
      return 'Indica um e-mail válido.';
    }
    return null;
  }

  // State field(s) for txt_senha widget.
  FocusNode? txtSenhaFocusNode;
  TextEditingController? txtSenhaTextController;
  late bool txtSenhaVisibility;
  String? Function(BuildContext, String?)? txtSenhaTextControllerValidator;
  String? _txtSenhaTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'A palavra-passe é obrigatória.';
    }

    if (val.length < 6) {
      return 'A palavra-passe deve ter pelo menos 6 caracteres.';
    }

    return null;
  }

  // State field(s) for txt_telefone widget.
  FocusNode? txtTelefoneFocusNode;
  TextEditingController? txtTelefoneTextController;
  String? Function(BuildContext, String?)? txtTelefoneTextControllerValidator;
  String? _txtTelefoneTextControllerValidator(
      BuildContext context, String? val) {
    final t = val?.trim() ?? '';
    if (t.isEmpty) return null;
    final digitsOnly =
        RegExp(r'\d').allMatches(t).map((m) => m.group(0)!).join();
    if (digitsOnly.length < 9) {
      return 'Telefone deve ter pelo menos 9 dígitos.';
    }
    return null;
  }

  @override
  void initState(BuildContext context) {
    txtNomeTextControllerValidator = _txtNomeTextControllerValidator;
    txtEmailTextControllerValidator = _txtEmailTextControllerValidator;
    txtSenhaVisibility = false;
    txtSenhaTextControllerValidator = _txtSenhaTextControllerValidator;
    txtTelefoneTextControllerValidator = _txtTelefoneTextControllerValidator;
  }

  @override
  void dispose() {
    txtNomeFocusNode?.dispose();
    txtNomeTextController?.dispose();

    txtEmailFocusNode?.dispose();
    txtEmailTextController?.dispose();

    txtSenhaFocusNode?.dispose();
    txtSenhaTextController?.dispose();

    txtTelefoneFocusNode?.dispose();
    txtTelefoneTextController?.dispose();
  }
}
