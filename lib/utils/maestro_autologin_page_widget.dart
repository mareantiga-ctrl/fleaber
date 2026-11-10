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
    this.next,
  });

  static String routeName = 'MaestroAutologin';
  static String routePath = '/maestroAutologin';

  final String? email;
  final String? password;
  /// Rota interna após login (ex. `/homePage`, `/fleaberLivePlayer?liveId=…`).
  final String? next;

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
    // Lab local (fleahub-lab / 127.0.0.1 / localhost): permitir mesmo em release web.
    // Produção (fleaber.pt) continua a bloquear.
    final host = Uri.base.host.toLowerCase();
    final path = Uri.base.path.toLowerCase();
    const labDefine = bool.fromEnvironment(
      'FLEABER_LAB_AUTOLOGIN',
      defaultValue: false,
    );
    final allowAutologin = !kReleaseMode ||
        labDefine ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        path.contains('fleahub-lab');

    if (!allowAutologin) {
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
    try {
      final user = await authManager
          .signInWithEmail(
            context,
            email,
            password,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (user != null && currentUserUid != '') {
        final nextRaw = (widget.next ?? '').trim();
        if (nextRaw.isNotEmpty) {
          var path = nextRaw.startsWith('/') ? nextRaw : '/$nextRaw';
          // adb/Maestro partem orderId/otherUserId do `next` — fundir da URI actual.
          final baseQp = Uri.base.queryParameters;
          final parsed = Uri.tryParse('https://local$path');
          if (parsed != null && parsed.path == '/chatPage') {
            final merged = Map<String, String>.from(parsed.queryParameters);
            for (final key in ['orderId', 'otherUserId', 'chatId']) {
              if ((merged[key] ?? '').isEmpty) {
                final v = baseQp[key]?.trim() ?? '';
                if (v.isNotEmpty) merged[key] = v;
              }
            }
            final q =
                merged.isEmpty ? '' : '?${Uri(queryParameters: merged).query}';
            path = '${parsed.path}$q';
          }
          context.go(path);
          return;
        }
        context.pushNamedAuth(HomePageWidget.routeName, context.mounted);
        return;
      }
    } catch (_) {
      // Timeout / rede / credenciais — nunca ficar na roda branca.
    }

    if (!mounted) return;
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
