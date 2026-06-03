import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'perfil_vendedor_copy_widget.dart' show PerfilVendedorCopyWidget;
import 'package:flutter/material.dart';

class PerfilVendedorCopyModel
    extends FlutterFlowModel<PerfilVendedorCopyWidget> {
  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in Container widget.
  List<ChatsRow>? chatExistente;
  // Stores action output result for [Backend Call - Insert Row] action in Container widget.
  ChatsRow? novoChat;
  // State field(s) for TabBar widget.
  TabController? tabBarController;
  int get tabBarCurrentIndex =>
      tabBarController != null ? tabBarController!.index : 0;
  int get tabBarPreviousIndex =>
      tabBarController != null ? tabBarController!.previousIndex : 0;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    tabBarController?.dispose();
  }
}
