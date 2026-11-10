import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_room_service.dart';
import '/widgets/live_public_chat_line.dart';
import '/widgets/live_tip_gift_bubble.dart';

/// Painel de chat + espectadores para a vendedora durante o directo.
class LiveRoomVendorPanel extends StatefulWidget {
  const LiveRoomVendorPanel({
    super.key,
    required this.liveId,
  });

  final String liveId;

  @override
  State<LiveRoomVendorPanel> createState() => _LiveRoomVendorPanelState();
}

class _LiveRoomVendorPanelState extends State<LiveRoomVendorPanel> {
  LiveRoomService? _room;
  Map<String, String> _tipContributors = {};
  StreamSubscription<List<LiveRoomMessage>>? _msgSub;
  final TextEditingController _replyController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final id = widget.liveId.trim();
    if (id.isEmpty) return;
    _room = LiveRoomService(id);
    unawaited(_room!.start());
    _msgSub = _room!.messagesStream.listen((msgs) {
      unawaited(_refreshTipContributors(msgs));
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshTipContributors(List<LiveRoomMessage> msgs) async {
    final tipIds = msgs
        .map((m) => m.tipId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (tipIds.isEmpty) {
      if (_tipContributors.isNotEmpty && mounted) {
        setState(() => _tipContributors = {});
      }
      return;
    }
    try {
      final rows = await SupaFlow.client
          .from('live_tips')
          .select('id, buyer_id')
          .inFilter('id', tipIds);
      final buyerIds = <String>{};
      final tipToBuyer = <String, String>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row);
        final tipId = map['id']?.toString();
        final buyerId = map['buyer_id']?.toString();
        if (tipId != null && buyerId != null && buyerId.isNotEmpty) {
          tipToBuyer[tipId] = buyerId;
          buyerIds.add(buyerId);
        }
      }
      if (buyerIds.isEmpty) return;
      final profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.inFilter('id', buyerIds.toList()),
      );
      final nameById = {
        for (final p in profiles)
          if (p.id != null)
            p.id!: (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim()
                : 'Utilizador',
      };
      final next = <String, String>{};
      tipToBuyer.forEach((tipId, buyerId) {
        final name = nameById[buyerId];
        if (name != null) next[tipId] = name;
      });
      if (mounted) setState(() => _tipContributors = next);
    } catch (_) {}
  }

  @override
  void dispose() {
    _replyController.dispose();
    unawaited(_msgSub?.cancel());
    final room = _room;
    _room = null;
    if (room != null) unawaited(room.dispose());
    super.dispose();
  }

  Future<void> _sendReply() async {
    final room = _room;
    if (room == null || _sending) return;
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final ok = await room.sendChat(text);
      if (!mounted) return;
      if (ok) {
        _replyController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: room.viewerCountStream,
      initialData: room.viewerCount,
      builder: (context, viewerSnap) {
        final viewers = viewerSnap.data ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$viewers',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 140,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: FleaberRadius.circularMd,
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: StreamBuilder<List<LiveRoomMessage>>(
                stream: room.messagesStream,
                initialData: List.unmodifiable(room.messages),
                builder: (context, snap) {
                  final msgs = snap.data ?? const [];
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        'Chat do directo',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      final m = msgs[msgs.length - 1 - index];
                      if (m.kind == LiveRoomMessageKind.tip) {
                        final amount = m.tipAmountEur ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: LiveTipGiftBubble(
                            amountEur: amount,
                            showPrivacyNote: false,
                            contributorLabel: m.tipId != null
                                ? _tipContributors[m.tipId!]
                                : null,
                          ),
                        );
                      }
                      if (m.kind == LiveRoomMessageKind.system) {
                        if (!LivePublicChatSystemLine.isVisibleInPublicChat(
                          m.body,
                        )) {
                          return const SizedBox.shrink();
                        }
                        return LivePublicChatSystemLine.fromBody(m.body);
                      }
                      final label = m.senderLabel?.trim().isNotEmpty == true
                          ? m.senderLabel!.trim()
                          : 'Utilizador';
                      final isSeller =
                          (m.userId?.trim() ?? '') == currentUserUid;
                      return LivePublicChatLine(
                        label: label,
                        text: m.body,
                        isSeller: isSeller,
                        compact: true,
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    style: GoogleFonts.inter(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendReply(),
                    decoration: InputDecoration(
                      hintText: 'Responder no chat…',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.42),
                      border: OutlineInputBorder(
                        borderRadius: FleaberRadius.circularMd,
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
