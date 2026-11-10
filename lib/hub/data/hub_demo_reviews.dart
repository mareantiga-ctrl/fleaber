import 'package:flutter/foundation.dart' show kIsWeb;

import 'hub_models.dart';

/// Avaliações **só de demonstração local** para validação visual H02.
///
/// Nunca persiste em BD. Não misturar com avaliações reais.
/// Controlo:
/// - `?demo_reviews=1` → força demo (mesmo com reviews reais vazias/força set)
/// - `?demo_reviews=0` → força estado vazio (sem demo)
/// - localhost / 127.0.0.1 sem param → demo **apenas** se count real == 0
abstract final class HubDemoReviews {
  static const bannerLabel =
      'Dados de demonstração — não são avaliações reais';

  static bool isLocalPreviewHost() {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0';
  }

  /// [queryDemo]: valor cru de `demo_reviews` (pode ser null).
  static bool shouldUse({
    required int realCount,
    String? queryDemo,
  }) {
    final q = (queryDemo ?? '').trim().toLowerCase();
    if (q == '0' || q == 'off' || q == 'false' || q == 'empty') {
      return false;
    }
    if (q == '1' || q == 'on' || q == 'true' || q == 'force') {
      return true;
    }
    if (!isLocalPreviewHost()) return false;
    return realCount == 0;
  }

  static HubReviewsStatsResult get stats {
    final dist = List<int>.filled(5, 0);
    var sum = 0;
    for (final r in all) {
      final s = r.stars.clamp(1, 5);
      dist[5 - s]++;
      sum += s;
    }
    final n = all.length;
    return HubReviewsStatsResult(
      count: n,
      average: n == 0 ? 0 : sum / n,
      distribution: dist,
    );
  }

  static List<HubReview> filtered({
    int? starsFilter,
    String sort = 'newest',
  }) {
    var list = List<HubReview>.from(all);
    if (starsFilter != null) {
      list = list.where((r) => r.stars == starsFilter).toList();
    }
    switch (sort) {
      case 'oldest':
        list.sort((a, b) => (a.createdAt ?? DateTime(2000))
            .compareTo(b.createdAt ?? DateTime(2000)));
      case 'highest':
        list.sort((a, b) {
          final c = b.stars.compareTo(a.stars);
          if (c != 0) return c;
          return (b.createdAt ?? DateTime(2000))
              .compareTo(a.createdAt ?? DateTime(2000));
        });
      case 'lowest':
        list.sort((a, b) {
          final c = a.stars.compareTo(b.stars);
          if (c != 0) return c;
          return (b.createdAt ?? DateTime(2000))
              .compareTo(a.createdAt ?? DateTime(2000));
        });
      case 'newest':
      default:
        list.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
    }
    return list;
  }

  static final List<HubReview> all = [
    HubReview(
      id: 'demo-rev-01',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Ana Sofia M.',
      createdAt: DateTime(2026, 9, 12, 18, 20),
      comment: 'Chegou rapidíssimo e exactamente como na foto. Super recomendo!',
    ),
    HubReview(
      id: 'demo-rev-02',
      targetId: 'demo',
      stars: 4,
      authorDisplay: 'Ricardo P.',
      createdAt: DateTime(2026, 8, 28, 11, 5),
      comment: 'Bom artigo, embalagem cuidada. Só demorou um dia a mais do que esperado.',
    ),
    HubReview(
      id: 'demo-rev-03',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Joana C.',
      createdAt: DateTime(2026, 8, 3, 9, 40),
      comment:
          'Comprei no directo e a vendedora foi impecável: respondeu a tudo, '
          'confirmou medidas e enviou no dia seguinte. O casaco veio com cheiro '
          'a novo e sem qualquer defeito. Voltarei a comprar sem dúvida — '
          'experiência top do início ao fim.',
    ),
    HubReview(
      id: 'demo-rev-04',
      targetId: 'demo',
      stars: 3,
      authorDisplay: 'Miguel T.',
      createdAt: DateTime(2026, 7, 19, 16, 12),
      comment: 'Artigo ok, mas a cor era um pouco diferente da luz do vídeo.',
    ),
    HubReview(
      id: 'demo-rev-05',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Beatriz L.',
      createdAt: DateTime(2026, 7, 2, 20, 55),
      comment: 'Perfeito.',
    ),
    HubReview(
      id: 'demo-rev-06',
      targetId: 'demo',
      stars: 2,
      authorDisplay: 'Carlos N.',
      createdAt: DateTime(2026, 6, 14, 13, 8),
      comment:
          'O tamanho não correspondia à etiqueta descrita no anúncio. '
          'Consegui trocar, mas perdi uma semana. Comunicação foi correcta, '
          'ainda assim fiquei desiludido com a primeira envio.',
    ),
    HubReview(
      id: 'demo-rev-07',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Inês R.',
      createdAt: DateTime(2026, 5, 30, 10, 22),
      comment: 'Adorei o atendimento no live. Peça única!',
    ),
    HubReview(
      id: 'demo-rev-08',
      targetId: 'demo',
      stars: 4,
      authorDisplay: 'Pedro A.',
      createdAt: DateTime(2026, 5, 8, 19, 1),
      comment: 'Muito bom custo-benefício. Embalagem protegida.',
    ),
    HubReview(
      id: 'demo-rev-09',
      targetId: 'demo',
      stars: 1,
      authorDisplay: 'Sofia V.',
      createdAt: DateTime(2026, 4, 22, 8, 45),
      comment:
          'Recebi um artigo com nódoa que não estava mencionada. '
          'Após reclamação houve reembolso parcial, mas a confiança ficou abalada. '
          'Espero que melhorem a descrição das peças usadas.',
    ),
    HubReview(
      id: 'demo-rev-10',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Tiago F.',
      createdAt: DateTime(2026, 3, 17, 15, 30),
      comment: 'Entrega DPD sem stress. 5 estrelas.',
    ),
    HubReview(
      id: 'demo-rev-11',
      targetId: 'demo',
      stars: 4,
      authorDisplay: 'Marta G.',
      createdAt: DateTime(2026, 2, 9, 12, 0),
      comment:
          'Gostei bastante da qualidade. A vendedora avisou do atraso no correio '
          'e manteve-me informada. Só tirei uma estrela pelo prazo alargado.',
    ),
    HubReview(
      id: 'demo-rev-12',
      targetId: 'demo',
      stars: 5,
      authorDisplay: 'Helena Q.',
      createdAt: DateTime(2026, 1, 21, 21, 18),
      comment: 'Como novo. Obrigada!',
    ),
  ];
}
