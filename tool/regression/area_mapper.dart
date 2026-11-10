/// Mapeia A### → área lógica do runner.
String areaForTestId(String id) {
  final n = int.tryParse(id.replaceFirst('A', ''));
  if (n == null) return 'unknown';
  if (n >= 1 && n <= 49) return 'prep';
  if (n >= 50 && n <= 79) return 'publish';
  if (n >= 80 && n <= 129) return 'seller_ops';
  if (n >= 130 && n <= 144) return 'catalog';
  if (n >= 145 && n <= 189) return 'buyer_player';
  if (n >= 190 && n <= 230) return 'checkout';
  if (n >= 231 && n <= 249) return 'payments';
  if (n >= 250 && n <= 279) return 'raffle';
  if (n >= 280 && n <= 309) return 'messages';
  if (n >= 310 && n <= 339) return 'gravado';
  if (n >= 340 && n <= 349) return 'cross_pool';
  if (n >= 350 && n <= 369) return 'marketplace';
  if (n >= 370 && n <= 389) return 'helpers';
  if (n >= 390 && n <= 419) return 'errors';
  if (n >= 420 && n <= 429) return 'sync';
  return 'unknown';
}

/// Alias de filtro `--area checkout` (aceita sinónimos).
bool areaMatchesFilter(String testArea, String filter) {
  final f = filter.trim().toLowerCase();
  final a = testArea.trim().toLowerCase();
  if (f == a) return true;
  const aliases = <String, List<String>>{
    'checkout': ['checkout', 'payments'],
    'payments': ['payments', 'checkout'],
    'rifa': ['raffle', 'rifa'],
    'raffle': ['raffle', 'rifa'],
    'gravado': ['gravado', 'vod', 'replay'],
    'messages': ['messages', 'chat', 'fomo'],
    'seller': ['seller_ops', 'catalog'],
    'buyer': ['buyer_player'],
    'infra': ['helpers', 'errors', 'sync'],
  };
  final expanded = aliases[f] ?? [f];
  return expanded.contains(a);
}
