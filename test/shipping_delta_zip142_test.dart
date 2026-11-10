import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/fleaber_pt_business_days.dart';
import 'package:fleaber/utils/order_shipment_weight.dart';
import 'package:fleaber/utils/shipping_delta_stripe_fee.dart';

void main() {
  group('ZIP142 Stripe fee policy (PSD2)', () {
    test('default NÃO repercutir taxa — charge = delta', () {
      final q = fleaberShippingDeltaChargeQuote(shippingDeltaCents: 150);
      expect(q.passStripeFeeToBuyer, isFalse);
      expect(q.amountChargeCents, 150);
      expect(q.stripeFeeGrossupCents, 0);
      expect(q.feePolicy, 'absorb_stripe_fee_psd2_safe');
    });

    test('GO gross-up usa lista 1,5%+0,25 (só se flag)', () {
      final q = fleaberShippingDeltaChargeQuote(
        shippingDeltaCents: 150,
        passStripeFeeToBuyer: true,
      );
      // ceil((150+25)/(1-0.015)) = ceil(175/0.985) = ceil(177.665) = 178
      expect(q.amountChargeCents, 178);
      expect(q.stripeFeeGrossupCents, 28);
      expect(q.feePolicy, 'grossup_list_rate_go_required');
    });

    test('lista Stripe PT: card EEE e MB WAY = mesmos bps/fixed na referência', () {
      expect(kFleaberStripePtStandardFeeBps, 150);
      expect(kFleaberStripePtStandardFeeFixedCents, 25);
      expect(kFleaberShippingDeltaPassStripeFeeDefault, isFalse);
    });
  });

  group('ZIP142 prazos 5 dias úteis + pause/resume', () {
    test('sexta + 1 dia útil → segunda (salta fim-de-semana)', () {
      // 2026-11-06 = sexta
      final from = DateTime(2026, 11, 6, 10);
      final end = fleaberAddBusinessDays(from, 1);
      expect(end.year, 2026);
      expect(end.month, 11);
      expect(end.day, 9); // segunda
    });

    test('5 dias úteis a partir de sexta 6/nov', () {
      final from = DateTime(2026, 11, 6, 12);
      final end = fleaberAddBusinessDays(from, 5);
      // sex+1=seg9, +2=ter10, +3=qua11, +4=qui12, +5=sex13
      expect(end.day, 13);
      expect(end.month, 11);
    });

    test('salta feriado 1/nov (domingo) e 25/dez', () {
      expect(fleaberIsPtBusinessDay(DateTime(2026, 12, 25)), isFalse);
      expect(fleaberIsPtBusinessDay(DateTime(2026, 12, 24)), isTrue); // quinta
    });

    test('pause/resume não reinicia contagem', () {
      final shipBy = DateTime(2026, 11, 13, 23, 59, 59);
      final now = DateTime(2026, 11, 10, 12);
      final rem = fleaberShipClockRemainingSeconds(shipByAt: shipBy, now: now);
      expect(rem, greaterThan(0));
      final resumed = fleaberShipClockResumeAt(
        remainingSeconds: rem,
        now: now.add(const Duration(hours: 48)),
      );
      // Mantém o mesmo remaining — não +5 dias novos
      final rem2 = fleaberShipClockRemainingSeconds(
        shipByAt: resumed,
        now: now.add(const Duration(hours: 48)),
      );
      expect(rem2, rem);
    });
  });

  group('ZIP142 multi-artigo peso', () {
    test('artigos 2kg + 4kg → escalão 3–6', () {
      final agg = fleaberAggregateShipmentWeight([
        const FleaberShipmentWeightInput(weightKg: 2, quantity: 1),
        const FleaberShipmentWeightInput(weightKg: 4, quantity: 1),
      ]);
      expect(agg.ok, isTrue);
      expect(agg.totalKg, 6.0);
      expect(agg.band, FleaberDpdWeightBand.from3To6);
    });

    test('mistura sem peso → buyer choice', () {
      final agg = fleaberAggregateShipmentWeight([
        const FleaberShipmentWeightInput(weightKg: 1, quantity: 1),
        const FleaberShipmentWeightInput(),
      ]);
      expect(agg.needsBuyerBandChoice, isTrue);
    });
  });

  group('ZIP142 invariantes de código (fonte)', () {
    test('webhook shipping_delta NÃO faz fall-through para settle', () {
      final src = File(
        'supabase/functions/stripe-webhook/index.ts',
      ).readAsStringSync();
      expect(src.contains('fleaber_mode: "shipping_delta"'), isTrue);
      expect(src.contains('settled_as_sale: false'), isTrue);
      expect(src.contains('NUNCA handleCheckoutSettle'), isTrue);
      // Após branch delta com erro → return 500, não settle
      final deltaIdx = src.indexOf('mode === "shipping_delta"');
      final settleIdx = src.lastIndexOf('handleCheckoutSettle');
      expect(deltaIdx, greaterThan(0));
      expect(settleIdx, greaterThan(deltaIdx));
      final errReturn = src.indexOf(
        'shipping_delta_handler_failed',
        deltaIdx,
      );
      expect(errReturn, greaterThan(deltaIdx));
      expect(errReturn, lessThan(settleIdx));
    });

    test('mark paid SQL não mexe em status pago/stock', () {
      final sql = File(
        'supabase/migrations/20261103200000_order_weight_shipping_delta_deadlines_batata.sql',
      ).readAsStringSync();
      final fnStart = sql.indexOf('batata_mark_shipping_adjustment_paid');
      expect(fnStart, greaterThan(0));
      final fnBody = sql.substring(fnStart, fnStart + 1800);
      expect(fnBody.contains("status = 'paid'"), isTrue); // adjustment
      expect(fnBody.contains("weight_confirm_status = 'delta_paid'"), isTrue);
      expect(fnBody.contains('shipping_cents_charged'), isTrue);
      expect(fnBody.contains("status = 'pago'"), isFalse);
      expect(fnBody.contains('quantity'), isFalse);
      expect(fnBody.contains('is_sold'), isFalse);
      expect(fnBody.contains('batata_release_seller_wallet'), isFalse);
    });

    test('tick sem autocancel devolve skipped', () {
      final sql = File(
        'supabase/migrations/20261103200000_order_weight_shipping_delta_deadlines_batata.sql',
      ).readAsStringSync();
      expect(
        sql.contains("reason', 'order_ship_deadline_autocancel_enabled=false'"),
        isTrue,
      );
    });

    test('gate DPD bloqueia delta pending', () {
      final sql = File(
        'supabase/migrations/20261103200000_order_weight_shipping_delta_deadlines_batata.sql',
      ).readAsStringSync();
      expect(sql.contains('shipping_delta_unpaid'), isTrue);
      expect(sql.contains('batata_order_blocks_dpd_create'), isTrue);
    });

    test('política PSD2 flag default false na migração 142', () {
      final sql = File(
        'supabase/migrations/20261103220000_shipping_delta_fee_policy_psd2_batata.sql',
      ).readAsStringSync();
      expect(sql.contains('order_shipping_delta_pass_stripe_fee'), isTrue);
      expect(sql.contains('absorb_stripe_fee_psd2_safe'), isTrue);
    });
  });
}
