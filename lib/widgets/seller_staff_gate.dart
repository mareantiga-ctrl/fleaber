import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';

/// Bloqueia conteúdo se o colaborador não tiver permissão (UI + mensagem).
class SellerStaffGate extends StatelessWidget {
  const SellerStaffGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.sellerId,
  });

  final String permission;
  final Widget child;
  final Widget? fallback;
  final String? sellerId;

  @override
  Widget build(BuildContext context) {
    final ctx = SellerStaffContext.instance;
    final allowed = ctx.isOwnerContext || ctx.can(permission);
    if (allowed) return child;
    return fallback ??
        _DeniedPanel(
          message:
              'Não tens permissão para: ${SellerStaffPermissions.label(permission)}.',
        );
  }
}

class SellerStaffDeniedPage extends StatelessWidget {
  const SellerStaffDeniedPage({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Acesso restrito',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
          ),
        ),
      ),
      body: _DeniedPanel(message: message),
    );
  }
}

class _DeniedPanel extends StatelessWidget {
  const _DeniedPanel({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              message ??
                  'O dono da loja não te deu acesso a esta área.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF57636C),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
