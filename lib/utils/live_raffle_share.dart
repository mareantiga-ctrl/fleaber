import 'package:flutter/services.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/utils/live_raffle_service.dart';
import '/utils/raffle_log.dart';

/// Resultado de partilhar um directo (Hub ou Fleaber) com as mesmas regras de rifa.
class LiveRaffleShareResult {
  const LiveRaffleShareResult({
    required this.link,
    required this.message,
    this.awardedShareBonus = false,
    this.ticketBalance,
    this.shareAlreadyClaimed = false,
  });

  final String link;
  final String message;
  final bool awardedShareBonus;
  /// Saldo após claim (quando conhecido).
  final int? ticketBalance;
  final bool shareAlreadyClaimed;
}

/// Partilha de directo — **mesmas regras** Hub live e Fleaber live.
///
/// Se o utilizador está logado e há rifa **activa**:
/// 1. Inscreve-o se ainda não estiver (join)
/// 2. Atribui bónus de partilha (+1 rifa) uma vez — **antes** do clipboard
/// 3. Copia link com `?ref=` quando aplicável
abstract final class LiveRaffleShare {
  static Future<LiveRaffleShareResult> shareLive({
    required String liveId,
    String? preferredLink,
  }) async {
    final id = liveId.trim();
    RaffleLog.d('shareLive start', {
      'liveId': id,
      'uid': currentUserUid.isEmpty ? 'anon' : currentUserUid.substring(0, 8),
      'preferred': (preferredLink ?? '').isNotEmpty,
    });
    if (id.isEmpty) {
      return const LiveRaffleShareResult(
        link: '',
        message: 'Directo inválido.',
      );
    }

    LiveRaffleState state = LiveRaffleState.empty();
    try {
      state = await LiveRaffleService.fetchState(id);
    } catch (e) {
      RaffleLog.e('shareLive fetchState', e, {'liveId': id});
    }

    final raffle = state.raffle;
    final raffleActive = state.hasRaffle && raffle?.isActive == true;
    final raffleId = (raffle?.id ?? '').trim();
    final loggedIn = currentUserUid.isNotEmpty;

    var joined = state.viewer.joined == true;
    var tickets = state.viewer.ticketBalance;
    var shareClaimed = state.viewer.shareBonusClaimed == true;

    RaffleLog.d('shareLive state', {
      'active': raffleActive,
      'raffleId': raffleId.isEmpty ? '-' : raffleId,
      'joined': joined,
      'tickets': tickets,
      'shareClaimed': shareClaimed,
      'loggedIn': loggedIn,
    });

    // Garante inscrição antes do bónus de partilha.
    if (raffleActive && raffleId.isNotEmpty && loggedIn && !joined) {
      try {
        tickets = await LiveRaffleService.join(raffleId);
        joined = true;
        RaffleLog.d('shareLive joined', {'tickets': tickets});
        try {
          state = await LiveRaffleService.fetchState(id);
          joined = state.viewer.joined || joined;
          tickets = state.viewer.ticketBalance > 0
              ? state.viewer.ticketBalance
              : tickets;
          shareClaimed = state.viewer.shareBonusClaimed;
        } catch (_) {
          /* mantém joined local */
        }
      } catch (e) {
        RaffleLog.e('shareLive join', e);
      }
    }

    var link = (preferredLink ?? '').trim();
    if (link.isEmpty) {
      link = 'https://fleaber.app/live/$id';
    }

    if (raffleActive && raffleId.isNotEmpty && joined) {
      try {
        final refCode = await LiveRaffleService.ensureReferralLink(raffleId);
        if (refCode != null && refCode.trim().isNotEmpty) {
          final uri = Uri.tryParse(link);
          if (uri != null && (uri.hasScheme || link.startsWith('http'))) {
            final q = Map<String, String>.from(uri.queryParameters);
            q['ref'] = refCode.trim();
            link = uri.replace(queryParameters: q).toString();
          } else {
            final sep = link.contains('?') ? '&' : '?';
            link = '$link${sep}ref=${Uri.encodeQueryComponent(refCode.trim())}';
          }
          RaffleLog.d('shareLive ref', {'code': refCode});
        }
      } catch (e) {
        RaffleLog.e('shareLive ensureReferral', e);
      }
    }

    // Claim **antes** do clipboard.
    var awarded = false;
    var already = false;
    String? claimError;
    if (raffleActive &&
        raffleId.isNotEmpty &&
        loggedIn &&
        joined &&
        !shareClaimed) {
      try {
        final res = await LiveRaffleService.claimShareIntent(raffleId);
        if (res.ok) {
          if (res.duplicate) {
            already = true;
            shareClaimed = true;
            if (res.ticketBalance > 0) tickets = res.ticketBalance;
            RaffleLog.d('shareLive claim duplicate', {'tickets': tickets});
          } else {
            awarded = true;
            shareClaimed = true;
            tickets = res.ticketBalance > 0
                ? res.ticketBalance
                : (tickets > 0 ? tickets + 1 : 2);
            RaffleLog.d('shareLive claim awarded', {'tickets': tickets});
          }
        } else {
          claimError = res.error;
          RaffleLog.d('shareLive claim not ok', {'error': res.error});
        }
      } catch (e) {
        claimError = e.toString();
        RaffleLog.e('shareLive claim', e);
      }
    } else {
      RaffleLog.d('shareLive skip claim', {
        'active': raffleActive,
        'joined': joined,
        'shareClaimed': shareClaimed,
        'loggedIn': loggedIn,
      });
    }

    try {
      await Clipboard.setData(ClipboardData(text: link));
      RaffleLog.d('shareLive clipboard ok');
    } catch (e) {
      RaffleLog.e('shareLive clipboard', e);
    }

    LiveRaffleShareResult out;
    if (awarded) {
      out = LiveRaffleShareResult(
        link: link,
        message: 'Link copiado — +1 rifa!',
        awardedShareBonus: true,
        ticketBalance: tickets,
      );
    } else if (already || shareClaimed) {
      out = LiveRaffleShareResult(
        link: link,
        message: 'Link copiado — já tinhas a rifa de partilha.',
        ticketBalance: tickets,
        shareAlreadyClaimed: true,
      );
    } else if (raffleActive && !loggedIn) {
      out = LiveRaffleShareResult(
        link: link,
        message:
            'Link copiado. Entra na conta (Hub ou Fleaber) e partilha de novo para ganhares rifa.',
      );
    } else if (raffleActive && loggedIn && !joined) {
      out = LiveRaffleShareResult(
        link: link,
        message:
            'Link copiado. Abre a Rifa e participa — depois partilha para +1.',
      );
    } else if (claimError != null && claimError.contains('join_required')) {
      out = LiveRaffleShareResult(
        link: link,
        message:
            'Link copiado. Abre a Rifa e participa — depois partilha para +1.',
      );
    } else if (claimError != null) {
      // Mensagem com código curto para reportares no chat.
      final code = claimError.length > 48
          ? claimError.substring(0, 48)
          : claimError;
      out = LiveRaffleShareResult(
        link: link,
        message: 'Link copiado. Rifa partilha falhou ($code).',
      );
    } else {
      out = LiveRaffleShareResult(
        link: link,
        message: 'Link copiado.',
        ticketBalance: tickets > 0 ? tickets : null,
      );
    }

    RaffleLog.d('shareLive done', {
      'awarded': out.awardedShareBonus,
      'already': out.shareAlreadyClaimed,
      'tickets': out.ticketBalance ?? -1,
      'msg': out.message,
    });
    return out;
  }
}
