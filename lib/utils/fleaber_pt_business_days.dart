/// Espelho Dart da lógica SQL `batata_add_business_days` (ZIP 140/142).
/// Usado em testes unitários — a autoridade em produção é o Postgres.
library;

/// Feriados PT mínimos 2026–2027 (mesma seed da migração).
const Set<String> kFleaberPtHolidayIsoDates = {
  '2026-01-01',
  '2026-04-03',
  '2026-04-05',
  '2026-04-25',
  '2026-05-01',
  '2026-06-10',
  '2026-06-11',
  '2026-08-15',
  '2026-10-05',
  '2026-11-01',
  '2026-12-01',
  '2026-12-08',
  '2026-12-25',
  '2027-01-01',
  '2027-03-26',
  '2027-03-28',
  '2027-04-25',
  '2027-05-01',
  '2027-06-10',
  '2027-08-15',
  '2027-10-05',
  '2027-11-01',
  '2027-12-01',
  '2027-12-08',
  '2027-12-25',
};

bool fleaberIsPtBusinessDay(DateTime dayLocal) {
  final d = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
  // DateTime.weekday: Mon=1 … Sun=7
  if (d.weekday >= 6) return false;
  final iso =
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return !kFleaberPtHolidayIsoDates.contains(iso);
}

/// Adiciona [businessDays] úteis a partir da data civil de [from] (Europe/Lisbon
/// aproximada via DateTime local do teste). Devolve fim do dia (23:59:59 local).
DateTime fleaberAddBusinessDays(DateTime from, int businessDays) {
  if (businessDays <= 0) return from;
  var day = DateTime(from.year, from.month, from.day);
  var left = businessDays;
  var guard = 0;
  while (left > 0) {
    day = day.add(const Duration(days: 1));
    guard++;
    if (guard > 400) {
      throw StateError('fleaberAddBusinessDays_guard');
    }
    if (fleaberIsPtBusinessDay(day)) left--;
  }
  return DateTime(day.year, day.month, day.day, 23, 59, 59);
}

/// Pause/resume: remaining seconds preservados (não reinicia 5 dias).
int fleaberShipClockRemainingSeconds({
  required DateTime shipByAt,
  required DateTime now,
}) {
  final rem = shipByAt.difference(now).inSeconds;
  return rem < 0 ? 0 : rem;
}

DateTime fleaberShipClockResumeAt({
  required int remainingSeconds,
  required DateTime now,
}) {
  return now.add(Duration(seconds: remainingSeconds < 0 ? 0 : remainingSeconds));
}
