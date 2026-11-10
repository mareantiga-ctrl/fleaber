import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'seller_product_form_widget.dart' show SellerProductFormWidget;

class SellerProductFormModel extends FlutterFlowModel<SellerProductFormWidget> {
  FocusNode? refFocusNode;
  TextEditingController? refTextController;

  FocusNode? titleFocusNode;
  TextEditingController? titleTextController;

  FocusNode? priceFocusNode;
  TextEditingController? priceTextController;

  FocusNode? descriptionFocusNode;
  TextEditingController? descriptionTextController;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    refFocusNode?.dispose();
    refTextController?.dispose();
    titleFocusNode?.dispose();
    titleTextController?.dispose();
    priceFocusNode?.dispose();
    priceTextController?.dispose();
    descriptionFocusNode?.dispose();
    descriptionTextController?.dispose();
  }
}
