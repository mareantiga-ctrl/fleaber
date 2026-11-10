import 'package:flutter/material.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/hub/hub_account_routes.dart';

/// Morada + nome legal necessários para checkout com pagamento na app / etiqueta.
class ProfileShippingRequirements {
  ProfileShippingRequirements._();

  static bool _legalNameOk(String? legalFullName) {
    final name = legalFullName?.trim() ?? '';
    if (name.length < 3) return false;
    // Alguns telemóveis/gravações guardam "espaços" como NBSP (U+00A0),
    // e o `\s` pode falhar dependendo do ambiente. Normalizamos e contamos palavras.
    final normalized = name.replaceAll('\u00A0', ' ');
    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    return parts.length >= 2;
  }

  /// Público — validação de nome legal (nome + apelido) na UI de definições.
  static bool isLegalNameOk(String? legalFullName) =>
      _legalNameOk(legalFullName);

  static bool _shippingFieldsOk({
    String? line1,
    String? postal,
    String? city,
    String? country,
  }) {
    if ((line1?.trim() ?? '').length < 4) return false;
    if ((postal?.trim() ?? '').length < 4) return false;
    if ((city?.trim() ?? '').length < 2) return false;
    final c = (country?.trim() ?? '').toUpperCase();
    if (c.length != 2) return false;
    return true;
  }

  static bool isComplete(ProfilesRow? profile) {
    if (profile == null) return false;
    if (!_legalNameOk(profile.legalFullName)) return false;
    return _shippingFieldsOk(
      line1: profile.shippingLine1,
      postal: profile.shippingPostalCode,
      city: profile.shippingCity,
      country: profile.shippingCountry,
    );
  }

  /// Validação com valores dos controladores (antes de gravar).
  static bool isCompleteFromValues({
    required String legalFullName,
    required String shippingLine1,
    required String shippingPostalCode,
    required String shippingCity,
    required String shippingCountry,
  }) {
    if (!_legalNameOk(legalFullName)) return false;
    return _shippingFieldsOk(
      line1: shippingLine1,
      postal: shippingPostalCode,
      city: shippingCity,
      country: shippingCountry,
    );
  }

  static List<String> missingFields(ProfilesRow? profile) {
    final missing = <String>[];
    if (profile == null) {
      return ['perfil'];
    }
    final name = profile.legalFullName?.trim() ?? '';
    if (!_legalNameOk(name)) {
      missing.add('nome completo legal');
    }
    if ((profile.shippingLine1?.trim() ?? '').length < 4) {
      missing.add('morada (rua e número)');
    }
    if ((profile.shippingPostalCode?.trim() ?? '').length < 4) {
      missing.add('código postal');
    }
    if ((profile.shippingCity?.trim() ?? '').length < 2) {
      missing.add('localidade');
    }
    if ((profile.shippingCountry?.trim() ?? '').length != 2) {
      missing.add('país');
    }
    return missing;
  }

  static String formatAddress(ProfilesRow profile) {
    final parts = <String>[
      profile.shippingLine1?.trim() ?? '',
      if ((profile.shippingLine2?.trim() ?? '').isNotEmpty)
        profile.shippingLine2!.trim(),
      '${profile.shippingPostalCode?.trim() ?? ''} ${profile.shippingCity?.trim() ?? ''}'
          .trim(),
      profile.shippingCountry?.trim().toUpperCase() ?? 'PT',
    ].where((s) => s.isNotEmpty);
    return parts.join('\n');
  }

  /// Pagamento na app ou envio com etiqueta exige morada completa.
  static bool checkoutNeedsCompleteProfile({
    required String shippingMethod,
    required String paymentMethod,
  }) {
    final inApp = paymentMethod.contains('na App') &&
        !paymentMethod.contains('Direto');
    final sm = shippingMethod.toLowerCase();
    final carrier = sm.contains('transportadora') ||
        sm.contains('carrier') ||
        sm.contains('dpd') ||
        sm == 'carrier';
    return inApp || carrier;
  }

  static Future<ProfilesRow?> fetchCurrentProfile() async {
    if (currentUserUid.isEmpty) return null;
    const cols =
        'id, full_name, legal_full_name, location, photo_url, phone, phone_verified_at, '
        'shipping_line1, shipping_line2, shipping_postal_code, shipping_city, shipping_country, '
        'external_payments_enabled';
    final row = await SupaFlow.client
        .from('profiles')
        .select(cols)
        .eq('id', currentUserUid)
        .maybeSingle();
    if (row == null) return null;
    return ProfilesRow(Map<String, dynamic>.from(row));
  }

  /// Devolve `true` se pode continuar; `false` se bloqueou e mostrou diálogo.
  static Future<bool> ensureCheckoutReady(BuildContext context) async {
    final profile = await fetchCurrentProfile();
    if (isComplete(profile)) return true;
    if (!context.mounted) return false;

    final missing = missingFields(profile);
    final list = missing.join(', ');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completa o teu perfil'),
        content: Text(
          'Para comprar com pagamento na app e envio com etiqueta, '
          'precisas de nome completo legal e morada de entrega nas definições.\n\n'
          'Em falta: $list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mais tarde'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              HubAccountRoutes.openContaDefinicoes(ctx);
            },
            child: const Text('Definições de conta'),
          ),
        ],
      ),
    );
    return false;
  }
}
