import '/live_director/models/director_run.dart';

class DirectorPostRunReportService {
  const DirectorPostRunReportService();

  Map<String, dynamic> build({
    required DirectorRun run,
    required int executed,
    required int blocked,
    required int delayed,
    required List<String> errors,
  }) {
    final m = run.parsedManifest;
    return {
      'run_id': run.id,
      'live_id': run.liveId,
      'script_name': m.scriptName,
      'checksum': m.checksum,
      'mode': m.mode.name,
      'beats_total': m.beats.length,
      'executed': executed,
      'blocked': blocked,
      'delayed': delayed,
      'errors': errors,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'suggestions': _suggestions(executed, blocked, errors),
    };
  }

  List<String> _suggestions(int executed, int blocked, List<String> errors) {
    final s = <String>[];
    if (blocked > executed) {
      s.add('Muitos beats bloqueados — rever seller gate ou janelas.');
    }
    if (errors.any((e) => e.contains('stock'))) {
      s.add('Stock insuficiente em beats comerciais — ajustar qty ou produtos.');
    }
    if (executed < 3) {
      s.add('Pouca actividade — considerar mais beats ou janelas mais largas.');
    }
    if (s.isEmpty) s.add('Run estável — pode duplicar script para próxima live.');
    return s;
  }
}
