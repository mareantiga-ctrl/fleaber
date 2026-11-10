import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fleaber/utils/login_remember_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('C1 purge remove password legada base64', () async {
    SharedPreferences.setMockInitialValues({
      'fleaber_login_remember_v1': true,
      'fleaber_login_email_v1': 'a@b.pt',
      'fleaber_login_password_v1': 'c2VjcmV0', // base64 "secret"
    });
    await LoginRememberStorage.purgeLegacyPasswords();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('fleaber_login_password_v1'), isFalse);
    final email = await LoginRememberStorage.loadRememberedEmail();
    expect(email, 'a@b.pt');
  });

  test('C1 saveRememberedEmail nunca grava password', () async {
    await LoginRememberStorage.saveCredentials(
      email: 'x@y.pt',
      password: 'nao_guardar',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fleaber_login_email_v1'), 'x@y.pt');
    expect(prefs.containsKey('fleaber_login_password_v1'), isFalse);
    final legacy = await LoginRememberStorage.loadCredentials();
    expect(legacy?.email, 'x@y.pt');
    expect(legacy?.password, '');
  });

  test('C1 clearCredentials limpa tudo', () async {
    await LoginRememberStorage.saveRememberedEmail('z@z.pt');
    await LoginRememberStorage.clearCredentials();
    expect(await LoginRememberStorage.loadRememberedEmail(), isNull);
    expect(await LoginRememberStorage.isRememberEnabled(), isFalse);
  });
}
