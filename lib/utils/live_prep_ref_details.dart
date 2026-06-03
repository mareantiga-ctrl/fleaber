import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Metadados opcionais por referência (ex. #B3) antes do directo.
class LiveRefChipDetail {
  const LiveRefChipDetail({
    this.title,
    this.price,
    this.quantity = 1,
    this.clothingSize,
    this.clothingColor,
    this.isClothing = false,
  });

  final String? title;
  final double? price;
  final int quantity;
  final String? clothingSize;
  final String? clothingColor;
  final bool isClothing;

  factory LiveRefChipDetail.fromJson(Map<String, dynamic> json) {
    final priceRaw = json['price'];
    double? price;
    if (priceRaw is num) {
      price = priceRaw.toDouble();
    } else if (priceRaw is String) {
      price = double.tryParse(priceRaw.replaceAll(',', '.'));
    }
    return LiveRefChipDetail(
      title: json['title']?.toString().trim(),
      price: price,
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      clothingSize: json['clothing_size']?.toString().trim(),
      clothingColor: json['clothing_color']?.toString().trim(),
      isClothing: json['is_clothing'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null && title!.isNotEmpty) 'title': title,
        if (price != null) 'price': price,
        'quantity': quantity < 1 ? 1 : quantity,
        if (clothingSize != null && clothingSize!.isNotEmpty)
          'clothing_size': clothingSize,
        if (clothingColor != null && clothingColor!.isNotEmpty)
          'clothing_color': clothingColor,
        'is_clothing': isClothing,
      };

  String buildLiveItemTitle(String fallback) {
    final base = (title != null && title!.isNotEmpty) ? title!.trim() : fallback;
    final parts = <String>[base];
    if (quantity > 1) parts.add('Qty $quantity');
    if (isClothing && clothingSize != null && clothingSize!.isNotEmpty) {
      parts.add('Tam. $clothingSize');
    }
    if (isClothing && clothingColor != null && clothingColor!.isNotEmpty) {
      parts.add(clothingColor!);
    }
    return parts.join(' · ');
  }
}

/// Persistência local dos detalhes por ref (#B3, etc.).
abstract final class LivePrepRefDetails {
  static const _key = 'batata_live_prep_ref_details_v1';

  static String normalizeRefKey(String raw) {
    var r = raw.trim().toUpperCase();
    if (r.startsWith('#')) r = r.substring(1);
    return r.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static Future<Map<String, LiveRefChipDetail>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(
          k,
          LiveRefChipDetail.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<LiveRefChipDetail?> read(String refKey) async {
    final all = await readAll();
    return all[normalizeRefKey(refKey)];
  }

  static Future<void> save(String refKey, LiveRefChipDetail detail) async {
    final key = normalizeRefKey(refKey);
    if (key.isEmpty) return;
    final all = await readAll();
    final empty = (detail.title == null || detail.title!.isEmpty) &&
        detail.price == null &&
        detail.quantity <= 1 &&
        !detail.isClothing &&
        (detail.clothingSize == null || detail.clothingSize!.isEmpty);
    if (empty) {
      all.remove(key);
    } else {
      all[key] = detail;
    }
    final prefs = await SharedPreferences.getInstance();
    if (all.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
