import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';
import '/utils/seller_staff_permissions.dart';

/// Contexto de loja: dono da conta ou colaborador com permissões.
class SellerStaffContext extends ChangeNotifier {
  SellerStaffContext._();
  static final SellerStaffContext instance = SellerStaffContext._();

  bool _loading = false;
  bool get loading => _loading;

  /// A trabalhar como colaborador (não na própria loja).
  bool actingAsHelper = false;

  /// ID da loja em que opera (dono = [currentUserUid]).
  String? activeSellerId;

  SellerHelpersRow? activeHelperRow;
  List<SellerHelpersRow> myHelperLinks = [];
  List<SellerHelpersRow> myPendingInvitations = [];
  List<SellerHelpersRow> myTeamHelpers = [];

  Map<String, bool> permissions =
      SellerStaffPermissions.ownerFullPermissions();

  String get effectiveSellerId {
    final sid = activeSellerId?.trim();
    if (sid != null && sid.isNotEmpty) return sid;
    return currentUserUid;
  }

  bool get isOwnerContext {
    // Sem UID (race web / sessão a restaurar) → não assumir dono.
    if (currentUserUid.isEmpty) return false;
    return !actingAsHelper || effectiveSellerId == currentUserUid;
  }

  String get contextLabel {
    if (isOwnerContext) return 'Modo pessoal';
    return activeHelperRow?.displayName?.trim().isNotEmpty == true
        ? activeHelperRow!.displayName!.trim()
        : 'Loja assistida';
  }

  /// Directo activo da loja (status live + is_active).
  static Future<LivesRow?> findActiveLiveForSeller(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return null;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sid)
            .eqOrNull('status', 'live')
            .eqOrNull('is_active', true)
            .order('created_at', ascending: false),
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('[SellerStaff] findActiveLiveForSeller: $e');
      return null;
    }
  }

  static Future<LivesRow?> findLiveById(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('[SellerStaff] findLiveById: $e');
      return null;
    }
  }

  Future<void> refresh() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      _reset();
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final links = await SellerHelpersTable().queryRows(
        queryFn: (q) => q.eqOrNull('helper_user_id', uid),
      );
      final team = await SellerHelpersTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', uid),
      );

      myPendingInvitations = links
          .where((h) => (h.invitationStatus ?? 'pending') == 'pending')
          .toList();
      myHelperLinks = links
          .where((h) => (h.invitationStatus ?? 'pending') == 'accepted')
          .toList();
      myTeamHelpers = team;

      final persisted = await _readPersistedSellerId();
      SellerHelpersRow? pick;

      // Persistido = loja pessoal → não voltar a auto-seleccionar loja assistida.
      if (persisted != null && persisted == uid) {
        pick = null;
      } else if (persisted != null) {
        for (final h in myHelperLinks) {
          if (h.sellerId == persisted) {
            pick = h;
            break;
          }
        }
      } else if (myHelperLinks.isNotEmpty) {
        pick = myHelperLinks.first;
      }

      if (pick != null && pick.sellerId != uid) {
        actingAsHelper = true;
        activeSellerId = pick.sellerId;
        activeHelperRow = pick;
        permissions = SellerStaffPermissions.fromJson(pick.permissionsRaw);
        await _pingActive(pick.sellerId!);
      } else {
        actingAsHelper = false;
        activeSellerId = uid;
        activeHelperRow = null;
        permissions = SellerStaffPermissions.ownerFullPermissions();
      }
    } catch (e) {
      debugPrint('[SellerStaff] refresh failed: $e');
      actingAsHelper = false;
      activeSellerId = currentUserUid;
      permissions = SellerStaffPermissions.ownerFullPermissions();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _reset() {
    actingAsHelper = false;
    activeSellerId = null;
    activeHelperRow = null;
    myHelperLinks = [];
    myPendingInvitations = [];
    myTeamHelpers = [];
    permissions = SellerStaffPermissions.ownerFullPermissions();
  }

  Future<void> switchToOwnStore() async {
    actingAsHelper = false;
    activeSellerId = currentUserUid;
    activeHelperRow = null;
    permissions = SellerStaffPermissions.ownerFullPermissions();
    await _persistSellerId(currentUserUid);
    notifyListeners();
  }

  Future<void> switchToHelperSeller(SellerHelpersRow row) async {
    final sid = row.sellerId?.trim();
    if (sid == null ||
        sid.isEmpty ||
        (row.invitationStatus ?? 'pending') != 'accepted' ||
        row.active != true) {
      return;
    }
    actingAsHelper = true;
    activeSellerId = sid;
    activeHelperRow = row;
    permissions = SellerStaffPermissions.fromJson(row.permissionsRaw);
    await _persistSellerId(sid);
    await _pingActive(sid);
    notifyListeners();
  }

  bool can(String permission) {
    if (!actingAsHelper) return true;
    return permissions[permission] == true;
  }

  bool canAny(Iterable<String> keys) => keys.any(can);

  Future<bool> serverCan(String permission, {String? sellerId}) async {
    final sid = sellerId ?? effectiveSellerId;
    if (sid.isEmpty) return false;
    if (!actingAsHelper && sid == currentUserUid) return true;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_staff_has_permission',
        params: {
          'p_seller_id': sid,
          'p_permission': permission,
        },
      );
      return res == true;
    } catch (_) {
      return can(permission);
    }
  }

  /// Legado: RPC já não devolve UUID a JWT (anti-oracle D1931).
  /// Convites: [SellerStaffRepository.inviteHelperByEmail].
  static Future<String?> findUserIdByEmail(String email) async {
    final e = email.trim();
    if (e.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_find_user_id_by_email',
        params: {'p_email': e},
      );
      final id = res?.toString().trim();
      if (id == null || id.isEmpty || id == 'null') return null;
      return id;
    } catch (e) {
      debugPrint('[SellerStaff] findUserIdByEmail failed: $e');
      return null;
    }
  }

  Future<void> _pingActive(String sellerId) async {
    try {
      await SupaFlow.client.rpc(
        'batata_staff_ping_active',
        params: {'p_seller_id': sellerId},
      );
    } catch (_) {}
  }

  static const _prefKey = 'batata_active_seller_staff_id_v1';

  Future<void> acceptInvitation(SellerHelpersRow invite) async {
    final id = invite.id?.trim();
    final sid = invite.sellerId?.trim();
    if (id == null || id.isEmpty || sid == null || sid.isEmpty) return;
    await SellerHelpersTable().update(
      data: {
        'invitation_status': 'accepted',
        'active': true,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (q) => q.eqOrNull('id', id),
    );
    await StaffActionLog.record(
      sellerId: sid,
      actionType: 'helper_invitation_accepted',
      targetEntity: 'seller_helpers',
      targetId: id,
    );
    await refresh();
    for (final h in myHelperLinks) {
      if (h.id == id) {
        await switchToHelperSeller(h);
        break;
      }
    }
  }

  Future<void> rejectInvitation(SellerHelpersRow invite) async {
    final id = invite.id?.trim();
    final sid = invite.sellerId?.trim();
    if (id == null || id.isEmpty || sid == null || sid.isEmpty) return;
    await SellerHelpersTable().update(
      data: {
        'invitation_status': 'rejected',
        'active': false,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (q) => q.eqOrNull('id', id),
    );
    await StaffActionLog.record(
      sellerId: sid,
      actionType: 'helper_invitation_rejected',
      targetEntity: 'seller_helpers',
      targetId: id,
    );
    await refresh();
  }

  Future<void> _persistSellerId(String sellerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, sellerId);
  }

  Future<String?> _readPersistedSellerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }
}

/// Registo de auditoria (ações da equipa).
abstract final class StaffActionLog {
  static Future<void> record({
    required String sellerId,
    required String actionType,
    required String targetEntity,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty || sellerId.trim().isEmpty) return;
    try {
      await StaffActionLogsTable().insert({
        'seller_id': sellerId,
        'performed_by_user_id': uid,
        'target_entity': targetEntity,
        'target_id': targetId,
        'action_type': actionType,
        'metadata': metadata ?? {},
      });
    } catch (e) {
      debugPrint('[StaffActionLog] $e');
    }
  }

  static Future<List<StaffActionLogsRow>> forSeller(
    String sellerId, {
    int limit = 40,
    String? helperUserId,
  }) async {
    return StaffActionLogsTable().queryRows(
      queryFn: (q) {
        var query = q.eqOrNull('seller_id', sellerId);
        if (helperUserId != null && helperUserId.isNotEmpty) {
          query = query.eqOrNull('performed_by_user_id', helperUserId);
        }
        return query.order('created_at', ascending: false);
      },
      limit: limit,
    );
  }
}

/// Gestão de colaboradores (dono da loja).
class SellerStaffRepository {
  /// Convite por e-mail no servidor.
  /// Resposta uniforme `{ok:true}` (com ou sem conta) — anti-enumeração.
  /// Devolve a linha pendente se existir após o RPC; senão `null` (sucesso genérico).
  Future<SellerHelpersRow?> inviteHelperByEmail({
    required String helperEmail,
    required String displayName,
    required Map<String, bool> permissions,
  }) async {
    final email = helperEmail.trim();
    final name = displayName.trim();
    if (email.isEmpty || name.isEmpty) {
      throw Exception('Preenche e-mail e nome na equipa.');
    }
    try {
      await SupaFlow.client.rpc(
        'batata_staff_invite_helper_by_email',
        params: {
          'p_email': email,
          'p_display_name': name,
          'p_permissions': SellerStaffPermissions.toJson(permissions),
        },
      );
      // Pode não haver linha (e-mail sem conta) — UI usa mensagem uniforme.
      final rows = await SellerHelpersTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', currentUserUid)
            .eqOrNull('invited_email', email.toLowerCase()),
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('already_member')) {
        throw Exception('Esta pessoa já faz parte da equipa.');
      }
      if (msg.contains('invite_pending')) {
        throw Exception('Já existe um convite pendente para este e-mail.');
      }
      if (msg.contains('cannot_invite_self')) {
        throw Exception('Não podes adicionar-te a ti próprio como colaborador.');
      }
      if (msg.contains('rate_limited')) {
        throw Exception('Demasiados convites. Tenta mais tarde.');
      }
      if (msg.contains('not_allowed')) {
        throw Exception('Sem permissão para convidar colaboradores.');
      }
      if (msg.contains('invalid_email')) {
        throw Exception('E-mail inválido.');
      }
      rethrow;
    }
  }

  Future<SellerHelpersRow?> inviteHelper({
    required String sellerId,
    required String helperUserId,
    required String helperEmail,
    required String displayName,
    required Map<String, bool> permissions,
  }) async {
    final existing = await SellerHelpersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sellerId)
          .eqOrNull('helper_user_id', helperUserId),
      limit: 1,
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    SellerHelpersRow? createdLink;

    if (existing.isNotEmpty) {
      final row = existing.first;
      final status = row.invitationStatus ?? 'pending';
      if (status == 'accepted') {
        throw Exception('Esta pessoa já faz parte da equipa.');
      }
      if (status == 'pending') {
        throw Exception('Já existe um convite pendente para este e-mail.');
      }
      if (status == 'rejected') {
        await SellerHelpersTable().update(
          data: {
            'invitation_status': 'pending',
            'display_name': displayName,
            'invited_email': helperEmail,
            'permissions': SellerStaffPermissions.toJson(permissions),
            'invited_by': currentUserUid,
            'updated_at': nowIso,
            'responded_at': null,
            'active': false,
          },
          matchingRows: (q) => q.eqOrNull('id', row.id),
        );
        createdLink = row;
      }
    }

    if (createdLink == null) {
      try {
        await SellerHelpersTable().insert({
          'seller_id': sellerId,
          'helper_user_id': helperUserId,
          'invited_email': helperEmail,
          'display_name': displayName,
          'active': false,
          'invitation_status': 'pending',
          'permissions': SellerStaffPermissions.toJson(permissions),
          'invited_by': currentUserUid,
          'updated_at': nowIso,
        });
      } catch (e, st) {
        await FleaberLogger.instance.logStaffHelper(
          'invite.insert_fail',
          sellerId: sellerId,
          helperUserId: helperUserId,
          data: {'email': helperEmail},
          error: e,
          stackTrace: st,
        );
        final msg = e.toString();
        if (msg.contains('23505') || msg.contains('duplicate key')) {
          throw Exception('Este colaborador já foi convidado.');
        }
        if (msg.contains('42501') || msg.contains('permission denied')) {
          throw Exception(
            'Sem permissão para convidar. Corre seller_helpers_staff_batata.sql no Supabase.',
          );
        }
        throw Exception('Não foi possível criar o convite. Tenta outra vez.');
      }
    }
    await StaffActionLog.record(
      sellerId: sellerId,
      actionType: 'helper_invited',
      targetEntity: 'seller_helpers',
      targetId: helperUserId,
      metadata: {'display_name': displayName, 'helper_email': helperEmail},
    );
    final rows = await SellerHelpersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sellerId)
          .eqOrNull('helper_user_id', helperUserId),
      limit: 1,
    );
    createdLink ??= rows.isEmpty ? null : rows.first;
    final linkId = createdLink?.id?.trim() ?? '';
    if (linkId.isNotEmpty) {
      try {
        final notifyId = await SupaFlow.client.rpc(
          'batata_notify_helper_invitation',
          params: {
            'p_helper_user_id': helperUserId,
            'p_seller_helpers_id': linkId,
            'p_actor_id': currentUserUid,
          },
        );
        await FleaberLogger.instance.logStaffHelper(
          'invite.notify_ok',
          sellerId: sellerId,
          helperUserId: helperUserId,
          sellerHelpersId: linkId,
          data: {'notification_id': notifyId?.toString()},
        );
      } catch (e, st) {
        await FleaberLogger.instance.logStaffHelper(
          'invite.notify_fail',
          sellerId: sellerId,
          helperUserId: helperUserId,
          sellerHelpersId: linkId,
          error: e,
          stackTrace: st,
        );
        // Convite criado — notificação é best-effort (RPC/SQL pode faltar no Supabase).
      }
    }
    await FleaberLogger.instance.logStaffHelper(
      'invite.created',
      sellerId: sellerId,
      helperUserId: helperUserId,
      sellerHelpersId: linkId.isEmpty ? null : linkId,
    );
    return createdLink;
  }

  Future<void> updateHelper(
    SellerHelpersRow row, {
    String? displayName,
    bool? active,
    Map<String, bool>? permissions,
  }) async {
    final id = row.id;
    if (id == null) return;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (displayName != null) data['display_name'] = displayName;
    if (active != null) data['active'] = active;
    if (permissions != null) {
      data['permissions'] = SellerStaffPermissions.toJson(permissions);
    }
    await SellerHelpersTable().update(
      data: data,
      matchingRows: (q) => q.eqOrNull('id', id),
    );
    await StaffActionLog.record(
      sellerId: row.sellerId ?? '',
      actionType: active == false ? 'helper_deactivated' : 'helper_updated',
      targetEntity: 'seller_helpers',
      targetId: id,
    );
  }

  Future<void> removeHelper(SellerHelpersRow row) async {
    final id = row.id;
    if (id == null) return;
    await SellerHelpersTable().delete(
      matchingRows: (q) => q.eqOrNull('id', id),
    );
    await StaffActionLog.record(
      sellerId: row.sellerId ?? '',
      actionType: 'helper_removed',
      targetEntity: 'seller_helpers',
      targetId: id,
    );
  }
}
