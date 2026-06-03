import 'package:flutter/material.dart';
import 'batata_cached_image.dart';

/// Foto de perfil considerada "manual" quando vem do upload no bucket da app.
bool hasUserUploadedProfilePhoto(String? photoUrl) {
  final url = photoUrl?.trim() ?? '';
  if (url.isEmpty) return false;
  return url.contains('/profile_photos/');
}

Widget _avatarFallback({
  required Color backgroundColor,
}) {
  return ColoredBox(
    color: backgroundColor,
    child: const Center(
      child: Icon(
        Icons.person_outline_rounded,
        color: Color(0xFF57636C),
        size: 22,
      ),
    ),
  );
}

class FleaberProfileAvatar extends StatelessWidget {
  const FleaberProfileAvatar({
    super.key,
    required this.userId,
    this.fullName,
    this.photoUrl,
    this.radius = 22,
    this.backgroundColor = const Color(0xFFE8F6F6),
    this.borderColor,
    this.borderWidth = 0,
  });

  final String? userId;
  final String? fullName;
  final String? photoUrl;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final primaryUrl = photoUrl?.trim() ?? '';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: borderColor == null || borderWidth <= 0
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: ClipOval(
        child: primaryUrl.isEmpty
            ? _avatarFallback(backgroundColor: backgroundColor)
            : BatataCachedNetworkImage(
                imageUrl: primaryUrl,
                fit: BoxFit.cover,
                placeholderColor: backgroundColor,
                errorWidget: _avatarFallback(backgroundColor: backgroundColor),
              ),
      ),
    );
  }
}
