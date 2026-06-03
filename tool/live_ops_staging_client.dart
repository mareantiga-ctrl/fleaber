import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Cliente HTTP mínimo para checks V0 em Supabase (sem Flutter).
class LiveOpsStagingClient {
  LiveOpsStagingClient({
    required this.url,
    required this.anonKey,
    required this.serviceRoleKey,
  });

  final String url;
  final String anonKey;
  final String serviceRoleKey;

  Map<String, String> get _serviceHeaders => {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Map<String, String> _userHeaders(String accessToken) => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$url/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'signIn failed ${res.statusCode}: ${res.body}',
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final token = map['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const HttpException('signIn: access_token em falta');
    }
    return token;
  }

  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? filter,
    int limit = 10,
  }) async {
    var path = '$url/rest/v1/$table?select=*';
    if (filter != null && filter.isNotEmpty) {
      path += '&$filter';
    }
    path += '&limit=$limit';
    final res = await http.get(Uri.parse(path), headers: _serviceHeaders);
    if (res.statusCode >= 400) {
      throw HttpException('select $table ${res.statusCode}: ${res.body}');
    }
    final list = jsonDecode(res.body);
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> row,
  ) async {
    final res = await http.post(
      Uri.parse('$url/rest/v1/$table'),
      headers: _serviceHeaders,
      body: jsonEncode(row),
    );
    if (res.statusCode >= 400) {
      throw HttpException('insert $table ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body);
    if (body is List && body.isNotEmpty) {
      return Map<String, dynamic>.from(body.first as Map);
    }
    if (body is Map) {
      return Map<String, dynamic>.from(body);
    }
    throw HttpException('insert $table: resposta inesperada');
  }

  Future<void> patch(
    String table,
    String filter,
    Map<String, dynamic> row,
  ) async {
    final res = await http.patch(
      Uri.parse('$url/rest/v1/$table?$filter'),
      headers: _serviceHeaders,
      body: jsonEncode(row),
    );
    if (res.statusCode >= 400) {
      throw HttpException('patch $table ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> deleteWhere(String table, String filter) async {
    final res = await http.delete(
      Uri.parse('$url/rest/v1/$table?$filter'),
      headers: _serviceHeaders,
    );
    if (res.statusCode >= 400) {
      throw HttpException('delete $table ${res.statusCode}: ${res.body}');
    }
  }

  Future<dynamic> rpc(
    String fn,
    Map<String, dynamic> params, {
    String? accessToken,
  }) async {
    final headers = accessToken == null
        ? _serviceHeaders
        : _userHeaders(accessToken);
    final res = await http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: headers,
      body: jsonEncode(params),
    );
    if (res.statusCode >= 400) {
      throw HttpException('rpc $fn ${res.statusCode}: ${res.body}');
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<http.Response> invokeEdge(
    String fn,
    Map<String, dynamic> body, {
    required String accessToken,
  }) async {
    return http.post(
      Uri.parse('$url/functions/v1/$fn'),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }
}

Map<String, String> loadLiveOpsStagingEnv([String? path]) {
  final file = File(path ?? 'tool/live_ops_staging.env');
  if (!file.existsSync()) {
    throw StateError(
      'Ficheiro ${file.path} em falta. Copia tool/live_ops_staging_env.example',
    );
  }
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}

String envRequire(Map<String, String> env, String key) {
  final v = env[key]?.trim() ?? '';
  if (v.isEmpty) {
    throw StateError('Variável $key em falta em tool/live_ops_staging.env');
  }
  return v;
}
