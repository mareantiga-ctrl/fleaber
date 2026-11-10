import '/flutter_flow/flutter_flow_util.dart';
import 'nova_senha_widget.dart' show NovaSenhaWidget;
import 'package:flutter/material.dart';

class NovaSenhaModel extends FlutterFlowModel<NovaSenhaWidget> {
  final formKey = GlobalKey<FormState>();
  FocusNode? newPasswordFocusNode;
  TextEditingController? newPasswordTextController;
  FocusNode? confirmPasswordFocusNode;
  TextEditingController? confirmPasswordTextController;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    newPasswordFocusNode?.dispose();
    newPasswordTextController?.dispose();
    confirmPasswordFocusNode?.dispose();
    confirmPasswordTextController?.dispose();
  }
}
