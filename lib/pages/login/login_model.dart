import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'login_widget.dart' show LoginWidget;
import 'package:flutter/material.dart';

class LoginModel extends FlutterFlowModel<LoginWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for EMAIL_LOGIN widget.
  FocusNode? emailLoginFocusNode;
  TextEditingController? emailLoginTextController;
  String? Function(BuildContext, String?)? emailLoginTextControllerValidator;
  // State field(s) for SENHA_LOGIN widget.
  FocusNode? senhaLoginFocusNode;
  TextEditingController? senhaLoginTextController;
  late bool senhaLoginVisibility;
  bool rememberOnDevice = true;
  String? Function(BuildContext, String?)? senhaLoginTextControllerValidator;

  @override
  void initState(BuildContext context) {
    senhaLoginVisibility = false;
  }

  @override
  void dispose() {
    emailLoginFocusNode?.dispose();
    emailLoginTextController?.dispose();

    senhaLoginFocusNode?.dispose();
    senhaLoginTextController?.dispose();
  }
}
