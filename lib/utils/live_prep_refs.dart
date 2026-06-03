import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'live_ref_scheme.dart';

/// Esquemas de referências só-texto (sem anúncio) antes do directo.
abstract final class LivePrepRefs {
  static const _schemesKey = 'batata_live_prep_schemes_v2';
  static const _legacyKey = 'batata_live_prep_refs_v1';

  static Future<List<LiveRefScheme>> readSchemes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_schemesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => LiveRefScheme.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((s) => s.spanCount > 0)
            .toList();
      } catch (_) {}
    }

    // Migração: lista antiga de refs individuais → um esquema por ref.
    final legacy = prefs.getString(_legacyKey);
    if (legacy == null || legacy.isEmpty) return const [];
    try {
      final list = jsonDecode(legacy) as List<dynamic>;
      final schemes = <LiveRefScheme>[];
      for (final e in list) {
        final ref = e.toString().trim();
        final m = RegExp(r'^#?([A-Za-z]*)(\d+)$').firstMatch(ref);
        if (m != null) {
          final n = int.tryParse(m.group(2)!);
          if (n != null) {
            schemes.add(LiveRefScheme(prefix: m.group(1) ?? '', from: n, to: n));
          }
        }
      }
      if (schemes.isNotEmpty) {
        await writeSchemes(schemes);
        await prefs.remove(_legacyKey);
      }
      return schemes;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeSchemes(List<LiveRefScheme> schemes) async {
    final prefs = await SharedPreferences.getInstance();
    if (schemes.isEmpty) {
      await prefs.remove(_schemesKey);
      return;
    }
    final payload = schemes.map((s) => s.toJson()).toList();
    await prefs.setString(_schemesKey, jsonEncode(payload));
  }

  static Future<void> appendScheme(LiveRefScheme scheme) async {
    if (scheme.spanCount <= 0) return;
    final existing = await readSchemes();
    await writeSchemes([...existing, scheme]);
  }

  static Future<void> removeAt(int index) async {
    final existing = await readSchemes();
    if (index < 0 || index >= existing.length) return;
    final next = [...existing]..removeAt(index);
    await writeSchemes(next);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_schemesKey);
    await prefs.remove(_legacyKey);
  }
}
