import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '/live_director/data/live_director_repository.dart';
import '/live_director/engine/director_actor_runtime.dart';
import '/live_director/engine/director_seller_activity_gate.dart';
import '/live_director/engine/director_world_model.dart';
import '/live_director/models/director_beat.dart';
import '/live_director/models/director_manifest.dart';
import '/live_director/models/director_run.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';
import '/live_director/replay/director_timeline_writer.dart';
import '/live_director/services/director_heat_map_service.dart';
import '/live_director/services/director_post_run_report_service.dart';

/// Motor principal — só corre durante directo (status running).
class LiveDirectorEngine extends ChangeNotifier {
  LiveDirectorEngine({
    LiveDirectorRepository? repository,
    DirectorActorRuntime? actorRuntime,
  })  : _repo = repository ?? LiveDirectorRepository(),
        _actors = actorRuntime ?? DirectorActorRuntime();

  final LiveDirectorRepository _repo;
  final DirectorActorRuntime _actors;
  final _sellerGate = DirectorSellerActivityGate();
  final _timeline = DirectorTimelineWriter();
  final _random = Random();

  DirectorRun? _run;
  DirectorManifest? _manifest;
  DirectorWorldModel? _world;
  Timer? _tickTimer;
  int _auditSeq = 0;
  int _commercialFailures = 0;
  bool _paused = false;
  bool _killed = false;
  DateTime? _liveStartedAt;

  final _scheduled = <_ScheduledBeat>[];
  final _executed = <ConsoleBeatState>[];
  final _blocked = <ConsoleBeatState>[];
  final _delayed = <ConsoleBeatState>[];
  final _pending = <ConsoleBeatState>[];
  final _errors = <String>[];

  DirectorConsoleState _console = const DirectorConsoleState();

  DirectorConsoleState get console => _console;
  DirectorRun? get run => _run;
  bool get isRunning => _run?.status == 'running' && !_killed;

  Future<void> startRun(DirectorRun run) async {
    if (run.status != 'preflight_ok' && run.status != 'pending') {
      throw StateError('Run não está pronta: ${run.status}');
    }
    _run = run;
    _manifest = run.parsedManifest;
    _liveStartedAt = DateTime.now().toUtc();
    _auditSeq = 0;
    _commercialFailures = 0;
    _killed = false;
    _paused = false;

    await _repo.updateRunStatus(
      run.id,
      status: 'running',
      startedAt: _liveStartedAt,
      liveStartedAt: _liveStartedAt,
    );
    await _repo.linkLiveToRun(
      run.liveId,
      run.id,
      run.mode,
    );

    _world = DirectorWorldModel(
      liveId: run.liveId,
      sellerId: run.sellerId,
    );
    _world = await _world!.refresh(_repo);
    _buildSchedule();
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    notifyListeners();
  }

  void _buildSchedule() {
    _scheduled.clear();
    final m = _manifest!;
    final start = _liveStartedAt ?? DateTime.now().toUtc();
    for (final beat in m.beats) {
      if (!beat.enabled) continue;
      DateTime? due;
      switch (beat.momentType) {
        case DirectorMomentType.approx:
          due = start.add(Duration(seconds: beat.approxSec ?? 0));
        case DirectorMomentType.window:
          final ws = beat.windowStartSec ?? 0;
          final we = beat.windowEndSec ?? ws;
          final mid = ws + ((we - ws) ~/ 2);
          due = start.add(Duration(seconds: mid + _jitter(m.policy.jitterSec)));
        case DirectorMomentType.immediateOnRun:
          due = start.add(const Duration(seconds: 2));
        case DirectorMomentType.manual:
          due = null;
        default:
          due = null; // event-driven — resolved in _tick
      }
      _scheduled.add(_ScheduledBeat(beat: beat, dueAt: due));
    }
    _scheduled.sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) return 0;
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    _refreshConsole();
  }

  int _jitter(int maxSec) {
    if (maxSec <= 0) return 0;
    return _random.nextInt(maxSec * 2 + 1) - maxSec;
  }

  Future<void> _tick() async {
    if (_run == null || _manifest == null || _killed || _paused) return;

    final killGlobal =
        await _repo.killSwitchActive('global') ||
        await _repo.killSwitchActive('run', _run!.id) ||
        await _repo.killSwitchActive('live', _run!.liveId);
    if (killGlobal) {
      await kill('kill_switch_active');
      return;
    }

    _world = await _world!.refresh(_repo);
    final now = DateTime.now().toUtc();
    final sellerActive = _sellerGate.isSellerActive(_world!, now);

    for (final sb in _scheduled.where((s) => !s.done)) {
      if (sb.dueAt == null) {
        if (_eventReady(sb.beat)) {
          sb.dueAt = now;
        } else {
          continue;
        }
      }
      if (sb.dueAt!.isAfter(now)) continue;

      if (sellerActive &&
          (sb.beat.action == DirectorActionType.chat ||
              sb.beat.action == DirectorActionType.like ||
              sb.beat.action == DirectorActionType.likeBurst)) {
        _delayBeat(sb, 'seller_active');
        continue;
      }
      if (sellerActive && sb.beat.isCommercial) {
        _delayBeat(sb, 'seller_active_commercial');
        continue;
      }

      if (sb.dueAt != null &&
          now.difference(sb.dueAt!).inSeconds > sb.beat.maxSlipSec) {
        await _audit(sb.beat, 'blocked', reason: 'max_slip_exceeded');
        sb.done = true;
        _blocked.add(ConsoleBeatState(
          beatId: sb.beat.beatId,
          status: 'blocked',
          reason: 'max_slip',
        ));
        continue;
      }

      await _executeBeat(sb);
    }

    _refreshConsole();
    notifyListeners();
  }

  bool _eventReady(DirectorBeat beat) {
    switch (beat.momentType) {
      case DirectorMomentType.afterRaffleActive:
        return _world!.raffleActive;
      case DirectorMomentType.afterSellerSilent:
        final last = _world!.lastSellerSignalAt;
        if (last == null) return true;
        return DateTime.now().toUtc().difference(last).inSeconds >=
            beat.afterSilentSec;
      case DirectorMomentType.afterEvent:
        final ev = beat.afterEvent ?? '';
        if (ev.startsWith('item=')) {
          final id = ev.substring(5);
          return _world!.activeItemId == id;
        }
        return false;
      default:
        return false;
    }
  }

  void _delayBeat(_ScheduledBeat sb, String reason) {
    sb.dueAt = DateTime.now().toUtc().add(const Duration(seconds: 30));
    _delayed.removeWhere((d) => d.beatId == sb.beat.beatId);
    _delayed.add(ConsoleBeatState(
      beatId: sb.beat.beatId,
      status: 'delayed',
      scheduledAt: sb.dueAt,
      reason: reason,
    ));
  }

  Future<void> _executeBeat(_ScheduledBeat sb) async {
    final beat = sb.beat;
    final m = _manifest!;
    final actor = _pickActor(beat, m);
    if (actor == null && _needsActor(beat)) {
      await _audit(beat, 'blocked', reason: 'no_actor');
      sb.done = true;
      return;
    }

    if (beat.isCommercial) {
      final stock = _world!.stockByItemId[beat.liveItemId ?? ''] ?? 0;
      if (stock < beat.qty) {
        await _audit(beat, 'stock_guard', reason: 'insufficient_stock');
        sb.done = true;
        _commercialFailures++;
        if (_commercialFailures >= 2) _paused = true;
        return;
      }
    }

    await _audit(beat, 'planned');

    if (actor == null) {
      sb.done = true;
      return;
    }

    final notesTag = '${m.policy.notesTagPrefix}:${_run!.id}';
    final result = await _actors.execute(
      actor: actor,
      beat: beat,
      liveId: _run!.liveId,
      sellerId: _run!.sellerId,
      notesTag: notesTag,
    );

    final offsetMs = _liveOffsetMs();
    if (result.ok) {
      await _timeline.write(
        repo: _repo,
        runId: _run!.id,
        liveId: _run!.liveId,
        manifestId: m.scriptId,
        liveOffsetMs: offsetMs,
        kind: beat.action.name,
        origin: 'sim',
        actorId: actor.profileId,
        beatId: beat.beatId,
        payload: result.payload,
        refTable: result.refTable,
        refId: result.refId,
      );
      await _audit(beat, 'executed', actorId: actor.profileId);
      _executed.add(ConsoleBeatState(
        beatId: beat.beatId,
        status: 'executed',
        actorTag: actor.internalTag,
        actionLabel: beat.action.name,
        confidence: beat.confidence,
      ));
      _commercialFailures = 0;
    } else {
      await _audit(beat, 'blocked', reason: result.error);
      _errors.add(result.error ?? 'fail');
      if (beat.isCommercial) _commercialFailures++;
    }
    sb.done = true;
  }

  DirectorCastMember? _pickActor(DirectorBeat beat, DirectorManifest m) {
    if (beat.actorTag != null) {
      for (final c in m.castPool) {
        if (c.internalTag == beat.actorTag) return c;
      }
      return null;
    }
    final persona = beat.actorPersona ?? 'observer';
    final pool = m.castPool.where((c) => c.persona == persona).toList();
    if (pool.isEmpty && m.castPool.isNotEmpty) return m.castPool.first;
    if (pool.isEmpty) return null;
    return pool[_random.nextInt(pool.length)];
  }

  bool _needsActor(DirectorBeat beat) {
    return beat.action != DirectorActionType.silence &&
        beat.action != DirectorActionType.wait;
  }

  int _liveOffsetMs() {
    if (_liveStartedAt == null) return 0;
    return DateTime.now().toUtc().difference(_liveStartedAt!).inMilliseconds;
  }

  Future<void> _audit(
    DirectorBeat beat,
    String outcome, {
    String? reason,
    String? actorId,
  }) async {
    if (_run == null) return;
    _auditSeq++;
    await _repo.appendAudit(
      runId: _run!.id,
      liveId: _run!.liveId,
      beatId: beat.beatId,
      seq: _auditSeq,
      eventType: beat.action.name,
      outcome: outcome,
      reason: reason,
      actorId: actorId,
      productId: beat.liveItemId,
      liveOffsetMs: _liveOffsetMs(),
      payload: {'moment': beat.momentType.name},
    );
  }

  void _refreshConsole() {
    final m = _manifest;
    if (m == null) return;
    final next = _scheduled.where((s) => !s.done).cast<_ScheduledBeat?>().firstOrNull;
    _pending
      ..clear()
      ..addAll(_scheduled
          .where((s) => !s.done)
          .map((s) => ConsoleBeatState(
                beatId: s.beat.beatId,
                status: 'pending',
                scheduledAt: s.dueAt,
                actionLabel: s.beat.action.name,
                actorTag: s.beat.actorTag,
                confidence: s.beat.confidence,
              )));
    final total = m.beats.length;
    final done = _executed.length + _blocked.length;
    _console = DirectorConsoleState(
      viewersTotal: _world?.viewerCount ?? 0,
      botsOnline: m.castPool.length,
      sellerMode: _sellerGate.isSellerActive(
              _world ?? DirectorWorldModel(liveId: '', sellerId: ''),
              DateTime.now().toUtc())
          ? 'active'
          : 'open',
      raffleActive: _world?.raffleActive ?? false,
      executed: List.unmodifiable(_executed),
      pending: List.unmodifiable(_pending),
      delayed: List.unmodifiable(_delayed),
      blocked: List.unmodifiable(_blocked),
      nextBeat: next != null
          ? ConsoleBeatState(
              beatId: next.beat.beatId,
              status: 'next',
              scheduledAt: next.dueAt,
              actionLabel: next.beat.action.name,
              confidence: next.beat.confidence,
            )
          : null,
      secondsToNext: next?.dueAt != null
          ? next!.dueAt!.difference(DateTime.now().toUtc()).inSeconds
          : null,
      stockByItem: _world?.stockByItemId ?? const {},
      progressPct: total > 0 ? (done / total) * 100 : 0,
      heatMap: DirectorHeatMapService().buildFromAudit([]),
      recentErrors: List.unmodifiable(_errors.take(5)),
      directorPaused: _paused,
      killActive: _killed,
    );
  }

  Future<void> pause() async {
    _paused = true;
    notifyListeners();
  }

  Future<void> resume() async {
    _paused = false;
    notifyListeners();
  }

  Future<void> executeNextNow() async {
    final sb = _scheduled.where((s) => !s.done).firstOrNull;
    if (sb == null) return;
    sb.dueAt = DateTime.now().toUtc();
    await _audit(sb.beat, 'manual_override');
    await _executeBeat(sb);
    _refreshConsole();
    notifyListeners();
  }

  Future<void> delayNext({int seconds = 30}) async {
    final sb = _scheduled.where((s) => !s.done).firstOrNull;
    if (sb == null) return;
    sb.dueAt = DateTime.now().toUtc().add(Duration(seconds: seconds));
    notifyListeners();
  }

  Future<void> cancelNext() async {
    final sb = _scheduled.where((s) => !s.done).firstOrNull;
    if (sb == null) return;
    sb.done = true;
    await _audit(sb.beat, 'skipped', reason: 'manual_cancel');
    notifyListeners();
  }

  Future<void> kill(String reason) async {
    _killed = true;
    _tickTimer?.cancel();
    _actors.dispose();
    if (_run != null) {
      final report = DirectorPostRunReportService().build(
        run: _run!,
        executed: _executed.length,
        blocked: _blocked.length,
        delayed: _delayed.length,
        errors: _errors,
      );
      await _repo.updateRunStatus(
        _run!.id,
        status: 'killed',
        endedAt: DateTime.now().toUtc(),
        killReason: reason,
        timelineSealed: true,
        report: report,
      );
    }
    notifyListeners();
  }

  Future<void> complete() async {
    _tickTimer?.cancel();
    _actors.dispose();
    if (_run != null) {
      final report = DirectorPostRunReportService().build(
        run: _run!,
        executed: _executed.length,
        blocked: _blocked.length,
        delayed: _delayed.length,
        errors: _errors,
      );
      await _repo.updateRunStatus(
        _run!.id,
        status: 'completed',
        endedAt: DateTime.now().toUtc(),
        timelineSealed: true,
        report: report,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _actors.dispose();
    super.dispose();
  }
}

class _ScheduledBeat {
  _ScheduledBeat({required this.beat, this.dueAt});
  final DirectorBeat beat;
  DateTime? dueAt;
  bool done = false;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
