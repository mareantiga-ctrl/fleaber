/// Cliente LLM local (Ollama) para títulos/descrições PT-PT — ZIP 157.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'amazon_copy_validate.dart';

const kDefaultOllamaBase = 'http://127.0.0.1:11434';
const kPreferredOllamaModels = <String>[
  'qwen2.5:7b',
  'qwen3:8b',
  'llama3.2:3b',
];

class AmazonLlmLocalResult {
  const AmazonLlmLocalResult({
    required this.title,
    required this.description,
    required this.model,
    required this.pass,
    required this.issues,
    required this.copyStatus,
    this.attempts = 1,
    this.raw,
  });

  final String title;
  final String description;
  final String model;
  final bool pass;
  final List<String> issues;
  final String copyStatus; // pass | revision_needed
  final int attempts;
  final String? raw;
}

class AmazonLlmLocal {
  AmazonLlmLocal({this.baseUrl = kDefaultOllamaBase, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<bool> isAvailable({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final res =
          await _client.get(Uri.parse('$baseUrl/api/tags')).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> listModels() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/api/tags'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(res.body);
    if (data is! Map) return const [];
    final models = data['models'];
    if (models is! List) return const [];
    return models
        .map((e) => (e is Map ? e['name'] : null)?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<String?> pickModel() async {
    final available = await listModels();
    for (final pref in kPreferredOllamaModels) {
      if (available.contains(pref)) return pref;
    }
    return available.isEmpty ? null : available.first;
  }

  String _hint(String source) {
    final l = source.toLowerCase();
    if (l.contains('steam') || l.contains('vapor') || l.contains('kärcher')) {
      return 'máquina de limpeza a vapor';
    }
    if (l.contains('padella') || l.contains('sartén') || l.contains('moneta')) {
      return 'frigideira';
    }
    if (l.contains('pancera') || l.contains('lombar')) {
      return 'cinta lombar térmica';
    }
    if (l.contains('candle') || l.contains('vela')) return 'vela perfumada';
    if (l.contains('espejo') || l.contains('mirror') || l.contains('grifema')) {
      return 'espelho de maquilhagem';
    }
    if (l.contains('osram') || l.contains('pendant') || l.contains('colgante')) {
      return 'candeeiro de suspensão';
    }
    if (l.contains('cojín') || l.contains('cushion')) return 'almofada para cadeira';
    if (l.contains('rodiller') || l.contains('knee')) {
      return 'joelheiras de compressão';
    }
    if (l.contains('hombro') || l.contains('shoulder')) {
      return 'suporte para ombro';
    }
    if (l.contains('cortina') || l.contains('curtain')) {
      return 'cortina para porta';
    }
    if (l.contains('joyas') || l.contains('jewelry')) {
      return 'organizadores para joias';
    }
    if (l.contains('cestas') || l.contains('basket')) {
      return 'cestos de arrumação';
    }
    if (l.contains('cocotte') || l.contains('creuset')) {
      return 'caçarola de ferro fundido';
    }
    if (l.contains('charleston') || l.contains('velamp')) {
      return 'candeeiro de secretária LED';
    }
    if (l.contains('lamp') || l.contains('candeeiro')) {
      return 'candeeiro de mesa';
    }
    return 'artigo';
  }

  String _glossary(String text) {
    var out = text;
    const pairs = <List<String>>[
      [r'\bpadella\b', 'frigideira'],
      [r'\bsart[eé]n\b', 'frigideira'],
      [r'\bl[aá]mpara\b', 'candeeiro'],
      [r'\bcoj[ií]n\b', 'almofada'],
      [r'\bespejo\b', 'espelho'],
      [r'\bjoyas\b', 'joias'],
      [r'\buomo\b', 'homem'],
      [r'\bdonna\b', 'mulher'],
      [r'\bhombre\b', 'homem'],
      [r'\bmujer\b', 'mulher'],
      [r'\briscaldante\b', 'térmica'],
      [r'\bcalentable\b', 'térmica'],
      [r'\binduzione\b', 'indução'],
      [r'\bpancera\b', 'cinta lombar'],
      [r'\brodilleras\b', 'joelheiras'],
    ];
    for (final p in pairs) {
      out = out.replaceAll(RegExp(p[0], caseSensitive: false), p[1]);
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<AmazonLlmLocalResult> generateCommercialPt({
    required String sourceTitle,
    String? brand,
    String? modelHint,
    String? conditionNote,
    String? amazonPriceNote,
    String? preferredModel,
    int maxAttempts = 3,
  }) async {
    final src = sourceTitle.trim();
    if (src.isEmpty) {
      throw StateError('Sem título de origem — LLM não inventa ficha vazia.');
    }
    final model = preferredModel ?? await pickModel();
    if (model == null) {
      throw StateError('Nenhum modelo Ollama disponível.');
    }
    final hint = _hint(src);
    String? feedback;
    Map<String, dynamic>? lastParsed;
    var attempts = 0;
    List<String> lastIssues = const [];

    for (var i = 1; i <= maxAttempts; i++) {
      attempts = i;
      final prompt = '''
Escreve APENAS JSON UTF-8: {"title":"...","description":"..."}
Português de Portugal. Proibido ES/IT/FR/EN corrido e chinês.
Título OBRIGATÓRIO: Tipo → Marca/modelo → Característica distintiva.
Exemplo: «Candeeiro de Secretária LED Velamp Charleston com Braço Flexível».
Não começes pelo nome da marca sozinho. Não uses títulos genéricos («de — …»).
Tipo de produto em PT: $hint
${feedback == null ? '' : 'Corrigir: $feedback'}
Origem: $src
Marca: ${brand ?? '—'} Modelo: ${modelHint ?? '—'}
Descrição: 2–4 frases comerciais + secção «Características» com factos confirmados.
Sem ASIN/LPN/preços Amazon/direitos. Sem inventar.
''';
      final body = <String, dynamic>{
        'model': model,
        'stream': false,
        'prompt': prompt,
        'format': 'json',
        'think': false,
        'options': {'temperature': 0.2, 'num_predict': 320},
      };
      final res = await _client
          .post(
            Uri.parse('$baseUrl/api/generate'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));
      if (res.statusCode != 200) {
        throw StateError('Ollama HTTP ${res.statusCode}');
      }
      final map = jsonDecode(res.body);
      final raw = (map is Map ? map['response'] : null)?.toString() ?? '';
      lastParsed = _parseJsonObject(raw);
      var title = _glossary((lastParsed['title'] ?? '').toString().trim());
      var description =
          _glossary((lastParsed['description'] ?? '').toString().trim());
      final assessed = assessCommercialCopyPt(
        title: title,
        description: description,
        sourceTitle: src,
        productHint: hint,
      );
      lastIssues = assessed.issues;
      if (assessed.pass) {
        return AmazonLlmLocalResult(
          title: title.length > 100 ? '${title.substring(0, 97)}…' : title,
          description: description,
          model: model,
          pass: true,
          issues: const [],
          copyStatus: 'pass',
          attempts: attempts,
          raw: raw,
        );
      }
      feedback = assessed.issues.join('; ');
    }

    return AmazonLlmLocalResult(
      title: _glossary((lastParsed?['title'] ?? '').toString().trim()),
      description:
          _glossary((lastParsed?['description'] ?? '').toString().trim()),
      model: model,
      pass: false,
      issues: lastIssues,
      copyStatus: 'revision_needed',
      attempts: attempts,
      raw: null,
    );
  }

  Map<String, dynamic> _parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s
          .replaceFirst(RegExp(r'^```(?:json)?'), '')
          .replaceFirst(RegExp(r'```$'), '')
          .trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) s = s.substring(start, end + 1);
    final decoded = jsonDecode(s);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }
}
