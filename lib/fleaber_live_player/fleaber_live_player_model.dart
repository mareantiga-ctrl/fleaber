import '/flutter_flow/flutter_flow_util.dart';
import 'fleaber_live_player_widget.dart' show FleaberLivePlayerWidget;
import 'package:flutter/material.dart';

class FleaberLivePlayerModel extends FlutterFlowModel<FleaberLivePlayerWidget> {
  late TextEditingController chatTextController;
  late FocusNode chatFocusNode;

  @override
  void initState(BuildContext context) {
    chatTextController = TextEditingController();
    chatFocusNode = FocusNode();
  }

  @override
  void dispose() {
    chatTextController.dispose();
    chatFocusNode.dispose();
  }
}
