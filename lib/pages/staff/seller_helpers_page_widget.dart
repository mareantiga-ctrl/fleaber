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
  const SellerHelpersPageWidget({super.key, this.embedded = false});

  final bool embedded;

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

  bool _inviteOpen = false;
  TextEditingController? _inviteEmailCtrl;
  TextEditingController? _inviteNameCtrl;
  Map<String, bool> _invitePerms =
      SellerStaffPermissions.defaultHelperPermissions();
  bool _inviteSubmitting = false;

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
    _inviteEmailCtrl?.dispose();
    _inviteNameCtrl?.dispose();
    super.dispose();
  }

  void _openInvite() {
    if (widget.embedded) {
      _inviteEmailCtrl?.dispose();
      _inviteNameCtrl?.dispose();
      _inviteEmailCtrl = TextEditingController();
      _inviteNameCtrl = TextEditingController();
      setState(() {
        _inviteOpen = true;
        _invitePerms = SellerStaffPermissions.defaultHelperPermissions();
        _inviteSubmitting = false;
      });
      return;
    }
    unawaited(_showInviteSheet());
  }

  void _closeInvitePane() {
    setState(() => _inviteOpen = false);
    _inviteEmailCtrl?.dispose();
    _inviteNameCtrl?.dispose();
    _inviteEmailCtrl = null;
    _inviteNameCtrl = null;
  }

  Future<void> _submitInvitePane() async {
    final email = _inviteEmailCtrl?.text.trim() ?? '';
    final displayName = _inviteNameCtrl?.text.trim() ?? '';
    if (email.isEmpty || displayName.isEmpty) {
      _snack('Preenche e-mail e nome na equipa.');
      return;
    }
    setState(() => _inviteSubmitting = true);
    try {
      await _repo.inviteHelperByEmail(
        helperEmail: email,
        displayName: displayName,
        permissions: _invitePerms,
      );
      await _load();
      if (!mounted) return;
      _closeInvitePane();
      _snack(
        'Se existir conta Fleaber com esse e-mail, o convite foi enviado. '
        'A pessoa tem de aceitar na app.',
      );
    } catch (e, st) {
      await FleaberLogger.instance.logStaffHelper(
        'invite.ui_fail',
        sellerId: currentUserUid,
        data: {'email': email, 'display_name': displayName},
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _inviteSubmitting = false);
        _snack(
          e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Não foi possível adicionar o colaborador.',
        );
      }
    }
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
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
                        lightChrome: false,
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

    try {
      await _repo.inviteHelperByEmail(
        helperEmail: email,
        displayName: displayName,
        permissions: perms,
      );
      await _load();
      if (mounted) {
        _snack(
          'Se existir conta Fleaber com esse e-mail, o convite foi enviado. '
          'A pessoa tem de aceitar na app.',
        );
      }
    } catch (e, st) {
      await FleaberLogger.instance.logStaffHelper(
        'invite.ui_fail',
        sellerId: currentUserUid,
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
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
                        lightChrome: false,
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
                    'Atividade — ${row.displayName}',
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

  Widget _buildInvitePane() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _inviteSubmitting ? null : _closeInvitePane,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Voltar à equipa'),
            style: TextButton.styleFrom(foregroundColor: FleaberColors.teal),
          ),
        ),
        Text(
          'Convidar colaborador',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: const Color(0xFF101518),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A pessoa precisa de conta Fleaber com este e-mail. '
          'Terá login e sessão próprios.',
          style: GoogleFonts.inter(
            color: const Color(0xFF57636C),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _inviteEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'E-mail da conta Fleaber',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: FleaberRadius.circularMd,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _inviteNameCtrl,
          decoration: InputDecoration(
            labelText: 'Nome na equipa (ex.: Maria — chat)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: FleaberRadius.circularMd,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PermissionEditor(
          permissions: _invitePerms,
          onChanged: (p) => setState(() => _invitePerms = p),
          lightChrome: true,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _inviteSubmitting ? null : _submitInvitePane,
            style: FilledButton.styleFrom(
              backgroundColor: FleaberColors.teal,
              minimumSize: const Size(220, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _inviteSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Adicionar colaborador'),
          ),
        ),
      ],
    );
  }

  Widget _buildPage(BuildContext context) {
    const bg = Color(0xFFF3F6F7);
    if (widget.embedded && _inviteOpen) {
      return ColoredBox(color: bg, child: _buildInvitePane());
    }
    final inviteFab = FloatingActionButton.extended(
      onPressed: _openInvite,
      backgroundColor: FleaberColors.teal,
      icon: const Icon(Icons.person_add_outlined),
      label: const Text('Convidar'),
    );
    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  widget.embedded ? 24 : 88,
                ),
                children: [
                  const AccountContextBadge(),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, c) {
                      final inviteBtn = widget.embedded
                          ? FilledButton.icon(
                              onPressed: _openInvite,
                              style: FilledButton.styleFrom(
                                backgroundColor: FleaberColors.teal,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.person_add_outlined,
                                size: 18,
                              ),
                              label: const Text('Convidar'),
                            )
                          : const SizedBox.shrink();
                      final blurb = Text(
                        'Cada colaborador tem login próprio. Define o que podem fazer na tua loja.',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF57636C),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      );
                      if (!widget.embedded || c.maxWidth < 420) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            blurb,
                            if (widget.embedded) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: inviteBtn,
                              ),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: blurb),
                          const SizedBox(width: 12),
                          inviteBtn,
                        ],
                      );
                    },
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
                    'Atividade recente da equipa',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_recentLogs.isEmpty)
                    Text(
                      'Ainda não há atividade registada.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF57636C),
                        fontSize: 13,
                      ),
                    )
                  else
                    ..._recentLogs.take(12).map(_logTile),
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
          'Equipa e colaboradores',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
            fontSize: 17,
          ),
        ),
      ),
      floatingActionButton: inviteFab,
      body: body,
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
            const PopupMenuItem(value: 'activity', child: Text('Atividade')),
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
    this.lightChrome = false,
  });

  final Map<String, bool> permissions;
  final ValueChanged<Map<String, bool>> onChanged;
  final bool lightChrome;

  @override
  Widget build(BuildContext context) {
    final titleColor = lightChrome ? const Color(0xFF101518) : Colors.white;
    final subColor = lightChrome ? const Color(0xFF57636C) : Colors.white54;
    final descColor = lightChrome ? const Color(0xFF8A9399) : Colors.white38;
    final sensitive = {
      SellerStaffPermissions.canManagePayouts,
      SellerStaffPermissions.canIssueRefunds,
      SellerStaffPermissions.canManageHelpers,
      SellerStaffPermissions.canEditStoreProfile,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final cat in SellerStaffPermissions.categories) ...[
          Text(
            cat.title,
            style: GoogleFonts.inter(
              color: titleColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          Text(
            cat.subtitle,
            style: GoogleFonts.inter(color: subColor, fontSize: 10),
          ),
          const SizedBox(height: 6),
          for (final key in cat.keys)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: sensitive.contains(key) && lightChrome
                  ? BoxDecoration(
                      color: const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFE0A3)),
                    )
                  : null,
              padding: sensitive.contains(key) && lightChrome
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                  : EdgeInsets.zero,
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FleaberColors.teal,
                value: permissions[key] == true,
                onChanged: (v) {
                  final next = Map<String, bool>.from(permissions);
                  next[key] = v;
                  onChanged(next);
                },
                title: Text(
                  SellerStaffPermissions.label(key),
                  style: GoogleFonts.inter(color: titleColor, fontSize: 12),
                ),
                subtitle: Text(
                  SellerStaffPermissions.description(key),
                  style: GoogleFonts.inter(color: descColor, fontSize: 10),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
