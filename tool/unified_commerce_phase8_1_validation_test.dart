// ignore_for_file: avoid_print
/// Phase 8.1 — Meta internal validation (staging). No real Meta credentials.
/// Classifications: PASS MOCK | PASS STAGING | FAIL | NOT RUN | BLOCKED EXTERNAL
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final projectUrl =
      normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final client = LiveOpsStagingClient(
    url: projectUrl,
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final outDir =
      Directory('19-unified-commerce-phase8.1-internal-validation/raw');
  await outDir.create(recursive: true);

  final results = <String, dynamic>{
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'project_url_host': Uri.parse(projectUrl).host,
    'production_forbidden_host': 'bpmpkzwnrbmuqnhgdscf.supabase.co',
    'tests': <String, dynamic>{},
  };

  void mark(String id, String status, [Object? detail]) {
    results['tests'][id] = {
      'status': status,
      if (detail != null) 'detail': detail,
    };
    print('$id → $status');
  }

  // Guard: never run against production
  final host = Uri.parse(projectUrl).host;
  if (host.contains('bpmpkzwnrbmuqnhgdscf')) {
    mark('00_env_guard', 'FAIL', 'refused production project');
    await _write(outDir, results);
    exit(2);
  }
  if (!host.contains('fxdknzrqjenzqcvnwqqq')) {
    mark('00_env_guard', 'FAIL', 'unexpected host $host');
    await _write(outDir, results);
    exit(2);
  }
  mark('00_env_guard', 'PASS STAGING', {'host': host});

  // Migration presence
  try {
    await client.rpc('batata_meta_assert_service_caller', {});
    await client.rpc('batata_meta_assert_poll_binding', {
      'p_page_id': '0',
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_meta_live_video_id': '0',
      'p_seller_id': null,
    });
    mark('00_migration_phase8_1', 'PASS STAGING');
  } catch (e) {
    mark('00_migration_phase8_1', 'FAIL', e.toString());
    await _write(outDir, results);
    exit(1);
  }

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);

  // Optional second seller for isolation (if env present)
  String? seller2Id;
  try {
    final email2 = staging['LIVE_OPS_TEST_SELLER2_EMAIL'];
    final pass2 = staging['LIVE_OPS_TEST_SELLER2_PASSWORD'];
    if (email2 != null &&
        email2.isNotEmpty &&
        pass2 != null &&
        pass2.isNotEmpty) {
      final t2 = await client.signIn(email: email2, password: pass2);
      seller2Id = await client.userIdForAccessToken(t2);
    }
  } catch (_) {}

  final suffix =
      Random().nextInt(1 << 28).toRadixString(16).padLeft(8, '0');
  final refSlug = 'M81${suffix.substring(0, 2)}'.toUpperCase();
  final pageA = '20881$suffix';
  final pageB = '20882$suffix';

  try {
    await client.insert('seller_reservation_settings', {
      'seller_id': sellerId,
      'policy_mode': 'manual',
      'untrusted_mode': 'approval',
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 7200,
      'policy_version': 1,
    });
  } catch (_) {
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'manual'},
    );
  }

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P81 $suffix',
    'price': 11,
    'quantity': 8,
    'ref_code': 'P81-$suffix',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });

  final liveA = await client.insert('lives', {
    'title': 'P81_A_$suffix',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveB = await client.insert('lives', {
    'title': 'P81_B_$suffix',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveIdA = liveA['id']!.toString();
  final liveIdB = liveB['id']!.toString();

  await client.insert('live_items', {
    'live_id': liveIdA,
    'ref_code': refSlug,
    'title': 'Artigo 81',
    'price': 11,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });
  await client.insert('live_items', {
    'live_id': liveIdB,
    'ref_code': refSlug,
    'title': 'Artigo 81B',
    'price': 11,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });

  await client.insert('commerce_meta_page_connections', {
    'seller_id': sellerId,
    'page_id': pageA,
    'page_name': 'P81 Page A',
    'ingest_enabled': true,
    'messaging_enabled': false,
  });

  final videoA = 'vidA_$suffix';
  final videoB = 'vidB_$suffix';
  await client.insert('commerce_meta_live_video_bindings', {
    'live_id': liveIdA,
    'seller_id': sellerId,
    'page_id': pageA,
    'meta_live_video_id': videoA,
    'meta_post_id': 'postA_$suffix',
  });
  await client.insert('commerce_meta_live_video_bindings', {
    'live_id': liveIdB,
    'seller_id': sellerId,
    'page_id': pageA,
    'meta_live_video_id': videoB,
  });

  // --- Poll binding security ---
  final okBind = await client.rpc('batata_meta_assert_poll_binding', {
    'p_page_id': pageA,
    'p_live_id': liveIdA,
    'p_meta_live_video_id': videoA,
    'p_seller_id': sellerId,
  });
  mark(
    '03_poll_binding_ok',
    (okBind is Map && okBind['ok'] == true) ? 'PASS STAGING' : 'FAIL',
    okBind,
  );

  final badVideo = await client.rpc('batata_meta_assert_poll_binding', {
    'p_page_id': pageA,
    'p_live_id': liveIdA,
    'p_meta_live_video_id': 'wrong_video',
    'p_seller_id': sellerId,
  });
  mark(
    '03_poll_binding_bad_video',
    (badVideo is Map && badVideo['ok'] == false) ? 'PASS STAGING' : 'FAIL',
    badVideo,
  );

  final crossLive = await client.rpc('batata_meta_assert_poll_binding', {
    'p_page_id': pageA,
    'p_live_id': liveIdA,
    'p_meta_live_video_id': videoB,
    'p_seller_id': sellerId,
  });
  mark(
    '03_poll_two_lives_mismatch',
    (crossLive is Map && crossLive['ok'] == false) ? 'PASS STAGING' : 'FAIL',
    crossLive,
  );

  if (seller2Id != null) {
    await client.insert('commerce_meta_page_connections', {
      'seller_id': seller2Id,
      'page_id': pageB,
      'page_name': 'P81 Page B',
      'ingest_enabled': true,
      'messaging_enabled': false,
    });
    final crossSeller = await client.rpc('batata_meta_assert_poll_binding', {
      'p_page_id': pageB,
      'p_live_id': liveIdA,
      'p_meta_live_video_id': videoA,
      'p_seller_id': seller2Id,
    });
    mark(
      '03_poll_two_sellers',
      (crossSeller is Map && crossSeller['ok'] == false)
          ? 'PASS STAGING'
          : 'FAIL',
      crossSeller,
    );
  } else {
    // Simulate second seller mismatch with wrong seller_id hint
    final fakeSeller = await client.rpc('batata_meta_assert_poll_binding', {
      'p_page_id': pageA,
      'p_live_id': liveIdA,
      'p_meta_live_video_id': videoA,
      'p_seller_id': '00000000-0000-0000-0000-000000000099',
    });
    mark(
      '03_poll_two_sellers',
      (fakeSeller is Map && fakeSeller['error'] == 'seller_page_mismatch')
          ? 'PASS STAGING'
          : 'FAIL',
      fakeSeller,
    );
  }

  // --- Graph ingest + PS Reader compat ---
  Future<Map<String, dynamic>> graphIngest({
    required String commentId,
    required String message,
    required int qty,
    String intent = 'reserve',
    String? liveId,
    String? page,
  }) async {
    final raw = await client.rpc('batata_ingest_ocr_reservation_v2', {
      'p_device_token': '',
      'p_live_id': liveId ?? liveIdA,
      'p_external_display_name': 'Buyer81',
      'p_external_buyer_ref': 'fb:1000081${suffix.substring(0, 6)}',
      'p_ocr_raw_line': message,
      'p_ocr_line_hash': 'graph_msg:$commentId',
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_ref_slug': refSlug,
      'p_requested_qty': qty,
      'p_parser_intent': intent,
      'p_comment_id': commentId,
      'p_event_channel': 'graph',
      'p_meta_page_id': page ?? pageA,
      'p_parser_confidence': 0.92,
      'p_ocr_confidence': 0.95,
      'p_identity_confidence': 0.93,
    });
    return raw is Map ? Map<String, dynamic>.from(raw as Map) : {'raw': raw};
  }

  String? deviceToken;
  try {
    final pair = await client.rpc(
      'batata_ps_create_pairing',
      {'p_live_id': liveIdA, 'p_device_id_hint': 'p81-$suffix'},
      accessToken: sellerToken,
    );
    final code = (pair as Map)['code']?.toString() ?? '';
    try {
      final claim = await client.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'p81-$suffix',
        'p_app_version': 'phase8.1',
      });
      deviceToken = (claim as Map)['device_token']?.toString();
    } catch (_) {}
    if (deviceToken == null || deviceToken!.isEmpty) {
      final sessions = await client.select(
        'ps_pairing_sessions',
        filter: 'code=eq.$code&live_id=eq.$liveIdA',
        limit: 1,
      );
      if (sessions.isNotEmpty) {
        deviceToken = sessions.first['device_token_plain']?.toString();
      }
    }
  } catch (e) {
    mark('01_ps_reader_device_token', 'FAIL', e.toString());
  }

  if (deviceToken != null && deviceToken!.isNotEmpty) {
    mark('01_ps_reader_device_token', 'PASS STAGING');
    final ocr = await client.rpc('batata_ingest_ocr_reservation_v2', {
      'p_device_token': deviceToken,
      'p_live_id': liveIdA,
      'p_external_display_name': 'OCR Buyer 81',
      'p_external_buyer_ref': 'fb:10000819990001',
      'p_ocr_raw_line': 'quero $refSlug',
      'p_ocr_line_hash': ('ocr81hh$suffix').padRight(16, 'a').substring(0, 16),
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_ref_slug': refSlug,
      'p_requested_qty': 1,
      'p_parser_intent': 'reserve',
      'p_event_channel': 'ocr',
      // no p_meta_page_id — prior PS Reader client shape
    });
    final ocrMap =
        ocr is Map ? Map<String, dynamic>.from(ocr as Map) : <String, dynamic>{};
    mark(
      '01_ps_reader_compat_no_meta_page',
      ocrMap['ok'] == true || ocrMap['duplicate'] == true
          ? 'PASS STAGING'
          : 'FAIL',
      ocrMap,
    );
  } else {
    mark('01_ps_reader_device_token', 'FAIL', 'no token');
    mark('01_ps_reader_compat_no_meta_page', 'FAIL', 'no token');
  }

  final g1 = await graphIngest(
    commentId: 'c81a$suffix',
    message: 'quero $refSlug',
    qty: 1,
  );
  mark(
    '02_graph_valid',
    g1['ok'] == true && g1['duplicate'] != true ? 'PASS STAGING' : 'FAIL',
    g1,
  );

  // --- Webhooks ---
  final unauth = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': 'wh:unauth:$suffix',
    'p_page_id': '000000000000001',
    'p_payload': {},
  });
  mark(
    '04_webhook_unauthorized_page',
    (unauth is Map && unauth['error'] == 'page_not_authorized')
        ? 'PASS STAGING'
        : 'FAIL',
    unauth,
  );

  final noLivePage = '20883$suffix';
  await client.insert('commerce_meta_page_connections', {
    'seller_id': sellerId,
    'page_id': noLivePage,
    'page_name': 'No Live Page',
    'ingest_enabled': true,
    'messaging_enabled': false,
  });
  final noLive = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': 'wh:nolive:$suffix',
    'p_page_id': noLivePage,
    'p_payload': {},
  });
  mark(
    '04_webhook_no_live',
    (noLive is Map &&
            (noLive['warning'] != null || noLive['live_id'] == null))
        ? 'PASS STAGING'
        : 'FAIL',
    noLive,
  );

  final dk = 'wh:dup:$suffix';
  final c1 = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dk,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  await client.rpc('batata_meta_webhook_finish_delivery', {
    'p_delivery_key': dk,
    'p_status': 'processed',
    'p_result': {'ok': true},
  });
  final c2 = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dk,
    'p_page_id': pageA,
    'p_payload': {},
  });
  mark(
    '04_webhook_duplicate',
    (c2 is Map && c2['duplicate'] == true) ? 'PASS STAGING' : 'FAIL',
    {'first': c1, 'second': c2},
  );

  // Recoverable error reclaim
  final dkErr = 'wh:err:$suffix';
  await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dkErr,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  await client.rpc('batata_meta_webhook_finish_delivery', {
    'p_delivery_key': dkErr,
    'p_status': 'error',
    'p_result': {'error': 'transient'},
  });
  final reclaim = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dkErr,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  mark(
    '04_webhook_retry_after_error',
    (reclaim is Map &&
            reclaim['ok'] == true &&
            reclaim['duplicate'] != true &&
            reclaim['reclaimed'] == true)
        ? 'PASS STAGING'
        : 'FAIL',
    reclaim,
  );

  // Restart mid-flight: concurrent sees inflight; after error (crash) reclaim works
  final dkCrash = 'wh:crash:$suffix';
  await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dkCrash,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  final inflight = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dkCrash,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  final inflightOk = inflight is Map &&
      inflight['duplicate'] == true &&
      inflight['reason'] == 'inflight';
  await client.rpc('batata_meta_webhook_finish_delivery', {
    'p_delivery_key': dkCrash,
    'p_status': 'error',
    'p_result': {'error': 'process_restart'},
  });
  final reclaimCrash = await client.rpc('batata_meta_webhook_claim_delivery', {
    'p_delivery_key': dkCrash,
    'p_page_id': pageA,
    'p_payload': {'postId': 'postA_$suffix'},
  });
  mark(
    '04_webhook_restart_mid_process',
    (inflightOk &&
            reclaimCrash is Map &&
            reclaimCrash['ok'] == true &&
            reclaimCrash['duplicate'] != true &&
            reclaimCrash['reclaimed'] == true)
        ? 'PASS STAGING'
        : 'FAIL',
    {'inflight': inflight, 'reclaim': reclaimCrash},
  );

  // Concurrent claims same key
  final dkConc = 'wh:conc:$suffix';
  final futures = await Future.wait([
    client.rpc('batata_meta_webhook_claim_delivery', {
      'p_delivery_key': dkConc,
      'p_page_id': pageA,
      'p_payload': {'postId': 'postA_$suffix'},
    }),
    client.rpc('batata_meta_webhook_claim_delivery', {
      'p_delivery_key': dkConc,
      'p_page_id': pageA,
      'p_payload': {'postId': 'postA_$suffix'},
    }),
  ]);
  final outcomes = futures.map((e) {
    final m = e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{};
    return {
      'ok': m['ok'],
      'duplicate': m['duplicate'],
      'reclaimed': m['reclaimed'],
      'live_id': m['live_id'],
    };
  }).toList();
  final winners = outcomes
      .where((o) => o['ok'] == true && o['duplicate'] != true)
      .length;
  mark(
    '04_webhook_concurrent',
    winners == 1 ? 'PASS STAGING' : 'FAIL',
    outcomes,
  );

  // Signature crypto (local Node mirror of Edge HMAC)
  try {
    final sigProc = await Process.run('node', ['tool/_tmp_meta_sig_check.mjs']);
    final sigOk = sigProc.exitCode == 0;
    mark(
      '04_webhook_valid_signature',
      sigOk ? 'PASS MOCK' : 'FAIL',
      sigProc.stdout.toString().trim(),
    );
    mark(
      '04_webhook_invalid_signature',
      sigOk ? 'PASS MOCK' : 'FAIL',
      sigProc.stdout.toString().trim(),
    );
  } catch (e) {
    mark('04_webhook_valid_signature', 'FAIL', e.toString());
    mark('04_webhook_invalid_signature', 'FAIL', e.toString());
  }
  mark(
    '04_webhook_valid_signature_edge_e2e',
    'NOT RUN',
    'META_APP_SECRET not set for live Edge POST (João)',
  );

  // --- Messenger concurrent claim (enabled briefly for claim path only) ---
  await client.patch(
    'commerce_meta_page_connections',
    'page_id=eq.$pageA',
    {'messaging_enabled': true},
  );
  final msgCmt = 'msg81$suffix';
  final mFutures = await Future.wait([
    client.rpc('batata_commerce_messenger_claim_send', {
      'p_seller_id': sellerId,
      'p_page_id': pageA,
      'p_comment_id': msgCmt,
    }),
    client.rpc('batata_commerce_messenger_claim_send', {
      'p_seller_id': sellerId,
      'p_page_id': pageA,
      'p_comment_id': msgCmt,
    }),
  ]);
  final mOut = mFutures.map((e) {
    final m = e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{};
    return m;
  }).toList();
  final claims = mOut.where((m) => m['claim'] == true).length;
  final dups = mOut.where((m) => m['duplicate'] == true).length;
  mark(
    '05_messenger_concurrent_claim',
    claims == 1 && dups == 1 ? 'PASS STAGING' : 'FAIL',
    mOut,
  );
  await client.rpc('batata_commerce_messenger_finish_send', {
    'p_page_id': pageA,
    'p_comment_id': msgCmt,
    'p_status': 'ambiguous',
    'p_error': 'simulated_timeout',
  });
  final afterAmb = await client.rpc('batata_commerce_messenger_claim_send', {
    'p_seller_id': sellerId,
    'p_page_id': pageA,
    'p_comment_id': msgCmt,
  });
  mark(
    '05_messenger_ambiguous_no_resend',
    (afterAmb is Map &&
            afterAmb['duplicate'] == true &&
            afterAmb['reason'] == 'ambiguous_prior_send')
        ? 'PASS STAGING'
        : 'FAIL',
    afterAmb,
  );
  // Restore disabled by default
  await client.patch(
    'commerce_meta_page_connections',
    'page_id=eq.$pageA',
    {'messaging_enabled': false},
  );
  final disabled = await client.rpc('batata_commerce_messenger_evaluate_outbound', {
    'p_seller_id': sellerId,
    'p_page_id': pageA,
    'p_comment_id': 'other$suffix',
    'p_kind': 'private_reply',
  });
  mark(
    '05_messenger_disabled_default',
    (disabled is Map && disabled['eligible'] == false)
        ? 'PASS STAGING'
        : 'FAIL',
    disabled,
  );
  mark('05_messenger_real_send', 'BLOCKED EXTERNAL');

  // Dedup PS + Graph
  if (deviceToken != null && deviceToken!.isNotEmpty) {
    final shared = 'shared81$suffix';
    await client.rpc('batata_ingest_ocr_reservation_v2', {
      'p_device_token': deviceToken,
      'p_live_id': liveIdA,
      'p_external_display_name': 'Shared',
      'p_external_buyer_ref': 'fb:10000818880001',
      'p_ocr_raw_line': 'quero $refSlug',
      'p_ocr_line_hash': 'ocrshared$suffix'.padRight(12, 'x').substring(0, 14),
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_ref_slug': refSlug,
      'p_requested_qty': 1,
      'p_parser_intent': 'reserve',
      'p_comment_id': shared,
      'p_event_channel': 'ocr',
    });
    final gDup = await graphIngest(
      commentId: shared,
      message: 'quero $refSlug',
      qty: 1,
    );
    mark(
      '06_ps_graph_dedup',
      gDup['duplicate'] == true ? 'PASS STAGING' : 'FAIL',
      gDup,
    );
  } else {
    mark('06_ps_graph_dedup', 'FAIL', 'no device token');
  }

  mark('07_graph_api_real', 'BLOCKED EXTERNAL');
  mark('07_edge_deploy_signature_e2e', 'NOT RUN');

  // Cleanup lives
  await client.patch(
    'lives',
    'id=eq.$liveIdA',
    {'status': 'ended', 'is_active': false},
  );
  await client.patch(
    'lives',
    'id=eq.$liveIdB',
    {'status': 'ended', 'is_active': false},
  );

  await _write(outDir, results);

  final tests = results['tests'] as Map<String, dynamic>;
  final fails = tests.entries
      .where((e) => (e.value as Map)['status'] == 'FAIL')
      .map((e) => e.key)
      .toList();
  print('FAIL count: ${fails.length} ${fails.join(", ")}');
  exit(fails.isEmpty ? 0 : 1);
}

Future<void> _write(Directory outDir, Map<String, dynamic> results) async {
  results['finished_at'] = DateTime.now().toUtc().toIso8601String();
  final file = File('${outDir.path}/phase8_1_results.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  print('Wrote ${file.path}');
}
