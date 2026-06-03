import '/backend/supabase/supabase.dart';

class WalletService {
  const WalletService._();

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
    return rows.first.balance;
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

  static Future<({String checkoutUrl, String? tipId})> openLiveTipStripeCheckout({
    required String liveId,
    required String sellerId,
    required double amountEur,
    String? message,
    String? playbackId,
    bool isLive = true,
  }) async {
    final response = await SupaFlow.client.functions.invoke(
      'create-live-tip-checkout',
      body: {
        'live_id': liveId,
        'seller_id': sellerId,
        'amount_eur': amountEur,
        'message': message,
        'playback_id': playbackId,
        'is_live': isLive,
      },
    );
    final data = response.data;
    final checkoutUrl = data is Map ? data['checkoutUrl']?.toString() : null;
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      final error = data is Map ? data['error']?.toString() : null;
      throw Exception(
        error == null || error.isEmpty
            ? 'Não foi possível iniciar o pagamento da gorjeta.'
            : error,
      );
    }
    final tipId = data is Map ? data['tipId']?.toString() : null;
    return (checkoutUrl: checkoutUrl, tipId: tipId);
  }

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

    final response = await SupaFlow.client.functions.invoke(
      'create-connect-account',
      body: {
        'user_id': id,
        'amount': amountCents,
      },
    );
    final data = response.data;
    if (data is Map && data['success'] == true) {
      return;
    }

    final error = data is Map ? data['error']?.toString() : null;
    throw Exception(
      error == null || error.isEmpty
          ? 'Não foi possível transferir o saldo.'
          : error,
    );
  }
}
