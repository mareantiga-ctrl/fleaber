import '/backend/supabase/supabase.dart';

/// Estatuto profissional do vendedor (fonte única app + web).
///
/// Regra 119.7: distintivo «Profissional» **apenas** se `verified`.
/// Trader incomplete/pending/rejected → vendas novas suspensas (servidor).
enum SellerVerificationStatus {
  none,
  incomplete,
  pending,
  verified,
  rejected;

  static SellerVerificationStatus parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'incomplete':
        return SellerVerificationStatus.incomplete;
      case 'pending':
        return SellerVerificationStatus.pending;
      case 'verified':
        return SellerVerificationStatus.verified;
      case 'rejected':
        return SellerVerificationStatus.rejected;
      default:
        return SellerVerificationStatus.none;
    }
  }

  String get dbValue => name;

  String get labelPt {
    switch (this) {
      case SellerVerificationStatus.none:
        return 'Conta de particular';
      case SellerVerificationStatus.incomplete:
        return 'Dados por preencher';
      case SellerVerificationStatus.pending:
        return 'Pedido em análise';
      case SellerVerificationStatus.verified:
        return 'Profissional verificado';
      case SellerVerificationStatus.rejected:
        return 'Pedido rejeitado';
    }
  }

  /// O que o utilizador pode fazer a seguir (PT-PT).
  String get nextStepPt {
    switch (this) {
      case SellerVerificationStatus.none:
        return 'Se vendes no âmbito de uma actividade comercial, declara-te '
            'como profissional e preenche os dados.';
      case SellerVerificationStatus.incomplete:
        return 'Completa os dados obrigatórios e envia o pedido para análise.';
      case SellerVerificationStatus.pending:
        return 'A Fleaber está a analisar o teu pedido. Não precisas de fazer '
            'nada agora — avisamos quando houver decisão.';
      case SellerVerificationStatus.verified:
        return 'O distintivo «Profissional» aparece no teu perfil e nos '
            'anúncios. Para voltares a particular, pede alteração de estatuto.';
      case SellerVerificationStatus.rejected:
        return 'Corrige os dados ou documentos conforme o motivo indicado e '
            'volta a submeter o pedido.';
    }
  }
}

class SellerTradeProfile {
  const SellerTradeProfile({
    required this.userId,
    required this.isTrader,
    required this.verificationStatus,
    this.tradeName,
    this.legalName,
    this.nif,
    this.addressLine,
    this.postalCode,
    this.city,
    this.country = 'PT',
    this.phone,
    this.email,
    this.companyRegistry,
    this.representativeName,
    this.rejectionReason,
    this.stripeKycHint = false,
    this.leaveRequestPending = false,
    this.leaveRequestReason,
    this.leaveRequestedAt,
  });

  final String userId;
  final bool isTrader;
  final SellerVerificationStatus verificationStatus;
  final String? tradeName;
  final String? legalName;
  final String? nif;
  final String? addressLine;
  final String? postalCode;
  final String? city;
  final String country;
  final String? phone;
  final String? email;
  final String? companyRegistry;
  final String? representativeName;
  final String? rejectionReason;
  final bool stripeKycHint;
  final bool leaveRequestPending;
  final String? leaveRequestReason;
  final DateTime? leaveRequestedAt;

  /// Distintivo público — só após aprovação.
  bool get showProfessionalBadge =>
      isTrader && verificationStatus == SellerVerificationStatus.verified;

  bool get isVerifiedProfessional => showProfessionalBadge;

  /// Declarou profissional e ainda não está aprovado → novas vendas suspensas.
  bool get salesSuspended =>
      isTrader && verificationStatus != SellerVerificationStatus.verified;

  /// Dados mínimos preenchidos para submeter a análise.
  bool get hasMinimumTraderFields {
    bool ok(String? v) => (v ?? '').trim().isNotEmpty;
    return ok(tradeName) &&
        ok(legalName) &&
        ok(nif) &&
        ok(addressLine) &&
        ok(postalCode) &&
        ok(city) &&
        ok(phone) &&
        ok(email);
  }

  factory SellerTradeProfile.empty(String userId) => SellerTradeProfile(
        userId: userId,
        isTrader: false,
        verificationStatus: SellerVerificationStatus.none,
      );

  factory SellerTradeProfile.fromMap(Map<String, dynamic> m) {
    DateTime? leaveAt;
    final rawLeave = m['leave_requested_at']?.toString();
    if (rawLeave != null && rawLeave.isNotEmpty) {
      leaveAt = DateTime.tryParse(rawLeave);
    }
    return SellerTradeProfile(
      userId: (m['user_id'] ?? '').toString(),
      isTrader: m['is_trader'] == true,
      verificationStatus:
          SellerVerificationStatus.parse(m['verification_status']?.toString()),
      tradeName: m['trade_name']?.toString(),
      legalName: m['legal_name']?.toString(),
      nif: m['nif']?.toString(),
      addressLine: m['address_line']?.toString(),
      postalCode: m['postal_code']?.toString(),
      city: m['city']?.toString(),
      country: (m['country']?.toString().trim().isNotEmpty == true)
          ? m['country'].toString()
          : 'PT',
      phone: m['phone']?.toString(),
      email: m['email']?.toString(),
      companyRegistry: m['company_registry']?.toString(),
      representativeName: m['representative_name']?.toString(),
      rejectionReason: m['rejection_reason']?.toString(),
      stripeKycHint: m['stripe_kyc_hint'] == true,
      leaveRequestPending: m['leave_request_pending'] == true,
      leaveRequestReason: m['leave_request_reason']?.toString(),
      leaveRequestedAt: leaveAt,
    );
  }

  Map<String, dynamic> toUpsertMap({required bool submitForReview}) {
    var status = verificationStatus;
    if (!isTrader) {
      status = SellerVerificationStatus.none;
    } else if (verificationStatus == SellerVerificationStatus.verified &&
        !submitForReview) {
      // Já aprovado: preservar verified ao guardar dados (servidor aceita se não mudar).
      status = SellerVerificationStatus.verified;
    } else if (submitForReview && hasMinimumTraderFields) {
      status = SellerVerificationStatus.pending;
    } else if (isTrader && status == SellerVerificationStatus.none) {
      status = SellerVerificationStatus.incomplete;
    } else if (isTrader &&
        status == SellerVerificationStatus.rejected &&
        !submitForReview) {
      // Após rejeição: guardar correcções como incomplete até nova submissão.
      status = SellerVerificationStatus.incomplete;
    } else if (isTrader &&
        !hasMinimumTraderFields &&
        status != SellerVerificationStatus.verified) {
      status = SellerVerificationStatus.incomplete;
    }
    return {
      'user_id': userId,
      'is_trader': isTrader,
      'verification_status': status.dbValue,
      'trade_name': tradeName?.trim(),
      'legal_name': legalName?.trim(),
      'nif': nif?.trim(),
      'address_line': addressLine?.trim(),
      'postal_code': postalCode?.trim(),
      'city': city?.trim(),
      'country': (country.trim().isEmpty) ? 'PT' : country.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'company_registry': companyRegistry?.trim(),
      'representative_name': representativeName?.trim(),
      if (submitForReview)
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'stripe_kyc_hint': stripeKycHint,
    };
  }
}

/// Snapshot público (checkout / cards) — sem NIF.
class SellerTradePublicInfo {
  const SellerTradePublicInfo({
    required this.userId,
    required this.isProfessional,
    required this.professionalVerified,
    this.tradeName,
    this.city,
    this.country,
    this.contactEmail,
    this.contactPhone,
    this.salesSuspended = false,
  });

  final String userId;

  /// True só se profissional **verificado** (119.7).
  final bool isProfessional;
  final bool professionalVerified;
  final String? tradeName;
  final String? city;
  final String? country;
  final String? contactEmail;
  final String? contactPhone;
  final bool salesSuspended;

  bool get showProfessionalBadge =>
      professionalVerified || isProfessional;

  factory SellerTradePublicInfo.fromMap(Map<String, dynamic> m) {
    final verified = m['professional_verified'] == true ||
        m['is_professional'] == true;
    return SellerTradePublicInfo(
      userId: (m['user_id'] ?? m['id'] ?? '').toString(),
      isProfessional: verified,
      professionalVerified: verified,
      tradeName: (m['trade_name'] ?? m['professional_trade_name'])?.toString(),
      city: (m['city'] ?? m['professional_city'])?.toString(),
      country: (m['country'] ?? m['professional_country'])?.toString(),
      contactEmail: m['contact_email']?.toString(),
      contactPhone: m['contact_phone']?.toString(),
      salesSuspended: m['sales_suspended'] == true,
    );
  }

  /// Particular / não verificado → aviso C2C no checkout.
  static SellerTradePublicInfo particular(String userId) =>
      SellerTradePublicInfo(
        userId: userId,
        isProfessional: false,
        professionalVerified: false,
      );
}

/// Cache em memória para badges / checkout (app + web).
abstract final class SellerProfessionalCache {
  static final Map<String, SellerTradePublicInfo> _cache = {};

  static SellerTradePublicInfo? peek(String sellerId) {
    final id = sellerId.trim();
    if (id.isEmpty) return null;
    return _cache[id];
  }

  /// Compat: «profissional» = verificado (badge).
  static bool isProfessional(String? sellerId) =>
      showBadge(sellerId);

  static bool showBadge(String? sellerId) =>
      peek(sellerId ?? '')?.showProfessionalBadge == true;

  static bool salesSuspended(String? sellerId) =>
      peek(sellerId ?? '')?.salesSuspended == true;

  static void put(SellerTradePublicInfo info) {
    final id = info.userId.trim();
    if (id.isEmpty) return;
    _cache[id] = info;
  }

  static void invalidate(String? sellerId) {
    final id = (sellerId ?? '').trim();
    if (id.isEmpty) return;
    _cache.remove(id);
  }

  static Future<Map<String, SellerTradePublicInfo>> warm(
    Iterable<String> sellerIds,
  ) async {
    final missing = sellerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_cache.containsKey(e))
        .toSet()
        .toList();
    if (missing.isNotEmpty) {
      final loaded =
          await SellerProfessionalService.loadPublicForSellers(missing);
      _cache.addAll(loaded);
    }
    return {
      for (final id
          in sellerIds.map((e) => e.trim()).where((e) => e.isNotEmpty))
        id: _cache[id] ?? SellerTradePublicInfo.particular(id),
    };
  }
}

abstract final class SellerProfessionalService {
  static Future<SellerTradeProfile> loadOwn(String userId) async {
    final row = await SupaFlow.client
        .from('seller_trade_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return SellerTradeProfile.empty(userId);
    return SellerTradeProfile.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<bool> canSell(String userId) async {
    try {
      final raw = await SupaFlow.client.rpc(
        'seller_trade_can_sell',
        params: {'p_user_id': userId},
      );
      return raw == true;
    } catch (_) {
      final own = await loadOwn(userId);
      return !own.salesSuspended;
    }
  }

  static Future<SellerTradeProfile> saveOwn(
    SellerTradeProfile profile, {
    bool submitForReview = false,
  }) async {
    final payload = profile.toUpsertMap(submitForReview: submitForReview);
    final row = await SupaFlow.client
        .from('seller_trade_profiles')
        .upsert(payload, onConflict: 'user_id')
        .select()
        .single();
    SellerProfessionalCache.invalidate(profile.userId);
    return SellerTradeProfile.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<Map<String, SellerTradePublicInfo>> loadPublicForSellers(
    Iterable<String> sellerIds,
  ) async {
    final ids = sellerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final out = <String, SellerTradePublicInfo>{
      for (final id in ids) id: SellerTradePublicInfo.particular(id),
    };
    if (ids.isEmpty) return out;
    try {
      final rows = await SupaFlow.client.rpc(
        'seller_trade_public_info',
        params: {'p_seller_ids': ids},
      );
      if (rows is List) {
        for (final raw in rows) {
          if (raw is! Map) continue;
          final info = SellerTradePublicInfo.fromMap(
            Map<String, dynamic>.from(raw),
          );
          if (info.userId.isNotEmpty) out[info.userId] = info;
        }
      }
    } catch (_) {
      try {
        final dir = await SupaFlow.client
            .from('profiles_directory_public')
            .select(
              'id, is_professional, professional_verified, '
              'professional_trade_name, professional_city, professional_country',
            )
            .inFilter('id', ids);
        for (final raw in dir) {
          final m = Map<String, dynamic>.from(raw);
          final id = m['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final verified = m['professional_verified'] == true ||
              m['is_professional'] == true;
          out[id] = SellerTradePublicInfo(
            userId: id,
            isProfessional: verified,
            professionalVerified: verified,
            tradeName: m['professional_trade_name']?.toString(),
            city: m['professional_city']?.toString(),
            country: m['professional_country']?.toString(),
          );
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> listOwnDocuments(
    String userId,
  ) async {
    final rows = await SupaFlow.client
        .from('seller_trade_documents')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> registerDocument({
    required String userId,
    required String storagePath,
    required String fileName,
    String? mimeType,
    int? byteSize,
    String docType = 'id_or_registry',
  }) async {
    await SupaFlow.client.from('seller_trade_documents').insert({
      'user_id': userId,
      'storage_path': storagePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'byte_size': byteSize,
      'doc_type': docType,
    });
  }

  static Future<List<Map<String, dynamic>>> adminListQueue({
    String status = 'pending',
    int limit = 50,
  }) async {
    final rows = await SupaFlow.client.rpc(
      'seller_trade_admin_list_queue',
      params: {'p_status': status, 'p_limit': limit},
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<SellerTradeProfile> adminReview({
    required String userId,
    required bool approve,
    String? reason,
  }) async {
    final row = await SupaFlow.client.rpc(
      'seller_trade_admin_review',
      params: {
        'p_user_id': userId,
        'p_approve': approve,
        'p_reason': reason,
      },
    );
    SellerProfessionalCache.invalidate(userId);
    if (row is Map) {
      return SellerTradeProfile.fromMap(Map<String, dynamic>.from(row));
    }
    return loadOwn(userId);
  }

  /// Pedido para deixar de ser profissional (sem desactivação imediata).
  static Future<SellerTradeProfile> requestLeave({String? reason}) async {
    final row = await SupaFlow.client.rpc(
      'seller_trade_request_leave',
      params: {'p_reason': reason},
    );
    if (row is Map) {
      final profile =
          SellerTradeProfile.fromMap(Map<String, dynamic>.from(row));
      SellerProfessionalCache.invalidate(profile.userId);
      return profile;
    }
    throw StateError('Não foi possível registar o pedido de alteração.');
  }

  /// Admin: aprovar ou rejeitar pedido de saída de profissional.
  static Future<SellerTradeProfile> adminDecideLeave({
    required String userId,
    required bool approve,
    String? reason,
  }) async {
    final row = await SupaFlow.client.rpc(
      'seller_trade_admin_decide_leave',
      params: {
        'p_user_id': userId,
        'p_approve': approve,
        'p_reason': reason,
      },
    );
    SellerProfessionalCache.invalidate(userId);
    if (row is Map) {
      return SellerTradeProfile.fromMap(Map<String, dynamic>.from(row));
    }
    return loadOwn(userId);
  }

  static Future<List<Map<String, dynamic>>> adminListDocs(String userId) async {
    final rows = await SupaFlow.client.rpc(
      'seller_trade_admin_list_docs',
      params: {'p_user_id': userId},
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<String?> createSignedDocUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;
    final res = await SupaFlow.client.storage
        .from('seller-trade-docs')
        .createSignedUrl(path, 60 * 10);
    return res;
  }
}
