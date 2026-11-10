// ignore_for_file: avoid_print
/// Testa qual Application Token BulkGate é válido (sem enviar SMS).
///
/// Usa o endpoint oficial de saldo/info:
/// https://portal.bulkgate.com/api/1.0/simple/info
///
/// Uso (PowerShell — não commitar tokens):
///   $env:BULKGATE_APPLICATION_ID = "37873"
///   $env:BULKGATE_APPLICATION_TOKEN = "token_a"
///   dart run tool/bulkgate_credentials_probe.dart
///
/// Testar duas candidatas:
///   $env:BULKGATE_APPLICATION_TOKEN_2 = "token_b"
///   dart run tool/bulkgate_credentials_probe.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _infoUrl = 'https://portal.bulkgate.com/api/1.0/simple/info';

Future<void> main() async {
  final appId = Platform.environment['BULKGATE_APPLICATION_ID']?.trim() ?? '';
  final tokenA = Platform.environment['BULKGATE_APPLICATION_TOKEN']?.trim() ?? '';
  final tokenB = Platform.environment['BULKGATE_APPLICATION_TOKEN_2']?.trim() ?? '';

  if (appId.isEmpty) {
    print('Define BULKGATE_APPLICATION_ID (ex.: 37873)');
    exit(2);
  }
  if (tokenA.isEmpty && tokenB.isEmpty) {
    print('Define BULKGATE_APPLICATION_TOKEN (e opcionalmente _2 para comparar)');
    exit(2);
  }

  print('# BulkGate credentials probe');
  print('application_id: $appId');
  print('endpoint: $_infoUrl\n');

  var anyOk = false;
  if (tokenA.isNotEmpty) {
    anyOk = await _probe('TOKEN_1 (BULKGATE_APPLICATION_TOKEN)', appId, tokenA) ||
        anyOk;
  }
  if (tokenB.isNotEmpty) {
    anyOk = await _probe('TOKEN_2 (BULKGATE_APPLICATION_TOKEN_2)', appId, tokenB) ||
        anyOk;
  }

  print(anyOk
      ? '\nUsa o token marcado PASS em BULKGATE_APPLICATION_TOKEN no Supabase.'
      : '\nNenhum token válido — regenera no portal (HTTP Simple API) e testa de novo.');
  exit(anyOk ? 0 : 1);
}

Future<bool> _probe(String label, String appId, String token) async {
  final fp = _fingerprint(token);
  try {
    final res = await http
        .post(
          Uri.parse(_infoUrl),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
          },
          body: jsonEncode({
            'application_id': appId,
            'application_token': token,
          }),
        )
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic>? json;
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map) json = Map<String, dynamic>.from(raw);
    } catch (_) {}

    final data = json?['data'];
    if (res.statusCode >= 200 &&
        res.statusCode < 300 &&
        data is Map &&
        data['credit'] != null) {
      print('[PASS] $label (fingerprint $fp)');
      print('       credit=${data['credit']} currency=${data['currency']}');
      return true;
    }

    final err = json?['error']?.toString() ??
        json?['type']?.toString() ??
        res.body;
    print('[FAIL] $label (fingerprint $fp)');
    print('       HTTP ${res.statusCode}: ${_truncate(err.toString(), 180)}');
    return false;
  } catch (e) {
    print('[FAIL] $label (fingerprint $fp)');
    print('       $e');
    return false;
  }
}

String _fingerprint(String s) =>
    s.length <= 8 ? '***' : '${s.substring(0, 4)}…${s.substring(s.length - 4)}';

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
