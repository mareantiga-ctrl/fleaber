import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import 'dart:typed_data';

/// Uploads sensíveis (provas MB WAY / disputas / media de chat)
/// → bucket privado + URL assinada.
class FleaberPrivateStorage {
  FleaberPrivateStorage._();

  static const bucket = 'fleaber_private';
  /// Chat / provas longas: 7 dias (re-assinar a partir do path).
  static const signedTtlSeconds = 60 * 60 * 24 * 7;
  /// Disputas: TTL curto — signed URL continua válida até exp após DELETE (CDN);
  /// janela pequena + revoke registry no servidor.
  static const signedTtlDisputeSeconds = 60 * 15; // 15 min

  static Future<String> uploadOrderProof({
    required Uint8List bytes,
    required String fileName,
    required String orderId,
  }) async {
    final uid = currentUserUid.trim();
    final oid = orderId.trim();
    if (uid.isEmpty) {
      throw Exception('Sessão em falta para enviar comprovativo.');
    }
    if (oid.isEmpty) {
      throw Exception('Encomenda em falta para enviar comprovativo.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final path =
        'order_proofs/$uid/$oid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await SupaFlow.client.storage.from(bucket).uploadBinary(path, bytes);
    return SupaFlow.client.storage
        .from(bucket)
        .createSignedUrl(path, signedTtlSeconds);
  }

  static Future<String> uploadOrderDisputePhoto({
    required Uint8List bytes,
    required String fileName,
    required String disputeOrOrderId,
    required int index,
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      throw Exception('Sessão em falta para enviar fotos da disputa.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final idSafe = disputeOrOrderId.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final path =
        'order_disputes/$uid/${idSafe}_${DateTime.now().millisecondsSinceEpoch}_${index}_$safe';
    await SupaFlow.client.storage.from(bucket).uploadBinary(path, bytes);
    return SupaFlow.client.storage
        .from(bucket)
        .createSignedUrl(path, signedTtlDisputeSeconds);
  }

  /// Após apagar objecto no storage, regista revoke (proof_ok / higiene).
  static Future<void> revokePrivateObjectPath(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    try {
      await SupaFlow.client.rpc(
        'batata_revoke_private_object',
        params: {'p_path': p},
      );
    } catch (_) {
      /* best-effort */
    }
  }

  /// Media de chat (imagens/vídeos). Path: `chat_uploads/{uid}/{chatId}/…`
  /// (counterpart só lê o chat concreto — não a pasta toda do UID).
  static Future<({String path, String signedUrl})> uploadChatMedia({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
  }) async {
    final uid = currentUserUid.trim();
    final cid = chatId.trim();
    if (uid.isEmpty) {
      throw Exception('Sessão em falta para enviar media.');
    }
    if (cid.isEmpty) {
      throw Exception('Chat em falta para enviar media.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final path =
        'chat_uploads/$uid/$cid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await SupaFlow.client.storage.from(bucket).uploadBinary(path, bytes);
    final signedUrl = await SupaFlow.client.storage
        .from(bucket)
        .createSignedUrl(path, signedTtlSeconds);
    return (path: path, signedUrl: signedUrl);
  }

  /// Extrai `chat_uploads/...` de URL pública antiga ou path já relativo.
  static String? chatUploadPathFromUrl(String? urlOrPath) {
    final raw = (urlOrPath ?? '').trim();
    if (raw.isEmpty) return null;
    final m =
        RegExp(r'chat_uploads/[^\s?#]+', caseSensitive: false).firstMatch(raw);
    final path = m?.group(0);
    if (path == null || path.isEmpty) return null;
    return path.replaceAll(RegExp(r'[,"}\]]+$'), '');
  }

  /// Resolve URL de visualização via URL assinada (bucket privado).
  /// Sem fallback público — ficheiros de chat/provas não são listáveis na web.
  static Future<String> resolveChatImageUrl(String urlOrPath) async {
    final path = chatUploadPathFromUrl(urlOrPath);
    if (path == null) return urlOrPath;
    try {
      return await SupaFlow.client.storage
          .from(bucket)
          .createSignedUrl(path, signedTtlSeconds);
    } catch (_) {
      return urlOrPath;
    }
  }
}
