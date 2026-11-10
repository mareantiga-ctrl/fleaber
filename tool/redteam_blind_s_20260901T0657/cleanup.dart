import '_rts.dart';

void main() async {
  final c = Rts.fromEnv(loadEnv());
  final h = await c.rest(
    'PATCH',
    'seller_helpers?id=eq.9b53de46-6d63-4ec5-8d6d-7f9175d4a283',
    service: true,
    body: {'active': false, 'invitation_status': 'rejected'},
    prefer: 'return=representation',
  );
  final pii = await c.rest(
    'PATCH',
    'profiles?id=eq.980f4fa1-0004-42f9-abca-69f1a9c29588',
    service: true,
    body: {
      'phone': null,
      'legal_full_name': null,
      'iban': null,
      'mb_way': null,
    },
    prefer: 'return=minimal',
  );
  // ignore: avoid_print
  print('helper ${h.brief}');
  // ignore: avoid_print
  print('pii ${pii.status}');
}
