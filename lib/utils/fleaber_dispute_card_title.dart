/// Título do card de disputa no chat (APP-072 UX).
///
/// - aberta / respondida_* → «Disputa aberta»
/// - escalada_fleaber (ou turno administração sem resolução) → «Disputa em análise»
/// - resolvida / recusada → «Disputa fechada»
String fleaberDisputeCardTitle({
  required String? status,
  required String? currentTurn,
}) {
  final statusKey = (status ?? '').trim();
  final turn = (currentTurn ?? '').trim();
  final resolved = statusKey == 'resolvida' || statusKey == 'recusada';
  if (resolved) return 'Disputa fechada';
  final escalated = statusKey == 'escalada_fleaber' || turn == 'administracao';
  if (escalated) return 'Disputa em análise';
  return 'Disputa aberta';
}
