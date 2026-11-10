/// Confirmar C3 com payment_method persistido (pass2 mk() omitiu payment).
import 'dart:io';

import '_rtdh.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DH confirm C3');
  await c.loginActors();

  Future<Map<String, Object?>> enc(String tag, String pm) async {
    final sql = await c.rpc(
      'batata_is_off_platform_payment',
      {'p_method': pm},
      service: true,
    );
    final pid = await c.createProduct(title: '$prefix-c3c-$tag', qty: 2, price: 18);
    String? oid;
    if (pid != null) {
      oid = await c.insertOrder(
        productId: pid,
        price: 18,
        jwt: c.buyerJwt,
        payment: pm,
      );
      if (oid == null) {
        oid = await c.insertOrder(
          productId: pid,
          price: 18,
          payment: pm,
          service: true,
        );
      }
    }
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (oid != null && pid != null) {
      cpi = await c.checkout(orderId: oid, productId: pid, amount: 1);
      row = await c.orderRow(oid);
    }
    final stored = '${row?['payment_method'] ?? ''}';
    return {
      'pm': pm,
      'sql': sql.json,
      'insert_oid': oid,
      'cpi': cpi?.brief,
      'opened': cpi != null && cpi.ok && (cpi.sessionId ?? '').startsWith('cs_'),
      'stored_pm': stored,
      'codes': stored.runes.map((r) => r.toRadixString(16)).toList(),
      'sid': cpi?.sessionId,
      'status_http': cpi?.status,
    };
  }

  final suffix = await enc('sfx', 'mb way x');
  stdout.writeln('C3-SUFFIX $suffix');
  final pfx = await enc('pfx', 'xxmbway');
  stdout.writeln('C3-PREFIX $pfx');
  final transx = await enc('trx', 'transferencia extra');
  stdout.writeln('C3-TRANSX $transx');

  await dumpJson('${outDir()}/confirm_c3.json', {
    'C3-SUFFIX': suffix,
    'C3-PREFIX': pfx,
    'C3-TRANSX': transx,
  });
}
