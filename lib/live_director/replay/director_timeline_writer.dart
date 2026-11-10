import '/live_director/data/live_director_repository.dart';

/// Escreve eventos na Live Timeline durante o directo.
class DirectorTimelineWriter {
  const DirectorTimelineWriter();

  Future<void> write({
    required LiveDirectorRepository repo,
    required String runId,
    required String liveId,
    required String manifestId,
    required int liveOffsetMs,
    required String kind,
    required String origin,
    String? actorId,
    String? beatId,
    Map<String, dynamic>? payload,
    String? refTable,
    String? refId,
    bool replayVisible = true,
  }) async {
    await repo.appendTimeline(
      runId: runId,
      liveId: liveId,
      manifestId: manifestId,
      liveOffsetMs: liveOffsetMs,
      kind: kind,
      origin: origin,
      actorId: actorId,
      beatId: beatId,
      payload: payload,
      replayVisible: replayVisible,
      refTable: refTable,
      refId: refId,
    );
  }
}
