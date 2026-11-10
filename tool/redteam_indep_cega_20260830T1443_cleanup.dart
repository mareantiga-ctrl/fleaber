import 'live_ops_staging_client.dart';

void main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const orders = [
    '2f692dda-03ae-4213-97e2-f2925b8ab3d6',
    '7066aa44-4b24-4c5f-b9f7-a3f45e6733ce',
  ];
  const products = [
    '468c49ac-b295-439f-98d1-b2601e582c45',
    'e549100d-31e3-44d2-8477-c56ada9622b4',
  ];
  for (final id in orders) {
    try {
      await c.patch('orders', 'id=eq.$id', {'status': 'cancelado'});
      print('cancel $id');
    } catch (err) {
      print('skip $id $err');
    }
  }
  for (final p in products) {
    try {
      await c.patch('products', 'id=eq.$p', {
        'list_on_marketplace': false,
        'quantity': 0,
      });
      print('bury $p');
    } catch (err) {
      print('skip $p $err');
    }
  }
}
