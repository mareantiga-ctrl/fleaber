import 'models.dart';

/// Classifica falhas: app vs infra/config vs manual.
enum FailureClass {
  appFail,
  infraFail,
  manualCheckpoint,
  guidedCheckpoint,
  pass,
  skip,
  blocked,
  other,
}

FailureClass classifyResult(TestRunResult r) {
  switch (r.status) {
    case 'pass':
      return FailureClass.pass;
    case 'manual':
      return FailureClass.manualCheckpoint;
    case 'skip_config_missing':
    case 'skip':
      return FailureClass.skip;
    case 'blocked':
      if (r.layersRun.contains('guided')) return FailureClass.guidedCheckpoint;
      return FailureClass.blocked;
    case 'fail':
    case 'flaky':
      return _isInfraFail(r) ? FailureClass.infraFail : FailureClass.appFail;
    default:
      return FailureClass.other;
  }
}

bool _isInfraFail(TestRunResult r) {
  final msg = (r.message ?? '').toLowerCase();
  const infraHints = [
    'dedupe',
    'já executado',
    'maestro/device em falta',
    'maestro cli',
    '.maestro/.env',
    'adb',
    'no devices',
    'emulador',
    'live_id em falta',
    'staging não',
    'skip_config',
    'ficheiro unit em falta',
  ];
  for (final h in infraHints) {
    if (msg.contains(h)) return true;
  }
  if (r.layersRun.contains('precheck')) return true;
  return false;
}

String failureClassLabel(FailureClass c) => switch (c) {
      FailureClass.appFail => 'app_fail',
      FailureClass.infraFail => 'infra_fail',
      FailureClass.manualCheckpoint => 'manual_checkpoint',
      FailureClass.guidedCheckpoint => 'guided_checkpoint',
      FailureClass.pass => 'pass',
      FailureClass.skip => 'skip_config',
      FailureClass.blocked => 'blocked',
      FailureClass.other => 'other',
    };
