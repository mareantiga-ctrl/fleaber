import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/live_director/models/director_beat.dart';
import 'package:fleaber/live_director/models/director_script.dart';
import 'package:fleaber/live_director/services/director_script_preview_service.dart';
import 'package:fleaber/live_director/services/director_script_validator.dart';
import 'package:fleaber/live_director/services/director_heat_map_service.dart';

void main() {
  test('preview orders beats by offset', () {
    final script = DirectorScript(
      name: 'test',
      beats: [
        DirectorBeat(
          beatId: 'b2',
          momentType: DirectorMomentType.approx,
          action: DirectorActionType.chat,
          approxSec: 120,
          messageText: 'Segunda',
        ),
        DirectorBeat(
          beatId: 'b1',
          momentType: DirectorMomentType.approx,
          action: DirectorActionType.enter,
          approxSec: 0,
        ),
      ],
    );
    final lines = DirectorScriptPreviewService().buildPreview(script);
    expect(lines.length, 2);
    expect(lines.first.offsetSec, 0);
    expect(lines.last.offsetSec, 120);
  });

  test('validator fails without live id', () async {
    final script = DirectorScript(
      name: 'x',
      operatorLabel: 'op',
      beats: const [],
    );
    final result = await DirectorScriptValidator().validate(
      script: script,
      liveRow: null,
      liveItems: const [],
      simProfiles: const [],
      killSwitchOk: true,
      confirmations: const {'products_stock': true},
    );
    expect(result.passed, isFalse);
    expect(result.errors.any((e) => e.code == 'live_id'), isTrue);
  });

  test('heat map builds segments', () {
    final script = DirectorScript(
      name: 'hm',
      beats: List.generate(
        5,
        (i) => DirectorBeat(
          beatId: 'b$i',
          momentType: DirectorMomentType.approx,
          action: DirectorActionType.like,
          approxSec: i * 60,
        ),
      ),
    );
    final segs = DirectorHeatMapService().buildFromScript(script, liveDurationMin: 10);
    expect(segs, isNotEmpty);
  });
}
