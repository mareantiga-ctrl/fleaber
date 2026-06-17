// Extrai texto e quantidades da hierarquia Maestro (commands JSON).
import 'dart:convert';
import 'dart:io';

import 'models.dart';

final _qtyPatterns = [
  RegExp(r'(\d+)\s*dispon[ií]ve', caseSensitive: false),
  RegExp(r'dispon[ií]ve[:\s]*(\d+)', caseSensitive: false),
  RegExp(r'stock[:\s]*(\d+)', caseSensitive: false),
  RegExp(r'(\d+)\s*em\s*stock', caseSensitive: false),
  RegExp(r'reservad[oa][:\s]*(\d+)', caseSensitive: false),
  RegExp(r'vendid[oa][:\s]*(\d+)', caseSensitive: false),
  RegExp(r'total[:\s]*(\d+)', caseSensitive: false),
  RegExp(r'qty[:\s]*(\d+)', caseSensitive: false),
  RegExp(r'x\s*(\d+)', caseSensitive: false),
];

class UiExtractor {
  UiExtractor({this.surface = 'ui'});

  final String surface;

  final Set<String> _texts = {};
  final List<String> _failedAsserts = [];
  final List<String> _warnedAsserts = [];

  List<String> extractTextsFromJsonFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return [];
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      _walk(decoded);
    } catch (_) {}
    return _texts.toList();
  }

  void _walk(dynamic node) {
    if (node is Map) {
      for (final e in node.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (k == 'status' && v == 'FAILED') {
          final msg = node['debugMessage']?.toString();
          if (msg != null && msg.isNotEmpty) _failedAsserts.add(msg);
        }
        if (k == 'status' && v == 'WARNED') {
          final msg = node['debugMessage']?.toString();
          if (msg != null && msg.isNotEmpty) _warnedAsserts.add(msg);
        }
        if (k == 'accessibilityText' ||
            k == 'text' ||
            k == 'label' ||
            k == 'contentDescription') {
          final t = v?.toString().trim();
          if (t != null && t.isNotEmpty) _texts.add(t);
        }
        _walk(v);
      }
    } else if (node is List) {
      for (final item in node) {
        _walk(item);
      }
    }
  }

  List<QtySnapshot> extractQtySnapshots({String liveItemId = ''}) {
    final out = <QtySnapshot>[];
    for (final text in _texts) {
      final metrics = _parseCatalogMetricsLine(text);
      if (metrics != null) {
        out.add(QtySnapshot(
          totalQty: metrics.totalQty,
          availableQty: metrics.availableQty,
          soldQty: metrics.soldQty,
          soldConvertedQty: metrics.soldConvertedQty,
          source: '$surface:$text',
          liveItemId: liveItemId,
          raw: metrics.raw,
        ));
        continue;
      }
      for (final p in _qtyPatterns) {
        final m = p.firstMatch(text);
        if (m == null) continue;
        final n = int.tryParse(m.group(1) ?? '');
        if (n == null) continue;
        final lower = text.toLowerCase();
        int? avail, sold, res, total, blocked, cross;
        if (lower.contains('dispon')) {
          avail = n;
        } else if (lower.contains('vendid')) {
          sold = n;
        } else if (lower.contains('reserv')) {
          res = n;
        } else if (lower.contains('bloq')) {
          blocked = n;
        } else if (lower.contains('cross')) {
          cross = n;
        } else if (lower.contains('total')) {
          total = n;
        } else {
          avail ??= n;
        }
        out.add(QtySnapshot(
          totalQty: total,
          availableQty: avail,
          reservedQty: res,
          soldQty: sold,
          blockedQty: blocked,
          crossReservedQty: cross,
          source: '$surface:$text',
          liveItemId: liveItemId,
          raw: {'text': text},
        ));
        break;
      }
    }
    return out;
  }

  /// Linha do catálogo vendedor: Disp: N · Total: M · Vendidos: K
  static QtySnapshot? _parseCatalogMetricsLine(String text) {
    final m = RegExp(
      r'Disp:\s*(\d+)\s*·\s*Total:\s*(\d+)\s*·\s*Vendidos:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    final disp = int.tryParse(m.group(1) ?? '');
    final total = int.tryParse(m.group(2) ?? '');
    final sold = int.tryParse(m.group(3) ?? '');
    if (disp == null && total == null && sold == null) return null;
    return QtySnapshot(
      totalQty: total,
      availableQty: disp,
      soldQty: sold,
      soldConvertedQty: sold,
      source: 'catalog_metrics',
      raw: {'text': text},
    );
  }

  List<String> get failedAsserts => List.unmodifiable(_failedAsserts);
  List<String> get warnedAsserts => List.unmodifiable(_warnedAsserts);
  List<String> get allTexts => _texts.toList();

  static Map<String, List<QtySnapshot>> fromEvidenceDir(
    String dir, {
    String sellerLabel = 'seller_ui',
    String buyerLabel = 'buyer_ui',
  }) {
    final root = Directory(dir);
    if (!root.existsSync()) return {};
    final seller = UiExtractor(surface: sellerLabel);
    final buyer = UiExtractor(surface: buyerLabel);
    final generic = UiExtractor(surface: 'ui');

    for (final f in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))) {
      final name = f.path.toLowerCase();
      if (name.contains('seller') || name.contains('harness')) {
        seller.extractTextsFromJsonFile(f.path);
      } else if (name.contains('buyer')) {
        buyer.extractTextsFromJsonFile(f.path);
      } else {
        generic.extractTextsFromJsonFile(f.path);
      }
    }

    return {
      sellerLabel: seller.extractQtySnapshots(),
      buyerLabel: buyer.extractQtySnapshots(),
      'ui': generic.extractQtySnapshots(),
      '${sellerLabel}_texts': seller.allTexts.map((t) => QtySnapshot(source: t)).toList(),
      '${buyerLabel}_texts': buyer.allTexts.map((t) => QtySnapshot(source: t)).toList(),
    };
  }
}
