import 'guided_session.dart';
import 'maestro_device.dart';
import 'staging_guard.dart';

/// Contexto partilhado durante uma execução `--full`.
class RegressionRunSession {
  RegressionRunSession({
    required this.guided,
    this.stagingEnv,
    this.stagingCheck,
    this.reportDir,
    this.maestroProbe,
    this.apkInstalled = false,
  }) : guidedSession = GuidedSession(enabled: guided, reportDir: reportDir);

  final bool guided;
  final Map<String, String>? stagingEnv;
  final StagingCheckResult? stagingCheck;
  final String? reportDir;
  final MaestroDeviceProbe? maestroProbe;
  final bool apkInstalled;
  final GuidedSession guidedSession;

  final Map<String, TestRunCache> _cache = {};

  String? get liveIdFromEnv {
    final direct = stagingEnv?['LIVE_OPS_TEST_LIVE_ID']?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final maestro = stagingEnv?['MAESTRO_LIVE_ID']?.trim();
    if (maestro != null && maestro.isNotEmpty) return maestro;
    return guidedSession.liveId;
  }

  String? get maestroDeviceBuyer =>
      stagingEnv?['MAESTRO_DEVICE_BUYER']?.trim() ??
      stagingEnv?['MAESTRO_DEVICE_DEFAULT']?.trim() ??
      maestroProbe?.defaultDevice;

  bool get maestroReady => maestroProbe?.canRunMaestro == true;

  bool get stagingOk => stagingCheck?.ok == true;

  TestRunCache? cached(String dedupeKey) => _cache[dedupeKey];

  void putCache(String dedupeKey, TestRunCache cache) {
    _cache[dedupeKey] = cache;
  }
}

class TestRunCache {
  TestRunCache({
    required this.status,
    this.layersRun = const [],
    this.message,
    this.durationMs = 0,
    this.realExecution = false,
  });

  final String status;
  final List<String> layersRun;
  final String? message;
  final int durationMs;
  final bool realExecution;
}
