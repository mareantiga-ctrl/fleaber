import 'dart:convert';

import 'amazon_importer_models.dart';

/// Parser CSV simples (RFC4180-ish) para manifestos Amazon Liquidation.
class AmazonManifestParser {
  AmazonManifestParser._();

  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    final field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (var i = 0; i < normalized.length; i++) {
      final c = normalized[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < normalized.length && normalized[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          row.add(field.toString());
          field.clear();
        } else if (c == '\n') {
          row.add(field.toString());
          field.clear();
          if (row.any((e) => e.trim().isNotEmpty)) {
            rows.add(row);
          }
          row = <String>[];
        } else {
          field.write(c);
        }
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (row.any((e) => e.trim().isNotEmpty)) {
        rows.add(row);
      }
    }
    return rows;
  }

  static AmazonManifestPreview preview(String text, {int sampleLimit = 8}) {
    final grid = parseCsv(text);
    if (grid.isEmpty) {
      return const AmazonManifestPreview(
        headers: [],
        sampleRows: [],
        totalRows: 0,
        distinctAsin: 0,
        missingRequired: kAmazonManifestRequiredColumns,
        hasLpn: false,
        hasAsin: false,
      );
    }
    final headers = grid.first.map((e) => e.trim()).toList();
    final headerIndex = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      headerIndex[headers[i]] = i;
    }
    String cell(List<String> r, String name) {
      final i = headerIndex[name];
      if (i == null || i >= r.length) return '';
      return r[i].trim();
    }

    final data = grid.skip(1).toList();
    final asins = <String>{};
    final lpns = <String>{};
    var rowsMissingLpn = 0;
    var rowsMissingAsin = 0;
    var duplicateLpnCount = 0;
    for (final r in data) {
      final a = cell(r, 'ASIN');
      final l = cell(r, 'LPN');
      if (a.isNotEmpty) asins.add(a);
      if (a.isEmpty) rowsMissingAsin++;
      if (l.isEmpty) {
        rowsMissingLpn++;
      } else if (!lpns.add(l)) {
        duplicateLpnCount++;
      }
    }
    final missing = kAmazonManifestRequiredColumns
        .where((c) => !headerIndex.containsKey(c))
        .toList();
    final samples = <Map<String, String>>[];
    for (final r in data.take(sampleLimit)) {
      final m = <String, String>{};
      for (final h in headers) {
        m[h] = cell(r, h);
      }
      samples.add(m);
    }
    return AmazonManifestPreview(
      headers: headers,
      sampleRows: samples,
      totalRows: data.length,
      distinctAsin: asins.length,
      missingRequired: missing,
      hasLpn: headerIndex.containsKey('LPN'),
      hasAsin: headerIndex.containsKey('ASIN'),
      rowsMissingLpn: rowsMissingLpn,
      rowsMissingAsin: rowsMissingAsin,
      duplicateLpnCount: duplicateLpnCount,
    );
  }

  static List<Map<String, String>> rowsAsMaps(String text) {
    final grid = parseCsv(text);
    if (grid.length < 2) return const [];
    final headers = grid.first.map((e) => e.trim()).toList();
    final out = <Map<String, String>>[];
    for (final r in grid.skip(1)) {
      final m = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i]] = i < r.length ? r[i].trim() : '';
      }
      if ((m['LPN'] ?? '').isEmpty && (m['ASIN'] ?? '').isEmpty) continue;
      out.add(m);
    }
    return out;
  }

  static String sha256HexPlaceholder(String text) {
    // Hash leve para dedupe de ficheiro (não criptográfico forte).
    return 'len:${text.length}:crc:${_crc32(utf8.encode(text)).toRadixString(16)}';
  }

  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final b in bytes) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return crc ^ 0xffffffff;
  }
}
