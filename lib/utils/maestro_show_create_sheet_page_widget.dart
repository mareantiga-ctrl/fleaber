import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/index.dart';
import '/widgets/fleaber_create_sheet.dart';

/// Abre o bottom sheet «Criar» para Maestro (contorna tap no FAB).
class MaestroShowCreateSheetPageWidget extends StatefulWidget {
  const MaestroShowCreateSheetPageWidget({super.key});

  static String routeName = 'MaestroShowCreateSheet';
  static String routePath = '/maestroShowCreateSheet';

  @override
  State<MaestroShowCreateSheetPageWidget> createState() =>
      _MaestroShowCreateSheetPageWidgetState();
}

class _MaestroShowCreateSheetPageWidgetState
    extends State<MaestroShowCreateSheetPageWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  Future<void> _open() async {
    if (kReleaseMode) {
      if (!mounted) return;
      context.go(HomePageWidget.routePath);
      return;
    }
    if (!mounted) return;
    await FleaberCreateSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.shrink(),
    );
  }
}
