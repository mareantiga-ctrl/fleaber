/// Código postal e localidades PT — validação + resolução (geoapi.pt via Edge).
library;

import '/backend/supabase/supabase.dart';

final RegExp kPtPostalCodeRegex = RegExp(r'^\d{4}-\d{3}$');

/// Normaliza entrada livre para `NNNN-NNN` quando possível.
String? normalizePtPostalCode(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length != 7) return null;
  return '${digits.substring(0, 4)}-${digits.substring(4)}';
}

bool isValidPtPostalCode(String? raw) {
  final n = normalizePtPostalCode(raw) ?? (raw ?? '').trim();
  return kPtPostalCodeRegex.hasMatch(n);
}

class PtPostalLookupResult {
  const PtPostalLookupResult({
    required this.postalCode,
    required this.locality,
    this.municipality,
    this.district,
  });

  final String postalCode;
  final String locality;
  final String? municipality;
  final String? district;
}

/// Resolve localidade a partir do CP (Edge `pt-postal-resolve` → geoapi.pt).
/// Não bloqueia moradas: se falhar, devolve null (utilizador pode escrever).
Future<PtPostalLookupResult?> lookupPtPostal(String postalRaw) async {
  final postal = normalizePtPostalCode(postalRaw);
  if (postal == null) return null;
  try {
    final res = await SupaFlow.client.functions.invoke(
      'pt-postal-resolve',
      body: {'postal_code': postal},
    );
    final data = res.data;
    if (data is! Map || data['ok'] != true) return null;
    final loc = (data['locality'] ?? data['Localidade'] ?? '').toString().trim();
    if (loc.isEmpty) return null;
    return PtPostalLookupResult(
      postalCode: postal,
      locality: loc,
      municipality: data['municipality']?.toString(),
      district: data['district']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

/// Sugestões de localidade (prefixo) — geoapi via Edge.
Future<List<String>> suggestPtLocalities(String query) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  try {
    final res = await SupaFlow.client.functions.invoke(
      'pt-postal-resolve',
      body: {'locality_query': q},
    );
    final data = res.data;
    if (data is! Map || data['ok'] != true) return const [];
    final raw = data['suggestions'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(12)
        .toList();
  } catch (_) {
    return const [];
  }
}
