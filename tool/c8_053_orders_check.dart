// ignore_for_file: avoid_print
/// C8 APP-053 — encomendas canceláveis do vendedor (sem tocar na prova C5 paga).
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  const protectPaid = 'ce4fba72-9efd-4f8f-b980-6251d6da9d7f';
  final orders = await client.select(
    'orders',
    filter: 'seller_id=eq.$seller&order=created_at.desc',
    limit: 16,
  );
  final pids = orders
      .map((o) => o['product_id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  final titles = <String, String>{};
  if (pids.isNotEmpty) {
    final products = await client.select(
      'products',
      filter: 'id=in.(${pids.join(',')})',
      limit: 40,
    );
    for (final p in products) {
      titles[p['id'].toString()] = (p['title'] ?? '').toString();
    }
  }
  print(const JsonEncoder.withIndent('  ').convert(orders.map((o) {
        final id = o['id'].toString();
        final st = (o['status'] ?? '').toString();
        final blocked = const {
          'enviado',
          'concluido',
          'pedido_devolucao',
          'em_devolucao',
          'devolvida',
        };
        final cancelled = st.toLowerCase().contains('cancel') ||
            st.toLowerCase().contains('anulad');
        return {
          'id': id,
          'status': st,
          'product': titles[o['product_id']?.toString()] ?? o['product_id'],
          'created_at': o['created_at'],
          'protect_c5_paid': id == protectPaid,
          'ui_cancel_likely': !cancelled && !blocked.contains(st),
        };
      }).toList()));
}
