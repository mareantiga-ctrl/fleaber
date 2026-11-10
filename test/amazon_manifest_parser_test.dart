import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/amazon_importer/amazon_importer_models.dart';
import 'package:fleaber/amazon_importer/amazon_manifest_parser.dart';

void main() {
  test('parseCsv handles quotes and commas', () {
    const csv = 'ASIN,LPN,"Item Desc"\n'
        'B00TEST,LPN1,"Hello, world"\n';
    final rows = AmazonManifestParser.parseCsv(csv);
    expect(rows.length, 2);
    expect(rows[1][2], 'Hello, world');
  });

  test('preview requires ASIN+LPN columns', () {
    const csv = 'ASIN,LPN,CONDITION,EAN,UPC,QTY,COST,Item Desc,CURRENCY CODE\n'
        'B00AAA,LPN-1,Sellable,123,456,1,10.5,Widget,EUR\n'
        'B00BBB,LPN-2,Sellable,789,012,1,20,Other,EUR\n';
    final p = AmazonManifestParser.preview(csv);
    expect(p.isValid, isTrue);
    expect(p.totalRows, 2);
    expect(p.distinctAsin, 2);
  });

  test('suggestedSale uses ES priority not lowest price', () {
    final offers = [
      const AmazonOfferView(
        marketplace: 'es',
        status: 'ok',
        priceAmount: 40,
        currency: 'EUR',
        availability: 'En stock',
      ),
      const AmazonOfferView(
        marketplace: 'it',
        status: 'ok',
        priceAmount: 20,
        currency: 'EUR',
        availability: 'In stock',
      ),
      const AmazonOfferView(
        marketplace: 'de',
        status: 'ok',
        priceAmount: 18,
        currency: 'EUR',
      ),
    ];
    // ES first → 40 * 50% = 20 (not DE 9)
    expect(pickAmazonReferenceOffer(offers)?.marketplace, 'es');
    expect(
      suggestedSaleFromOffers(offers: offers, discountPct: 50),
      20.0,
    );
  });

  test('skips unavailable ES and uses next market', () {
    final offers = [
      const AmazonOfferView(
        marketplace: 'es',
        status: 'ok',
        priceAmount: 27.36,
        currency: 'EUR',
        availability: 'unavailable',
      ),
      const AmazonOfferView(
        marketplace: 'it',
        status: 'ok',
        priceAmount: 19.99,
        currency: 'EUR',
        availability: 'In stock',
      ),
    ];
    final ref = pickAmazonReferenceOffer(offers);
    expect(ref?.marketplace, 'it');
    expect(suggestedSaleFromOffers(offers: offers, discountPct: 50), 9.99);
  });

  test('suspicious spread blocks auto suggestion', () {
    final offers = [
      const AmazonOfferView(
        marketplace: 'es',
        status: 'ok',
        priceAmount: 236.81,
        currency: 'EUR',
        availability: 'En stock',
      ),
      const AmazonOfferView(
        marketplace: 'de',
        status: 'ok',
        priceAmount: 27.95,
        currency: 'EUR',
        availability: 'In stock',
      ),
    ];
    expect(hasSuspiciousAmazonPriceSpread(offers), isTrue);
  });

  test('suggestedSaleFromOffers null when no reliable price', () {
    final offers = [
      const AmazonOfferView(marketplace: 'es', status: 'not_found'),
      const AmazonOfferView(marketplace: 'it', status: 'captcha'),
    ];
    expect(
      suggestedSaleFromOffers(offers: offers, discountPct: 50),
      isNull,
    );
  });

  test('preview rejects rows with empty LPN', () {
    const csv = 'ASIN,LPN,CONDITION,EAN,UPC,QTY,COST,Item Desc,CURRENCY CODE\n'
        'B00AAA,LPN-1,Sellable,123,456,1,10.5,Widget,EUR\n'
        'B00BBB,,Sellable,789,012,1,20,Other,EUR\n';
    final p = AmazonManifestParser.preview(csv);
    expect(p.rowsMissingLpn, 1);
    expect(p.isValid, isFalse);
  });
}
