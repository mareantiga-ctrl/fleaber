import '/backend/supabase/supabase.dart';
import '/live_amazon/live_amazon_models.dart';

/// Lookup local (catálogo Fleaber/Amazon preparado) — sem nova pesquisa Amazon.
class LiveAmazonLookupService {
  LiveAmazonLookupService._();
  static final instance = LiveAmazonLookupService._();

  static final _asinRe = RegExp(r'^[A-Z0-9]{10}$');
  static final _flbRe = RegExp(r'^FLB\d{6}$');

  Future<LiveAmazonLookupResult> lookup(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      return LiveAmazonLookupResult(query: q, hits: const [], notFound: true);
    }
    final upper = q.toUpperCase();

    // 1) LPN
    final byLpn = await _fromUnits(lpn: q);
    if (byLpn.isNotEmpty) {
      return LiveAmazonLookupResult(query: q, hits: byLpn);
    }

    // 2) FLB###### via moloni_product_links → fleaber product → ASIN
    if (_flbRe.hasMatch(upper)) {
      final flbHits = await _fromFlb(upper);
      if (flbHits.isNotEmpty) {
        return LiveAmazonLookupResult(query: q, hits: flbHits);
      }
    }

    // 3) ASIN / AMZ-ASIN
    var asin = upper;
    if (asin.startsWith('AMZ-')) asin = asin.substring(4);
    if (_asinRe.hasMatch(asin)) {
      final byAsin = await _fromCatalogAsin(asin);
      if (byAsin.isNotEmpty) {
        return LiveAmazonLookupResult(query: q, hits: byAsin);
      }
    }

    // 4) EAN
    final byEan = await _fromCatalogEan(q);
    if (byEan.isNotEmpty) {
      return LiveAmazonLookupResult(query: q, hits: byEan);
    }

    // 5) Produto Fleaber por ref_code
    final byRef = await _fromFleaberRef(upper);
    if (byRef.isNotEmpty) {
      return LiveAmazonLookupResult(query: q, hits: byRef);
    }

    return LiveAmazonLookupResult(query: q, hits: const [], notFound: true);
  }

  Future<List<LiveAmazonPresentItem>> _fromUnits({required String lpn}) async {
    final rows = await SupaFlow.client
        .from('amazon_catalog_units')
        .select(
          'id, lpn, asin, qty, condition_label, product_id, '
          'amazon_catalog_products(id, asin, ean, title, primary_image_url, '
          'approved_sale_eur, suggested_sale_eur, discount_pct, fleaber_product_id, '
          'catalog_status, copy_status)',
        )
        .eq('lpn', lpn)
        .limit(20);
    final out = <LiveAmazonPresentItem>[];
    for (final raw in (rows as List)) {
      final u = Map<String, dynamic>.from(raw as Map);
      final pRaw = u['amazon_catalog_products'];
      final p = pRaw is Map
          ? Map<String, dynamic>.from(pRaw)
          : <String, dynamic>{};
      out.add(await _buildItem(
        asin: (u['asin'] ?? p['asin'] ?? '').toString(),
        catalogProductId: p['id']?.toString() ?? u['product_id']?.toString(),
        unitId: u['id']?.toString(),
        lpn: u['lpn']?.toString(),
        ean: p['ean']?.toString(),
        title: p['title']?.toString(),
        imageUrl: p['primary_image_url']?.toString(),
        approved: (p['approved_sale_eur'] as num?)?.toDouble(),
        suggested: (p['suggested_sale_eur'] as num?)?.toDouble(),
        discount: (p['discount_pct'] as num?)?.toDouble() ?? 50,
        fleaberProductId: p['fleaber_product_id']?.toString(),
        qty: (u['qty'] as num?)?.toInt() ?? 1,
        condition: u['condition_label']?.toString() ?? 'Novo',
        needsReview: p['copy_status']?.toString() == 'revision_needed' ||
            p['catalog_status']?.toString() == 'needs_review',
      ));
    }
    return out;
  }

  Future<List<LiveAmazonPresentItem>> _fromCatalogAsin(String asin) async {
    final rows = await SupaFlow.client
        .from('amazon_catalog_products')
        .select(
          'id, asin, ean, title, primary_image_url, approved_sale_eur, '
          'suggested_sale_eur, discount_pct, fleaber_product_id, catalog_status, copy_status',
        )
        .eq('asin', asin)
        .limit(5);
    final out = <LiveAmazonPresentItem>[];
    for (final raw in (rows as List)) {
      final p = Map<String, dynamic>.from(raw as Map);
      final units = await SupaFlow.client
          .from('amazon_catalog_units')
          .select('id, lpn, qty, condition_label')
          .eq('product_id', p['id'])
          .limit(40);
      final unitList = units as List;
      if (unitList.isEmpty) {
        out.add(await _buildItem(
          asin: asin,
          catalogProductId: p['id']?.toString(),
          ean: p['ean']?.toString(),
          title: p['title']?.toString(),
          imageUrl: p['primary_image_url']?.toString(),
          approved: (p['approved_sale_eur'] as num?)?.toDouble(),
          suggested: (p['suggested_sale_eur'] as num?)?.toDouble(),
          discount: (p['discount_pct'] as num?)?.toDouble() ?? 50,
          fleaberProductId: p['fleaber_product_id']?.toString(),
          qty: 0,
          condition: 'Novo',
          needsReview: true,
        ));
      } else {
        for (final uRaw in unitList) {
          final u = Map<String, dynamic>.from(uRaw as Map);
          out.add(await _buildItem(
            asin: asin,
            catalogProductId: p['id']?.toString(),
            unitId: u['id']?.toString(),
            lpn: u['lpn']?.toString(),
            ean: p['ean']?.toString(),
            title: p['title']?.toString(),
            imageUrl: p['primary_image_url']?.toString(),
            approved: (p['approved_sale_eur'] as num?)?.toDouble(),
            suggested: (p['suggested_sale_eur'] as num?)?.toDouble(),
            discount: (p['discount_pct'] as num?)?.toDouble() ?? 50,
            fleaberProductId: p['fleaber_product_id']?.toString(),
            qty: (u['qty'] as num?)?.toInt() ?? 1,
            condition: u['condition_label']?.toString() ?? 'Novo',
            needsReview: p['copy_status']?.toString() == 'revision_needed',
          ));
        }
      }
    }
    return out;
  }

  Future<List<LiveAmazonPresentItem>> _fromCatalogEan(String ean) async {
    final rows = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('asin')
        .eq('ean', ean)
        .limit(10);
    final out = <LiveAmazonPresentItem>[];
    for (final r in (rows as List)) {
      final asin = r['asin']?.toString();
      if (asin == null || asin.isEmpty) continue;
      out.addAll(await _fromCatalogAsin(asin));
    }
    return out;
  }

  Future<List<LiveAmazonPresentItem>> _fromFlb(String flb) async {
    final links = await SupaFlow.client
        .from('moloni_product_links')
        .select('fleaber_product_id, moloni_reference, asin')
        .eq('moloni_reference', flb)
        .eq('link_status', 'linked')
        .limit(5);
    final out = <LiveAmazonPresentItem>[];
    for (final raw in (links as List)) {
      final link = Map<String, dynamic>.from(raw as Map);
      final asin = (link['asin'] ?? '').toString().trim();
      if (asin.isNotEmpty) {
        final hits = await _fromCatalogAsin(asin);
        out.addAll(hits.map((h) => LiveAmazonPresentItem(
              asin: h.asin,
              ean: h.ean,
              lpn: h.lpn,
              flbReference: flb,
              titlePt: h.titlePt,
              imageUrl: h.imageUrl,
              amazonRefPriceEur: h.amazonRefPriceEur,
              amazonRefMarket: h.amazonRefMarket,
              amazonRefFetchedAt: h.amazonRefFetchedAt,
              fleaberPriceEur: h.fleaberPriceEur,
              discountPct: h.discountPct,
              availableQty: h.availableQty,
              unitCount: h.unitCount,
              fleaberProductId:
                  h.fleaberProductId ?? link['fleaber_product_id']?.toString(),
              catalogProductId: h.catalogProductId,
              unitId: h.unitId,
              saleCondition: h.saleCondition,
              companyKey: h.companyKey,
              needsReview: h.needsReview,
            )));
        continue;
      }
      final pid = link['fleaber_product_id']?.toString();
      if (pid == null) continue;
      out.addAll(await _fromFleaberProductId(pid, flb: flb));
    }
    return out;
  }

  Future<List<LiveAmazonPresentItem>> _fromFleaberRef(String ref) async {
    final rows = await SupaFlow.client
        .from('products')
        .select('id, ref_code, title, price, quantity, image_urls')
        .eq('ref_code', ref)
        .limit(5);
    final out = <LiveAmazonPresentItem>[];
    for (final raw in (rows as List)) {
      final p = Map<String, dynamic>.from(raw as Map);
      out.add(await _fromFleaberRow(p));
    }
    return out;
  }

  Future<List<LiveAmazonPresentItem>> _fromFleaberProductId(
    String id, {
    String? flb,
  }) async {
    final rows = await SupaFlow.client
        .from('products')
        .select('id, ref_code, title, price, quantity, image_urls')
        .eq('id', id)
        .limit(1);
    if ((rows as List).isEmpty) return const [];
    final item = await _fromFleaberRow(
      Map<String, dynamic>.from(rows.first as Map),
      flb: flb,
    );
    return [item];
  }

  Future<LiveAmazonPresentItem> _fromFleaberRow(
    Map<String, dynamic> p, {
    String? flb,
  }) async {
    final ref = p['ref_code']?.toString() ?? '';
    var asin = '';
    if (ref.startsWith('AMZ-')) asin = ref.substring(4);
    final imgs = p['image_urls'];
    String? image;
    if (imgs is List && imgs.isNotEmpty) image = imgs.first?.toString();
    return _buildItem(
      asin: asin.isEmpty ? ref : asin,
      title: p['title']?.toString(),
      imageUrl: image,
      approved: (p['price'] as num?)?.toDouble(),
      suggested: (p['price'] as num?)?.toDouble(),
      discount: 50,
      fleaberProductId: p['id']?.toString(),
      qty: (p['quantity'] as num?)?.toInt() ?? 0,
      condition: 'Novo',
      flb: flb,
    );
  }

  Future<LiveAmazonPresentItem> _buildItem({
    required String asin,
    String? catalogProductId,
    String? unitId,
    String? lpn,
    String? ean,
    String? title,
    String? imageUrl,
    double? approved,
    double? suggested,
    double discount = 50,
    String? fleaberProductId,
    int qty = 0,
    String condition = 'Novo',
    bool needsReview = false,
    String? flb,
  }) async {
    // Oferta Amazon em cache (ES→IT→DE→FR) — sem HTTP externo.
    double? amazonPrice;
    String? market;
    DateTime? fetchedAt;
    if (asin.isNotEmpty) {
      final offers = await SupaFlow.client
          .from('amazon_market_offers')
          .select('marketplace, status, price_amount, fetched_at')
          .eq('asin', asin)
          .eq('status', 'ok')
          .order('fetched_at', ascending: false)
          .limit(20);
      const order = ['es', 'it', 'de', 'fr'];
      final by = <String, Map<String, dynamic>>{};
      for (final raw in (offers as List)) {
        final o = Map<String, dynamic>.from(raw as Map);
        final m = o['marketplace']?.toString().toLowerCase() ?? '';
        if (!order.contains(m)) continue;
        if (!by.containsKey(m)) by[m] = o;
      }
      for (final m in order) {
        final o = by[m];
        if (o == null) continue;
        final amt = (o['price_amount'] as num?)?.toDouble();
        if (amt == null || amt <= 0) continue;
        amazonPrice = amt;
        market = m;
        fetchedAt = DateTime.tryParse(o['fetched_at']?.toString() ?? '');
        break;
      }
    }

    // Stock real Fleaber se existir produto; senão qty do LPN (não é stock de venda).
    var available = qty;
    var companyKey = 'mare_antiga';
    var resolvedFleaberId = fleaberProductId;
    if ((resolvedFleaberId == null || resolvedFleaberId.isEmpty) &&
        asin.isNotEmpty) {
      final prod = await SupaFlow.client
          .from('products')
          .select('id, quantity, seller_id, price, title, image_urls')
          .eq('ref_code', 'AMZ-$asin')
          .limit(1);
      if ((prod as List).isNotEmpty) {
        final row = Map<String, dynamic>.from(prod.first as Map);
        resolvedFleaberId = row['id']?.toString();
        available = (row['quantity'] as num?)?.toInt() ?? 0;
        approved ??= (row['price'] as num?)?.toDouble();
        title ??= row['title']?.toString();
        final imgs = row['image_urls'];
        if ((imageUrl == null || imageUrl.isEmpty) &&
            imgs is List &&
            imgs.isNotEmpty) {
          imageUrl = imgs.first?.toString();
        }
      }
    } else if (resolvedFleaberId != null && resolvedFleaberId.isNotEmpty) {
      final prod = await SupaFlow.client
          .from('products')
          .select('quantity, seller_id')
          .eq('id', resolvedFleaberId)
          .maybeSingle();
      if (prod != null) {
        available = (prod['quantity'] as num?)?.toInt() ?? 0;
      }
    }

    // FLB link
    var flbRef = flb;
    if ((flbRef == null || flbRef.isEmpty) &&
        resolvedFleaberId != null &&
        resolvedFleaberId.isNotEmpty) {
      final link = await SupaFlow.client
          .from('moloni_product_links')
          .select('moloni_reference')
          .eq('fleaber_product_id', resolvedFleaberId)
          .eq('link_status', 'linked')
          .maybeSingle();
      flbRef = link?['moloni_reference']?.toString();
    }

    final fleaberPrice = approved ?? suggested ?? 0.0;
    return LiveAmazonPresentItem(
      asin: asin,
      ean: ean,
      lpn: lpn,
      flbReference: flbRef,
      titlePt: (title ?? '').trim().isEmpty ? 'Artigo $asin' : title!.trim(),
      imageUrl: imageUrl,
      amazonRefPriceEur: amazonPrice,
      amazonRefMarket: market,
      amazonRefFetchedAt: fetchedAt,
      fleaberPriceEur: fleaberPrice,
      discountPct: discount,
      availableQty: available,
      unitCount: qty,
      fleaberProductId: resolvedFleaberId,
      catalogProductId: catalogProductId,
      unitId: unitId,
      saleCondition: condition.trim().isEmpty ? 'Novo' : condition,
      companyKey: companyKey,
      needsReview: needsReview || fleaberPrice <= 0,
    );
  }
}
