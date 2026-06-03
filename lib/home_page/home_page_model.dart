import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_widget.dart' show HomePageWidget;
import 'package:flutter/material.dart';

class HomePageModel extends FlutterFlowModel<HomePageWidget> {
  ///  State fields for stateful widgets in this page.

  // Pesquisa — separador Diretos / Marketplace.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  VoidCallback? textControllerListener;
  String? Function(BuildContext, String?)? textControllerValidator;

  FocusNode? marketplaceSearchFocusNode;
  TextEditingController? marketplaceSearchController;
  VoidCallback? marketplaceSearchControllerListener;
  String? Function(BuildContext, String?)? marketplaceSearchControllerValidator;

  void setupTextControllerListener(VoidCallback listener) {
    textControllerListener = listener;
    textController?.addListener(listener);
  }

  void setupMarketplaceSearchControllerListener(VoidCallback listener) {
    marketplaceSearchControllerListener = listener;
    marketplaceSearchController?.addListener(listener);
  }

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    if (textControllerListener != null) {
      textController?.removeListener(textControllerListener!);
    }
    if (marketplaceSearchControllerListener != null) {
      marketplaceSearchController?.removeListener(
        marketplaceSearchControllerListener!,
      );
    }
    textFieldFocusNode?.dispose();
    textController?.dispose();
    marketplaceSearchFocusNode?.dispose();
    marketplaceSearchController?.dispose();
  }
}
