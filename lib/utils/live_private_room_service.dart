import 'dart:async';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

enum LiveThreadEntryKind { private, publicChat, reservation, purchase }

class LiveThreadEntry {
  const LiveThreadEntry({
    required this.id,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.senderLabel,
    this.meta,
  });

  final String id;
  final LiveThreadEntryKind kind;
  final String body;
  final DateTime createdAt;
  final String? senderId;
  final String? senderLabel;
  final Map<String, dynamic>? meta;
}

class LivePrivateMessage {
  const LivePrivateMessage({
    required this.id,
    required this.liveId,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.isRead,
    this.createdAt,
  });

  final String id;
  final String liveId;
  final String senderId;
  final String recipientId;
  final String body;
  final bool isRead;
  final DateTime? createdAt;

  static LivePrivateMessage fromRow(Map<String, dynamic> row) {
    return LivePrivateMessage(
      id: row['id']?.toString() ?? '',
      liveId: row['live_id']?.toString() ?? '',
      senderId: row['sender_id']?.toString() ?? '',
      recipientId: row['recipient_id']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      isRead: row['is_read'] == true,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
          : null,
    );
  }
}

class LivePrivateThreadSummary {
  const LivePrivateThreadSummary({
    required this.viewerId,
    required this.viewerLabel,
    required this.unreadCount,
    required this.lastMessage,
    required this.lastAt,
  });

  final String viewerId;
  final String viewerLabel;
  final int unreadCount;
  final String lastMessage;
  final DateTime? lastAt;
}

/// Chat privado viewer↔vendedora durante um directo.
class LivePrivateRoomService {
  LivePrivateRoomService({
    required this.liveId,
    required this.sellerId,
    this.viewerId,
  });

  final String liveId;
  final String sellerId;
  final String? viewerId;

  final List<LivePrivateMessage> messages = [];
  RealtimeChannel? _channel;
  Timer? _refreshTimer;

  final _messagesController =
      StreamController<List<LivePrivateMessage>>.broadcast();
  final _unreadController = StreamController<int>.broadcast();

  Stream<List<LivePrivateMessage>> get messagesStream =>
      _messagesController.stream;
  Stream<int> get unreadStream => _unreadController.stream;

  bool get isSeller => currentUserUid == sellerId;

  Future<void> start() async {
    if (liveId.isEmpty) return;
    await _loadMessages();
    _subscribe();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_loadMessages(silent: true));
      if (isSeller) unawaited(_emitUnreadCount());
    });
    if (isSeller) await _emitUnreadCount();
  }

  Future<void> dispose() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_channel != null) {
      await SupaFlow.client.removeChannel(_channel!);
      _channel = null;
    }
    await _messagesController.close();
    await _unreadController.close();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (liveId.isEmpty || currentUserUid.isEmpty) return;
    try {
      PostgrestFilterBuilder<dynamic> q = SupaFlow.client
          .from('live_private_messages')
          .select()
          .eq('live_id', liveId);
      if (!isSeller) {
        q = q.or(
          'and(sender_id.eq.$currentUserUid,recipient_id.eq.$sellerId),'
          'and(sender_id.eq.$sellerId,recipient_id.eq.$currentUserUid)',
        );
      } else if (viewerId != null && viewerId!.isNotEmpty) {
        final v = viewerId!;
        q = q.or(
          'and(sender_id.eq.$v,recipient_id.eq.$sellerId),'
          'and(sender_id.eq.$sellerId,recipient_id.eq.$v)',
        );
      }
      final rows = await q.order('created_at', ascending: true).limit(200);
      final next = (rows as List)
          .map((e) =>
              LivePrivateMessage.fromRow(Map<String, dynamic>.from(e)))
          .where((m) => m.id.isNotEmpty)
          .toList();
      final changed = next.length != messages.length ||
          (next.isNotEmpty &&
              messages.isNotEmpty &&
              next.last.id != messages.last.id);
      if (changed || !silent) {
        messages
          ..clear()
          ..addAll(next);
        _emitMessages();
      }
    } catch (_) {}
  }

  void _subscribe() {
    _channel = SupaFlow.client
        .channel('live_private:$liveId:${currentUserUid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'live_id',
            value: liveId,
          ),
          callback: (payload) {
            unawaited(_loadMessages());
            if (isSeller) unawaited(_emitUnreadCount());
          },
        )
        .subscribe();
  }

  Future<bool> sendPrivate(String body, {required String recipientId}) async {
    final text = body.trim();
    if (text.isEmpty ||
        liveId.isEmpty ||
        currentUserUid.isEmpty ||
        recipientId.isEmpty) {
      return false;
    }
    try {
      final row = await SupaFlow.client
          .from('live_private_messages')
          .insert({
            'live_id': liveId,
            'sender_id': currentUserUid,
            'recipient_id': recipientId,
            'body': text,
            'kind': 'private',
          })
          .select()
          .maybeSingle();
      if (row == null) return false;
      final msg =
          LivePrivateMessage.fromRow(Map<String, dynamic>.from(row));
      if (msg.id.isNotEmpty && !messages.any((m) => m.id == msg.id)) {
        messages.add(msg);
        _emitMessages();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> unreadCountForSeller() async {
    if (!isSeller || liveId.isEmpty) return 0;
    try {
      final rows = await SupaFlow.client
          .from('live_private_messages')
          .select('id')
          .eq('live_id', liveId)
          .eq('recipient_id', currentUserUid)
          .eq('is_read', false);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markThreadRead(String otherUserId) async {
    if (liveId.isEmpty || currentUserUid.isEmpty || otherUserId.isEmpty) {
      return;
    }
    try {
      await SupaFlow.client
          .from('live_private_messages')
          .update({'is_read': true})
          .eq('live_id', liveId)
          .eq('recipient_id', currentUserUid)
          .eq('sender_id', otherUserId)
          .eq('is_read', false);
      await _emitUnreadCount();
    } catch (_) {}
  }

  Future<List<LivePrivateThreadSummary>> listThreadsForSeller() async {
    if (!isSeller || liveId.isEmpty) return const [];
    try {
      final rows = await SupaFlow.client
          .from('live_private_messages')
          .select()
          .eq('live_id', liveId)
          .or('sender_id.eq.$sellerId,recipient_id.eq.$sellerId')
          .order('created_at', ascending: false)
          .limit(300);
      final byViewer = <String, LivePrivateThreadSummary>{};
      final unreadByViewer = <String, int>{};
      for (final row in rows as List) {
        final m = LivePrivateMessage.fromRow(Map<String, dynamic>.from(row));
        final viewer = m.senderId == sellerId ? m.recipientId : m.senderId;
        if (viewer.isEmpty || viewer == sellerId) continue;
        if (m.recipientId == sellerId && !m.isRead) {
          unreadByViewer[viewer] = (unreadByViewer[viewer] ?? 0) + 1;
        }
        if (!byViewer.containsKey(viewer)) {
          byViewer[viewer] = LivePrivateThreadSummary(
            viewerId: viewer,
            viewerLabel: 'Utilizador',
            unreadCount: 0,
            lastMessage: m.body,
            lastAt: m.createdAt,
          );
        }
      }
      if (byViewer.isEmpty) return const [];
      final profiles = await ProfilesTable().queryRows(
        queryFn: (q) => q.inFilter('id', byViewer.keys.toList()),
      );
      final names = {
        for (final p in profiles)
          if (p.id != null)
            p.id!: (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim()
                : 'Utilizador',
      };
      return byViewer.entries.map((e) {
        final base = e.value;
        return LivePrivateThreadSummary(
          viewerId: base.viewerId,
          viewerLabel: names[base.viewerId] ?? base.viewerLabel,
          unreadCount: unreadByViewer[base.viewerId] ?? 0,
          lastMessage: base.lastMessage,
          lastAt: base.lastAt,
        );
      }).toList()
        ..sort((a, b) {
          final ta = a.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiveThreadEntry>> threadWithViewer(String viewerUserId) async {
    if (liveId.isEmpty || viewerUserId.isEmpty) return const [];
    final entries = <LiveThreadEntry>[];

    try {
      final privateRows = await SupaFlow.client
          .from('live_private_messages')
          .select()
          .eq('live_id', liveId)
          .or(
            'and(sender_id.eq.$viewerUserId,recipient_id.eq.$sellerId),'
            'and(sender_id.eq.$sellerId,recipient_id.eq.$viewerUserId)',
          )
          .order('created_at', ascending: true)
          .limit(200);
      for (final row in privateRows as List) {
        final m = LivePrivateMessage.fromRow(Map<String, dynamic>.from(row));
        entries.add(
          LiveThreadEntry(
            id: 'p-${m.id}',
            kind: LiveThreadEntryKind.private,
            body: m.body,
            createdAt: m.createdAt ?? DateTime.now(),
            senderId: m.senderId,
          ),
        );
      }
    } catch (_) {}

    try {
      final publicRows = await SupaFlow.client
          .from('live_messages')
          .select()
          .eq('live_id', liveId)
          .eq('user_id', viewerUserId)
          .eq('kind', 'chat')
          .order('created_at', ascending: true)
          .limit(120);
      for (final row in publicRows as List) {
        final map = Map<String, dynamic>.from(row);
        entries.add(
          LiveThreadEntry(
            id: 'pub-${map['id']}',
            kind: LiveThreadEntryKind.publicChat,
            body: map['body']?.toString() ?? '',
            createdAt: DateTime.tryParse(map['created_at'].toString())
                    ?.toLocal() ??
                DateTime.now(),
            senderId: viewerUserId,
            senderLabel: map['sender_label']?.toString(),
          ),
        );
      }
    } catch (_) {}

    try {
      final eventRows = await SupaFlow.client
          .from('live_private_messages')
          .select()
          .eq('live_id', liveId)
          .eq('sender_id', viewerUserId)
          .inFilter('kind', ['reservation', 'purchase'])
          .order('created_at', ascending: true)
          .limit(80);
      for (final row in eventRows as List) {
        final map = Map<String, dynamic>.from(row);
        final kindRaw = map['kind']?.toString() ?? '';
        entries.add(
          LiveThreadEntry(
            id: 'e-${map['id']}',
            kind: kindRaw == 'purchase'
                ? LiveThreadEntryKind.purchase
                : LiveThreadEntryKind.reservation,
            body: map['body']?.toString() ?? '',
            createdAt: DateTime.tryParse(map['created_at'].toString())
                    ?.toLocal() ??
                DateTime.now(),
            senderId: viewerUserId,
            meta: map['meta'] is Map
                ? Map<String, dynamic>.from(map['meta'] as Map)
                : null,
          ),
        );
      }
    } catch (_) {}

    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }

  Future<void> _emitUnreadCount() async {
    if (_unreadController.isClosed) return;
    _unreadController.add(await unreadCountForSeller());
  }

  void _emitMessages() {
    if (_messagesController.isClosed) return;
    _messagesController.add(List.unmodifiable(messages));
  }
}
