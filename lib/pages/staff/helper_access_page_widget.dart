import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_account_routes.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/pages/staff/helper_access_copy.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/profile_avatar.dart';

/// Painel do colaborador: permissões, loja e atalhos operacionais.
class HelperAccessPageWidget extends StatefulWidget {
  const HelperAccessPageWidget({super.key, this.embedded = false});

  final bool embedded;

  static String routeName = 'HelperAccess';
  static String routePath = '/acessoColaborador';

  @override
  State<HelperAccessPageWidget> createState() => _HelperAccessPageWidgetState();
}

class _HelperAccessPageWidgetState extends State<HelperAccessPageWidget> {
  ProfilesRow? _sellerProfile;
  LivesRow? _activeLive;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await SellerStaffContext.instance.refresh();
    final staff = SellerStaffContext.instance;
    final sid = staff.effectiveSellerId;
    LivesRow? activeLive;
    if (staff.can(SellerStaffPermissions.canViewLiveDashboard)) {
      if (staff.actingAsHelper) {
        activeLive =
            await SellerStaffContext.findActiveLiveForSeller(sid);
      } else {
        for (final link in staff.myHelperLinks) {
          final storeId = link.sellerId?.trim() ?? '';
          if (storeId.isEmpty) continue;
          activeLive =
              await SellerStaffContext.findActiveLiveForSeller(storeId);
          if (activeLive != null) break;
        }
      }
    }
    try {
      final profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sid),
        limit: 1,
      );
      if (!mounted) return;
      setState(() {
        _sellerProfile = profiles.isEmpty ? null : profiles.first;
        _activeLive = activeLive;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeLive = activeLive;
          _loading = false;
        });
      }
    }
  }

  Future<void> _enterHelperLive({String? liveId}) async {
    final staff = SellerStaffContext.instance;
    if (!staff.can(SellerStaffPermissions.canViewLiveDashboard)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não tens permissão para entrar no painel do directo.',
          ),
        ),
      );
      return;
    }

    if (!staff.actingAsHelper && staff.myHelperLinks.length == 1) {
      await staff.switchToHelperSeller(staff.myHelperLinks.first);
    } else if (!staff.actingAsHelper && liveId != null && liveId.trim().isNotEmpty) {
      final live = await SellerStaffContext.findLiveById(liveId);
      final storeId = live?.sellerId?.trim() ?? '';
      if (storeId.isNotEmpty) {
        for (final link in staff.myHelperLinks) {
          if (link.sellerId == storeId) {
            await staff.switchToHelperSeller(link);
            break;
          }
        }
      }
    } else if (!staff.actingAsHelper && staff.myHelperLinks.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona primeiro a loja em «Contas associadas».',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    context.pushNamed(
      HelperLiveOpsPageWidget.routeName,
      queryParameters: {
        if (liveId != null && liveId.trim().isNotEmpty)
          'liveId': serializeParam(liveId.trim(), ParamType.String),
      }.withoutNulls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = SellerStaffContext.instance;
    final sellerName = _sellerProfile?.fullName?.trim().isNotEmpty == true
        ? _sellerProfile!.fullName!
        : 'Loja';

    const bg = Color(0xFFF3F6F7);
    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const AccountContextBadge(),
                  const SizedBox(height: 12),
                  if (_activeLive != null &&
                      staff.can(SellerStaffPermissions.canViewLiveDashboard))
                    _activeLiveBanner(staff, _activeLive!),
                  if (_activeLive != null &&
                      staff.can(SellerStaffPermissions.canViewLiveDashboard))
                    const SizedBox(height: 12),
                  _storeCard(staff, sellerName),
                  const SizedBox(height: 16),
                  if (staff.myPendingInvitations.isNotEmpty) ...[
                    Text(
                      'Convites pendentes',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...staff.myPendingInvitations
                        .map((invite) => _pendingInvitationCard(staff, invite)),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Contas associadas',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (staff.myHelperLinks.length > 1) ...[
                    ...staff.myHelperLinks.map((link) {
                      final selected =
                          link.sellerId == staff.effectiveSellerId;
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                        title: Text(link.displayName ?? 'Loja'),
                        trailing: selected
                            ? Icon(Icons.check_circle,
                                color: FleaberColors.teal)
                            : null,
                        subtitle: Text(
                          selected
                              ? 'Contexto ativo'
                              : 'Toque para operar nesta loja',
                          style: GoogleFonts.inter(fontSize: 11),
                        ),
                        onTap: () => _confirmSwitchContext(staff, link),
                      );
                    }),
                  ] else if (staff.myHelperLinks.isEmpty) ...[
                    Text(
                      HelperAccessCopy.associatedEmpty(
                        isOwnerContext: staff.isOwnerContext,
                      ),
                      style: GoogleFonts.inter(
                        color: const Color(0xFF57636C),
                        fontSize: 12,
                      ),
                    ),
                  ] else ...[
                    ListTile(
                      tileColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: FleaberRadius.circularMd,
                      ),
                      title: Text(staff.myHelperLinks.first.displayName ?? 'Loja'),
                      subtitle: Text(
                        'Única loja disponível',
                        style: GoogleFonts.inter(fontSize: 11),
                      ),
                      trailing:
                          Icon(Icons.check_circle, color: FleaberColors.teal),
                      onTap: () => _confirmSwitchContext(
                        staff,
                        staff.myHelperLinks.first,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'O que podes fazer',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._permissionSummary(staff),
                  const SizedBox(height: 16),
                  Text(
                    'Atalhos operacionais',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._shortcuts(context, staff),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      await staff.switchToOwnStore();
                      if (!context.mounted) return;
                      context.pushNamed(PerfilWidget.routeName);
                    },
                    child: const Text('Voltar à minha loja pessoal'),
                  ),
                ],
              ),
            );
    if (widget.embedded) {
      return ColoredBox(color: bg, child: body);
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Acesso de colaborador',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
            fontSize: 17,
          ),
        ),
      ),
      body: body,
    );
  }

  Future<void> _confirmSwitchContext(
    SellerStaffContext staff,
    SellerHelpersRow link,
  ) async {
    final nextLabel = link.displayName?.trim().isNotEmpty == true
        ? link.displayName!.trim()
        : 'Loja assistida';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar de contexto?'),
        content: Text(
          'Vais operar como: $nextLabel.\n'
          'As próximas alterações (anúncios, encomendas, reservas) serão nesta loja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await staff.switchToHelperSeller(link);
    await _load();
  }

  Widget _pendingInvitationCard(
    SellerStaffContext staff,
    SellerHelpersRow invite,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFFFE7B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invite.displayName?.trim().isNotEmpty == true
                ? invite.displayName!.trim()
                : 'Convite para colaborar',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Permissões: ${_permissionPreview(invite.permissionsRaw)}',
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    context.pushNamed(
                      HelperInvitationPageWidget.routeName,
                      queryParameters: {
                        'helperLinkId': serializeParam(
                          invite.id,
                          ParamType.String,
                        ),
                      }.withoutNulls,
                    );
                  },
                  child: const Text('Ver detalhes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await staff.rejectInvitation(invite);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Convite rejeitado.')),
                    );
                    await _load();
                  },
                  child: const Text('Rejeitar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    await staff.acceptInvitation(invite);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Convite aceite. Contexto disponível.'),
                      ),
                    );
                    await _load();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: FleaberColors.teal,
                  ),
                  child: const Text('Aceitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _permissionPreview(Map<String, dynamic> raw) {
    final perms = SellerStaffPermissions.fromJson(raw);
    final allowed = SellerStaffPermissions.allKeys
        .where((k) => perms[k] == true)
        .map(SellerStaffPermissions.label)
        .take(3)
        .join(' · ');
    return allowed.isEmpty ? 'Sem permissões' : allowed;
  }

  Widget _activeLiveBanner(SellerStaffContext staff, LivesRow live) {
    final title = (live.title ?? '').trim().isNotEmpty
        ? live.title!.trim()
        : 'Directo em curso';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101518),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FleaberColors.danger,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A loja está em directo. Entra no painel operacional como colaborador.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          FleaberPrimaryButton(
            label: 'Entrar no directo (colaborador)',
            onPressed: () => unawaited(
              _enterHelperLive(liveId: live.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeCard(SellerStaffContext staff, String sellerName) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          FleaberProfileAvatar(
            userId: _sellerProfile?.id,
            fullName: sellerName,
            photoUrl: _sellerProfile?.photoUrl,
            radius: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HelperAccessCopy.storeEyebrow(
                    isOwnerContext: staff.isOwnerContext,
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF57636C),
                  ),
                ),
                Text(
                  sellerName,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (staff.isOwnerContext)
                  Text(
                    HelperAccessCopy.storeOwnerHint(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF57636C),
                      height: 1.35,
                    ),
                  )
                else if (staff.activeHelperRow?.displayName?.isNotEmpty == true)
                  Text(
                    'O teu papel: ${staff.activeHelperRow!.displayName}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: FleaberColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _permissionSummary(SellerStaffContext staff) {
    if (staff.isOwnerContext) {
      return [
        _infoBlock(
          HelperAccessCopy.ownerPermissionsTitle(),
          HelperAccessCopy.ownerPermissionsBody(),
          '',
          const Color(0xFFE8F7F8),
        ),
      ];
    }
    final allowed = <String>[];
    final denied = <String>[];
    for (final k in SellerStaffPermissions.allKeys) {
      if (staff.can(k)) {
        allowed.add(SellerStaffPermissions.label(k));
      } else {
        denied.add(SellerStaffPermissions.label(k));
      }
    }
    return [
      _infoBlock(
        'Permitido (${allowed.length})',
        allowed.take(8).join(' · '),
        allowed.length > 8 ? '… e mais ${allowed.length - 8}' : '',
        const Color(0xFFE8F7F8),
      ),
      const SizedBox(height: 8),
      _infoBlock(
        'Sem acesso (${denied.length})',
        denied.take(6).join(' · '),
        denied.length > 6
            ? 'Contacta o dono da loja se precisares de mais permissões.'
            : '',
        const Color(0xFFF5F5F5),
      ),
    ];
  }

  Widget _infoBlock(
    String title,
    String body,
    String footer,
    Color bg,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: FleaberRadius.circularMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            body.isEmpty ? '—' : body,
            style: GoogleFonts.inter(fontSize: 11, height: 1.35),
          ),
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              footer,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: const Color(0xFF57636C),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _shortcuts(BuildContext context, SellerStaffContext staff) {
    final items = <({String label, IconData icon, VoidCallback? onTap})>[];

    if (staff.can(SellerStaffPermissions.canViewLiveDashboard)) {
      items.add((
        label: _activeLive != null
            ? 'Entrar no directo (colaborador)'
            : 'Painel do directo (quando houver LIVE)',
        icon: Icons.live_tv_rounded,
        onTap: staff.myHelperLinks.isEmpty
            ? null
            : () => unawaited(_enterHelperLive(liveId: _activeLive?.id)),
      ));
    }
    if (staff.can(SellerStaffPermissions.canManageOrders)) {
      items.add((
        label: 'Encomendas da loja',
        icon: Icons.receipt_long_outlined,
        onTap: () => HubAccountRoutes.openEncomendas(context),
      ));
    }
    if (staff.can(SellerStaffPermissions.canReplyCustomers)) {
      items.add((
        label: 'Mensagens',
        icon: Icons.chat_bubble_outline_rounded,
        onTap: () => context.pushNamed(ListaConversasWidget.routeName),
      ));
    }
    if (staff.can(SellerStaffPermissions.canCreateProducts) ||
        staff.can(SellerStaffPermissions.canEditProducts)) {
      items.add((
        label: 'Anúncios',
        icon: Icons.inventory_2_outlined,
        onTap: () => context.pushNamed(SellerProductFormWidget.routeName),
      ));
    }

    if (items.isEmpty) {
      return [
        Text(
          'Sem atalhos — pede ao dono da loja permissões operacionais.',
          style: GoogleFonts.inter(color: const Color(0xFF57636C), fontSize: 12),
        ),
      ];
    }

    return items
        .map(
          (e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: FleaberRadius.circularMd,
            ),
            child: ListTile(
              leading: Icon(
                e.icon,
                color: e.onTap == null ? Colors.grey : FleaberColors.teal,
              ),
              title: Text(
                e.label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: e.onTap == null
                      ? const Color(0xFF98A1AA)
                      : const Color(0xFF101518),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: e.onTap,
            ),
          ),
        )
        .toList();
  }
}
