import '/utils/fleaber_stripe_launch.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

class WalletService {
  const WalletService._();

  static const _payoutPrefsPrefix = 'fleaber_payout_intent_';

  static String _payoutPrefsKey(String userId, int amountCents) =>
      '$_payoutPrefsPrefix${userId}_$amountCents';

  /// Chave estável por intenção (RAM + SharedPreferences) até sucesso.
  static Future<String> _durablePayoutKey({
    required String userId,
    required int amountCents,
  }) async {
    if (_activePayoutKey != null &&
        _activePayoutUserId == userId &&
        _activePayoutAmountCents == amountCents) {
      return _activePayoutKey!;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_payoutPrefsKey(userId, amountCents));
    if (stored != null && stored.trim().length >= 8) {
      return stored.trim();
    }
    final key =
        'wd_${userId}_${amountCents}_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_payoutPrefsKey(userId, amountCents), key);
    return key;
  }

  static Future<void> _clearDurablePayoutKey({
    required String userId,
    required int amountCents,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_payoutPrefsKey(userId, amountCents));
  }

  /// Chave estável por intenção de levantamento (double-tap / retry / restart app).
  static String? _activePayoutKey;
  static int? _activePayoutAmountCents;
  static String? _activePayoutUserId;

  static Future<void> requestPayout({
    required String userId,
    required int amountCents,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) {
      throw Exception('Utilizador inválido.');
    }
    if (amountCents <= 0) {
      throw Exception('Valor de levantamento inválido.');
    }

    final idempotencyKey = await _durablePayoutKey(
      userId: id,
      amountCents: amountCents,
    );
    _activePayoutKey = idempotencyKey;
    _activePayoutUserId = id;
    _activePayoutAmountCents = amountCents;

    try {
      final response = await SupaFlow.client.functions.invoke(
        'create-connect-account',
        body: {
          'user_id': id,
          'amount': amountCents,
          'idempotency_key': idempotencyKey,
          ...fleaberStripeWebReturnFields(),
        },
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        _activePayoutKey = null;
        _activePayoutUserId = null;
        _activePayoutAmountCents = null;
        await _clearDurablePayoutKey(userId: id, amountCents: amountCents);
        return;
      }

      throw Exception(_payoutErrorFromPayload(data));
    } catch (e, st) {
      final message = payoutErrorMessage(e);
      FleaberLogger.instance.error(
        'wallet.payout',
        e,
        st,
        {
          'user_id': id,
          'amount_cents': amountCents,
          'idempotency_key': idempotencyKey,
          'message': message,
        },
      );
      throw Exception(message);
    }
  }
  static Future<void> ensureWallet(String? userId) async {
    final id = userId?.trim();
    if (id == null || id.isEmpty) return;
    await SupaFlow.client.rpc(
      'batata_ensure_wallet',
      params: {'p_user_id': id},
    );
  }

  static Future<void> ensureWallets(Iterable<String?> userIds) async {
    final seen = <String>{};
    for (final raw in userIds) {
      final id = raw?.trim();
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      await ensureWallet(id);
    }
  }

  static Future<bool> releaseSellerBalanceForOrder(String? orderId) async {
    final id = orderId?.trim();
    if (id == null || id.isEmpty) return false;
    final result = await SupaFlow.client.rpc(
      'batata_release_seller_wallet_for_order',
      params: {'p_order_id': id},
    );
    return result == true;
  }

  static Future<bool> refundBuyerBalanceForOrder(String? orderId) async {
    final id = orderId?.trim();
    if (id == null || id.isEmpty) return false;
    final result = await SupaFlow.client.rpc(
      'batata_refund_buyer_wallet_for_order',
      params: {'p_order_id': id},
    );
    return result == true;
  }

  static Future<double> fetchAvailableBalance(String? userId) async {
    final id = userId?.trim();
    if (id == null || id.isEmpty) return 0;
    await ensureWallet(id);
    final rows = await WalletsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', id),
    );
    if (rows.isEmpty) return 0;
    return rows.first.availableBalance;
  }

  static Future<String?> sendLiveTipFromWallet({
    required String liveId,
    required String sellerId,
    required double amountEur,
    String? message,
  }) async {
    final result = await SupaFlow.client.rpc(
      'batata_send_live_tip_from_wallet',
      params: {
        'p_live_id': liveId.isEmpty ? null : liveId,
        'p_seller_id': sellerId,
        'p_amount': amountEur,
        'p_message': message,
      },
    );
    return result?.toString();
  }

  static Future<
      ({String checkoutUrl, String? tipId, String? checkoutSessionId})>
      openLiveTipStripeCheckout({
    required String liveId,
    required String sellerId,
    required double amountEur,
    String? message,
    String? playbackId,
    bool isLive = true,
  }) async {
    return fleaberInvokeCreateLiveTipCheckout(
      body: {
        'live_id': liveId,
        'seller_id': sellerId,
        'amount_eur': amountEur,
        'message': message,
        'playback_id': playbackId,
        'is_live': isLive,
      },
      logContext: {
        'source': 'live_tip_wallet_service',
        'live_id': liveId,
        'seller_id': sellerId,
      },
    );
  }

  /// Abre o onboarding Stripe Connect Express (sem levantamento).
  static Future<Uri> startConnectOnboarding({required String userId}) async {
    final id = userId.trim();
    if (id.isEmpty) {
      throw Exception('Utilizador inválido.');
    }
    final response = await SupaFlow.client.functions.invoke(
      'create-connect-account',
      body: {
        'user_id': id,
        ...fleaberStripeWebReturnFields(),
      },
    );
    final data = response.data;
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      final error = data is Map ? data['error']?.toString() : null;
      throw Exception(
        error == null || error.isEmpty
            ? 'Não foi possível abrir a configuração Stripe Connect.'
            : error,
      );
    }
    return Uri.parse(url);
  }

  static String payoutErrorMessage(Object error) {
    if (error is FunctionException) {
      final fromDetails = _payoutErrorFromPayload(error.details);
      if (fromDetails.isNotEmpty &&
          fromDetails != 'Não foi possível transferir o saldo.') {
        return fromDetails;
      }
    }
    final fromPayload = _payoutErrorFromPayload(error);
    if (fromPayload.isNotEmpty &&
        fromPayload != 'Não foi possível transferir o saldo.') {
      return fromPayload;
    }
    var text = error.toString();
    const prefixes = ['Exception: ', 'Erro Stripe: '];
    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
      }
    }
    if (text.contains('FunctionException')) {
      return 'Não foi possível transferir o saldo. Tenta outra vez.';
    }
    return text.isEmpty ? 'Não foi possível transferir o saldo.' : text;
  }

  static String _payoutErrorFromPayload(Object? data) {
    if (data is Map) {
      final error = data['error']?.toString();
      if (error != null && error.trim().isNotEmpty) {
        final e = error.trim();
        if (e == 'payout_blocked_risk_hold') {
          return 'Levantamento suspenso por revisão de risco. Contacta geral@fleaber.pt.';
        }
        if (e == 'insufficient_balance') {
          return 'Saldo disponível insuficiente (parte pode estar retida por disputa).';
        }
        return e;
      }
    }
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return 'Não foi possível transferir o saldo.';
  }
}
