/// Validação rigorosa de títulos/descrições PT-PT (ZIP 157).
library;

final _foreign = RegExp(
  r'[\u4e00-\u9fff\u3040-\u30ff]|'
  r'\b('
  r'l[aá]mpara|sarten|sartén|hombre|mujer|coj[ií]n|espejo|joyas|limpiadora|'
  r'bandejas|cajones|soporte de|hierro fundido|todas las|disponible|'
  r'padella|uomo|donna|riscaldante|induzione|calentable|contenitiva|'
  r'almacenamiento|powerful|handheld|cleaning|steam cleaner|frying pan'
  r')\b',
  caseSensitive: false,
);

class AmazonCopyAssessment {
  const AmazonCopyAssessment({required this.pass, required this.issues});
  final bool pass;
  final List<String> issues;
}

AmazonCopyAssessment assessCommercialCopyPt({
  required String title,
  required String description,
  required String sourceTitle,
  String? productHint,
}) {
  final issues = <String>[];
  final t = title.trim();
  final d = description.trim();
  final src = sourceTitle.toLowerCase();
  if (t.length < 18) issues.add('título demasiado curto');
  if (t.length > 110) issues.add('título demasiado longo');
  if (RegExp(r'^(de|da|do|o|a)\s*[—\-]').hasMatch(t.toLowerCase())) {
    issues.add('título sem tipo/marca útil');
  }
  if (d.length < 60) issues.add('descrição demasiado curta');
  if (!d.toLowerCase().contains('caracter')) {
    issues.add('falta secção Características');
  }
  for (final bad in ['ASIN:', 'LPN:', 'Preço Amazon', 'direitos pendentes']) {
    if (d.contains(bad) || t.contains(bad)) {
      issues.add('meta interna na ficha pública');
    }
  }
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch('$t$d')) {
    issues.add('caracteres chineses');
  }
  final hits = _foreign.allMatches('$t $d').map((m) => m.group(0)!.toLowerCase()).toSet();
  if (hits.isNotEmpty) {
    issues.add('texto estrangeiro: ${hits.take(6).join(', ')}');
  }
  if (t.toLowerCase().contains('kärcher') &&
      !src.contains('kärcher') &&
      !src.contains('karcher')) {
    issues.add('alucinação Kärcher');
  }
  for (final bad in [
    'confirme dimensões',
    'não incluímos garantias',
    'preço em amazon',
    'disponível em stock',
  ]) {
    if (d.toLowerCase().contains(bad)) {
      issues.add('frase genérica: $bad');
    }
  }
  return AmazonCopyAssessment(pass: issues.isEmpty, issues: issues);
}
