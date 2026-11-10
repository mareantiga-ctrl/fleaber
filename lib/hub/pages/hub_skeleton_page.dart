import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../routing/hub_handle_resolver.dart';
import '../routing/hub_route_paths.dart';

/// Placeholder Hub — sem UI final; prova routing + resolver.
class HubSkeletonPage extends StatelessWidget {
  const HubSkeletonPage({
    super.key,
    required this.section,
    required this.handle,
    required this.profileId,
  });

  final HubSection section;
  final String handle;
  final String profileId;

  String get _title => switch (section) {
        HubSection.profile => 'Hub Perfil',
        HubSection.live => 'Hub Direto',
        HubSection.shop => 'Hub Marketplace',
        HubSection.reviews => 'Hub Avaliações',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101518),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101518),
        foregroundColor: Colors.white,
        title: Text(
          '@$handle',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Skeleton routing #21 — UI final pendente.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _row('handle', handle),
              _row('profile_id', profileId),
              _row('path', _pathLabel()),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (section != HubSection.profile)
                    OutlinedButton(
                      onPressed: () =>
                          context.go(HubRoutePaths.profileFor(handle)),
                      child: const Text('profile'),
                    ),
                  if (section != HubSection.live)
                    OutlinedButton(
                      onPressed: () =>
                          context.go(HubRoutePaths.liveFor(handle)),
                      child: const Text('live'),
                    ),
                  if (section != HubSection.shop)
                    OutlinedButton(
                      onPressed: () =>
                          context.go(HubRoutePaths.shopFor(handle)),
                      child: const Text('shop'),
                    ),
                  if (section != HubSection.reviews)
                    OutlinedButton(
                      onPressed: () =>
                          context.go(HubRoutePaths.reviewsFor(handle)),
                      child: const Text('reviews'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pathLabel() => switch (section) {
        HubSection.profile => HubRoutePaths.profileFor(handle),
        HubSection.live => HubRoutePaths.liveFor(handle),
        HubSection.shop => HubRoutePaths.shopFor(handle),
        HubSection.reviews => HubRoutePaths.reviewsFor(handle),
      };

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
      ),
    );
  }
}
