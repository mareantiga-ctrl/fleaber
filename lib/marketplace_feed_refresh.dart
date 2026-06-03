import 'package:flutter/foundation.dart';

/// Incrementado para forçar novo carregamento do feed do marketplace na Home
/// (ex.: após «Vender outro igual» ou ao voltar com [RouteAware]).
final ValueNotifier<int> marketplaceFeedRefreshTick = ValueNotifier<int>(0);

void requestMarketplaceFeedRefresh() {
  marketplaceFeedRefreshTick.value++;
}

/// Força recarga dos diretos na tab «Diretos» da Home.
final ValueNotifier<int> liveFeedRefreshTick = ValueNotifier<int>(0);

void requestLiveFeedRefresh() {
  liveFeedRefreshTick.value++;
}

/// Incrementado para sincronizar corações / contagens na Home após favoritos
/// noutros ecrãs (ex.: detalhes do artigo) ou ao voltar à tab Início.
final ValueNotifier<int> homeFavoritesUiRefreshTick = ValueNotifier<int>(0);

void requestHomeFavoritesUiReload() {
  homeFavoritesUiRefreshTick.value++;
}

/// Força recarga das listas «Minhas Encomendas» após mudanças de estado (chat/checkout).
final ValueNotifier<int> ordersListRefreshTick = ValueNotifier<int>(0);

void requestOrdersListRefresh() {
  ordersListRefreshTick.value++;
}

/// Último ping BATATA (reserva/pagamento no chat) — usado no sininho da Home.
DateTime? lastBatataReservationPingUtc;

void pingBatataReservationForNotificationBell() {
  lastBatataReservationPingUtc = DateTime.now().toUtc();
  notificationBadgeRefreshTick.value++;
}

/// Limpa o ping temporário do sininho (ex.: utilizador abriu notificações).
void clearBatataReservationNotificationBellPing() {
  if (lastBatataReservationPingUtc == null) return;
  lastBatataReservationPingUtc = null;
  notificationBadgeRefreshTick.value++;
}

/// Rebuild do badge de notificações na Home (reconsulta `notifications_view`).
final ValueNotifier<int> notificationBadgeRefreshTick = ValueNotifier<int>(0);

bool batataReservationBellPingActive({
  Duration window = const Duration(minutes: 15),
}) {
  final t = lastBatataReservationPingUtc;
  if (t == null) return false;
  return DateTime.now().toUtc().difference(t) <= window;
}
