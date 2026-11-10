import '/live_director/models/director_beat.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';
import '/live_director/services/director_script_preview_service.dart';

/// Heat map de actividade planeado (preview / console).
class DirectorHeatMapService {
  const DirectorHeatMapService();

  static const int bucketMin = 1;

  List<HeatMapSegment> buildFromScript(
    DirectorScript script, {
    int liveDurationMin = 60,
  }) {
    final preview = DirectorScriptPreviewService().buildPreview(script);
    final buckets = List<int>.filled(liveDurationMin, 0);

    for (final line in preview) {
      final min = (line.offsetSec / 60).floor().clamp(0, liveDurationMin - 1);
      buckets[min]++;
    }

    return _segmentsFromBuckets(buckets);
  }

  List<HeatMapSegment> buildFromAudit(
    List<Map<String, dynamic>> auditRows, {
    int liveDurationMin = 60,
  }) {
    final buckets = List<int>.filled(liveDurationMin, 0);
    for (final row in auditRows) {
      if (row['outcome']?.toString() != 'executed') continue;
      final ms = (row['live_offset_ms'] as num?)?.toInt() ?? 0;
      final min = (ms / 60000).floor().clamp(0, liveDurationMin - 1);
      buckets[min]++;
    }
    return _segmentsFromBuckets(buckets);
  }

  List<HeatMapSegment> _segmentsFromBuckets(List<int> buckets) {
    final segments = <HeatMapSegment>[];
    var i = 0;
    while (i < buckets.length) {
      final count = buckets[i];
      var j = i + 1;
      while (j < buckets.length && _sameLevel(buckets[j], count) == _sameLevel(count, count)) {
        if ((buckets[j] - count).abs() > 1) break;
        j++;
      }
      final level = _levelForCount(count);
      segments.add(HeatMapSegment(
        startMin: i,
        endMin: j,
        level: level,
        activityCount: count,
        label: count == 0
            ? 'Silêncio'
            : level == 'red'
                ? 'Excesso'
                : level == 'yellow'
                    ? (count <= 1 ? 'Parado' : 'Denso')
                    : 'Normal',
      ));
      i = j;
    }
    return segments;
  }

  String _levelForCount(int count) {
    if (count == 0) return 'yellow';
    if (count <= 2) return 'green';
    if (count <= 4) return 'yellow';
    return 'red';
  }

  bool _sameLevel(int a, int b) => _levelForCount(a) == _levelForCount(b);
}
