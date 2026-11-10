import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/services/commerce_guest_session_service.dart';

void main() {
  test('isValidGuestToken exige ≥32 chars', () {
    expect(CommerceGuestSessionService.isValidGuestToken('short'), isFalse);
    expect(
      CommerceGuestSessionService.isValidGuestToken(
        'abcdefghijklmnopqrstuvwxyz012345',
      ),
      isTrue,
    );
  });

  test('checkoutGuestParams só envia o token próprio', () {
    final p = CommerceGuestSessionService.checkoutGuestParamsStatic(
      '  abcdefghijklmnopqrstuvwxyz012345  ',
    );
    expect(p.keys, ['p_guest_token']);
    expect(p['p_guest_token'], 'abcdefghijklmnopqrstuvwxyz012345');
  });

  test('checkoutBeginParams inclui token e lines sem pagamento', () {
    final p = CommerceGuestSessionService.checkoutBeginParams(
      guestToken: 'abcdefghijklmnopqrstuvwxyz012345',
      lines: [
        {'reservation_request_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'},
      ],
      clientIdempotencyKey: 'e76-test',
    );
    expect(p['p_guest_token'], 'abcdefghijklmnopqrstuvwxyz012345');
    expect(p['p_payment_rail'], 'off_platform');
    expect(p['p_lines'], isA<List>());
    expect(p['p_client_idempotency_key'], 'e76-test');
  });

  test('checkoutBeginParams rejeita token curto', () {
    expect(
      () => CommerceGuestSessionService.checkoutBeginParams(
        guestToken: 'short',
        lines: const [],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('checkoutBeginParams mantém literais RPC guest (anti tree-shake)', () {
    final p = CommerceGuestSessionService.checkoutBeginParams(
      guestToken: 'abcdefghijklmnopqrstuvwxyz012345',
      lines: const [],
    );
    expect(p.containsKey('p_guest_token'), isTrue);
    expect(p['p_guest_token'], isNotEmpty);
  });
}
