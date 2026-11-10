/// URLs públicas de imagem Amazon por ASIN (CDN), sem scrape HTML / CAPTCHA.
/// Encontrar a imagem ≠ autorização para publicar o anúncio.
library;

/// Padrões CDN conhecidos. Muitos ASIN devolvem JPEG real; outros devolvem GIF 1×1.
List<String> amazonCdnImageCandidates(String asin, {int maxSlots = 5}) {
  final a = asin.trim().toUpperCase();
  if (a.isEmpty) return const [];
  final out = <String>[];
  for (var i = 1; i <= maxSlots; i++) {
    final nn = i.toString().padLeft(2, '0');
    out.addAll([
      'https://m.media-amazon.com/images/P/$a.$nn.LZZZZZZZ.jpg',
      'https://images-eu.ssl-images-amazon.com/images/P/$a.$nn.LZZZZZZZ.jpg',
      'https://images-eu.ssl-images-amazon.com/images/P/$a.$nn._SCLZZZZZZZ_SX500_.jpg',
    ]);
  }
  return out;
}

const kAmazonPhotoSourceCdnPending = 'amazon_cdn_pending_rights';
const kAmazonPhotoSourceHtmlPending = 'amazon_ref_pending_rights';
const kAmazonPhotoSourceDpHtml = 'amazon_dp_html';
const kAmazonPhotoSourceBrowserPending = 'amazon_browser_pending_rights';

String photoRightsLabel(String? source) {
  switch ((source ?? '').trim()) {
    case kAmazonPhotoSourceCdnPending:
    case kAmazonPhotoSourceHtmlPending:
    case kAmazonPhotoSourceDpHtml:
    case kAmazonPhotoSourceBrowserPending:
      return 'Referência Amazon — direitos pendentes (não publicar sem autorização)';
    case 'upload':
      return 'Upload próprio';
    case 'camera':
      return 'Fotografia própria (câmara)';
    default:
      return source ?? 'origem desconhecida';
  }
}
