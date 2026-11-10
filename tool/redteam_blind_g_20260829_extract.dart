import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_g_20260829/pass1_raw.json').readAsStringSync(),
  ) as Map;
  final probes = (j['probes'] as List).cast<Map>();
  void show(String id) {
    final p = probes.firstWhere(
      (x) => x['id'] == id,
      orElse: () => {},
    );
    if (p.isEmpty) {
      print('MISSING $id');
      return;
    }
    print('--- $id http=${p['http']} sev=${p['severity_hint']} pers=${p['persisted']}');
    print('before=${p['before']} after=${p['after']} impact=${p['impact']}');
    print(p['response']);
    print('');
  }

  for (final id in [
    'rpc.batata_release_seller_wallet_for_order.buyer',
    'rpc.batata_release_seller_wallet_for_order.seller',
    'rpc.batata_release_seller_wallet_for_order.extra_buyer',
    'rpc.batata_refund_buyer_wallet_for_order.buyer',
    'rpc.batata_refund_buyer_wallet_for_order.extra_buyer',
    'rpc.batata_find_user_id_by_email.buyer',
    'rpc.batata_find_user_id_by_email.seller',
    'rpc.batata_find_user_id_by_email.extra_buyer',
    'rpc.batata_seller_direct_payment_details.buyer',
    'rpc.batata_seller_direct_payment_details.extra_buyer',
    'rpc.batata_is_admin.buyer',
    'rpc.batata_process_partial_refund_dispute.buyer',
    'rpc.batata_wallet_payout_debit.buyer',
    'rpc.batata_wallet_apply_tip_once.buyer',
    'rpc.batata_credit_wallet_once.buyer',
    'rpc.batata_send_live_tip_from_wallet.buyer',
    'rpc.batata_finalize_stripe_order_refund.buyer',
    'edge.cpi.underpay',
    'edge.cpi.hand',
    'edge.cpi.settle.fake',
    'edge.refund.buyer',
    'edge.connect.cross',
    'edge.mux.buyer',
    'edge.webhook.nosig',
    'edge.ps.claim.anon',
    'edge.ocr.buyer',
    'edge.livekit.token.buyer',
    'fin.wallet.patch.buyer',
    'fin.ledger.insert.buyer',
    'ord.patch.buyer.0.price_total',
    'ord.patch.buyer.4.status',
    'ord.insert.buyer.pago',
    'ord.ghost.seller.insert',
    'auth.profile.user_type',
    'priv.lives.mux_stream_key.buyer',
    'priv.profiles.banking.buyer',
    'rep.review.forge',
    'disp.cross.insert',
    'tip.insert.completed',
    'rls.select.notifications_view.anon',
    'rls.select.stripe_checkout_events.buyer',
    'rls.select.wallet_transactions.buyer',
    'rls.select.live_item_show_events.anon',
    'stor.list.chat_media.buyer',
    'priv.chats.extra',
    'cat.patch.0.buyer',
    'ord.patch.seller.money',
    'edge.sms.anon',
    'edge.nuke.buyer',
  ]) {
    show(id);
  }

  print('=== RPC buyer ===');
  for (final r in (j['inventory'] as Map)['rpcs_buyer'] as List) {
    print('  $r');
  }
}
