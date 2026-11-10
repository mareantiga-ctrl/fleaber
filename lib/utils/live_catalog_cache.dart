import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';

/// Cache local (SharedPreferences) do catálogo de uma live — abre mais rápido.
class LiveCatalogCache {
  LiveCatalogCache._();

  static const _prefix = 'batata_live_catalog_v1_';
  static const _scrollHintKey = 'batata_live_catalog_scroll_hint_dismissed';

  static String _catalogKey(String liveId) => '$_prefix$liveId';

  static Future<bool> scrollHintDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scrollHintKey) ?? false;
  }

  static Future<void> dismissScrollHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scrollHintKey, true);
  }

  static Future<List<LiveItemsRow>?> read(String liveId) async {
    if (liveId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_catalogKey(liveId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LiveItemsRow(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String liveId, List<LiveItemsRow> rows) async {
    if (liveId.isEmpty || rows.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = rows.map((r) => r.data).toList();
    await prefs.setString(_catalogKey(liveId), jsonEncode(payload));
  }
}
