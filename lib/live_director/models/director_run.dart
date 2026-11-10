import 'director_manifest.dart';

class DirectorRun {
  const DirectorRun({
    required this.id,
    required this.scriptId,
    required this.scriptChecksum,
    required this.manifest,
    required this.liveId,
    required this.sellerId,
    required this.mode,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.killReason,
    this.liveStartedAt,
    this.timelineSealed = false,
    this.stats = const {},
    this.report,
  });

  final String id;
  final String scriptId;
  final String scriptChecksum;
  final Map<String, dynamic> manifest;
  final String liveId;
  final String sellerId;
  final String mode;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? killReason;
  final DateTime? liveStartedAt;
  final bool timelineSealed;
  final Map<String, dynamic> stats;
  final Map<String, dynamic>? report;

  DirectorManifest get parsedManifest =>
      DirectorManifest.fromJson(Map<String, dynamic>.from(manifest));

  factory DirectorRun.fromRow(Map<String, dynamic> row) => DirectorRun(
        id: row['id']?.toString() ?? '',
        scriptId: row['script_id']?.toString() ?? '',
        scriptChecksum: row['script_checksum']?.toString() ?? '',
        manifest: row['manifest'] is Map
            ? Map<String, dynamic>.from(row['manifest'] as Map)
            : const {},
        liveId: row['live_id']?.toString() ?? '',
        sellerId: row['seller_id']?.toString() ?? '',
        mode: row['mode']?.toString() ?? 'demo',
        status: row['status']?.toString() ?? 'pending',
        startedAt: DateTime.tryParse(row['started_at']?.toString() ?? ''),
        endedAt: DateTime.tryParse(row['ended_at']?.toString() ?? ''),
        killReason: row['kill_reason']?.toString(),
        liveStartedAt:
            DateTime.tryParse(row['live_started_at']?.toString() ?? ''),
        timelineSealed: row['timeline_sealed'] == true,
        stats: row['stats'] is Map
            ? Map<String, dynamic>.from(row['stats'] as Map)
            : const {},
        report: row['report'] is Map
            ? Map<String, dynamic>.from(row['report'] as Map)
            : null,
      );
}
