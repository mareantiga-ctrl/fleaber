import '/live_director/data/live_director_repository.dart';

/// Replay Reader — só leitura; nunca executa bots.
class DirectorReplayReader {
  const DirectorReplayReader();

  Future<List<ReplayTimelineEntry>> loadForLive(
    String liveId, {
    LiveDirectorRepository? repo,
  }) async {
    final r = repo ?? LiveDirectorRepository();
    final rows = await r.listTimeline(liveId);
    return rows
        .map((row) => ReplayTimelineEntry(
              liveOffsetMs: (row['live_offset_ms'] as num?)?.toInt() ?? 0,
              kind: row['kind']?.toString() ?? '',
              origin: row['origin']?.toString() ?? 'system',
              actorId: row['actor_id']?.toString(),
              payload: row['payload'] is Map
                  ? Map<String, dynamic>.from(row['payload'] as Map)
                  : const {},
              replayVisible: row['replay_visible'] != false,
              refTable: row['ref_table']?.toString(),
              refId: row['ref_id']?.toString(),
            ))
        .where((e) => e.replayVisible)
        .toList()
      ..sort((a, b) => a.liveOffsetMs.compareTo(b.liveOffsetMs));
  }

  /// Mensagens de chat para sincronizar com offset VOD (sem enviar novas).
  List<ReplayChatLine> chatLines(List<ReplayTimelineEntry> entries) {
    return entries
        .where((e) => e.kind == 'chat' || e.kind.contains('chat'))
        .map((e) => ReplayChatLine(
              liveOffsetMs: e.liveOffsetMs,
              body: e.payload['body']?.toString() ?? '',
              senderLabel: e.payload['sender_label']?.toString(),
            ))
        .toList();
  }
}

class ReplayTimelineEntry {
  const ReplayTimelineEntry({
    required this.liveOffsetMs,
    required this.kind,
    required this.origin,
    this.actorId,
    this.payload = const {},
    this.replayVisible = true,
    this.refTable,
    this.refId,
  });

  final int liveOffsetMs;
  final String kind;
  final String origin;
  final String? actorId;
  final Map<String, dynamic> payload;
  final bool replayVisible;
  final String? refTable;
  final String? refId;
}

class ReplayChatLine {
  const ReplayChatLine({
    required this.liveOffsetMs,
    required this.body,
    this.senderLabel,
  });

  final int liveOffsetMs;
  final String body;
  final String? senderLabel;
}
