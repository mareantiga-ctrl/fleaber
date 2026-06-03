import '/backend/supabase/supabase.dart';

/// "003/2" → "003". "003" → "003".
String refFamilyBase(String ref) {
  final t = ref.trim();
  if (t.isEmpty) return '';
  final m = RegExp(r'^(.*)/(\d+)$').firstMatch(t);
  return m != null ? m.group(1)! : t;
}

/// Próximo `base/N` para o vendedor (ex.: 003 → 003/1; já existindo 003/2 → 003/3).
Future<String> nextRecolocarRefForSeller({
  required String sellerId,
  required String base,
}) async {
  final b = base.trim();
  if (b.isEmpty) {
    return 'FB-${DateTime.now().millisecondsSinceEpoch}/1';
  }

  final rows = await ProductsTable().queryRows(
    queryFn: (q) => q.eqOrNull('seller_id', sellerId).limit(500),
  );

  final esc = RegExp.escape(b);
  final slashNum = RegExp('^$esc/(\\d+)\$');
  var maxN = 0;

  for (final r in rows) {
    final rc = (r.refCode ?? '').toString().trim();
    if (rc.isEmpty) continue;
    if (rc == b) {
      continue;
    }
    final m = slashNum.firstMatch(rc);
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > maxN) maxN = n;
    }
  }

  final next = maxN + 1;
  var candidate = '$b/$next';
  const maxLen = 80;
  if (candidate.length > maxLen) {
    final suffix = '/$next';
    final budget = (maxLen - suffix.length).clamp(1, b.length);
    candidate = '${b.substring(0, budget)}$suffix';
  }
  return candidate;
}

/// Novo anúncio (UUID novo) com a mesma série de ref [base/N] que «Vender outro igual».
Future<ProductsRow> insertRelistedProductFromSource({
  required ProductsRow source,
  required String sellerId,
}) async {
  final rawRef = source.refCode?.toString().trim() ?? '';
  final familyBase = refFamilyBase(rawRef);
  final fallbackBase = 'REF-${source.id}';
  final baseForSeries = familyBase.isNotEmpty
      ? familyBase
      : (fallbackBase.length > 48
          ? fallbackBase.substring(0, 48)
          : fallbackBase);
  final newRef = await nextRecolocarRefForSeller(
    sellerId: sellerId,
    base: baseForSeries,
  );

  return ProductsTable().insert({
    'seller_id': sellerId,
    'title': source.title,
    'description': source.description,
    'price': source.price,
    'category': source.category,
    'image_urls': List<String>.from(source.imageUrls),
    'is_sold': false,
    'list_on_marketplace': true,
    'available_for_live': source.availableForLive ?? false,
    'favorites_count': 0,
    'ref_code': newRef,
    'state': source.state,
    'clothing_size': source.clothingSize,
    'gender': source.gender,
  });
}
