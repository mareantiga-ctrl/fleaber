import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Galeria com permissões Android/iOS e fallback para dispositivos (ex. Xiaomi/Redmi).
class FleaberGalleryPicker {
  FleaberGalleryPicker._();

  static final ImagePicker _picker = ImagePicker();

  static Future<bool> ensureAccess() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    var status = await Permission.photos.status;
    if (status.isGranted || status.isLimited) return true;

    status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;

    if (Platform.isAndroid) {
      final storage = await Permission.storage.status;
      if (storage.isGranted) return true;
      final storageReq = await Permission.storage.request();
      if (storageReq.isGranted) return true;
    }

    return false;
  }

  static Future<bool> ensureCameraAccess() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) return true;

    status = await Permission.camera.request();
    return status.isGranted || status.isLimited;
  }

  static const _allowedImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
    '.gif',
    '.bmp',
  };

  static bool isAllowedImageFile(XFile file) {
    final name = file.name.trim().toLowerCase();
    final path = file.path.trim().toLowerCase();
    for (final ext in _allowedImageExtensions) {
      if (name.endsWith(ext) || path.endsWith(ext)) return true;
    }
    // Web: blobs sem extensão — confiar no MIME do browser.
    final mime = (file.mimeType ?? '').trim().toLowerCase();
    if (mime.startsWith('image/')) return true;
    return false;
  }

  /// Uma imagem (perfil, etc.) — tenta formatos mais comuns em Android/iOS.
  static Future<XFile?> pickSingleImage({
    int imageQuality = 85,
    double? maxWidth = 1200,
  }) async {
    final allowed = await ensureAccess();
    if (!allowed) {
      throw const FleaberGalleryPickerException(
        'Permissão de fotos negada. Activa o acesso à galeria nas definições do telemóvel.',
      );
    }

    Future<XFile?> tryPickMedia() async {
      try {
        return await _picker.pickMedia(
          imageQuality: imageQuality,
        );
      } catch (_) {
        return null;
      }
    }

    Future<XFile?> tryPickImage() async {
      try {
        return await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
        );
      } catch (_) {
        return null;
      }
    }

    XFile? picked = await tryPickMedia();
    picked ??= await tryPickImage();
    if (picked == null) return null;
    if (!isAllowedImageFile(picked)) {
      throw const FleaberGalleryPickerException(
        'Formato não suportado. Usa JPG, PNG, WEBP ou HEIC.',
      );
    }
    return picked;
  }

  /// Uma foto tirada com a câmara (sem exigir guardar na galeria do utilizador).
  static Future<XFile?> pickCameraImage({
    int imageQuality = 82,
    double? maxWidth = 1800,
  }) async {
    final allowed = await ensureCameraAccess();
    if (!allowed) {
      throw const FleaberGalleryPickerException(
        'Permissão da câmara negada. Activa o acesso nas definições do telemóvel.',
      );
    }
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
      );
    } catch (_) {
      return null;
    }
    if (picked == null) return null;
    return picked;
  }

  /// Até [limit] imagens da galeria. Devolve lista vazia se o utilizador cancelar.
  static Future<List<XFile>> pickImages({
    required int limit,
    int imageQuality = 82,
    double? maxWidth = 1600,
  }) async {
    if (limit <= 0) return const [];

    final allowed = await ensureAccess();
    if (!allowed) {
      throw const FleaberGalleryPickerException(
        'Permissão de fotos negada. Activa o acesso à galeria nas definições do telemóvel.',
      );
    }

    List<XFile> _filterAllowed(Iterable<XFile> files) {
      return files.where(isAllowedImageFile).take(limit).toList();
    }

    try {
      final multi = await _picker.pickMultiImage(
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        limit: limit,
      );
      if (multi.isNotEmpty) {
        final ok = _filterAllowed(multi);
        if (ok.isNotEmpty) return ok;
        throw const FleaberGalleryPickerException(
          'Formato não suportado. Usa JPG, PNG, WEBP ou HEIC.',
        );
      }
    } catch (e) {
      if (e is FleaberGalleryPickerException) rethrow;
      // pickMultiImage falha em alguns Android (MIUI / Redmi).
    }

    // Fallback: abre a galeria repetidamente até cancelar ou atingir o limite.
    final batch = <XFile>[];
    var rejected = 0;
    while (batch.length < limit) {
      XFile? one;
      try {
        one = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
        );
      } catch (_) {
        break;
      }
      if (one == null) break;
      if (isAllowedImageFile(one)) {
        batch.add(one);
      } else {
        rejected++;
      }
    }
    if (batch.isEmpty && rejected > 0) {
      throw const FleaberGalleryPickerException(
        'Formato não suportado. Usa JPG, PNG, WEBP ou HEIC.',
      );
    }
    return batch;
  }
}

class FleaberGalleryPickerException implements Exception {
  const FleaberGalleryPickerException(this.message);
  final String message;

  @override
  String toString() => message;
}
