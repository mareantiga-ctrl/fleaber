import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'esqueci_senha_widget.dart' show EsqueciSenhaWidget;
import 'package:flutter/material.dart';

class EsqueciSenhaModel extends FlutterFlowModel<EsqueciSenhaWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? emailTextController;
  String? Function(BuildContext, String?)? emailTextControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    textFieldFocusNode?.dispose();
    emailTextController?.dispose();
  }
}
