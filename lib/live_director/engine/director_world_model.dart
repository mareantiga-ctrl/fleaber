import '/live_director/data/live_director_repository.dart';

/// Estado da live para o Director — poll leve, sem afectar fluxos normais.
class DirectorWorldModel {
  DirectorWorldModel({
    required this.liveId,
    required this.sellerId,
    this.activeItemId,
    this.raffleActive = false,
    this.viewerCount = 0,
    this.stockByItemId = const {},
    this.lastSellerSignalAt,
    this.sellerPresentingManual = false,
    this.sellerAmbiencePaused = false,
  });

  final String liveId;
  final String sellerId;
  final String? activeItemId;
  final bool raffleActive;
  final int viewerCount;
  final Map<String, int> stockByItemId;
  final DateTime? lastSellerSignalAt;
  final bool sellerPresentingManual;
  final bool sellerAmbiencePaused;

  Future<DirectorWorldModel> refresh(LiveDirectorRepository repo) async {
    final live = await repo.getLive(liveId);
    final items = await repo.getLiveItems(liveId);
    String? active;
    final stock = <String, int>{};
    for (final it in items) {
      final id = it['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (it['is_active'] == true) active = id;
      stock[id] = (it['quantity'] as num?)?.toInt() ??
          (it['available_qty'] as num?)?.toInt() ??
          0;
    }
    return DirectorWorldModel(
      liveId: liveId,
      sellerId: sellerId,
      activeItemId: active,
      raffleActive: raffleActive,
      viewerCount: (live?['viewer_count'] as num?)?.toInt() ?? viewerCount,
      stockByItemId: stock,
      lastSellerSignalAt: lastSellerSignalAt,
      sellerPresentingManual: sellerPresentingManual,
      sellerAmbiencePaused: sellerAmbiencePaused,
    );
  }

  DirectorWorldModel copyWith({
    String? activeItemId,
    bool? raffleActive,
    int? viewerCount,
    DateTime? lastSellerSignalAt,
    bool? sellerPresentingManual,
    bool? sellerAmbiencePaused,
  }) =>
      DirectorWorldModel(
        liveId: liveId,
        sellerId: sellerId,
        activeItemId: activeItemId ?? this.activeItemId,
        raffleActive: raffleActive ?? this.raffleActive,
        viewerCount: viewerCount ?? this.viewerCount,
        stockByItemId: stockByItemId,
        lastSellerSignalAt: lastSellerSignalAt ?? this.lastSellerSignalAt,
        sellerPresentingManual:
            sellerPresentingManual ?? this.sellerPresentingManual,
        sellerAmbiencePaused:
            sellerAmbiencePaused ?? this.sellerAmbiencePaused,
      );
}
