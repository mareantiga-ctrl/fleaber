import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:go_router/go_router.dart';

/// Login programático só para Maestro/debug (`fleaber://fleaber.com/maestroAutologin?…`).
/// Em release redirecciona para o login normal.
class MaestroAutologinPageWidget extends StatefulWidget {
  const MaestroAutologinPageWidget({
    super.key,
    this.email,
    this.password,
  });

  static String routeName = 'MaestroAutologin';
  static String routePath = '/maestroAutologin';

  final String? email;
  final String? password;

  @override
  State<MaestroAutologinPageWidget> createState() =>
      _MaestroAutologinPageWidgetState();
}

class _MaestroAutologinPageWidgetState extends State<MaestroAutologinPageWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    if (kReleaseMode) {
      if (!mounted) return;
      context.go(LoginWidget.routePath);
      return;
    }

    final email = widget.email?.trim() ?? '';
    final password = widget.password ?? '';
    if (email.isEmpty || password.isEmpty) {
      if (!mounted) return;
      context.go(LoginWidget.routePath);
      return;
    }

    GoRouter.of(context).prepareAuthEvent();
    final user = await authManager.signInWithEmail(
      context,
      email,
      password,
    );
    if (!mounted) return;

    if (user != null && currentUserUid != '') {
      context.pushNamedAuth(HomePageWidget.routeName, context.mounted);
      return;
    }

    context.go(LoginWidget.routePath);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF007782)),
      ),
    );
  }
}
