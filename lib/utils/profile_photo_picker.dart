import 'package:flutter/material.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/utils/profile_patch_service.dart';

/// Escolhe foto da galeria, faz upload e grava `profiles.photo_url`.
class ProfilePhotoPicker {
  ProfilePhotoPicker._();

  static Future<String?> pickAndSave(BuildContext context) async {
    if (currentUserUid.isEmpty) return null;
    try {
      final picked = await FleaberGalleryPicker.pickSingleImage(
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return null;

      final bytes = await picked.readAsBytes();
      final name =
          picked.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path =
          'profile_photos/$currentUserUid/${DateTime.now().millisecondsSinceEpoch}_$name';
      final lower = name.toLowerCase();
      var contentType = 'image/jpeg';
      if (lower.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lower.endsWith('.webp')) {
        contentType = 'image/webp';
      } else if (lower.endsWith('.gif')) {
        contentType = 'image/gif';
      } else if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
        contentType = 'image/heic';
      }

      await SupaFlow.client.storage.from('chat_media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );
      final url =
          SupaFlow.client.storage.from('chat_media').getPublicUrl(path);

      final updated = await ProfilePatchService.patchOwnProfile(
        {'photo_url': url},
        select: 'id, photo_url',
      );
      if (updated == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível guardar a foto de perfil.'),
            ),
          );
        }
        return null;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de perfil actualizada.')),
        );
      }
      return url;
    } on FleaberGalleryPickerException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível actualizar a foto: '
              '${ProfilePatchService.friendlyError(e)}',
            ),
          ),
        );
      }
      return null;
    }
  }
}
