import '/components/comp_master_footer_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'live_stream_vendor_widget.dart' show LiveStreamVendorWidget;
import 'package:flutter/material.dart';

class LiveStreamVendorModel extends FlutterFlowModel<LiveStreamVendorWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for comp_MasterFooter component.
  late CompMasterFooterModel compMasterFooterModel;

  @override
  void initState(BuildContext context) {
    compMasterFooterModel = createModel(context, () => CompMasterFooterModel());
  }

  @override
  void dispose() {
    compMasterFooterModel.dispose();
  }
}
