/// Confirm A4 stored payment_method + CPI; array MB WAY; B1 fav vs Hub.
import 'dart:convert';
import 'dart:io';
import '_rtdo.dart';

Future<void> main() async {
  final c = Rtdo.fromEnv(loadEnv());
  await c.loginActors();

  const arrId = 'fe81c5e7-b208-4cef-80ee-196bd3b48cc1';
  const numId = '927a7428-c98c-4dab-81ed-09f3cd9b890d';
  const b1pid = '70076908-9986-4a07-930a-9fa9d9c9baa1';
  const favId = '8448d712-665a-4b94-a679-484cc7456d22';

  final arr = await c.orderRow(arrId);
  final numRow = await c.orderRow(numId);
  HttpHit? arrCpi;
  HttpHit? numCpi;
  if (arr != null) {
    arrCpi = await c.checkout(
      orderId: arrId,
      productId: '${arr['product_id']}',
      amount: 1,
    );
  }
  if (numRow != null) {
    numCpi = await c.checkout(
      orderId: numId,
      productId: '${numRow['product_id']}',
      amount: 1,
    );
  }

  final pid = await c.createProduct(title: '$prefix-a4c-mbway-arr', qty: 2);
  HttpHit? arrOff;
  HttpHit? arrOffCpi;
  Map<String, dynamic>? arrOffRow;
  if (pid != null) {
    arrOff = await c.insertOrderRaw(
      productId: pid,
      payment: <String>['MB WAY'],
      jwt: c.buyerJwt,
    );
    if (arrOff.firstId != null) {
      arrOffRow = await c.orderRow(arrOff.firstId!);
      arrOffCpi = await c.checkout(
        orderId: arrOff.firstId!,
        productId: pid,
        amount: 1,
      );
    }
  }

  final sqlArr = await c.sqlOff('${arr?['payment_method']}');
  final sqlNum = await c.sqlOff('${numRow?['payment_method']}');
  final sqlOffStored = await c.sqlOff('${arrOffRow?['payment_method']}');

  final hub = await c.hubSku(b1pid, anon: true);
  final fav = await c.rest(
    'GET',
    'favorites?id=eq.$favId&select=id,user_id,product_id',
    service: true,
  );
  final sell = await c.hubSellable(b1pid);
  final allowed = await c.rpc(
    'batata_product_is_favorite_allowed',
    {'p_product_id': b1pid},
    service: true,
  );

  final out = {
    'arr_row_pm': arr?['payment_method'],
    'arr_status': arr?['status'],
    'arr_cpi': arrCpi?.brief,
    'arr_sql': sqlArr.json,
    'num_row_pm': numRow?['payment_method'],
    'num_status': numRow?['status'],
    'num_cpi': numCpi?.brief,
    'num_sql': sqlNum.json,
    'arr_off_insert': arrOff?.brief,
    'arr_off_pm': arrOffRow?['payment_method'],
    'arr_off_cpi': arrOffCpi?.brief,
    'arr_off_sql': sqlOffStored.json,
    'b1_hub': hub.brief,
    'b1_hub_n': c.hubN(hub),
    'b1_fav': fav.brief,
    'b1_sellable': sell.json,
    'b1_fav_allowed': allowed.json,
  };
  await dumpJson('${outDir()}/confirm_a4.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
