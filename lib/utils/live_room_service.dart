import 'dart:async';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

enum LiveRoomMessageKind { chat, tip, system }

class LiveRoomMessage {
  const LiveRoomMessage({
    required this.id,
    required this.kind,
    required this.body,
    this.userId,
    this.senderLabel,
    this.tipAmountEur,
    this.tipId,
    this.createdAt,
  });

  final String id;
  final LiveRoomMessageKind kind;
  final String body;
  final String? userId;
  final String? senderLabel;
  final double? tipAmountEur;
  final String? tipId;
  final DateTime? createdAt;

  static LiveRoomMessage fromRow(Map<String, dynamic> row) {
    final kindRaw = (row['kind'] as String?)?.trim() ?? 'chat';
    final amount = row['tip_amount'];
    double? tipAmount;
    if (amount is num) {
      tipAmount = amount.toDouble();
    } else if (amount is String) {
      tipAmount = double.tryParse(amount.replaceAll(',', '.'));
    }
    return LiveRoomMessage(
      id: row['id']?.toString() ?? '',
      kind: kindRaw == 'tip'
          ? LiveRoomMessageKind.tip
          : kindRaw == 'system'
              ? LiveRoomMessageKind.system
              : LiveRoomMessageKind.chat,
      body: row['body']?.toString() ?? '',
      userId: row['user_id']?.toString(),
      senderLabel: row['sender_label']?.toString(),
      tipAmountEur: tipAmount,
      tipId: row['tip_id']?.toString(),
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
          : null,
    );
  }
}

/// Chat + presença de espectadores num directo (Supabase Realtime).
class LiveRoomService {
  LiveRoomService(this.liveId);

  final String liveId;
  final List<LiveRoomMessage> messages = [];
  RealtimeChannel? _channel;
  Timer? _presenceTimer;
  Timer? _refreshTimer;
  int viewerCount = 0;
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;

  final _messagesController = StreamController<List<LiveRoomMessage>>.broadcast();
  final _viewerCountController = StreamController<int>.broadcast();

  Stream<List<LiveRoomMessage>> get messagesStream =>
      _messagesController.stream;
  Stream<int> get viewerCountStream => _viewerCountController.stream;

  Future<void> start() async {
    if (liveId.isEmpty) return;
    await _loadInitial();
    _subscribe();
    await _pingPresence();
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_pingPresence());
    });
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(refreshMessages());
    });
  }

  Future<void> dispose() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_channel != null) {
      await SupaFlow.client.removeChannel(_channel!);
      _channel = null;
    }
    await _messagesController.close();
    await _viewerCountController.close();
  }

  Future<void> _loadInitial() async {
    final rows = await SupaFlow.client
        .from('live_messages')
        .select()
        .eq('live_id', liveId)
        .order('created_at', ascending: true)
        .limit(600);
    messages
      ..clear()
      ..addAll(
        (rows as List)
            .map((e) => LiveRoomMessage.fromRow(Map<String, dynamic>.from(e)))
            .where((m) => m.id.isNotEmpty),
      );
    _hasMoreOlder = messages.length >= 600;
    _emitMessages();
  }

  void _subscribe() {
    _channel = SupaFlow.client
        .channel('live_room:$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'live_id',
            value: liveId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final msg = LiveRoomMessage.fromRow(Map<String, dynamic>.from(row));
            if (msg.id.isEmpty) return;
            if (messages.any((m) => m.id == msg.id)) return;
            messages.add(msg);
            _emitMessages();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'lives',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: liveId,
          ),
          callback: (payload) {
            final raw = payload.newRecord['viewer_count'];
            if (raw is num) {
              viewerCount = raw.toInt();
              if (!_viewerCountController.isClosed) {
                _viewerCountController.add(viewerCount);
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _pingPresence() async {
    if (liveId.isEmpty || currentUserUid.isEmpty) return;
    try {
      final raw = await SupaFlow.client.rpc(
        'batata_live_viewer_ping',
        params: {'p_live_id': liveId},
      );
      final count = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
      viewerCount = count;
      _viewerCountController.add(count);
    } catch (_) {
      // Coluna/RPC em falta até correr live_room_batata.sql
    }
  }

  static Future<String> _chatSenderLabelForUser(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return 'Utilizador';
    try {
      final rows = await ProfilesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', uid),
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final name = rows.first.fullName?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    final fallback = currentUserDisplayName.trim();
    return fallback.isNotEmpty ? fallback : 'Utilizador';
  }

  Future<bool> sendChat(String text) async {
    final body = text.trim();
    if (body.isEmpty || liveId.isEmpty || currentUserUid.isEmpty) {
      return false;
    }
    final label = await _chatSenderLabelForUser(currentUserUid);
    try {
      final row = await SupaFlow.client
          .from('live_messages')
          .insert({
            'live_id': liveId,
            'user_id': currentUserUid,
            'kind': 'chat',
            'body': body,
            'sender_label': label,
          })
          .select()
          .maybeSingle();
      if (row == null) return false;
      final msg = LiveRoomMessage.fromRow(Map<String, dynamic>.from(row));
      if (msg.id.isNotEmpty && !messages.any((m) => m.id == msg.id)) {
        messages.add(msg);
        if (messages.length > 600) {
          messages.removeRange(0, messages.length - 600);
        }
        _emitMessages();
      }
      return true;
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('policy') ||
          err.contains('live') ||
          err.contains('ended') ||
          err.contains('active')) {
        return false;
      }
      return false;
    }
  }

  /// Carrega mensagens mais antigas (scroll até à 1.ª mensagem).
  Future<void> loadOlderMessages() async {
    if (liveId.isEmpty || _loadingOlder || !_hasMoreOlder || messages.isEmpty) {
      return;
    }
    _loadingOlder = true;
    try {
      final oldest = messages.first.createdAt;
      if (oldest == null) {
        _hasMoreOlder = false;
        return;
      }
      final rows = await SupaFlow.client
          .from('live_messages')
          .select()
          .eq('live_id', liveId)
          .lt('created_at', oldest.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(120);
      final batch = (rows as List)
          .map((e) => LiveRoomMessage.fromRow(Map<String, dynamic>.from(e)))
          .where((m) => m.id.isNotEmpty)
          .toList();
      if (batch.isEmpty) {
        _hasMoreOlder = false;
        return;
      }
      batch.sort(
        (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      final existingIds = messages.map((m) => m.id).toSet();
      final older =
          batch.where((m) => !existingIds.contains(m.id)).toList(growable: false);
      if (older.isEmpty) {
        _hasMoreOlder = false;
        return;
      }
      messages.insertAll(0, older);
      if (batch.length < 120) _hasMoreOlder = false;
      _emitMessages();
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  /// Recarrega mensagens (fallback se Realtime não estiver activo).
  Future<void> refreshMessages() async {
    if (liveId.isEmpty) return;
    try {
      final rows = await SupaFlow.client
          .from('live_messages')
          .select()
          .eq('live_id', liveId)
          .order('created_at', ascending: true)
          .limit(600);
      final next = (rows as List)
          .map((e) => LiveRoomMessage.fromRow(Map<String, dynamic>.from(e)))
          .where((m) => m.id.isNotEmpty)
          .toList();
      if (next.length != messages.length ||
          (next.isNotEmpty &&
              messages.isNotEmpty &&
              next.last.id != messages.last.id)) {
        messages
          ..clear()
          ..addAll(next);
        _emitMessages();
      }
    } catch (_) {}
  }

  void _emitMessages() {
    if (_messagesController.isClosed) return;
    _messagesController.add(List.unmodifiable(messages));
  }
}
