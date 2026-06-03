import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_logger.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/seller_staff_gate.dart';

/// Gestão de colaboradores (dono da loja).
class SellerHelpersPageWidget extends StatefulWidget {
  const SellerHelpersPageWidget({super.key});

  static String routeName = 'SellerHelpers';
  static String routePath = '/equipaColaboradores';

  @override
  State<SellerHelpersPageWidget> createState() =>
      _SellerHelpersPageWidgetState();
}

class _SellerHelpersPageWidgetState extends State<SellerHelpersPageWidget> {
  final _repo = SellerStaffRepository();
  final _searchController = TextEditingController();
  String _query = '';
  bool _loading = true;
  List<SellerHelpersRow> _helpers = [];
  List<StaffActionLogsRow> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await SellerStaffContext.instance.refresh();
    final sid = currentUserUid;
    try {
      final helpers = await SellerHelpersTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', sid),
      );
      final logs = await StaffActionLog.forSeller(sid, limit: 30);
      if (!mounted) return;
      setState(() {
        _helpers = helpers;
        _recentLogs = logs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SellerHelpersRow> get _filtered {
    if (_query.isEmpty) return _helpers;
    return _helpers.where((h) {
      final name = (h.displayName ?? '').toLowerCase();
      final hid = (h.helperUserId ?? '').toLowerCase();
      return name.contains(_query) || hid.contains(_query);
    }).toList();
  }

  Future<void> _showInviteSheet() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var perms = SellerStaffPermissions.defaultHelperPermissions();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Convidar colaborador',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A pessoa precisa de conta Fleaber com este e-mail. '
                        'Terá login e sessão próprios.',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _fieldDeco('E-mail da conta Fleaber'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _fieldDeco('Nome na equipa (ex.: Maria — chat)'),
                      ),
                      const SizedBox(height: 16),
                      _PermissionEditor(
                        permissions: perms,
                        onChanged: (p) => setModal(() => perms = p),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: FleaberColors.teal,
                        ),
                        child: const Text('Adicionar colaborador'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;

    final email = emailCtrl.text.trim();
    final displayName = nameCtrl.text.trim();
    emailCtrl.dispose();
    nameCtrl.dispose();

    if (email.isEmpty || displayName.isEmpty) {
      _snack('Preenche e-mail e nome na equipa.');
      return;
    }

    final helperId = await SellerStaffContext.findUserIdByEmail(email);
    if (helperId == null || helperId.isEmpty) {
      _snack(
        'Não encontrámos conta com esse e-mail. '
        'A pessoa deve registar-se primeiro (ou confirma que o SQL helper está aplicado no Supabase).',
      );
      return;
    }
    if (helperId == currentUserUid) {
      _snack('Não podes adicionar-te a ti próprio como colaborador.');
      return;
    }

    try {
      await _repo.inviteHelper(
        sellerId: currentUserUid,
        helperUserId: helperId,
        helperEmail: email,
        displayName: displayName,
        permissions: perms,
      );
      await _load();
      if (mounted) {
        _snack(
          'Colaborador adicionado. Convite pendente até aceitação na app.',
        );
      }
    } catch (e, st) {
      await FleaberLogger.instance.logStaffHelper(
        'invite.ui_fail',
        sellerId: currentUserUid,
        helperUserId: helperId,
        data: {'email': email, 'display_name': displayName},
        error: e,
        stackTrace: st,
      );
      _snack(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Não foi possível adicionar o colaborador.');
    }
  }

  InputDecoration _fieldDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: FleaberRadius.circularMd,
        borderSide: BorderSide.none,
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editHelper(SellerHelpersRow row) async {
    final nameCtrl = TextEditingController(text: row.displayName ?? '');
    var perms = SellerStaffPermissions.fromJson(row.permissionsRaw);
    var active = row.active == true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.displayName ?? 'Colaborador',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _fieldDeco('Nome na equipa'),
                      ),
                      SwitchListTile(
                        value: active,
                        onChanged: (v) => setModal(() => active = v),
                        title: Text(
                          'Conta activa',
                          style: GoogleFonts.inter(color: Colors.white),
                        ),
                        subtitle: Text(
                          'Desactivar bloqueia o acesso sem apagar histórico.',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      _PermissionEditor(
                        permissions: perms,
                        onChanged: (p) => setModal(() => perms = p),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await _repo.updateHelper(
                            row,
                            displayName: nameCtrl.text.trim(),
                            active: active,
                            permissions: perms,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: FleaberColors.teal,
                        ),
                        child: const Text('Guardar'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (d) => AlertDialog(
                              title: const Text('Remover colaborador?'),
                              content: const Text(
                                'Esta pessoa deixa de aceder à tua loja. O histórico mantém-se.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(d, true),
                                  child: const Text(
                                    'Remover',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          await _repo.removeHelper(row);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Remover da equipa',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    await _load();
  }

  Future<void> _showHelperActivity(SellerHelpersRow row) async {
    final logs = await StaffActionLog.forSeller(
      currentUserUid,
      limit: 50,
      helperUserId: row.helperUserId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Actividade — ${row.displayName}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            'Sem acções registadas ainda.',
                            style: GoogleFonts.inter(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: logs.length,
                          itemBuilder: (_, i) {
                            final log = logs[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                log.actionType ?? '—',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${log.targetEntity ?? ''} · ${_formatWhen(log.createdAt)}',
                                style: GoogleFonts.inter(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatWhen(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SellerStaffGate(
      permission: SellerStaffPermissions.canManageHelpers,
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Equipa e colaboradores',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
            fontSize: 17,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showInviteSheet,
        backgroundColor: FleaberColors.teal,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Convidar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                children: [
                  const AccountContextBadge(),
                  const SizedBox(height: 12),
                  Text(
                    'Cada colaborador tem login próprio. Define o que podem fazer na tua loja.',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF57636C),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Procurar colaborador…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: FleaberRadius.circularMd,
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_filtered.isEmpty)
                    _emptyCard()
                  else
                    ..._filtered.map(_helperCard),
                  const SizedBox(height: 20),
                  Text(
                    'Actividade recente da equipa',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._recentLogs.take(12).map(_logTile),
                ],
              ),
            ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
      ),
      child: Text(
        _helpers.isEmpty
            ? 'Ainda não tens colaboradores. Convida alguém da tua equipa de vendas ao vivo.'
            : 'Nenhum resultado para a pesquisa.',
        style: GoogleFonts.inter(color: const Color(0xFF57636C), height: 1.35),
      ),
    );
  }

  Widget _helperCard(SellerHelpersRow row) {
    final active = row.active == true;
    final invitationStatus = row.invitationStatus ?? 'pending';
    final last = row.lastActiveAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: active
              ? FleaberColors.teal.withValues(alpha: 0.35)
              : const Color(0xFFE0E7EA),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: FleaberProfileAvatar(
          userId: row.helperUserId,
          fullName: row.displayName,
          radius: 22,
        ),
        title: Text(
          row.displayName ?? 'Colaborador',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          invitationStatus == 'pending'
              ? 'Convite pendente de aceitação'
              : invitationStatus == 'rejected'
                  ? 'Convite rejeitado'
                  : active
                      ? 'Última actividade: ${_formatWhen(last)}'
                      : 'Desactivado',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFF57636C),
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _editHelper(row);
            if (v == 'activity') _showHelperActivity(row);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Permissões')),
            const PopupMenuItem(value: 'activity', child: Text('Actividade')),
          ],
        ),
        onTap: () => _editHelper(row),
      ),
    );
  }

  Widget _logTile(StaffActionLogsRow log) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              log.actionType ?? '—',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            _formatWhen(log.createdAt),
            style: GoogleFonts.inter(
              fontSize: 10,
              color: const Color(0xFF98A1AA),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionEditor extends StatelessWidget {
  const _PermissionEditor({
    required this.permissions,
    required this.onChanged,
  });

  final Map<String, bool> permissions;
  final ValueChanged<Map<String, bool>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final cat in SellerStaffPermissions.categories) ...[
          Text(
            cat.title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          Text(
            cat.subtitle,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 6),
          for (final key in cat.keys)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: permissions[key] == true,
              onChanged: (v) {
                final next = Map<String, bool>.from(permissions);
                next[key] = v;
                onChanged(next);
              },
              title: Text(
                SellerStaffPermissions.label(key),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
              ),
              subtitle: Text(
                SellerStaffPermissions.description(key),
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
