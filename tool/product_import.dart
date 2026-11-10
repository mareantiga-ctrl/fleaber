// ignore_for_file: avoid_print
/// Importa artigos para a tabela `products` (mesmas regras que Novo Anúncio).
///
/// Uso:
///   dart run tool/product_import.dart --file tool/product_import.example.json
///   dart run tool/product_import.dart --file artigos.json --execute
///   dart run tool/product_import.dart --clone-id {uuid} --execute
///
/// Credenciais: `tool/live_ops_staging.env` (email/password do vendedor).
/// Por defeito corre em **dry-run** (só valida). `--execute` grava na BD.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'live_ops_staging_client.dart';

const _kCategories = <String>[
  'Roupa e Acessórios',
  'Calçado',
  'Beleza e Cuidados',
  'Casa e Decoração',
  'Eletrónica',
  'Electrodomésticos',
  'Livros e Media',
  'Brinquedos',
  'Desporto e Ar Livre',
  'Colecionáveis',
  'Outra',
];

const _kConditions = <String>[
  'Novo',
  'Muito bom',
  'Bom',
  'Satisfatório',
  'Com Defeito',
];

const _kRoupaCategory = 'Roupa e Acessórios';

const _kClothingSizes = <String>[
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  '3XL',
];

const _kGenders = <String>[
  'Masculino',
  'Feminino',
  'Unissexo',
  'Criança',
];

const _categoryAliases = <String, String>{
  'roupa': 'Roupa e Acessórios',
  'roupa e acessorios': 'Roupa e Acessórios',
  'clothing': 'Roupa e Acessórios',
  'shoes': 'Calçado',
  'calcado': 'Calçado',
  'calçado': 'Calçado',
  'beauty': 'Beleza e Cuidados',
  'home': 'Casa e Decoração',
  'electronics': 'Eletrónica',
  'eletronica': 'Eletrónica',
  'books': 'Livros e Media',
  'toys': 'Brinquedos',
  'sports': 'Desporto e Ar Livre',
  'other': 'Outra',
};

const _conditionAliases = <String, String>{
  'new': 'Novo',
  'novo': 'Novo',
  'like new': 'Muito bom',
  'very good': 'Muito bom',
  'muito bom': 'Muito bom',
  'good': 'Bom',
  'bom': 'Bom',
  'fair': 'Satisfatório',
  'satisfatorio': 'Satisfatório',
  'satisfatório': 'Satisfatório',
  'defect': 'Com Defeito',
  'com defeito': 'Com Defeito',
};

class ImportArticle {
  ImportArticle({
    required this.title,
    required this.price,
    required this.category,
    required this.state,
    required this.description,
    this.clothingSize,
    this.gender,
    this.refCode,
    this.quantity = 1,
    this.listOnMarketplace = true,
    this.availableForLive = false,
    this.photos = const [],
    this.imageUrls = const [],
  });

  final String title;
  final double price;
  final String category;
  final String state;
  final String description;
  final String? clothingSize;
  final String? gender;
  final String? refCode;
  final int quantity;
  final bool listOnMarketplace;
  final bool availableForLive;
  final List<String> photos;
  final List<String> imageUrls;

  Map<String, dynamic> toInsertPayload(String sellerId) => {
        'seller_id': sellerId,
        'title': title,
        'price': price,
        'image_urls': imageUrls,
        'ref_code': refCode,
        'category': category,
        'state': state,
        'description': description.isEmpty ? null : description,
        'clothing_size': category == _kRoupaCategory ? clothingSize : null,
        'gender': category == _kRoupaCategory ? gender : null,
        'list_on_marketplace': listOnMarketplace,
        'available_for_live': availableForLive,
        'quantity': quantity < 1 ? 1 : quantity,
      };
}

String _normKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? _resolveCategory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = raw.trim();
  if (_kCategories.contains(t)) return t;
  return _categoryAliases[_normKey(t)];
}

String? _resolveCondition(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = raw.trim();
  if (_kConditions.contains(t)) return t;
  return _conditionAliases[_normKey(t)];
}

String? _resolveFromList(String? raw, List<String> allowed) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = raw.trim();
  if (allowed.contains(t)) return t;
  for (final a in allowed) {
    if (_normKey(a) == _normKey(t)) return a;
  }
  return null;
}

double? _parsePrice(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  final t = raw.toString().trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll('€', ''));
}

String _normalizeRefForStorage(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  if (t.startsWith('#')) return t;
  if (RegExp(r'^\d+$').hasMatch(t)) {
    return '#${t.padLeft(3, '0')}';
  }
  return '#$t';
}

List<String> validateArticle(ImportArticle a) {
  final missing = <String>[];

  if (!a.listOnMarketplace && !a.availableForLive) {
    missing.add('Ativa list_on_marketplace ou available_for_live');
  }
  if (a.price < 1) {
    missing.add('Preço mínimo 1,00 €');
  }
  if (a.listOnMarketplace) {
    if (a.title.trim().isEmpty) missing.add('Título');
    if (a.category.isEmpty) missing.add('Categoria inválida');
    if (a.state.isEmpty) missing.add('Estado inválido');
    if (a.quantity < 1) missing.add('Quantidade');
    if (a.description.trim().isEmpty) missing.add('Descrição');
    if (a.category == _kRoupaCategory) {
      if (a.clothingSize == null) missing.add('Tamanho (Roupa)');
      if (a.gender == null) missing.add('Género (Roupa)');
    }
  }
  if (a.availableForLive && a.photos.isEmpty && a.imageUrls.isEmpty) {
    missing.add('Pelo menos uma foto (Live)');
  }
  if (a.listOnMarketplace &&
      a.availableForLive &&
      a.photos.isEmpty &&
      a.imageUrls.isEmpty) {
    missing.add('Com Live ativo, adiciona pelo menos uma foto');
  }

  return missing;
}

ImportArticle parseArticleJson(Map<String, dynamic> map, {String? baseDir}) {
  final category = _resolveCategory(map['category']?.toString()) ?? '';
  final state = _resolveCondition(
        map['state']?.toString() ?? map['condition']?.toString(),
      ) ??
      '';

  final price = _parsePrice(map['price']);
  if (price == null) {
    throw FormatException('Preço inválido: ${map['price']}');
  }

  final rawPhotos = map['photos'];
  final photos = <String>[];
  if (rawPhotos is List) {
    for (final item in rawPhotos) {
      final s = item?.toString().trim() ?? '';
      if (s.isEmpty) continue;
      if (s.startsWith('http://') || s.startsWith('https://')) {
        photos.add(s);
      } else {
        final path = p.isAbsolute(s)
            ? s
            : p.normalize(p.join(baseDir ?? '.', s));
        photos.add(path);
      }
    }
  }

  final rawUrls = map['image_urls'];
  final imageUrls = <String>[];
  if (rawUrls is List) {
    for (final item in rawUrls) {
      final s = item?.toString().trim() ?? '';
      if (s.isNotEmpty) imageUrls.add(s);
    }
  }

  var title = map['title']?.toString().trim() ?? '';
  final listOnMarketplace = map['list_on_marketplace'] != false;
  final availableForLive = map['available_for_live'] == true;
  if (title.isEmpty && availableForLive && !listOnMarketplace) {
    final ref = map['ref_code']?.toString().trim() ?? '';
    title = ref.isNotEmpty ? 'Artigo $ref' : 'Artigo Live';
  }

  final refRaw = map['ref_code']?.toString().trim() ?? '';
  final refCode = refRaw.isEmpty ? null : _normalizeRefForStorage(refRaw);

  final qtyRaw = map['quantity'];
  var quantity = 1;
  if (qtyRaw is num) {
    quantity = qtyRaw.toInt();
  } else if (qtyRaw != null) {
    quantity = int.tryParse(qtyRaw.toString()) ?? 1;
  }

  return ImportArticle(
    title: title,
    price: price,
    category: category,
    state: state,
    description: map['description']?.toString().trim() ?? '',
    clothingSize: _resolveFromList(
      map['clothing_size']?.toString(),
      _kClothingSizes,
    ),
    gender: _resolveFromList(map['gender']?.toString(), _kGenders),
    refCode: refCode,
    quantity: quantity,
    listOnMarketplace: listOnMarketplace,
    availableForLive: availableForLive,
    photos: photos,
    imageUrls: imageUrls,
  );
}

ImportArticle articleFromFleaberRow(Map<String, dynamic> row) {
  return ImportArticle(
    title: row['title']?.toString() ?? '',
    price: _parsePrice(row['price']) ?? 0,
    category: row['category']?.toString() ?? '',
    state: row['state']?.toString() ?? row['condition']?.toString() ?? '',
    description: row['description']?.toString() ?? '',
    clothingSize: row['clothing_size']?.toString(),
    gender: row['gender']?.toString(),
    refCode: row['ref_code']?.toString(),
    quantity: (row['quantity'] is num)
        ? (row['quantity'] as num).toInt()
        : int.tryParse('${row['quantity']}') ?? 1,
    listOnMarketplace: row['list_on_marketplace'] != false,
    availableForLive: row['available_for_live'] == true,
    imageUrls: _urlsFromRow(row['image_urls']),
  );
}

List<String> _urlsFromRow(dynamic raw) {
  if (raw is! List) return [];
  return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
}

Future<Uint8List> _loadPhotoBytes(String source) async {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    final res = await http.get(Uri.parse(source));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'Download foto $source → ${res.statusCode}',
      );
    }
    return res.bodyBytes;
  }
  final file = File(source);
  if (!file.existsSync()) {
    throw HttpException('Ficheiro não encontrado: $source');
  }
  return file.readAsBytes();
}

String _contentTypeForFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Future<String> uploadProductPhoto({
  required LiveOpsStagingClient client,
  required String accessToken,
  required String sellerId,
  required Uint8List bytes,
  required String fileName,
  required int index,
}) async {
  final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
  final path =
      'product_photos/$sellerId/${DateTime.now().millisecondsSinceEpoch}_${index}_$safeName';

  final res = await http.post(
    Uri.parse('${client.url}/storage/v1/object/chat_media/$path'),
    headers: {
      'apikey': client.anonKey,
      'Authorization': 'Bearer $accessToken',
      'Content-Type': _contentTypeForFileName(safeName),
      'x-upsert': 'false',
    },
    body: bytes,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException(
      'Upload foto ${res.statusCode}: ${res.body}',
    );
  }
  return '${client.url}/storage/v1/object/public/chat_media/$path';
}

Future<List<String>> resolveImageUrls({
  required LiveOpsStagingClient client,
  required String accessToken,
  required String sellerId,
  required ImportArticle article,
}) async {
  if (article.imageUrls.isNotEmpty) {
    return List<String>.from(article.imageUrls);
  }
  final urls = <String>[];
  for (var i = 0; i < article.photos.length; i++) {
    final source = article.photos[i];
    final bytes = await _loadPhotoBytes(source);
    final name = source.startsWith('http')
        ? 'photo_$i.jpg'
        : p.basename(source);
    final url = await uploadProductPhoto(
      client: client,
      accessToken: accessToken,
      sellerId: sellerId,
      bytes: bytes,
      fileName: name,
      index: i,
    );
    urls.add(url);
  }
  return urls;
}

Future<void> main(List<String> args) async {
  final execute = args.contains('--execute');
  final continueOnError = args.contains('--continue-on-error');

  String? filePath;
  String? cloneId;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--file' && i + 1 < args.length) {
      filePath = args[i + 1];
    }
    if (args[i] == '--clone-id' && i + 1 < args.length) {
      cloneId = args[i + 1];
    }
  }

  if (filePath == null && cloneId == null) {
    print('Uso:');
    print('  dart run tool/product_import.dart --file artigos.json');
    print('  dart run tool/product_import.dart --file artigos.json --execute');
    print('  dart run tool/product_import.dart --clone-id {uuid} --execute');
    exit(64);
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerEmail = envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD');

  print(execute ? 'Modo: EXECUTE (grava na BD)' : 'Modo: DRY-RUN (só valida)');
  print('Login vendedor: $sellerEmail');

  final token = await client.signIn(
    email: sellerEmail,
    password: sellerPassword,
  );
  final sellerId = await client.userIdForAccessToken(token);
  print('Seller ID: $sellerId\n');

  final articles = <ImportArticle>[];

  if (cloneId != null) {
    final rows = await client.selectAsUser(
      'products',
      accessToken: token,
      filter: 'id=eq.$cloneId',
      limit: 1,
    );
    if (rows.isEmpty) {
      print('FAIL: artigo $cloneId não encontrado ou sem permissão.');
      exit(1);
    }
    articles.add(articleFromFleaberRow(rows.first));
    print('Clone de ${rows.first['title']} ($cloneId)\n');
  } else {
    final file = File(filePath!);
    if (!file.existsSync()) {
      print('FAIL: ficheiro não encontrado: ${file.path}');
      exit(1);
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded['articles'] is! List) {
      print('FAIL: JSON inválido — esperado { "articles": [ ... ] }');
      exit(1);
    }
    final baseDir = p.dirname(file.absolute.path);
    for (final item in decoded['articles'] as List) {
      if (item is! Map) continue;
      try {
        articles.add(
          parseArticleJson(
            Map<String, dynamic>.from(item),
            baseDir: baseDir,
          ),
        );
      } catch (e) {
        print('FAIL parse artigo: $e');
        exit(1);
      }
    }
  }

  if (articles.isEmpty) {
    print('Nada para importar.');
    exit(0);
  }

  var ok = 0;
  var fail = 0;

  for (var i = 0; i < articles.length; i++) {
    final n = i + 1;
    final a = articles[i];
    print('--- Artigo $n/${articles.length}: ${a.title.isEmpty ? "(sem título)" : a.title} ---');

    final missing = validateArticle(a);
    if (missing.isNotEmpty) {
      fail++;
      print('  VALIDAÇÃO FAIL: ${missing.join(', ')}');
      if (!continueOnError) exit(1);
      continue;
    }

    for (final photo in a.photos) {
      if (!photo.startsWith('http') && !File(photo).existsSync()) {
        fail++;
        print('  FOTO FAIL: ficheiro não existe: $photo');
        if (!continueOnError) exit(1);
        continue;
      }
    }

    if (!execute) {
      ok++;
      print('  OK (dry-run)');
      print('  Payload: ${jsonEncode(a.toInsertPayload(sellerId))}');
      if (a.photos.isNotEmpty) {
        print('  Fotos locais/URL: ${a.photos.length}');
      }
      continue;
    }

    try {
      final imageUrls = await resolveImageUrls(
        client: client,
        accessToken: token,
        sellerId: sellerId,
        article: a,
      );
      final payload = a.toInsertPayload(sellerId);
      payload['image_urls'] = imageUrls;

      final created = await client.insertAsUser(
        'products',
        payload,
        accessToken: token,
      );
      ok++;
      print('  CRIADO id=${created['id']} ref=${created['ref_code'] ?? '-'}');
    } catch (e) {
      fail++;
      print('  ERRO: $e');
      if (!continueOnError) exit(1);
    }
  }

  print('\nResumo: $ok OK, $fail FAIL (${articles.length} total)');
  exit(fail > 0 ? 1 : 0);
}
