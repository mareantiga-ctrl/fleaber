import 'dart:convert';
import 'dart:io';

enum BotEventOutcome { ok, fail, skip }

class BotSimEvent {
  BotSimEvent({
    required this.timestamp,
    required this.botId,
    required this.botTag,
    required this.action,
    required this.outcome,
    this.expected,
    this.actual,
    this.durationMs,
    this.error,
    this.meta,
  });

  final DateTime timestamp;
  final String botId;
  final String botTag;
  final String action;
  final BotEventOutcome outcome;
  final dynamic expected;
  final dynamic actual;
  final int? durationMs;
  final String? error;
  final Map<String, dynamic>? meta;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'bot_id': botId,
        'bot_tag': botTag,
        'action': action,
        'outcome': outcome.name,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        if (durationMs != null) 'duration_ms': durationMs,
        if (error != null) 'error': error,
        if (meta != null) ...meta!,
      };
}

class EventLogger {
  EventLogger(this.reportDir);

  final Directory reportDir;
  late final File _events = File('${reportDir.path}/events.jsonl');
  late final File _errors = File('${reportDir.path}/errors.jsonl');

  final List<BotSimEvent> events = [];
  final List<BotSimEvent> errors = [];

  Future<void> log(BotSimEvent event) async {
    events.add(event);
    await _events.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
    );
    if (event.outcome == BotEventOutcome.fail) {
      errors.add(event);
      await _errors.writeAsString(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
      );
    }
  }

  Future<BotSimEvent> timed<T>({
    required String botId,
    required String botTag,
    required String action,
    dynamic expected,
    Map<String, dynamic>? meta,
    required Future<T> Function() run,
    Object? Function(T value)? actualFrom,
  }) async {
    final started = DateTime.now();
    try {
      final result = await run();
      final ms = DateTime.now().difference(started).inMilliseconds;
      final event = BotSimEvent(
        timestamp: started,
        botId: botId,
        botTag: botTag,
        action: action,
        outcome: BotEventOutcome.ok,
        expected: expected,
        actual: actualFrom != null ? actualFrom(result) : result,
        durationMs: ms,
        meta: meta,
      );
      await log(event);
      return event;
    } catch (e) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      final event = BotSimEvent(
        timestamp: started,
        botId: botId,
        botTag: botTag,
        action: action,
        outcome: BotEventOutcome.fail,
        expected: expected,
        durationMs: ms,
        error: e.toString(),
        meta: meta,
      );
      await log(event);
      rethrow;
    }
  }
}
