
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'chat_page_widget.dart' show ChatPageWidget;
import 'package:flutter/material.dart';

class ChatPageModel extends FlutterFlowModel<ChatPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in ChatPage widget.
  List<ChatMessagesRow>? resultadoSupabase;
  Stream<List<ChatMessagesRow>>? containerSupabaseStream;
  // State field(s) for input_mensagem widget.
  FocusNode? inputMensagemFocusNode;
  TextEditingController? inputMensagemTextController;
  String? Function(BuildContext, String?)? inputMensagemTextControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    inputMensagemFocusNode?.dispose();
    inputMensagemTextController?.dispose();
  }
}
