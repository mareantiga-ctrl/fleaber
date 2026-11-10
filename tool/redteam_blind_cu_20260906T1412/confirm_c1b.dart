/// Confirm C1b persisted URL (full, unclipped).
import '_rtcu.dart';

void main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  final h = await c.rest(
    'GET',
    'order_dispute_replies?id=eq.0c24fb88-b585-427b-b2c0-6a2b48a17e83&select=id,dispute_id,proof_photos,message',
    service: true,
  );
  print('STATUS ${h.status}');
  print(h.body);
  final canon = await c.rpc(
    'batata_storage_url_path_canonical',
    {
      'p_url':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/eca7b51c-9fb9-4824-845b-5a27caf808e9/ok.png%252f%255corder_disputes/4064686f-1949-45fc-8806-c499d1bf0688/00000000-0000-0000-0000-00000000c2c2/rtcu-secret.png',
    },
    service: true,
  );
  print('CANON ${canon.status} ${canon.body}');
}
