/// Exact-signature calls for RPCs whose OpenAPI parse missed arg names.
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  final calls = <Map<String, dynamic>>[
    {'fn': 'batata_is_admin', 'p': <String, dynamic>{}},
    {
      'fn': 'batata_admin_resolve_dispute',
      'p': {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_resolution': 'favor_buyer_refund',
        'p_note': prefix,
      },
    },
    {
      'fn': 'batata_order_payment_confirmed',
      'p': {
        'p_payment_method': 'Pagamento na app',
        'p_status': 'pago',
        'p_amount_paid_cents': 1,
        'p_stripe_payment_intent_id': 'pi_x',
      },
    },
    {
      'fn': 'batata_credit_wallet_once',
      'p': {
        'p_wallet_id': c.buyerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 50,
        'p_type': 'credit',
        'p_source': prefix,
      },
    },
    {
      'fn': 'staging_nuke_user_data',
      'p': {'p_user_id': c.buyerId},
    },
    {
      'fn': 'batata_admin_list_profiles',
      'p': <String, dynamic>{},
    },
    {
      'fn': 'batata_process_partial_refund_dispute',
      'p': {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount_cents': 100,
      },
    },
    {
      'fn': 'batata_clawback_seller_wallet_for_order',
      'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    },
    {
      'fn': 'batata_create_raffle_prize_order',
      'p': {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_id': c.buyerId,
      },
    },
    {
      'fn': 'batata_wallet_payout_finish',
      'p': {
        'p_idempotency_key': '${prefix}_x',
        'p_stripe_transfer_id': 'tr_x',
      },
    },
    {
      'fn': 'batata_debit_wallet_once',
      'p': {
        'p_wallet_id': c.sellerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 1,
        'p_type': 'x',
        'p_source': 'x',
      },
    },
    {
      'fn': 'batata_staging_h_v1_ux_demo_seed',
      'p': <String, dynamic>{},
    },
    {
      'fn': 'staging_restore_stock_before_nuke',
      'p': {'p_user_id': c.sellerId},
    },
  ];

  for (final x in calls) {
    for (final ident in ['anon', 'buyer', 'seller']) {
      final h = ident == 'anon'
          ? c.anonH
          : ident == 'buyer'
              ? c.buyerH
              : c.sellerH;
      final r = await rpcRaw(
        c.url,
        x['fn'] as String,
        Map<String, dynamic>.from(x['p'] as Map),
        headers: h,
      );
      rec(
        surface: 'RPC ${x['fn']}',
        attack: 'exact args',
        identity: ident,
        result: brief(r, 280),
      );
      if (looksOk(r) && (x['fn'] as String).contains('nuke')) {
        finding(
          id: 'RT1752-P0-NUKE',
          severity: 'P0',
          title: 'JWT/anon nuke',
          actor: ident,
          pre: 'staging_nuke',
          repro: '${x['fn']}',
          impact: 'destruição de dados',
          evidence: brief(r),
        );
      }
      if (looksOk(r) &&
          (x['fn'] as String) == 'batata_is_admin' &&
          r.body.trim() == 'true') {
        finding(
          id: 'RT1752-P0-IS-ADMIN',
          severity: 'P0',
          title: 'JWT is_admin=true',
          actor: ident,
          pre: 'lab buyer/seller',
          repro: 'batata_is_admin',
          impact: 'autoridade admin',
          evidence: brief(r),
        );
      }
      if (looksOk(r) &&
          (x['fn'] as String) == 'batata_admin_resolve_dispute' &&
          r.body.trim() == 'true') {
        finding(
          id: 'RT1752-P0-RESOLVE-DISPUTE',
          severity: 'P0',
          title: 'JWT resolveu disputa admin',
          actor: ident,
          pre: 'não admin',
          repro: 'batata_admin_resolve_dispute favor_buyer_refund',
          impact: 'refund privilegiado',
          evidence: brief(r),
        );
      }
    }
  }

  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass5b.json',
    {'matrix': matrix, 'findings': findings},
  );
  stdout.writeln('PASS5b findings=${findings.length}');
}
