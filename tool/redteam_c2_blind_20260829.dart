/// RED TEAM CEGO C2 — probe independente (staging only).
/// Não usa service_role. Não altera schema. Produção não tocada.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';

final results = <Map<String, dynamic>>[];
final blocked = <Map<String, dynamic>>[];
final races = <Map<String, dynamic>>[];
final chains = <Map<String, dynamic>>[];
final coverage = <String>[];

late String anon;
late String buyerJwt, sellerJwt, extraJwt;
late String buyerId, sellerId, extraId;
String? extraEmail;

final httpClient = HttpClient()..userAgent = 'fleaber-rt-c2-blind/20260829';

Map<String, String> loadEnv(String path) {
  final m = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    m[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return m;
}

Future<Map<String, dynamic>> req({
  required String jwt,
  required String method,
  required String path,
  Object? body,
  Map<String, String>? extraHeaders,
  bool fn = false,
}) async {
  final uri = Uri.parse(
    fn ? '$base/functions/v1/$path' : '$base/rest/v1/$path',
  );
  final r = await httpClient.openUrl(method, uri);
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $jwt');
  r.headers.set('Accept', 'application/json');
  if (!fn) {
    r.headers.set('Prefer', 'return=representation,count=exact');
    r.headers.set('Content-Profile', 'public');
  }
  extraHeaders?.forEach(r.headers.set);
  if (body != null) {
    r.headers.set('Content-Type', 'application/json');
    r.add(utf8.encode(body is String ? body : jsonEncode(body)));
  }
  final resp = await r.close().timeout(const Duration(seconds: 40));
  final txt = await utf8.decodeStream(resp);
  String? range;
  try {
    range = resp.headers.value('content-range');
  } catch (_) {}
  dynamic parsed;
  try {
    parsed = txt.isEmpty ? null : jsonDecode(txt);
  } catch (_) {
    parsed = txt;
  }
  return {
    'status': resp.statusCode,
    'body': parsed,
    'raw': txt.length > 2500 ? '${txt.substring(0, 2500)}…' : txt,
    'range': range,
  };
}

Future<Map<String, dynamic>> rest(
  String jwt,
  String method,
  String path, [
  Object? body,
]) =>
    req(jwt: jwt, method: method, path: path, body: body);

Future<Map<String, dynamic>> rpc(
  String jwt,
  String name, [
  Map<String, dynamic>? params,
]) =>
    req(jwt: jwt, method: 'POST', path: 'rpc/$name', body: params ?? {});

Future<Map<String, dynamic>> edge(
  String jwt,
  String name, {
  String method = 'POST',
  Object? body,
  String query = '',
}) =>
    req(
      jwt: jwt,
      method: method,
      path: query.isEmpty ? name : '$name$query',
      body: body,
      fn: true,
    );

Future<Map<String, dynamic>> signIn(String email, String password) async {
  final uri = Uri.parse('$base/auth/v1/token?grant_type=password');
  final r = await httpClient.postUrl(uri);
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $anon');
  r.headers.set('Content-Type', 'application/json');
  r.add(utf8.encode(jsonEncode({'email': email, 'password': password})));
  final resp = await r.close();
  final txt = await utf8.decodeStream(resp);
  if (resp.statusCode >= 300) {
    throw StateError('signin $email failed ${resp.statusCode} $txt');
  }
  return jsonDecode(txt) as Map<String, dynamic>;
}

void rec({
  required String id,
  required String kind, // FINDING | BLOCKED | RACE | CHAIN | INFO
  String severity = '',
  required String title,
  required Map<String, dynamic> evidence,
  String invariant = '',
}) {
  final row = {
    'id': id,
    'kind': kind,
    'severity': severity,
    'title': title,
    'invariant': invariant,
    'evidence': evidence,
  };
  results.add(row);
  if (kind == 'BLOCKED') blocked.add(row);
  if (kind == 'RACE') races.add(row);
  if (kind == 'CHAIN') chains.add(row);
}

bool okish(Map<String, dynamic> r) {
  final s = r['status'] as int;
  return s >= 200 && s < 300;
}

String snippet(dynamic v, [int n = 400]) {
  final s = v is String ? v : jsonEncode(v);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  return const [];
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

Future<void> main() async {
  final env = loadEnv(
    '${Directory.current.path}/tool/live_ops_staging.env',
  );
  anon = env['SUPABASE_ANON_KEY']!;
  if (!(env['SUPABASE_URL'] ?? '').contains(stagingRef)) {
    stderr.writeln('REFUSE: not staging');
    exit(2);
  }

  final b = await signIn(
    env['LIVE_OPS_TEST_BUYER_EMAIL']!,
    env['LIVE_OPS_TEST_BUYER_PASSWORD']!,
  );
  final s = await signIn(
    env['LIVE_OPS_TEST_SELLER_EMAIL']!,
    env['LIVE_OPS_TEST_SELLER_PASSWORD']!,
  );
  buyerJwt = b['access_token'] as String;
  sellerJwt = s['access_token'] as String;
  buyerId = (b['user'] as Map)['id'] as String;
  sellerId = (s['user'] as Map)['id'] as String;

  extraEmail =
      'c2blind${DateTime.now().millisecondsSinceEpoch}@axinoquaa.pt';
  final signupUri = Uri.parse('$base/auth/v1/signup');
  final su = await httpClient.postUrl(signupUri);
  su.headers.set('apikey', anon);
  su.headers.set('Authorization', 'Bearer $anon');
  su.headers.set('Content-Type', 'application/json');
  su.add(utf8.encode(jsonEncode({
    'email': extraEmail,
    'password': 'testeteste123',
  })));
  final suResp = await su.close();
  final suTxt = await utf8.decodeStream(suResp);
  final suJson = jsonDecode(suTxt) as Map<String, dynamic>;
  extraJwt = (suJson['access_token'] ?? '') as String;
  extraId = ((suJson['user'] as Map?)?['id'] ?? '') as String;
  if (extraJwt.isEmpty) {
    rec(
      id: 'C2-INFO-SIGNUP',
      kind: 'INFO',
      title: 'signup extra buyer falhou; races 2-compradores limitadas',
      evidence: {'status': suResp.statusCode, 'body': snippet(suTxt)},
    );
  } else {
    coverage.add('auth.signup extra buyer');
  }

  rec(
    id: 'C2-INFO-IDS',
    kind: 'INFO',
    title: 'identidades',
    evidence: {
      'buyer': buyerId,
      'seller': sellerId,
      'extra': extraId,
      'staging': stagingRef,
    },
  );

  await _surfaceRecon();
  await _rlsAndGrants();
  await _orderStateMachine();
  await _crossObjectMix();
  await _financialRpcs();
  await _edgeFunctions();
  await _storageAndPii();
  await _liveRaffleReservations();
  await _races();
  await _walletPayout();
  await _adminStaffPs();

  final out = {
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'project': stagingRef,
    'production_untouched': true,
    'identities': {
      'buyer': buyerId,
      'seller': sellerId,
      'extra': extraId,
      'extra_email': extraEmail,
    },
    'coverage': coverage,
    'results': results,
    'blocked': blocked.map((e) => e['id']).toList(),
    'races': races,
    'chains': chains,
  };
  final dir = Directory('tool/reports')..createSync(recursive: true);
  final path =
      '${dir.path}/REDTEAM_C2_BLIND_20260829.json';
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('WROTE $path results=${results.length}');
  for (final r in results.where((e) => e['kind'] == 'FINDING')) {
    stdout.writeln(
      'FINDING ${r['severity']} ${r['id']} ${r['title']}',
    );
  }
}

Future<void> _surfaceRecon() async {
  coverage.add('recon tables/events/wallets');
  final events = await rest(
    buyerJwt,
    'GET',
    'stripe_checkout_events?select=event,order_id,session_id,buyer_id,live_id,product_id,detail&order=created_at.desc&limit=20',
  );
  final evList = asList(events['body']);
  final foreignSessions = evList.where((e) {
    final m = asMap(e);
    if (m == null) return false;
    final bid = '${m['buyer_id'] ?? ''}';
    return bid.isNotEmpty && bid != buyerId;
  }).toList();
  rec(
    id: 'C2-EV-01',
    kind: foreignSessions.isNotEmpty ? 'FINDING' : 'INFO',
    severity: foreignSessions.isNotEmpty ? 'P2' : '',
    title: 'stripe_checkout_events visibilidade',
    invariant: 'eventos de checkout só do próprio',
    evidence: {
      'status': events['status'],
      'range': events['range'],
      'sample_n': evList.length,
      'foreign_sessions_n': foreignSessions.length,
      'foreign_sample': foreignSessions.take(3).toList(),
    },
  );

  final winners = await rest(
    buyerJwt,
    'GET',
    'live_raffle_winners?select=id,raffle_id,user_id,rank&limit=10',
  );
  final wList = asList(winners['body']);
  final foreignW = wList.where((e) {
    final m = asMap(e);
    return m != null && '${m['user_id']}' != buyerId;
  }).toList();
  rec(
    id: 'C2-RF-01',
    kind: foreignW.isNotEmpty ? 'FINDING' : 'INFO',
    severity: foreignW.isNotEmpty ? 'P3' : '',
    title: 'live_raffle_winners leitura global',
    invariant: 'vencedores de rifa não são dump autenticado',
    evidence: {
      'status': winners['status'],
      'n': wList.length,
      'foreign_n': foreignW.length,
    },
  );

  final lives = await rest(
    buyerJwt,
    'GET',
    'lives?select=id,seller_id,status,is_active,mux_playback_id&limit=5',
  );
  rec(
    id: 'C2-LV-01',
    kind: 'INFO',
    title: 'lives select sem keys',
    evidence: {'status': lives['status'], 'range': lives['range']},
  );

  final keys = await rest(
    buyerJwt,
    'GET',
    'lives?select=id,stream_key,mux_stream_key,livekit_url&limit=2',
  );
  rec(
    id: 'C2-LV-02',
    kind: (keys['status'] as int) >= 400 ? 'BLOCKED' : 'FINDING',
    severity: (keys['status'] as int) < 400 ? 'P1' : '',
    title: 'lives stream keys via PostgREST',
    invariant: 'chaves de ingestão não são SELECT authenticated',
    evidence: {'status': keys['status'], 'raw': snippet(keys['raw'])},
  );
}

Future<void> _rlsAndGrants() async {
  coverage.add('RLS INSERT/UPDATE/DELETE orders products wallets profiles');

  // Anon
  final anonOrders = await rest(anon, 'GET', 'orders?select=id&limit=1');
  rec(
    id: 'C2-ANON-ORDERS',
    kind: okish(anonOrders) && asList(anonOrders['body']).isNotEmpty
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(anonOrders) && asList(anonOrders['body']).isNotEmpty
        ? 'P1'
        : '',
    title: 'anon SELECT orders',
    evidence: {'status': anonOrders['status'], 'raw': snippet(anonOrders['raw'])},
  );

  final walletOther = await rest(
    buyerJwt,
    'GET',
    'wallets?id=eq.$sellerId&select=id,balance,stripe_account_id',
  );
  final wRows = asList(walletOther['body']);
  rec(
    id: 'C2-WL-OTHER',
    kind: wRows.isNotEmpty ? 'FINDING' : 'BLOCKED',
    severity: wRows.isNotEmpty ? 'P2' : '',
    title: 'buyer SELECT wallet do seller',
    invariant: 'saldo wallet só próprio',
    evidence: {
      'status': walletOther['status'],
      'rows': wRows,
      'range': walletOther['range'],
    },
  );

  final balPatch = await rest(
    buyerJwt,
    'PATCH',
    'wallets?id=eq.$buyerId',
    {'balance': 99999.12},
  );
  rec(
    id: 'C2-WL-PATCH',
    kind: okish(balPatch) ? 'FINDING' : 'BLOCKED',
    severity: okish(balPatch) ? 'P0' : '',
    title: 'buyer PATCH wallets.balance',
    invariant: 'saldo não é writable pelo JWT',
    evidence: {'status': balPatch['status'], 'raw': snippet(balPatch['raw'])},
  );

  final credit = await rpc(buyerJwt, 'batata_credit_wallet_once', {
    'p_user_id': buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 50,
    'p_type': 'reembolso',
    'p_description': 'c2',
  });
  rec(
    id: 'C2-WL-CREDIT-RPC',
    kind: okish(credit) && credit['body'] == true ? 'FINDING' : 'BLOCKED',
    severity: okish(credit) && credit['body'] == true ? 'P0' : '',
    title: 'authenticated EXECUTE batata_credit_wallet_once',
    invariant: 'mint wallet não é JWT',
    evidence: {'status': credit['status'], 'raw': snippet(credit['raw'])},
  );

  final ensureOther = await rpc(buyerJwt, 'batata_ensure_wallet', {
    'p_user_id': sellerId,
  });
  rec(
    id: 'C2-WL-ENSURE-OTHER',
    kind: 'CHAIN',
    title: 'ensure_wallet(p_user_id=seller) como buyer',
    evidence: {
      'status': ensureOther['status'],
      'raw': snippet(ensureOther['raw']),
    },
  );

  final ibanOther = await rest(
    buyerJwt,
    'GET',
    'profiles?id=eq.$sellerId&select=id,iban,mb_way',
  );
  final ibanRows = asList(ibanOther['body']);
  rec(
    id: 'C2-PII-IBAN-OTHER',
    kind: ibanRows.isNotEmpty &&
            (asMap(ibanRows.first)?['iban'] != null ||
                asMap(ibanRows.first)?['mb_way'] != null)
        ? 'FINDING'
        : (okish(ibanOther) ? 'INFO' : 'BLOCKED'),
    severity: ibanRows.isNotEmpty &&
            (asMap(ibanRows.first)?['iban'] != null ||
                asMap(ibanRows.first)?['mb_way'] != null)
        ? 'P1'
        : '',
    title: 'buyer SELECT iban/mb_way do seller via profiles',
    invariant: 'dados bancários não são SELECT cross-user',
    evidence: {
      'status': ibanOther['status'],
      'range': ibanOther['range'],
      'rows': ibanRows,
    },
  );

  final prodPatch = await rest(
    buyerJwt,
    'PATCH',
    'products?id=eq.7fde1403-5a3c-47cd-8fe6-dab6ad863016',
    {'quantity': 999, 'price': 0.01},
  );
  rec(
    id: 'C2-PR-PATCH-QTY',
    kind: okish(prodPatch) ? 'FINDING' : 'BLOCKED',
    severity: okish(prodPatch) ? 'P1' : '',
    title: 'buyer PATCH quantity/price produto do seller',
    invariant: 'catálogo só o dono escreve',
    evidence: {'status': prodPatch['status'], 'raw': snippet(prodPatch['raw'])},
  );

  final findEmail = await rpc(buyerJwt, 'batata_find_user_id_by_email', {
    'p_email': envSellerEmailFallback(),
  });
  rec(
    id: 'C2-STAFF-EMAIL',
    kind: okish(findEmail) && '${findEmail['body']}'.contains('-')
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(findEmail) && '${findEmail['body']}'.contains('-')
        ? 'P2'
        : '',
    title: 'buyer enumera user_id por email',
    evidence: {'status': findEmail['status'], 'raw': snippet(findEmail['raw'])},
  );

  final payoutOther = await rpc(
    buyerJwt,
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
  );
  rec(
    id: 'C2-BANK-RPC',
    kind: 'CHAIN',
    title: 'buyer chama seller_direct_payment_details(seller)',
    invariant: 'oráculo bancário só com relação comercial activa',
    evidence: {
      'status': payoutOther['status'],
      'raw': snippet(payoutOther['raw'], 800),
    },
  );
  final bodyBank = payoutOther['body'];
  if (okish(payoutOther) &&
      bodyBank is List &&
      bodyBank.isNotEmpty) {
    rec(
      id: 'C2-BANK-RPC-HIT',
      kind: 'FINDING',
      severity: 'P2',
      title: 'oráculo bancário devolveu linhas ao buyer',
      invariant: 'IBAN/MB WAY não são dump sem encomenda activa',
      evidence: {'body': bodyBank},
    );
  }

  final myPayoutAsBuyer = await rpc(buyerJwt, 'batata_get_my_payout_details');
  rec(
    id: 'C2-BANK-MY',
    kind: 'INFO',
    title: 'get_my_payout_details como buyer',
    evidence: {
      'status': myPayoutAsBuyer['status'],
      'raw': snippet(myPayoutAsBuyer['raw']),
    },
  );

  final adminList = await rpc(buyerJwt, 'batata_admin_list_profiles', {
    'p_limit': 5,
  });
  rec(
    id: 'C2-ADMIN-LIST',
    kind: okish(adminList) && asList(adminList['body']).isNotEmpty
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(adminList) && asList(adminList['body']).isNotEmpty
        ? 'P1'
        : '',
    title: 'buyer admin_list_profiles',
    evidence: {'status': adminList['status'], 'raw': snippet(adminList['raw'])},
  );
}

String envSellerEmailFallback() => 'axinoquaa@axinoquaa.pt';

Future<String?> _insertOrder({
  required String jwt,
  required String asBuyer,
  required String productId,
  String? asSeller,
  String status = 'reserva_pendente',
  String paymentMethod = 'Seguro Fleaber',
  num price = 5,
  int qty = 1,
  String? liveId,
  String? liveItemId,
  int? amountPaidCents,
  String? contractNote,
}) async {
  final payload = <String, dynamic>{
    'product_id': productId,
    'buyer_id': asBuyer,
    'seller_id': asSeller ?? sellerId,
    'price_total': price,
    'shipping_method': 'Entrega em mão (€0.00)',
    'payment_method': paymentMethod,
    'status': status,
    'is_reservation': status != 'pago',
    'quantity': qty,
  };
  if (liveId != null) payload['live_id'] = liveId;
  if (liveItemId != null) payload['live_item_id'] = liveItemId;
  if (amountPaidCents != null) payload['amount_paid_cents'] = amountPaidCents;
  final r = await rest(jwt, 'POST', 'orders', payload);
  rec(
    id: 'C2-ORD-INS-${status}_${paymentMethod.hashCode.abs() % 99}_$qty',
    kind: 'CHAIN',
    title:
        'INSERT order status=$status pm=$paymentMethod qty=$qty as=${asBuyer == buyerId ? 'buyer' : 'other'}',
    evidence: {
      'status': r['status'],
      'raw': snippet(r['raw']),
      'note': contractNote,
    },
  );
  final rows = asList(r['body']);
  if (okish(r) && rows.isNotEmpty) {
    return asMap(rows.first)?['id']?.toString();
  }
  return null;
}

Future<void> _orderStateMachine() async {
  coverage.add('order FSM insert/patch/skip/repeat');
  const prod = '7fde1403-5a3c-47cd-8fe6-dab6ad863016'; // V0 product qty 6

  final paidIns = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: prod,
    status: 'pago',
    price: 5,
  );
  rec(
    id: 'C2-FSM-INS-PAGO',
    kind: paidIns != null ? 'FINDING' : 'BLOCKED',
    severity: paidIns != null ? 'P1' : '',
    title: 'buyer INSERT order já em pago',
    invariant: 'criação não fabrica estado liquidado',
    evidence: {'order_id': paidIns},
  );

  final conclIns = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: prod,
    status: 'concluido',
    paymentMethod: 'MB WAY',
  );
  rec(
    id: 'C2-FSM-INS-CONCLUIDO',
    kind: conclIns != null ? 'FINDING' : 'BLOCKED',
    severity: conclIns != null ? 'P1' : '',
    title: 'buyer INSERT order concluido',
    evidence: {'order_id': conclIns},
  );

  final otherBuyer = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: extraId.isNotEmpty ? extraId : sellerId,
    productId: prod,
    status: 'reserva_pendente',
  );
  rec(
    id: 'C2-FSM-INS-OTHER-BUYER',
    kind: otherBuyer != null ? 'FINDING' : 'BLOCKED',
    severity: otherBuyer != null ? 'P1' : '',
    title: 'buyer INSERT order com buyer_id de outra identidade',
    invariant: 'buyer_id = auth.uid()',
    evidence: {'order_id': otherBuyer, 'claimed_buyer': extraId},
  );

  final oid = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: prod,
    status: 'reserva_pendente',
    price: 1.23,
    qty: 1,
  );
  if (oid == null) return;

  Future<void> tryPatch(String label, Map<String, dynamic> data) async {
    final r = await rest(buyerJwt, 'PATCH', 'orders?id=eq.$oid', data);
    final hit = okish(r) && asList(r['body']).isNotEmpty;
    rec(
      id: 'C2-FSM-PATCH-$label',
      kind: hit ? 'FINDING' : 'BLOCKED',
      severity: hit &&
              (label.contains('PAGO') ||
                  label.contains('CONCLUIDO') ||
                  label.contains('DEVOLVIDA') ||
                  label.contains('AMOUNT') ||
                  label.contains('CONTRACT'))
          ? (label.contains('AMOUNT') || label.contains('PAGO') ? 'P0' : 'P1')
          : (hit ? 'P2' : ''),
      title: 'buyer PATCH $label',
      invariant: 'JWT não salta FSM nem fabrica captura',
      evidence: {
        'status': r['status'],
        'raw': snippet(r['raw']),
        'patch': data,
        'order': oid,
      },
    );
  }

  await tryPatch('PAGO', {'status': 'pago'});
  await tryPatch('CONCLUIDO', {'status': 'concluido'});
  await tryPatch('DEVOLVIDA', {'status': 'devolvida'});
  await tryPatch('ENTREGUE', {'status': 'entregue'});
  await tryPatch('AMOUNT', {'amount_paid_cents': 1});
  await tryPatch('CONTRACT_UNIT', {'contract_unit_cents': 1});
  await tryPatch('QTY99', {'quantity': 99});
  await tryPatch('PRICE', {'price_total': 0.5});
  await tryPatch('PI', {'stripe_payment_intent_id': 'pi_c2_fake'});

  // Seller PATCH Stripe unpaid → pago
  final sellerPago = await rest(
    sellerJwt,
    'PATCH',
    'orders?id=eq.$oid',
    {'status': 'pago'},
  );
  rec(
    id: 'C2-FSM-SELLER-PAGO-STRIPE',
    kind: okish(sellerPago) && asList(sellerPago['body']).isNotEmpty
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(sellerPago) && asList(sellerPago['body']).isNotEmpty
        ? 'P1'
        : '',
    title: 'seller PATCH Seguro Fleaber unpaid → pago',
    invariant: 'plataforma: só captura Stripe liquida',
    evidence: {
      'status': sellerPago['status'],
      'raw': snippet(sellerPago['raw']),
    },
  );

  final mbOid = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: prod,
    status: 'reserva_pendente',
    paymentMethod: 'MB WAY',
    price: 5,
  );
  if (mbOid != null) {
    final sellerMb = await rest(
      sellerJwt,
      'PATCH',
      'orders?id=eq.$mbOid',
      {'status': 'pago'},
    );
    rec(
      id: 'C2-FSM-SELLER-PAGO-MBWAY',
      kind: 'INFO',
      title: 'seller PATCH MB WAY → pago (caminho legítimo?)',
      evidence: {
        'status': sellerMb['status'],
        'raw': snippet(sellerMb['raw']),
        'order': mbOid,
      },
    );

    // After possible pago, buyer tries concluido then wallet release
    final toConcl = await rest(
      buyerJwt,
      'PATCH',
      'orders?id=eq.$mbOid',
      {'status': 'concluido'},
    );
    rec(
      id: 'C2-FSM-BUYER-CONCLUIDO-AFTER-MB',
      kind: okish(toConcl) && asList(toConcl['body']).isNotEmpty
          ? 'FINDING'
          : 'BLOCKED',
      severity: okish(toConcl) && asList(toConcl['body']).isNotEmpty
          ? 'P1'
          : '',
      title: 'buyer PATCH concluido após (possível) MB WAY pago',
      evidence: {
        'status': toConcl['status'],
        'raw': snippet(toConcl['raw']),
      },
    );
  }

  // Repeat terminal
  final paidList = await rest(
    buyerJwt,
    'GET',
    'orders?status=eq.pago&select=id,status,payment_method,amount_paid_cents&limit=1',
  );
  final paidRow = asList(paidList['body']);
  if (paidRow.isNotEmpty) {
    final pid = asMap(paidRow.first)!['id'];
    final back = await rest(
      buyerJwt,
      'PATCH',
      'orders?id=eq.$pid',
      {'status': 'reserva_pendente'},
    );
    rec(
      id: 'C2-FSM-BACK-TO-UNPAID',
      kind: okish(back) && asList(back['body']).isNotEmpty
          ? 'FINDING'
          : 'BLOCKED',
      severity: okish(back) && asList(back['body']).isNotEmpty ? 'P1' : '',
      title: 'buyer reabre order paga → reserva_pendente',
      invariant: 'estados terminais/liquidados não regridem',
      evidence: {'status': back['status'], 'raw': snippet(back['raw']), 'order': pid},
    );

    final toDev = await rest(
      buyerJwt,
      'PATCH',
      'orders?id=eq.$pid',
      {'status': 'devolvida'},
    );
    rec(
      id: 'C2-FSM-PAGO-TO-DEVOLVIDA',
      kind: okish(toDev) && asList(toDev['body']).isNotEmpty
          ? 'FINDING'
          : 'BLOCKED',
      severity: okish(toDev) && asList(toDev['body']).isNotEmpty ? 'P1' : '',
      title: 'buyer PATCH pago → devolvida',
      evidence: {'status': toDev['status'], 'raw': snippet(toDev['raw'])},
    );
  }
}

Future<void> _crossObjectMix() async {
  coverage.add('cross-object order/product/live/raffle/reservation');
  const prodA = '7fde1403-5a3c-47cd-8fe6-dab6ad863016';
  const prodB = '7c468319-a043-43bf-b7c9-f6aaea7c286e';

  // Product of another seller from lives
  final otherProds = await rest(
    buyerJwt,
    'GET',
    'products?seller_id=neq.$sellerId&select=id,seller_id,title,price,quantity&limit=3',
  );
  rec(
    id: 'C2-X-OTHER-PRODUCTS',
    kind: 'INFO',
    title: 'produtos de outros sellers visíveis',
    evidence: {
      'status': otherProds['status'],
      'raw': snippet(otherProds['raw'], 600),
    },
  );
  final op = asList(otherProds['body']);
  if (op.isNotEmpty) {
    final p = asMap(op.first)!;
    final mix = await _insertOrder(
      jwt: buyerJwt,
      asBuyer: buyerId,
      productId: '${p['id']}',
      asSeller: sellerId, // claim our seller owns someone else's product
      status: 'reserva_pendente',
      price: 5,
    );
    rec(
      id: 'C2-X-PRODUCT-SELLER-MISMATCH',
      kind: mix != null ? 'FINDING' : 'BLOCKED',
      severity: mix != null ? 'P1' : '',
      title: 'order.product de seller X + order.seller_id do nosso seller',
      invariant: 'servidor confirma RELAÇÃO product.seller_id = order.seller_id',
      evidence: {
        'order_id': mix,
        'product_seller': p['seller_id'],
        'claimed_seller': sellerId,
        'product': p['id'],
      },
    );
  }

  final lives = await rest(
    buyerJwt,
    'GET',
    'live_items?select=id,live_id,seller_id,product_id,price,status&limit=8',
  );
  rec(
    id: 'C2-X-LIVE-ITEMS',
    kind: 'INFO',
    title: 'live_items visíveis',
    evidence: {'status': lives['status'], 'raw': snippet(lives['raw'], 500)},
  );
  final items = asList(lives['body']);
  if (items.length >= 2) {
    final a = asMap(items[0])!;
    final b = asMap(items[1])!;
    final mixed = await _insertOrder(
      jwt: buyerJwt,
      asBuyer: buyerId,
      productId: prodA,
      liveId: '${a['live_id']}',
      liveItemId: '${b['id']}',
      status: 'reserva_pendente',
    );
    rec(
      id: 'C2-X-LIVE-ITEM-FROM-OTHER-LIVE',
      kind: mixed != null ? 'FINDING' : 'BLOCKED',
      severity: mixed != null ? 'P2' : '',
      title: 'order.live_id A + live_item_id de live B',
      invariant: 'live_item pertence à live da order',
      evidence: {
        'order_id': mixed,
        'live_a': a['live_id'],
        'item_b': b['id'],
        'item_b_live': b['live_id'],
      },
    );
  }

  final oid = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: prodA,
  );
  if (oid != null) {
    final checkoutWrongProduct = await edge(
      buyerJwt,
      'create-payment-intent',
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'product_id': prodB,
        'seller_id': sellerId,
        'amount': 50,
        'shipping_method': 'hand',
      },
    );
    rec(
      id: 'C2-X-CHECKOUT-WRONG-PRODUCT',
      kind: okish(checkoutWrongProduct) ? 'FINDING' : 'BLOCKED',
      severity: okish(checkoutWrongProduct) ? 'P1' : '',
      title: 'checkout order A + product_id B',
      evidence: {
        'status': checkoutWrongProduct['status'],
        'raw': snippet(checkoutWrongProduct['raw']),
      },
    );

    final checkoutLow = await edge(
      buyerJwt,
      'create-payment-intent',
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'amount': 50,
        'shipping_method': 'hand',
      },
    );
    rec(
      id: 'C2-X-CHECKOUT-CLIENT-AMOUNT',
      kind: 'CHAIN',
      title: 'checkout amount cliente 50 cêntimos vs contrato',
      evidence: {
        'status': checkoutLow['status'],
        'raw': snippet(checkoutLow['raw'], 700),
      },
    );
    final q = asMap(checkoutLow['body']);
    if (okish(checkoutLow) && q != null) {
      final serverAmt = q['server_amount_cents'];
      rec(
        id: 'C2-X-CHECKOUT-AMOUNT-AUTH',
        kind: (serverAmt is num && serverAmt <= 50) ? 'FINDING' : 'INFO',
        severity: (serverAmt is num && serverAmt <= 50) ? 'P0' : '',
        title: 'quote servidor vs amount cliente',
        evidence: q,
      );
    }

    final prize = await edge(
      buyerJwt,
      'create-payment-intent',
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'prize_shipping': true,
        'shipping_method': 'carrier',
      },
    );
    rec(
      id: 'C2-X-PRIZE-ON-NORMAL',
      kind: okish(prize) ? 'FINDING' : 'BLOCKED',
      severity: okish(prize) ? 'P0' : '',
      title: 'prize_shipping em order que não é prémio',
      invariant: 'portes-only só com winner autoritativo',
      evidence: {'status': prize['status'], 'raw': snippet(prize['raw'])},
    );

    // Extra buyer tenta pagar order do buyer
    if (extraJwt.isNotEmpty) {
      final steal = await edge(
        extraJwt,
        'create-payment-intent',
        body: {
          'buyer_id': extraId,
          'order_id': oid,
          'shipping_method': 'hand',
        },
      );
      rec(
        id: 'C2-X-CHECKOUT-FOREIGN-ORDER',
        kind: okish(steal) ? 'FINDING' : 'BLOCKED',
        severity: okish(steal) ? 'P1' : '',
        title: 'extra buyer checkout da order do buyer A',
        evidence: {'status': steal['status'], 'raw': snippet(steal['raw'])},
      );

      final stealClaim = await edge(
        extraJwt,
        'create-payment-intent',
        body: {
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'hand',
        },
      );
      rec(
        id: 'C2-X-CHECKOUT-JWT-NE-BODY-BUYER',
        kind: okish(stealClaim) ? 'FINDING' : 'BLOCKED',
        severity: okish(stealClaim) ? 'P1' : '',
        title: 'JWT extra + body.buyer_id do dono da order',
        evidence: {
          'status': stealClaim['status'],
          'raw': snippet(stealClaim['raw']),
        },
      );
    }
  }

  // Bag mix two products same seller (ok) vs if we find another seller order
  final bagMix = await edge(
    buyerJwt,
    'create-payment-intent',
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'bag_checkout': true,
      'shipping_method': 'carrier',
      'bag_lines': [
        {'order_id': oid},
        {
          'order_id': oid,
          'seller_id': '00000000-0000-0000-0000-000000000099',
        },
      ],
    },
  );
  rec(
    id: 'C2-X-BAG-FAKE-SELLER-LINE',
    kind: okish(bagMix) ? 'FINDING' : 'BLOCKED',
    title: 'bag line com seller_id inventado',
    evidence: {'status': bagMix['status'], 'raw': snippet(bagMix['raw'])},
  );
}

Future<void> _financialRpcs() async {
  coverage.add('wallet refund/release/dispute/tip');
  final paid = await rest(
    buyerJwt,
    'GET',
    'orders?status=in.(pago,enviado,concluido,devolvida)&select=id,status,price_total,amount_paid_cents,seller_id,buyer_id&limit=5',
  );
  final rows = asList(paid['body']);
  rec(
    id: 'C2-FIN-PAID-SAMPLE',
    kind: 'INFO',
    title: 'orders liquidáveis visíveis ao buyer',
    evidence: {'n': rows.length, 'sample': rows.take(3).toList()},
  );

  for (final raw in rows.take(3)) {
    final m = asMap(raw)!;
    final id = m['id'];
    final rel = await rpc(buyerJwt, 'batata_release_seller_wallet_for_order', {
      'p_order_id': id,
    });
    rec(
      id: 'C2-FIN-RELEASE-$id',
      kind: rel['body'] == true ? 'FINDING' : 'BLOCKED',
      severity: rel['body'] == true && m['status'] != 'concluido' ? 'P0' : '',
      title: 'buyer release_seller_wallet order ${m['status']}',
      evidence: {
        'order': m,
        'rpc_status': rel['status'],
        'rpc_body': rel['body'],
        'raw': snippet(rel['raw']),
      },
    );
    final ref = await rpc(buyerJwt, 'batata_refund_buyer_wallet_for_order', {
      'p_order_id': id,
    });
    rec(
      id: 'C2-FIN-REFUND-WL-$id',
      kind: ref['body'] == true ? 'FINDING' : 'BLOCKED',
      severity: ref['body'] == true && m['status'] != 'devolvida' ? 'P0' : '',
      title: 'buyer refund_buyer_wallet order ${m['status']}',
      evidence: {
        'order': m,
        'rpc_status': ref['status'],
        'rpc_body': ref['body'],
        'raw': snippet(ref['raw']),
      },
    );
    final disp = await rpc(buyerJwt, 'batata_process_partial_refund_dispute', {
      'p_order_id': id,
      'p_refund_percent': 100,
    });
    rec(
      id: 'C2-FIN-DISPUTE-100-$id',
      kind: okish(disp) && disp['body'] != null && disp['body'] != false
          ? 'FINDING'
          : 'BLOCKED',
      severity: okish(disp) && disp['body'] == true ? 'P0' : '',
      title: 'buyer process_partial_refund 100% sem disputa seller',
      evidence: {
        'order': id,
        'status': disp['status'],
        'raw': snippet(disp['raw']),
      },
    );
  }

  // Seller tries refund wallet on unpaid
  final pending = await rest(
    sellerJwt,
    'GET',
    'orders?status=eq.reserva_pendente&select=id,status&limit=1',
  );
  final pend = asList(pending['body']);
  if (pend.isNotEmpty) {
    final id = asMap(pend.first)!['id'];
    final ref = await rpc(sellerJwt, 'batata_refund_buyer_wallet_for_order', {
      'p_order_id': id,
    });
    rec(
      id: 'C2-FIN-SELLER-REFUND-UNPAID',
      kind: ref['body'] == true ? 'FINDING' : 'BLOCKED',
      severity: ref['body'] == true ? 'P0' : '',
      title: 'seller refund_wallet em reserva_pendente',
      evidence: {'status': ref['status'], 'body': ref['body'], 'raw': snippet(ref['raw'])},
    );
  }

  final tip = await rpc(buyerJwt, 'batata_send_live_tip_from_wallet', {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
    'p_seller_id': sellerId,
    'p_amount': 1,
    'p_message': 'c2',
  });
  rec(
    id: 'C2-FIN-TIP-FAKE-LIVE',
    kind: okish(tip) && tip['body'] != null && '${tip['body']}'.isNotEmpty
        ? 'FINDING'
        : 'BLOCKED',
    title: 'tip wallet para live_id inexistente',
    evidence: {'status': tip['status'], 'raw': snippet(tip['raw'])},
  );

  final settleTip = await rpc(buyerJwt, 'batata_settle_live_tip_from_stripe', {
    'p_tip_id': '00000000-0000-0000-0000-000000000001',
    'p_stripe_session_id': 'cs_test_c2',
    'p_paid_amount_cents': 100,
  });
  rec(
    id: 'C2-FIN-SETTLE-TIP-JWT',
    kind: settleTip['body'] == true ? 'FINDING' : 'BLOCKED',
    severity: settleTip['body'] == true ? 'P0' : '',
    title: 'buyer chama settle_live_tip_from_stripe',
    invariant: 'settle Stripe não é JWT',
    evidence: {
      'status': settleTip['status'],
      'raw': snippet(settleTip['raw']),
    },
  );
}

Future<void> _edgeFunctions() async {
  coverage.add('edge: payment, refund, webhook, connect, mux, e2e, sms, delete');

  final e2e = await edge(
    buyerJwt,
    'create-payment-intent?fase2_e2e_settle=1',
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_c2',
    },
  );
  rec(
    id: 'C2-EDGE-E2E-SETTLE',
    kind: okish(e2e) ? 'FINDING' : 'BLOCKED',
    severity: okish(e2e) ? 'P0' : '',
    title: 'fase2_e2e_settle com JWT buyer',
    evidence: {'status': e2e['status'], 'raw': snippet(e2e['raw'])},
  );

  final wh = await edge(
    buyerJwt,
    'stripe-webhook',
    body: {'type': 'checkout.session.completed', 'data': {}},
  );
  rec(
    id: 'C2-EDGE-WEBHOOK-NOSIG',
    kind: okish(wh) ? 'FINDING' : 'BLOCKED',
    severity: okish(wh) ? 'P0' : '',
    title: 'stripe-webhook sem assinatura',
    evidence: {'status': wh['status'], 'raw': snippet(wh['raw'])},
  );

  final refundAsBuyer = await edge(
    buyerJwt,
    'refund-order',
    body: {
      'order_id': (await rest(
            buyerJwt,
            'GET',
            'orders?status=eq.pago&select=id&limit=1',
          ))
              .let(),
    },
  );
  rec(
    id: 'C2-EDGE-REFUND-BUYER',
    kind: okish(refundAsBuyer) && asMap(refundAsBuyer['body'])?['ok'] == true
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(refundAsBuyer) && asMap(refundAsBuyer['body'])?['ok'] == true
        ? 'P0'
        : '',
    title: 'refund-order como buyer',
    invariant: 'refund Stripe seller-only',
    evidence: {
      'status': refundAsBuyer['status'],
      'raw': snippet(refundAsBuyer['raw']),
    },
  );

  final connectOther = await edge(
    buyerJwt,
    'create-connect-account',
    body: {'user_id': sellerId, 'amount': 100},
  );
  rec(
    id: 'C2-EDGE-PAYOUT-OTHER-USER',
    kind: okish(connectOther) &&
            asMap(connectOther['body'])?['success'] == true
        ? 'FINDING'
        : 'BLOCKED',
    severity: okish(connectOther) &&
            asMap(connectOther['body'])?['success'] == true
        ? 'P0'
        : '',
    title: 'payout/connect com user_id do seller usando JWT buyer',
    evidence: {
      'status': connectOther['status'],
      'raw': snippet(connectOther['raw']),
    },
  );

  final mux = await edge(
    buyerJwt,
    'create-mux-live',
    body: {'title': 'c2'},
  );
  rec(
    id: 'C2-EDGE-MUX-BUYER',
    kind: 'INFO',
    title: 'create-mux-live como buyer',
    evidence: {'status': mux['status'], 'raw': snippet(mux['raw'])},
  );

  final del = await edge(
    extraJwt.isNotEmpty ? extraJwt : buyerJwt,
    'delete-test-account',
    body: {},
  );
  rec(
    id: 'C2-EDGE-DELETE-ACCOUNT',
    kind: 'INFO',
    title: 'delete-test-account (staging helper)',
    evidence: {'status': del['status'], 'raw': snippet(del['raw'])},
  );

  final sms = await edge(
    buyerJwt,
    'send-sms-bulkgate',
    body: {'to': '+351910000000', 'text': 'c2'},
  );
  rec(
    id: 'C2-EDGE-SMS',
    kind: okish(sms) ? 'FINDING' : 'BLOCKED',
    severity: okish(sms) ? 'P2' : '',
    title: 'send-sms-bulkgate como buyer',
    evidence: {'status': sms['status'], 'raw': snippet(sms['raw'])},
  );

  final oversell = await edge(
    buyerJwt,
    'sec-fase2-e2e-oversell',
    body: {},
  );
  rec(
    id: 'C2-EDGE-OVERSELL-FN',
    kind: okish(oversell) ? 'FINDING' : 'BLOCKED',
    severity: okish(oversell) ? 'P1' : '',
    title: 'sec-fase2-e2e-oversell JWT buyer',
    evidence: {'status': oversell['status'], 'raw': snippet(oversell['raw'])},
  );

  // Replay GET settle with leaked session if any
  final ev = await rest(
    buyerJwt,
    'GET',
    'stripe_checkout_events?session_id=not.is.null&select=session_id,order_id,buyer_id,event&order=created_at.desc&limit=15',
  );
  final sessions = asList(ev['body'])
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .where((e) => '${e['session_id']}'.startsWith('cs_'))
      .toList();
  if (sessions.isNotEmpty) {
    final ses = sessions.first;
    final sid = ses['session_id'];
    final settle = await edge(
      anon,
      'create-payment-intent?checkout_return=success&session_id=$sid',
      method: 'GET',
    );
    rec(
      id: 'C2-EDGE-SETTLE-GET-REPLAY',
      kind: 'CHAIN',
      title: 'GET settle session_id (anon) replay',
      evidence: {
        'session': ses,
        'http': settle['status'],
        'raw': snippet(settle['raw'], 500),
      },
    );
  }

  final tipFake = await edge(
    buyerJwt,
    'create-live-tip-checkout',
    body: {
      'seller_id': sellerId,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000099',
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  rec(
    id: 'C2-EDGE-TIP-CLIENT-ID',
    kind: okish(tipFake) ? 'FINDING' : 'BLOCKED',
    title: 'tip checkout com tip_id cliente + live inexistente',
    evidence: {'status': tipFake['status'], 'raw': snippet(tipFake['raw'])},
  );
}

Future<void> _storageAndPii() async {
  coverage.add('storage chat_media / product images / profiles phone');
  Future<Map<String, dynamic>> storage(
    String jwt,
    String method,
    String path, {
    List<int>? bytes,
    String? contentType,
  }) async {
    final uri = Uri.parse('$base/storage/v1/$path');
    final r = await httpClient.openUrl(method, uri);
    r.headers.set('apikey', anon);
    r.headers.set('Authorization', 'Bearer $jwt');
    if (bytes != null) {
      r.headers.set('Content-Type', contentType ?? 'text/plain');
      r.add(bytes);
    }
    final resp = await r.close().timeout(const Duration(seconds: 30));
    final txt = await utf8.decodeStream(resp);
    return {'status': resp.statusCode, 'raw': snippet(txt, 500)};
  }

  final list = await storage(
    buyerJwt,
    'GET',
    'object/list/chat_media',
  );
  rec(
    id: 'C2-ST-LIST-CHAT',
    kind: 'INFO',
    title: 'list chat_media',
    evidence: list,
  );

  final uploadOther = await storage(
    buyerJwt,
    'POST',
    'object/chat_media/chat_uploads/$sellerId/c2_blind.txt',
    bytes: utf8.encode('c2-cross-user-upload'),
  );
  rec(
    id: 'C2-ST-UPLOAD-OTHER-PREFIX',
    kind: (uploadOther['status'] as int) < 300 ? 'FINDING' : 'BLOCKED',
    severity: (uploadOther['status'] as int) < 300 ? 'P2' : '',
    title: 'buyer upload path chat_uploads/{sellerId}/',
    invariant: 'storage path amarra-se a auth.uid()',
    evidence: uploadOther,
  );

  final readOther = await storage(
    extraJwt.isNotEmpty ? extraJwt : buyerJwt,
    'GET',
    'object/chat_media/chat_uploads/$sellerId/c2_blind.txt',
  );
  rec(
    id: 'C2-ST-READ-CROSS',
    kind: (readOther['status'] as int) == 200 ? 'FINDING' : 'BLOCKED',
    severity: (readOther['status'] as int) == 200 ? 'P2' : '',
    title: 'leitura storage path de outro user',
    evidence: readOther,
  );

  final phone = await rest(
    buyerJwt,
    'GET',
    'profiles?id=eq.$sellerId&select=id,phone,legal_full_name,shipping_address',
  );
  rec(
    id: 'C2-PII-PHONE',
    kind: 'INFO',
    title: 'profiles PII columns seller as buyer',
    evidence: {'status': phone['status'], 'raw': snippet(phone['raw'])},
  );
}

Future<void> _liveRaffleReservations() async {
  coverage.add('raffle join/draw/winner insert; reservations convert');
  final raffles = await rest(
    buyerJwt,
    'GET',
    'live_raffles?status=eq.active&select=id,live_id,status,seller_id&limit=3',
  );
  rec(
    id: 'C2-RF-LIST',
    kind: 'INFO',
    title: 'rifas activas',
    evidence: {'status': raffles['status'], 'raw': snippet(raffles['raw'], 500)},
  );
  final rf = asList(raffles['body']);
  if (rf.isNotEmpty) {
    final id = asMap(rf.first)!['id'];
    final join = await rpc(buyerJwt, 'batata_join_live_raffle', {
      'p_raffle_id': id,
    });
    rec(
      id: 'C2-RF-JOIN',
      kind: 'CHAIN',
      title: 'join raffle activa',
      evidence: {'status': join['status'], 'raw': snippet(join['raw'])},
    );
    final draw = await rpc(buyerJwt, 'batata_draw_live_raffle_winners', {
      'p_raffle_id': id,
    });
    rec(
      id: 'C2-RF-DRAW-AS-BUYER',
      kind: okish(draw) && draw['body'] != null ? 'FINDING' : 'BLOCKED',
      severity: okish(draw) && asList(draw['body']).isNotEmpty ? 'P1' : '',
      title: 'buyer dispara draw da rifa',
      invariant: 'sorteio só seller/director da live',
      evidence: {'status': draw['status'], 'raw': snippet(draw['raw'])},
    );
  }

  final insWin = await rest(buyerJwt, 'POST', 'live_raffle_winners', {
    'raffle_id': rf.isNotEmpty
        ? asMap(rf.first)!['id']
        : '00000000-0000-0000-0000-000000000001',
    'user_id': buyerId,
    'rank': 1,
    'tickets_at_draw': 1,
  });
  rec(
    id: 'C2-RF-INSERT-WINNER',
    kind: okish(insWin) ? 'FINDING' : 'BLOCKED',
    severity: okish(insWin) ? 'P1' : '',
    title: 'buyer INSERT live_raffle_winners',
    evidence: {'status': insWin['status'], 'raw': snippet(insWin['raw'])},
  );

  final reqs = await rest(
    buyerJwt,
    'GET',
    'live_reservation_requests?select=id,buyer_id,seller_id,status,live_id,live_item_id,requested_qty&limit=8',
  );
  rec(
    id: 'C2-RES-LIST',
    kind: 'INFO',
    title: 'reservas visíveis ao buyer',
    evidence: {'status': reqs['status'], 'raw': snippet(reqs['raw'], 600)},
  );
  final reqList = asList(reqs['body']);
  final foreignReq = reqList
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .where((e) => '${e['buyer_id']}' != buyerId)
      .toList();
  if (foreignReq.isNotEmpty) {
    rec(
      id: 'C2-RES-FOREIGN-SELECT',
      kind: 'FINDING',
      severity: 'P2',
      title: 'buyer lê reservas de outros compradores',
      evidence: {'n': foreignReq.length, 'sample': foreignReq.take(2).toList()},
    );
    final fr = foreignReq.first;
    final conv = await rpc(buyerJwt, 'batata_live_reservation_stripe_convert', {
      'p_request_id': fr['id'],
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    });
    rec(
      id: 'C2-RES-CONVERT-FOREIGN',
      kind: okish(conv) && asMap(conv['body'])?['ok'] == true
          ? 'FINDING'
          : 'BLOCKED',
      severity: okish(conv) && asMap(conv['body'])?['ok'] == true ? 'P1' : '',
      title: 'convert reserva de outro buyer',
      evidence: {'status': conv['status'], 'raw': snippet(conv['raw'])},
    );
  }

  final accept = await rpc(buyerJwt, 'batata_process_live_reservation_request', {
    'p_request_id': reqList.isNotEmpty
        ? asMap(reqList.first)!['id']
        : '00000000-0000-0000-0000-000000000001',
    'p_action': 'accepted',
  });
  rec(
    id: 'C2-RES-ACCEPT-AS-BUYER',
    kind: okish(accept) && asMap(accept['body'])?['ok'] == true
        ? 'FINDING'
        : 'BLOCKED',
    title: 'buyer process reservation (acção seller)',
    evidence: {'status': accept['status'], 'raw': snippet(accept['raw'])},
  );

  final qtyPatch = await rest(
    extraJwt.isNotEmpty ? extraJwt : buyerJwt,
    'POST',
    'live_reservation_requests',
    {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'live_item_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'buyer_id': extraId.isNotEmpty ? extraId : buyerId,
      'requested_qty': 99,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  rec(
    id: 'C2-RES-INSERT-ACCEPTED-Q99',
    kind: okish(qtyPatch) ? 'FINDING' : 'BLOCKED',
    severity: okish(qtyPatch) ? 'P1' : '',
    title: 'INSERT reserva já accepted qty 99',
    evidence: {'status': qtyPatch['status'], 'raw': snippet(qtyPatch['raw'])},
  );
}

Future<void> _races() async {
  coverage.add('races: last unit, wallet, refund, patch, checkout, payout');
  // Seller sets a dedicated qty=1 product
  final createProd = await rest(sellerJwt, 'POST', 'products', {
    'title': 'C2 RACE LAST UNIT ${DateTime.now().millisecondsSinceEpoch}',
    'price': 5,
    'quantity': 1,
    'seller_id': sellerId,
    'list_on_marketplace': true,
    'is_sold': false,
    'status': 'active',
  });
  rec(
    id: 'C2-RACE-MK-PRODUCT',
    kind: 'INFO',
    title: 'seller cria produto qty=1 para corrida',
    evidence: {
      'status': createProd['status'],
      'raw': snippet(createProd['raw']),
    },
  );
  String? racePid;
  final created = asList(createProd['body']);
  if (created.isNotEmpty) {
    racePid = asMap(created.first)?['id']?.toString();
  } else {
    racePid = 'd4cb123c-0176-4e5b-a476-6751ec615ac2'; // existing qty 1
  }

  // Two buyers insert MB WAY holds then seller marks both pago concurrently
  final o1 = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: racePid!,
    paymentMethod: 'MB WAY',
    status: 'reserva_pendente',
    price: 5,
  );
  String? o2;
  if (extraJwt.isNotEmpty) {
    o2 = await _insertOrder(
      jwt: extraJwt,
      asBuyer: extraId,
      productId: racePid,
      paymentMethod: 'MB WAY',
      status: 'reserva_pendente',
      price: 5,
    );
  } else {
    o2 = await _insertOrder(
      jwt: buyerJwt,
      asBuyer: buyerId,
      productId: racePid,
      paymentMethod: 'MB WAY',
      status: 'reserva_pendente',
      price: 5,
    );
  }

  if (o1 != null && o2 != null) {
    final f1 = rest(sellerJwt, 'PATCH', 'orders?id=eq.$o1', {'status': 'pago'});
    final f2 = rest(sellerJwt, 'PATCH', 'orders?id=eq.$o2', {'status': 'pago'});
    final rs = await Future.wait([f1, f2]);
    final stock = await rest(
      sellerJwt,
      'GET',
      'products?id=eq.$racePid&select=id,quantity,is_sold',
    );
    final oAfter = await rest(
      sellerJwt,
      'GET',
      'orders?id=in.($o1,$o2)&select=id,status,quantity,stock_units_applied',
    );
    rec(
      id: 'C2-RACE-LAST-UNIT-MBWAY',
      kind: 'RACE',
      title: 'seller PATCH pago simultâneo em 2 orders MB WAY qty=1',
      evidence: {
        'patch_a': {'http': rs[0]['status'], 'raw': snippet(rs[0]['raw'])},
        'patch_b': {'http': rs[1]['status'], 'raw': snippet(rs[1]['raw'])},
        'stock_after': stock['body'],
        'orders_after': oAfter['body'],
      },
    );
    final stockRows = asList(stock['body']);
    final ordersAfter = asList(oAfter['body']);
    final paidN = ordersAfter
        .where((e) => asMap(e)?['status']?.toString() == 'pago')
        .length;
    final qty = stockRows.isEmpty
        ? null
        : asMap(stockRows.first)?['quantity'];
    if (paidN >= 2 && qty is num && qty < 0) {
      rec(
        id: 'C2-RACE-LAST-UNIT-OVERSELL',
        kind: 'FINDING',
        severity: 'P1',
        title: 'corrida MB WAY: 2 pago sobre 1 unidade (qty negativa)',
        invariant: 'stock nunca negativo; 1 unidade ≤ 1 liquidação',
        evidence: {'paid_n': paidN, 'qty': qty, 'orders': ordersAfter},
      );
    } else if (paidN >= 2 && (qty == 0 || qty == 1)) {
      rec(
        id: 'C2-RACE-LAST-UNIT-DOUBLE-PAID',
        kind: 'FINDING',
        severity: 'P1',
        title: 'corrida MB WAY: duas orders pago com stock qty=$qty',
        invariant: 'última unidade não liquida duas vendas',
        evidence: {'paid_n': paidN, 'qty': qty, 'orders': ordersAfter},
      );
    }
  }

  // Concurrent wallet release
  final concl = await rest(
    buyerJwt,
    'GET',
    'orders?status=eq.concluido&select=id&limit=1',
  );
  final cRows = asList(concl['body']);
  if (cRows.isNotEmpty) {
    final cid = asMap(cRows.first)!['id'];
    final a = rpc(buyerJwt, 'batata_release_seller_wallet_for_order', {
      'p_order_id': cid,
    });
    final b = rpc(buyerJwt, 'batata_release_seller_wallet_for_order', {
      'p_order_id': cid,
    });
    final rr = await Future.wait([a, b]);
    rec(
      id: 'C2-RACE-WALLET-RELEASE',
      kind: 'RACE',
      title: 'release_seller_wallet ×2 simultâneo',
      evidence: {
        'a': {'http': rr[0]['status'], 'body': rr[0]['body']},
        'b': {'http': rr[1]['status'], 'body': rr[1]['body']},
      },
    );
  }

  // Concurrent checkout create
  final hold = await _insertOrder(
    jwt: buyerJwt,
    asBuyer: buyerId,
    productId: racePid,
    paymentMethod: 'Seguro Fleaber',
  );
  if (hold != null) {
    final c1 = edge(buyerJwt, 'create-payment-intent', body: {
      'buyer_id': buyerId,
      'order_id': hold,
      'shipping_method': 'hand',
      'amount': 999999,
    });
    final c2 = edge(buyerJwt, 'create-payment-intent', body: {
      'buyer_id': buyerId,
      'order_id': hold,
      'shipping_method': 'carrier',
      'amount': 50,
    });
    final cr = await Future.wait([c1, c2]);
    rec(
      id: 'C2-RACE-DOUBLE-CHECKOUT',
      kind: 'RACE',
      title: 'dois checkouts simultâneos mesma order (hand vs carrier)',
      evidence: {
        'a': {'http': cr[0]['status'], 'raw': snippet(cr[0]['raw'], 400)},
        'b': {'http': cr[1]['status'], 'raw': snippet(cr[1]['raw'], 400)},
      },
    );
  }

  // Concurrent refund-order as seller on same paid stripe order
  final stripePaid = await rest(
    sellerJwt,
    'GET',
    'orders?payment_method=ilike.*Seguro*&status=eq.pago&select=id,status,stripe_payment_intent_id,amount_paid_cents,stripe_refund_id&limit=3',
  );
  rec(
    id: 'C2-RACE-STRIPE-PAID-SAMPLE',
    kind: 'INFO',
    title: 'orders Seguro pago para corrida refund',
    evidence: {'raw': snippet(stripePaid['raw'], 600)},
  );
  final sp = asList(stripePaid['body'])
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .where((e) => '${e['stripe_refund_id'] ?? ''}'.isEmpty)
      .toList();
  if (sp.isNotEmpty) {
    final rid = sp.first['id'];
    final r1 = edge(sellerJwt, 'refund-order', body: {'order_id': rid});
    final r2 = edge(sellerJwt, 'refund-order', body: {'order_id': rid});
    final rr = await Future.wait([r1, r2]);
    rec(
      id: 'C2-RACE-DOUBLE-REFUND',
      kind: 'RACE',
      title: 'refund-order ×2 simultâneo mesma order',
      evidence: {
        'order': rid,
        'a': {'http': rr[0]['status'], 'raw': snippet(rr[0]['raw'], 400)},
        'b': {'http': rr[1]['status'], 'raw': snippet(rr[1]['raw'], 400)},
      },
    );
  }

  // Retry payout with slightly different keys
  if (true) {
    final k1 = 'c2_${Random().nextInt(1 << 20)}';
    final p1 = edge(sellerJwt, 'create-connect-account', body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': k1,
    });
    final p2 = edge(sellerJwt, 'create-connect-account', body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': '${k1}_b',
    });
    final pr = await Future.wait([p1, p2]);
    rec(
      id: 'C2-RACE-PAYOUT-KEYS',
      kind: 'RACE',
      title: 'payout ×2 keys ligeiramente diferentes amount=1€',
      evidence: {
        'a': {'http': pr[0]['status'], 'raw': snippet(pr[0]['raw'], 400)},
        'b': {'http': pr[1]['status'], 'raw': snippet(pr[1]['raw'], 400)},
      },
    );
  }
}

Future<void> _walletPayout() async {
  coverage.add('wallet tx insert; disputes; reviews; chats');
  final txIns = await rest(buyerJwt, 'POST', 'wallet_transactions', {
    'wallet_id': buyerId,
    'amount': 50,
    'type': 'reembolso',
    'description': 'c2 mint',
  });
  rec(
    id: 'C2-WL-TX-INSERT',
    kind: okish(txIns) ? 'FINDING' : 'BLOCKED',
    severity: okish(txIns) ? 'P0' : '',
    title: 'buyer INSERT wallet_transactions crédito',
    evidence: {'status': txIns['status'], 'raw': snippet(txIns['raw'])},
  );

  final dispIns = await rest(buyerJwt, 'POST', 'order_disputes', {
    'order_id': '00000000-0000-0000-0000-000000000001',
    'status': 'aberta',
    'seller_refund_percent': 100,
    'seller_offer_set_by': 'seller',
  });
  rec(
    id: 'C2-DISP-INSERT-FAKE',
    kind: okish(dispIns) ? 'FINDING' : 'BLOCKED',
    title: 'INSERT disputa order inexistente 100%',
    evidence: {'status': dispIns['status'], 'raw': snippet(dispIns['raw'])},
  );

  final chats = await rest(
    extraJwt.isNotEmpty ? extraJwt : buyerJwt,
    'GET',
    'chats?select=id,user_a,user_b,product_id,last_message&limit=5',
  );
  rec(
    id: 'C2-CHAT-LIST',
    kind: 'INFO',
    title: 'chats visíveis extra/buyer',
    evidence: {'status': chats['status'], 'raw': snippet(chats['raw'], 500)},
  );

  final msgs = await rest(
    extraJwt.isNotEmpty ? extraJwt : buyerJwt,
    'GET',
    'chat_messages?select=id,chat_id,sender_id,text&limit=5',
  );
  rec(
    id: 'C2-CHAT-MSGS',
    kind: 'INFO',
    title: 'chat_messages visíveis',
    evidence: {'status': msgs['status'], 'range': msgs['range'], 'raw': snippet(msgs['raw'], 400)},
  );

  final rev = await rest(buyerJwt, 'POST', 'reviews', {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'rating': 1,
    'comment': 'c2',
  });
  rec(
    id: 'C2-REV-INSERT',
    kind: 'INFO',
    title: 'INSERT review sem order',
    evidence: {'status': rev['status'], 'raw': snippet(rev['raw'])},
  );
}

Future<void> _adminStaffPs() async {
  coverage.add('staff, director, ps, kill switch, claim');
  final kill = await rpc(buyerJwt, 'batata_director_activate_kill_switch', {});
  rec(
    id: 'C2-DIR-KILL',
    kind: okish(kill) ? 'FINDING' : 'BLOCKED',
    severity: okish(kill) ? 'P1' : '',
    title: 'buyer activate director kill switch',
    evidence: {'status': kill['status'], 'raw': snippet(kill['raw'])},
  );

  final claim = await rpc(buyerJwt, 'batata_claim_external_reservations', {
    'p_email': 'axinoqua@axinoquaa.pt',
  });
  rec(
    id: 'C2-PS-CLAIM-EMAIL',
    kind: 'CHAIN',
    title: 'claim_external_reservations email próprio',
    evidence: {'status': claim['status'], 'raw': snippet(claim['raw'])},
  );

  final claimOther = await rpc(buyerJwt, 'batata_claim_external_reservations', {
    'p_email': 'axinoquaa@axinoquaa.pt',
  });
  rec(
    id: 'C2-PS-CLAIM-SELLER-EMAIL',
    kind: okish(claimOther) && asList(claimOther['body']).isNotEmpty
        ? 'FINDING'
        : 'BLOCKED',
    title: 'buyer claim reservas do email do seller',
    evidence: {
      'status': claimOther['status'],
      'raw': snippet(claimOther['raw']),
    },
  );

  final staff = await rpc(buyerJwt, 'batata_staff_has_permission', {
    'p_seller_id': sellerId,
    'p_permission': 'live_control',
  });
  rec(
    id: 'C2-STAFF-PERM',
    kind: 'INFO',
    title: 'staff_has_permission buyer vs seller',
    evidence: {'status': staff['status'], 'raw': snippet(staff['raw'])},
  );

  final helpersIns = await rest(buyerJwt, 'POST', 'seller_helpers', {
    'seller_id': sellerId,
    'helper_id': buyerId,
    'status': 'active',
    'permissions': ['live_control', 'stock'],
  });
  rec(
    id: 'C2-STAFF-SELF-INSERT',
    kind: okish(helpersIns) ? 'FINDING' : 'BLOCKED',
    severity: okish(helpersIns) ? 'P1' : '',
    title: 'buyer INSERT-se como helper activo do seller',
    evidence: {
      'status': helpersIns['status'],
      'raw': snippet(helpersIns['raw']),
    },
  );
}

extension _Let on Map<String, dynamic> {
  dynamic let() {
    final rows = asList(this['body']);
    if (rows.isEmpty) return '00000000-0000-0000-0000-000000000001';
    return asMap(rows.first)?['id'] ?? '00000000-0000-0000-0000-000000000001';
  }
}
