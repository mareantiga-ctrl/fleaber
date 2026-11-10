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

/// Avatar com overlay de câmara — perfil próprio (tap abre picker).
class FleaberProfileAvatarEditable extends StatelessWidget {
  const FleaberProfileAvatarEditable({
    super.key,
    required this.userId,
    this.fullName,
    this.photoUrl,
    this.radius = 35,
    this.backgroundColor = const Color(0xFFE8F6F6),
    this.borderColor,
    this.borderWidth = 0,
    required this.onTap,
    this.uploading = false,
  });

  final String? userId;
  final String? fullName;
  final String? photoUrl;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: uploading ? null : onTap,
            customBorder: const CircleBorder(),
            child: FleaberProfileAvatar(
              userId: userId,
              fullName: fullName,
              photoUrl: photoUrl,
              radius: radius,
              backgroundColor: backgroundColor,
              borderColor: borderColor,
              borderWidth: borderWidth,
            ),
          ),
        ),
        if (uploading)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black38,
              ),
              child: Center(
                child: SizedBox(
                  width: radius * 0.5,
                  height: radius * 0.5,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Material(
            color: const Color(0xFF007782),
            shape: const CircleBorder(),
            child: Padding(
              padding: EdgeInsets.all(radius * 0.14),
              child: Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: radius * 0.34,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
