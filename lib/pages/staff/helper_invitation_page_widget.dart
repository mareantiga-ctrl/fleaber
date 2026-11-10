import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_navigation.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';

import '/widgets/fleaber_primary_button.dart';

enum _InviteEmptyReason {
  noPending,
  alreadyAccepted,
  alreadyRejected,
  notFound,
}

/// Ecrã dedicado para aceitar/rejeitar convite de colaborador.
class HelperInvitationPageWidget extends StatefulWidget {
  const HelperInvitationPageWidget({super.key, this.helperLinkId});

  static String routeName = 'HelperInvitation';
  static String routePath = '/conviteColaborador';

  final String? helperLinkId;

  @override
  State<HelperInvitationPageWidget> createState() =>
      _HelperInvitationPageWidgetState();
}

class _HelperInvitationPageWidgetState extends State<HelperInvitationPageWidget> {
  bool _loading = true;
  SellerHelpersRow? _invite;
  ProfilesRow? _seller;
  ProfilesRow? _inviter;
  _InviteEmptyReason? _emptyReason;

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    HubNavigation.goAppHome(context);
  }

  Future<void> _openHelperAccess() async {
    if (Navigator.of(context).canPop()) {
      context.pop();
    }
    if (!mounted) return;
    context.pushNamed(HelperAccessPageWidget.routeName);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await SellerStaffContext.instance.refresh();
    final pending = SellerStaffContext.instance.myPendingInvitations;
    SellerHelpersRow? row;
    final wanted = widget.helperLinkId?.trim();
    if (wanted != null && wanted.isNotEmpty) {
      for (final r in pending) {
        if (r.id == wanted) {
          row = r;
          break;
        }
      }
    } else if (pending.isNotEmpty) {
      row = pending.first;
    }

    if (row == null) {
      _InviteEmptyReason reason = _InviteEmptyReason.noPending;
      if (wanted != null && wanted.isNotEmpty) {
        try {
          final rows = await SellerHelpersTable().queryRows(
            queryFn: (q) => q
                .eqOrNull('id', wanted)
                .eqOrNull('helper_user_id', currentUserUid),
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final status = (rows.first.invitationStatus ?? 'pending').trim();
            reason = switch (status) {
              'accepted' => _InviteEmptyReason.alreadyAccepted,
              'rejected' => _InviteEmptyReason.alreadyRejected,
              _ => _InviteEmptyReason.noPending,
            };
          } else {
            reason = _InviteEmptyReason.notFound;
          }
        } catch (_) {
          reason = _InviteEmptyReason.notFound;
        }
      } else if (SellerStaffContext.instance.myHelperLinks.isEmpty) {
        reason = _InviteEmptyReason.noPending;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _invite = null;
        _emptyReason = reason;
      });
      return;
    }

    final sellerId = row.sellerId?.trim();
    final inviterId = row.invitedBy?.trim();
    if (sellerId != null && sellerId.isNotEmpty) {
      final rows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sellerId),
        limit: 1,
      );
      _seller = rows.isEmpty ? null : rows.first;
    }
    if (inviterId != null && inviterId.isNotEmpty) {
      final rows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', inviterId),
        limit: 1,
      );
      _inviter = rows.isEmpty ? null : rows.first;
    }

    if (!mounted) return;
    setState(() {
      _invite = row;
      _emptyReason = null;
      _loading = false;
    });
  }

  Widget _buildEmptyState() {
    final reason = _emptyReason ?? _InviteEmptyReason.noPending;
    final hasHelperAccess =
        SellerStaffContext.instance.myHelperLinks.isNotEmpty;

    final (title, body) = switch (reason) {
      _InviteEmptyReason.alreadyAccepted => (
          'Convite já aceite',
          'Este convite já foi aceite. Podes entrar no painel de colaborador.',
        ),
      _InviteEmptyReason.alreadyRejected => (
          'Convite rejeitado',
          'Este convite já foi rejeitado e já não está activo.',
        ),
      _InviteEmptyReason.notFound => (
          'Convite indisponível',
          'Este convite já não existe ou expirou.',
        ),
      _InviteEmptyReason.noPending => (
          'Sem convites pendentes',
          hasHelperAccess
              ? 'Não tens convites por responder. O teu acesso de colaborador continua disponível.'
              : 'Não tens convites pendentes neste momento.',
        ),
    };

    final showHelperAccess = reason == _InviteEmptyReason.alreadyAccepted ||
        (reason == _InviteEmptyReason.noPending && hasHelperAccess);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            reason == _InviteEmptyReason.alreadyAccepted
                ? Icons.check_circle_outline_rounded
                : Icons.mail_outline_rounded,
            size: 48,
            color: FleaberColors.teal.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101518),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          if (showHelperAccess) ...[
            FleaberPrimaryButton(
              label: 'Acesso de colaborador',
              onPressed: _openHelperAccess,
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton(
            onPressed: _goBack,
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF101518)),
          onPressed: _goBack,
        ),
        title: Text(
          'Convite de colaborador',
          style: GoogleFonts.inter(
            color: const Color(0xFF101518),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invite == null
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: FleaberRadius.circularMd,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _seller?.fullName?.trim().isNotEmpty == true
                                  ? _seller!.fullName!.trim()
                                  : 'Loja Fleaber',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF101518),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Convidado por: ${_inviter?.fullName ?? 'Dono da loja'}',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF57636C),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Função proposta: ${_invite!.displayName}',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF57636C),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Permissões incluídas',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._allowedPermissions(_invite!.permissionsRaw).map(
                              (p) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 16,
                                      color: FleaberColors.teal,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p,
                                        style: GoogleFonts.inter(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _reject,
                              child: const Text('Rejeitar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _accept,
                              style: FilledButton.styleFrom(
                                backgroundColor: FleaberColors.teal,
                              ),
                              child: const Text('Aceitar convite'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  List<String> _allowedPermissions(Map<String, dynamic> raw) {
    final perms = SellerStaffPermissions.fromJson(raw);
    return SellerStaffPermissions.allKeys
        .where((k) => perms[k] == true)
        .map(SellerStaffPermissions.label)
        .toList();
  }

  Future<void> _accept() async {
    final invite = _invite;
    if (invite == null) return;
    await SellerStaffContext.instance.acceptInvitation(invite);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Convite aceite. Podes entrar no directo como colaborador.'),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () {
            // ignore: use_build_context_synchronously
            context.pushNamed(HelperAccessPageWidget.routeName);
          },
        ),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _reject() async {
    final invite = _invite;
    if (invite == null) return;
    await SellerStaffContext.instance.rejectInvitation(invite);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Convite rejeitado.')),
    );
    Navigator.pop(context);
  }
}
