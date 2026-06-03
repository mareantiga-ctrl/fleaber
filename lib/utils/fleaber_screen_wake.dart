import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Mantém o ecrã ligado durante direto (publicar ou ver).
abstract final class FleaberScreenWake {
  static int _refs = 0;

  static Future<void> acquire() async {
    _refs++;
    if (_refs == 1) {
      await WakelockPlus.enable();
    }
  }

  static Future<void> release() async {
    if (_refs <= 0) return;
    _refs--;
    if (_refs == 0) {
      await WakelockPlus.disable();
    }
  }
}

/// Liga wakelock no [initState] e desliga no [dispose].
mixin FleaberScreenWakeMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    unawaited(FleaberScreenWake.acquire());
  }

  @override
  void dispose() {
    unawaited(FleaberScreenWake.release());
    super.dispose();
  }
}
