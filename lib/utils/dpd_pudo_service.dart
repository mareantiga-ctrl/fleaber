import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '/backend/supabase/supabase.dart';

/// Ponto Pickup DPD (MyPudo GetPudoList) — sem credenciais no cliente.
class DpdPudoPoint {
  const DpdPudoPoint({
    required this.pudoId,
    required this.name,
    required this.address1,
    required this.zipCode,
    required this.city,
    this.distanceKm,
  });

  final String pudoId;
  final String name;
  final String address1;
  final String zipCode;
  final String city;
  final double? distanceKm;

  String get subtitle =>
      [address1, '$zipCode $city'].where((e) => e.trim().isNotEmpty).join(' · ');

  factory DpdPudoPoint.fromJson(Map<String, dynamic> m) {
    double? dist;
    final rawDist = m['distance_km'] ?? m['distanceKm'] ?? m['distance'];
    if (rawDist is num) {
      dist = rawDist.toDouble();
    } else if (rawDist != null) {
      dist = double.tryParse(rawDist.toString());
    }
    return DpdPudoPoint(
      pudoId: (m['pudoId'] ?? m['pudo_id'] ?? '').toString().trim(),
      name: (m['name'] ?? '').toString().trim(),
      address1: (m['address1'] ?? m['address'] ?? '').toString().trim(),
      zipCode: (m['zipCode'] ?? m['zip_code'] ?? '').toString().trim(),
      city: (m['city'] ?? '').toString().trim(),
      distanceKm: dist,
    );
  }
}

class DpdPudoSearchResult {
  const DpdPudoSearchResult({
    required this.points,
    this.resolvedCity,
    this.postalCode,
  });

  final List<DpdPudoPoint> points;
  final String? resolvedCity;
  final String? postalCode;
}

class DpdPudoService {
  DpdPudoService._();

  /// Pesquisa pontos Pickup. Aceita CP, localidade, ou ambos.
  static Future<DpdPudoSearchResult> searchDetailed({
    String zipCode = '',
    String city = '',
    String countrycode = 'PRT',
  }) async {
    try {
      final res = await SupaFlow.client.functions.invoke(
        'dpd-pudo-list',
        body: {
          'zipCode': zipCode.trim(),
          'city': city.trim(),
          'countrycode': countrycode.trim().isEmpty ? 'PRT' : countrycode.trim(),
        },
      );
      return _parseSearch(res.data);
    } on FunctionException catch (e) {
      final fromDetails = _hintFromPayload(e.details);
      throw Exception(
        fromDetails.isNotEmpty
            ? fromDetails
            : 'Não foi possível obter pontos Pickup.',
      );
    }
  }

  static DpdPudoSearchResult _parseSearch(dynamic data) {
    if (data is! Map) {
      throw Exception('Não foi possível obter pontos Pickup.');
    }
    if (data['ok'] != true) {
      final hint = data['hint']?.toString().trim();
      final err = (data['error'] ?? 'pesquisa_pickup_falhou').toString();
      throw Exception(
        (hint != null && hint.isNotEmpty) ? hint : err,
      );
    }
    final raw = data['points'];
    final points = raw is! List
        ? const <DpdPudoPoint>[]
        : raw
            .whereType<Map>()
            .map((e) => DpdPudoPoint.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.pudoId.isNotEmpty)
            .toList();
    return DpdPudoSearchResult(
      points: points,
      resolvedCity: (data['resolved_city'] ?? data['city'])?.toString(),
      postalCode: data['postal_code']?.toString(),
    );
  }

  static String _hintFromPayload(Object? details) {
    if (details is Map) {
      final hint = details['hint']?.toString().trim();
      if (hint != null && hint.isNotEmpty) return hint;
      final err = details['error']?.toString().trim();
      if (err != null && err.isNotEmpty) return err;
    }
    return '';
  }

  static Future<List<DpdPudoPoint>> search({
    required String zipCode,
    required String city,
    String countrycode = 'PRT',
  }) async {
    final r = await searchDetailed(
      zipCode: zipCode,
      city: city,
      countrycode: countrycode,
    );
    return r.points;
  }

  static Future<bool> attachPickupToOrder({
    required String orderId,
    required DpdPudoPoint point,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_set_order_delivery_pickup',
      params: {
        'p_order_id': orderId,
        'p_pudo_id': point.pudoId,
        'p_label': point.name,
        'p_address1': point.address1,
        'p_zip': point.zipCode,
        'p_city': point.city,
        'p_country': 'PT',
      },
    );
    if (res is Map && res['ok'] == true) return true;
    return false;
  }

  static Future<bool> attachHomeToOrder(String orderId) async {
    final res = await SupaFlow.client.rpc(
      'batata_set_order_delivery_home',
      params: {'p_order_id': orderId},
    );
    if (res is Map && res['ok'] == true) return true;
    return false;
  }
}
