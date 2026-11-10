import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_gallery_picker.dart';
import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/pages/registo/phone_verify_sheet.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_radius.dart';
import '/utils/phone_verification_service.dart';
import '/utils/profile_patch_service.dart';
import '/utils/profile_shipping_requirements.dart';
import '/utils/pt_postal.dart';
import '/utils/seller_reservation_policy_service.dart';
import '/widgets/seller_reservation_policy_sheet.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/hub/seller/hub_seller_copy.dart';
import '/hub/seller/hub_seller_sheet.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/account_context_badge.dart';
import '/utils/test_account_deletion_service.dart';
import '/utils/account_deletion_service.dart';
import '/utils/login_remember_storage.dart';
import '/pages/login/login_widget.dart';
import '/hub/hub_navigation.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/pages/conta/dados_profissionais_section.dart';

class ContaDefinicoesWidget extends StatefulWidget {
  const ContaDefinicoesWidget({super.key, this.embedded = false});

  /// H11 desktop shell: sem AppBar duplicada.
  final bool embedded;

  static String routeName = 'ContaDefinicoes';
  static String routePath = '/contaDefinicoes';

  @override
  State<ContaDefinicoesWidget> createState() => _ContaDefinicoesWidgetState();
}

class _ContaDefinicoesWidgetState extends State<ContaDefinicoesWidget> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _legalFullNameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _shippingLine1Ctrl;
  late final TextEditingController _shippingLine2Ctrl;
  late final TextEditingController _shippingPostalCtrl;
  late final TextEditingController _shippingCityCtrl;
  late final TextEditingController _shippingCountryCtrl;
  late final TextEditingController _mbWayCtrl;
  late final TextEditingController _ibanCtrl;
  late final TextEditingController _oldPasswordCtrl;
  late final TextEditingController _newPasswordCtrl;
  late final TextEditingController _confirmPasswordCtrl;

  ProfilesRow? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _savingPayments = false;
  bool _changingPassword = false;
  bool _deletingTestAccount = false;
  bool _deletingAccount = false;
  final _deleteConfirmCtrl = TextEditingController();
  bool _externalPaymentsEnabled = false;
  bool _paymentsOpen = false;
  bool _reservationsPolicyOpen = true;
  bool _securityOpen = false;
  Uint8List? _newPhotoBytes;
  String? _newPhotoName;
  Timer? _usernameDebounce;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String _lastCheckedUsername = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _legalFullNameCtrl = TextEditingController();
    _locationCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController(text: currentUserEmail);
    _shippingLine1Ctrl = TextEditingController();
    _shippingLine2Ctrl = TextEditingController();
    _shippingPostalCtrl = TextEditingController();
    _shippingCityCtrl = TextEditingController();
    _shippingCountryCtrl = TextEditingController(text: 'PT');
    _mbWayCtrl = TextEditingController();
    _ibanCtrl = TextEditingController();
    _oldPasswordCtrl = TextEditingController();
    _newPasswordCtrl = TextEditingController();
    _confirmPasswordCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _deleteConfirmCtrl.dispose();
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _legalFullNameCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _shippingLine1Ctrl.dispose();
    _shippingLine2Ctrl.dispose();
    _shippingPostalCtrl.dispose();
    _shippingCityCtrl.dispose();
    _shippingCountryCtrl.dispose();
    _mbWayCtrl.dispose();
    _ibanCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  /// Telemóvel só conta como verificado se o número guardado coincide com o campo.
  bool get _phoneVerified {
    if (_profile?.phoneVerifiedAt == null) return false;
    final saved = (_profile?.phone ?? '').trim();
    final current = _phoneCtrl.text.trim();
    if (saved.isNotEmpty && current.isNotEmpty && _phonesMatch(saved, current)) {
      return true;
    }
    final authPhone = currentPhoneNumber.trim();
    return authPhone.isNotEmpty &&
        current.isNotEmpty &&
        _phonesMatch(authPhone, current) &&
        SupaFlow.client.auth.currentUser?.phoneConfirmedAt != null;
  }

  static bool _phonesMatch(String a, String b) {
    final ea = PhoneVerificationService.toE164(a) ?? a.trim();
    final eb = PhoneVerificationService.toE164(b) ?? b.trim();
    return ea.isNotEmpty && ea == eb;
  }

  String? _normalizedPhoneDraft(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return PhoneVerificationService.toE164(trimmed) ?? trimmed;
  }

  bool get _hasAnyVerifiedBadge =>
      currentUserEmailVerified || _phoneVerified;

  bool get _shippingComplete => ProfileShippingRequirements.isComplete(_profile);

  void _applyProfileToForm(ProfilesRow? profile) {
    _profile = profile;
    _nameCtrl.text = profile?.fullName ?? '';
    _legalFullNameCtrl.text = profile?.legalFullName ?? '';
    _locationCtrl.text = profile?.location ?? '';
    _phoneCtrl.text = () {
      final saved = profile?.phone?.trim();
      if (saved != null && saved.isNotEmpty) return saved;
      final authPhone = currentPhoneNumber.trim();
      if (authPhone.isNotEmpty) return authPhone;
      return '';
    }();
    _emailCtrl.text = currentUserEmail;
    _externalPaymentsEnabled = profile?.externalPaymentsEnabled ?? false;
    _shippingLine1Ctrl.text = profile?.shippingLine1 ?? '';
    _shippingLine2Ctrl.text = profile?.shippingLine2 ?? '';
    _shippingPostalCtrl.text = profile?.shippingPostalCode ?? '';
    _shippingCityCtrl.text = profile?.shippingCity ?? '';
    _shippingCountryCtrl.text =
        (profile?.shippingCountry?.trim().isNotEmpty ?? false)
            ? profile!.shippingCountry!.trim().toUpperCase()
            : 'PT';
    _mbWayCtrl.text = profile?.mbWay ?? '';
    _ibanCtrl.text = profile?.iban ?? '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      for (var i = 0; i < 25 && currentUserUid.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (currentUserUid.isEmpty) {
        _applyProfileToForm(null);
        return;
      }
      await ProfilePatchService.ensureOwnProfileRow();
      final row = await SupaFlow.client
          .from('profiles')
          .select(_profileShippingSelect)
          .eq('id', currentUserUid)
          .maybeSingle();
      _applyProfileToForm(
        row != null ? ProfilesRow(Map<String, dynamic>.from(row)) : null,
      );
      try {
        final payout = await SupaFlow.client.rpc('batata_get_my_payout_details');
        if (payout is List && payout.isNotEmpty) {
          final p = Map<String, dynamic>.from(payout.first as Map);
          _mbWayCtrl.text = p['mb_way']?.toString().trim() ?? '';
          _ibanCtrl.text = p['iban']?.toString().trim() ?? '';
          if (p['external_payments_enabled'] == true) {
            _externalPaymentsEnabled = true;
          }
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _uploadAvatarIfNeeded() async {
    final bytes = _newPhotoBytes;
    if (bytes == null || currentUserUid.isEmpty) return null;
    final name =
        (_newPhotoName ?? 'avatar.jpg').replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        'profile_photos/$currentUserUid/${DateTime.now().millisecondsSinceEpoch}_$name';
    final lower = name.toLowerCase();
    String contentType = 'image/jpeg';
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
    return SupaFlow.client.storage.from('chat_media').getPublicUrl(path);
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await FleaberGalleryPicker.pickSingleImage(
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _newPhotoBytes = bytes;
        _newPhotoName = picked.name;
      });
    } on FleaberGalleryPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível escolher a foto: $e')),
      );
    }
  }

  static const _profileShippingSelect =
      'id, full_name, legal_full_name, location, photo_url, phone, phone_verified_at, '
      'shipping_line1, shipping_line2, shipping_postal_code, shipping_city, '
      'shipping_country, external_payments_enabled';

  Future<void> _logProfileSave(
    String phase, {
    Map<String, dynamic>? extra,
  }) async {
    unawaited(
      FleaberLogger.instance.event('profile.shipping.save.$phase', {
        if (extra != null) ...extra,
        'user_id': currentUserUid,
      }),
    );
  }

  Map<String, dynamic> _shippingPayload() {
    final country = _shippingCountryCtrl.text.trim().toUpperCase();
    return {
      'shipping_line1': _shippingLine1Ctrl.text.trim().isEmpty
          ? null
          : _shippingLine1Ctrl.text.trim(),
      'shipping_line2': _shippingLine2Ctrl.text.trim().isEmpty
          ? null
          : _shippingLine2Ctrl.text.trim(),
      'shipping_postal_code': _shippingPostalCtrl.text.trim().isEmpty
          ? null
          : _shippingPostalCtrl.text.trim(),
      'shipping_city': _shippingCityCtrl.text.trim().isEmpty
          ? null
          : _shippingCityCtrl.text.trim(),
      'shipping_country': country.length == 2 ? country : 'PT',
    };
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Corrige os campos assinalados a vermelho e tenta guardar outra vez.',
          ),
        ),
      );
      return;
    }
    if (currentUserUid.isEmpty) return;

    final username = _nameCtrl.text.trim();
    final legalFullName = _legalFullNameCtrl.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O nome de utilizador é obrigatório.')),
      );
      return;
    }
    if (legalFullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O nome completo legal é obrigatório.')),
      );
      return;
    }
    // Nome legal: pelo menos nome + apelido (mesmo critério das etiquetas).
    if (!ProfileShippingRequirements.isLegalNameOk(legalFullName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No nome completo escreve o nome e o apelido (como no cartão de cidadão).',
          ),
        ),
      );
      return;
    }
    final available = await _isUsernameAvailable(username);
    if (!available) {
      if (!mounted) return;
      setState(() => _usernameAvailable = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este nome de utilizador já existe. Escolhe outro.',
          ),
        ),
      );
      return;
    }
    final shipping = _shippingPayload();
    final line1 = (shipping['shipping_line1'] as String?)?.trim() ?? '';
    final postal = (shipping['shipping_postal_code'] as String?)?.trim() ?? '';
    final city = (shipping['shipping_city'] as String?)?.trim() ?? '';
    final country = (shipping['shipping_country'] as String?)?.trim() ?? 'PT';

    final wantsShipping = line1.isNotEmpty ||
        postal.isNotEmpty ||
        city.isNotEmpty;

    if (wantsShipping && postal.isNotEmpty && !isValidPtPostalCode(postal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Código postal inválido. Usa o formato português NNNN-NNN (ex. 1000-001).',
          ),
        ),
      );
      return;
    }

    if (wantsShipping &&
        !ProfileShippingRequirements.isCompleteFromValues(
          legalFullName: legalFullName,
          shippingLine1: line1,
          shippingPostalCode: postal,
          shippingCity: city,
          shippingCountry: country,
        )) {
      final missing = ProfileShippingRequirements.missingFields(
        ProfilesRow({
          'legal_full_name': legalFullName,
          'shipping_line1': line1,
          'shipping_postal_code': postal,
          'shipping_city': city,
          'shipping_country': country,
        }),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Para guardar a morada de entrega, completa: ${missing.join(', ')}.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    await _logProfileSave(
      'begin',
      extra: {
        'wants_shipping': wantsShipping,
        'line1_len': line1.length,
        'postal_len': postal.length,
        'city_len': city.length,
        'name_has_space': legalFullName.contains(RegExp(r'\s')),
      },
    );
    try {
      String? photoUrl = _profile?.photoUrl;
      final uploaded = await _uploadAvatarIfNeeded();
      if (uploaded != null) photoUrl = uploaded;

      final phoneRaw = _phoneCtrl.text.trim();
      final location = _locationCtrl.text.trim();
      final mbWay = _mbWayCtrl.text.trim();
      final iban = _ibanCtrl.text.trim();
      final profilePatch = <String, dynamic>{
        'full_name': username.isEmpty ? null : username,
        'legal_full_name': legalFullName.isEmpty ? null : legalFullName,
        'location': location.isEmpty ? (city.isNotEmpty ? city : null) : location,
        'external_payments_enabled': _externalPaymentsEnabled,
        'mb_way':
            _externalPaymentsEnabled && mbWay.isNotEmpty ? mbWay : null,
        'iban': _externalPaymentsEnabled && iban.isNotEmpty ? iban : null,
        if (photoUrl != null) 'photo_url': photoUrl,
        ...shipping,
      };
      // Guardar telemóvel mesmo antes da verificação SMS (rascunho persistido).
      if (phoneRaw.isNotEmpty) {
        final normalized = _normalizedPhoneDraft(phoneRaw);
        if (normalized == null) {
          throw Exception(
            'Número de telemóvel inválido. Usa 9 dígitos (PT) ou formato internacional.',
          );
        }
        profilePatch['phone'] = normalized;
        final savedPhone = (_profile?.phone ?? '').trim();
        if (_profile?.phoneVerifiedAt != null &&
            savedPhone.isNotEmpty &&
            !_phonesMatch(savedPhone, normalized)) {
          profilePatch['phone_verified_at'] = null;
        }
      }

      final updated = await ProfilePatchService.patchOwnProfile(
        profilePatch,
        select: _profileShippingSelect,
      );

      if (updated == null) {
        await _logProfileSave('error', extra: {'reason': 'update_returned_null'});
        throw Exception(
          'Não foi possível actualizar o perfil. Executa supabase/sql/profiles_rls_batata.sql '
          'no Supabase e tenta outra vez.',
        );
      }

      final saved = ProfilesRow(Map<String, dynamic>.from(updated));
      final reread = await ProfileShippingRequirements.fetchCurrentProfile();
      final persistedLine1 = reread?.shippingLine1?.trim() ?? '';
      if (line1.isNotEmpty && persistedLine1 != line1) {
        await _logProfileSave(
          'verify_failed',
          extra: {
            'sent_line1_len': line1.length,
            'got_line1_len': persistedLine1.length,
            'patch_keys': profilePatch.keys.toList(),
          },
        );
        throw Exception(
          'A morada não ficou guardada na base de dados. '
          'Corre o ficheiro supabase/sql/profiles_shipping_payments_batata.sql no SQL Editor do Supabase.',
        );
      }

      final profileForUi = reread ?? saved;
      _applyProfileToForm(profileForUi);
      await _logProfileSave(
        'success',
        extra: {
          'shipping_complete':
              ProfileShippingRequirements.isComplete(profileForUi),
          'line1_len': persistedLine1.length,
        },
      );

      String? emailWarning;
      final newEmail = _emailCtrl.text.trim();
      if (newEmail.isNotEmpty &&
          newEmail != currentUserEmail &&
          mounted) {
        try {
          await authManager.updateEmail(email: newEmail, context: context);
        } catch (e) {
          emailWarning =
              'Perfil guardado, mas não foi possível alterar o email: '
              '${e.toString().replaceFirst('Exception: ', '')}';
          await _logProfileSave('email_error', extra: {'error': e.toString()});
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emailWarning ??
                (ProfileShippingRequirements.isComplete(profileForUi)
                    ? 'Perfil actualizado. Já podes comprar com pagamento na app.'
                    : 'Perfil actualizado.'),
          ),
        ),
      );
      setState(() {
        _newPhotoBytes = null;
        _newPhotoName = null;
      });
    } catch (e, st) {
      await _logProfileSave(
        'error',
        extra: {
          'error': e.toString(),
          'friendly': _friendlyDbError(e),
          if (e is PostgrestException) 'pg_code': e.code,
          if (e is PostgrestException) 'pg_message': e.message,
          'stack': st.toString().split('\n').take(3).join(' | '),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyDbError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveExternalPayments() async {
    if (currentUserUid.isEmpty) return;
    setState(() => _savingPayments = true);
    try {
      final enabled = _externalPaymentsEnabled;
      final row = await ProfilePatchService.patchOwnProfile(
        {
          'external_payments_enabled': enabled,
          'mb_way': enabled && _mbWayCtrl.text.trim().isNotEmpty
              ? _mbWayCtrl.text.trim()
              : null,
          'iban': enabled && _ibanCtrl.text.trim().isNotEmpty
              ? _ibanCtrl.text.trim()
              : null,
        },
        select: 'id',
      );
      if (row == null) {
        throw Exception('Não foi possível guardar os dados de pagamento.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados de pagamento guardados.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyDbError(e))),
      );
    } finally {
      if (mounted) setState(() => _savingPayments = false);
    }
  }

  String _friendlyDbError(Object e) => ProfilePatchService.friendlyError(e);

  Future<void> _verifyEmail() async {
    final email = _emailCtrl.text.trim().isNotEmpty
        ? _emailCtrl.text.trim()
        : currentUserEmail;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduz o teu email.')),
      );
      return;
    }
    try {
      await SupaFlow.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enviámos um email de confirmação. Verifica a caixa de entrada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _verifyPhone() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduz o teu número de telemóvel.')),
      );
      return;
    }
    final e164 = _normalizedPhoneDraft(raw);
    if (e164 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Número inválido. Usa 9 dígitos (PT) ou formato internacional.',
          ),
        ),
      );
      return;
    }
    final ok = await showPhoneVerificationSheet(context, phoneRaw: raw);
    if (ok && mounted) {
      await ProfilePatchService.patchOwnProfile(
        {
          'phone': e164,
          'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
        },
        select: _profileShippingSelect,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telemóvel verificado.')),
      );
    }
  }

  Future<bool> _isUsernameAvailable(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    _lastCheckedUsername = normalized;
    try {
      final taken = await SupaFlow.client.rpc(
        'batata_is_full_name_taken',
        params: {'p_name': username.trim()},
      );
      return taken != true;
    } catch (_) {
      // Se a verificação falhar por rede, não bloquear edição do campo.
      return true;
    }
  }

  void _onUsernameChanged(String value) {
    final normalized = value.trim().toLowerCase();
    _usernameDebounce?.cancel();
    setState(() {
      _usernameAvailable = null;
      _checkingUsername = normalized.isNotEmpty;
    });
    if (normalized.isEmpty) {
      setState(() => _checkingUsername = false);
      return;
    }
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      final ok = await _isUsernameAvailable(value);
      if (!mounted) return;
      if (_lastCheckedUsername != value.trim().toLowerCase()) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = ok;
      });
    });
  }

  Future<void> _changePassword() async {
    final oldPwd = _oldPasswordCtrl.text;
    final newPwd = _newPasswordCtrl.text;
    final confirmPwd = _confirmPasswordCtrl.text;

    if (oldPwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduz a palavra-passe actual.')),
      );
      return;
    }
    if (newPwd.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nova palavra-passe deve ter pelo menos 6 caracteres.'),
        ),
      );
      return;
    }
    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A confirmação não coincide com a nova palavra-passe.'),
        ),
      );
      return;
    }
    if (oldPwd == newPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nova palavra-passe deve ser diferente da actual.'),
        ),
      );
      return;
    }

    setState(() => _changingPassword = true);
    try {
      final ok = await authManager.changePasswordWithReauth(
        currentPassword: oldPwd,
        newPassword: newPwd,
        context: context,
      );
      if (!ok || !mounted) return;
      _oldPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      setState(() => _securityOpen = false);
      final email = currentUserEmail.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            email.isNotEmpty
                ? 'Palavra-passe alterada. Se o teu email $email estiver activo, '
                    'deves receber uma notificação de segurança do Fleaber.'
                : 'Palavra-passe alterada.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;

    _deleteConfirmCtrl.clear();
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final typed = _deleteConfirmCtrl.text.trim();
            final canDelete = typed == AccountDeletionService.confirmPhrase;
            return AlertDialog(
              title: const Text('Eliminar conta'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vamos anonimizar os teus dados pessoais e bloquear o login. '
                      'Encomendas, pagamentos e disputas podem ser conservados '
                      'por obrigação legal/operacional (sem o teu nome, morada, '
                      'telefone ou dados de pagamento).',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.4,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Não é possível eliminar se tiveres encomendas activas, '
                      'disputas abertas, direto ao vivo ou saldo na carteira.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deleteConfirmCtrl,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText:
                            'Escreve ${AccountDeletionService.confirmPhrase}',
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Eliminar conta'),
                ),
              ],
            );
          },
        );
      },
    );

    if (proceed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      final result = await AccountDeletionService.requestDeletion(
        confirmation: _deleteConfirmCtrl.text.trim(),
      );
      if (!mounted) return;

      if (result['blocked'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ??
                  'Conta com obrigações activas — não eliminada.',
            ),
          ),
        );
        return;
      }

      await LoginRememberStorage.clearCredentials();
      await authManager.signOut();
      if (!mounted) return;
      context.goNamedAuth(LoginWidget.routeName, context.mounted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conta eliminada. Código: ${result['confirmation_code'] ?? '—'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao eliminar conta: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _confirmDeleteTestAccount() async {
    if (!TestAccountDeletionService.isAvailable || _deletingTestAccount) return;

    _deleteConfirmCtrl.clear();
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final typed = _deleteConfirmCtrl.text.trim();
            final canDelete =
                typed == TestAccountDeletionService.confirmPhrase;
            return AlertDialog(
              title: const Text('Apagar conta (testes)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Isto remove tudo associado a esta conta em staging: '
                      'anúncios, mensagens, encomendas, diretos, reservas, '
                      'carteira e perfil. Não há recuperação.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.4,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O teu perfil Facebook/Meta **não** é afectado — podes '
                      'voltar a entrar como se fosse a primeira vez.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deleteConfirmCtrl,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText:
                            'Escreve ${TestAccountDeletionService.confirmPhrase}',
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Apagar tudo'),
                ),
              ],
            );
          },
        );
      },
    );

    if (proceed != true || !mounted) return;

    setState(() => _deletingTestAccount = true);
    try {
      await TestAccountDeletionService.nukeCurrentAccount(
        confirmation: _deleteConfirmCtrl.text.trim(),
      );
      if (!mounted) return;
      await authManager.signOut();
      if (!mounted) return;
      context.goNamedAuth(LoginWidget.routeName, context.mounted);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conta apagada. Podes voltar a registar-te (ex.: Facebook).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _deletingTestAccount = false);
    }
  }

  /// H11 desktop: grelha de secções. Mobile / app: coluna nativa.
  bool _desktopGrid(BoxConstraints c) =>
      widget.embedded && c.maxWidth >= 720;

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = _desktopGrid(constraints);
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 20 : 16,
                    desktop ? 4 : 8,
                    desktop ? 20 : 16,
                    desktop ? 24 : 28,
                  ),
                  children: [
                    if (!widget.embedded) ...[
                      const AccountContextBadge(compact: true),
                      const SizedBox(height: 10),
                    ],
                    ..._headerBlocks(compact: desktop),
                    if (desktop)
                      ..._desktopFormLayout()
                    else
                      ..._mobileFormLayout(),
                  ],
                );
              },
            ),
          );
    if (widget.embedded) {
      return ColoredBox(
        color: Colors.white,
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
        leading: IconButton(
          tooltip: Navigator.canPop(context) ? 'Voltar' : 'Ir para Início',
          icon: Icon(
            Navigator.canPop(context)
                ? Icons.arrow_back_rounded
                : Icons.home_outlined,
          ),
          onPressed: () {
            if (Navigator.canPop(context)) {
              context.safePop();
            } else {
              HubNavigation.goAppHome(context);
            }
          },
        ),
        title: Text(
          'Definições de conta',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
            fontSize: 18,
          ),
        ),
      ),
      body: body,
    );
  }

  List<Widget> _headerBlocks({required bool compact}) {
    final radius = compact ? 36.0 : 44.0;
    return [
      Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _newPhotoBytes != null
                ? CircleAvatar(
                    radius: radius,
                    backgroundImage: MemoryImage(_newPhotoBytes!),
                  )
                : FleaberProfileAvatar(
                    userId: currentUserUid,
                    fullName: _nameCtrl.text,
                    photoUrl: _profile?.photoUrl,
                    radius: radius,
                  ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Material(
                color: FleaberColors.teal,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _pickPhoto,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: compact ? 10 : 16),
      if (_hasAnyVerifiedBadge)
        FleaberVerificationBadges(
          emailVerified: currentUserEmailVerified,
          phoneVerified: _phoneVerified,
        ),
      if (!_shippingComplete) ...[
        SizedBox(height: compact ? 8 : 12),
        _infoBanner(
          'Para comprar com pagamento na app e envio com etiqueta, '
          'preenche o nome completo legal e a morada de entrega.',
        ),
      ],
      SizedBox(height: compact ? 12 : 20),
    ];
  }

  /// Desktop: 2 colunas de secções para reduzir scroll e usar a largura H11.
  List<Widget> _desktopFormLayout() {
    return [
      _desktopSectionRow(
        _publicProfileSection(dense: true),
        _fleahubSection(dense: true),
      ),
      const SizedBox(height: 16),
      _desktopSectionRow(
        _addressSection(dense: true),
        _contactSection(dense: true),
      ),
      const SizedBox(height: 16),
      const DadosProfissionaisSection(dense: true),
      const SizedBox(height: 16),
      _desktopSectionRow(
        _reservationsSection(dense: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _paymentsSection(dense: true),
            const SizedBox(height: 10),
            _securitySection(dense: true),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _saveActionsRow(),
      const SizedBox(height: 28),
      _deleteAccountSection(dense: true),
      ..._stagingSection(),
    ];
  }

  /// Mobile / app: ordem e densidade iguais à experiência nativa.
  List<Widget> _mobileFormLayout() {
    return [
      _reservationsSection(dense: false),
      const SizedBox(height: 28),
      _publicProfileSection(dense: false),
      const SizedBox(height: 20),
      _fleahubSection(dense: false),
      const SizedBox(height: 20),
      _addressSection(dense: false),
      const SizedBox(height: 20),
      _contactSection(dense: false),
      const SizedBox(height: 20),
      const DadosProfissionaisSection(dense: false),
      const SizedBox(height: 20),
      _paymentsSection(dense: false),
      const SizedBox(height: 12),
      _securitySection(dense: false),
      const SizedBox(height: 28),
      Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 180,
          child: FleaberPrimaryButton(
            label: 'Guardar alterações',
            height: 48,
            borderRadius: 14,
            loading: _saving,
            onPressed: _saving ? null : _saveProfile,
          ),
        ),
      ),
      const SizedBox(height: 32),
      _deleteAccountSection(dense: false),
      ..._stagingSection(),
    ];
  }

  Widget _desktopSectionRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 24),
        Expanded(child: right),
      ],
    );
  }

  Widget _saveActionsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FleaberColors.bgTint,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFE0E3E7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Guarda o perfil, a morada e os contactos.',
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeSecondary,
                color: FleaberColors.muted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 200,
            child: FleaberPrimaryButton(
              label: 'Guardar alterações',
              height: 48,
              borderRadius: 14,
              loading: _saving,
              onPressed: _saving ? null : _saveProfile,
            ),
          ),
        ],
      ),
    );
  }

  Widget _publicProfileSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Perfil público', dense: dense),
        _desktopPair(
          _field(
            _nameCtrl,
            'Nome de utilizador',
            Icons.alternate_email_rounded,
            hint: 'Como apareces na app (chat, perfil, diretos)',
            helper: _checkingUsername
                ? 'A verificar disponibilidade...'
                : _usernameAvailable == false
                    ? 'Já existe. Escolhe outro nome de utilizador.'
                    : _usernameAvailable == true
                        ? HubSellerCopy.usernameHelperAvailable
                        : HubSellerCopy.usernameHelperRequired,
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Escreve um nome de utilizador.';
              }
              if (_usernameAvailable == false) {
                return 'Este nome já está em uso. Escolhe outro.';
              }
              return null;
            },
            onChanged: _onUsernameChanged,
          ),
          _field(
            _locationCtrl,
            'Localização pública (cidade)',
            Icons.location_on_outlined,
            helper:
                'Aparece no perfil. A morada de entrega está na secção abaixo.',
          ),
        ),
      ],
    );
  }

  Widget _fleahubSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(HubSellerCopy.brand, dense: dense),
        Text(
          HubSellerCopy.settingsSectionBlurb,
          style: GoogleFonts.inter(
            fontSize: FleaHubSiteLayout.typeSecondary,
            color: FleaberColors.muted,
            height: 1.35,
          ),
        ),
        SizedBox(height: dense ? 8 : 10),
        const HubSellerHubCard(compact: true),
      ],
    );
  }

  Widget _addressSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Morada de entrega', dense: dense),
        Text(
          'Usada para receberes encomendas e gerar etiquetas de envio.',
          style: GoogleFonts.inter(
            fontSize: FleaHubSiteLayout.typeSecondary,
            color: FleaberColors.muted,
            height: 1.35,
          ),
        ),
        SizedBox(height: dense ? 8 : 10),
        _field(
          _legalFullNameCtrl,
          'Nome completo',
          Icons.person_outline_rounded,
          hint: 'Nome e apelido legal (como no CC)',
          helper: 'Obrigatório para etiquetas, envio e pagamentos.',
          validator: (value) {
            final v = (value ?? '').trim();
            if (v.isEmpty) {
              return 'Escreve o teu nome completo (nome e apelido).';
            }
            if (!ProfileShippingRequirements.isLegalNameOk(v)) {
              return 'Usa nome e apelido (mín. 2 palavras).';
            }
            return null;
          },
        ),
        _desktopPair(
          _field(
            _shippingLine1Ctrl,
            'Morada (rua e número)',
            Icons.home_outlined,
          ),
          _field(
            _shippingLine2Ctrl,
            'Andar / bloco (opcional)',
            Icons.apartment_outlined,
          ),
        ),
        _desktopPair(
          _field(
            _shippingPostalCtrl,
            'Código postal',
            Icons.markunread_mailbox_outlined,
            keyboard: TextInputType.text,
            hint: '1000-001',
            helper: 'Formato NNNN-NNN. A localidade pode preencher-se sozinha.',
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.isEmpty) return null;
              if (!isValidPtPostalCode(v)) {
                return 'Formato inválido (ex. 2600-100).';
              }
              return null;
            },
            onChanged: (raw) async {
              final n = normalizePtPostalCode(raw);
              if (n == null) return;
              if (n != _shippingPostalCtrl.text.trim()) {
                _shippingPostalCtrl.value = TextEditingValue(
                  text: n,
                  selection: TextSelection.collapsed(offset: n.length),
                );
              }
              // CP mudou → nunca reutilizar localidade antiga (par incompatível).
              if (_shippingCityCtrl.text.isNotEmpty) {
                setState(() => _shippingCityCtrl.text = '');
              }
              final look = await lookupPtPostal(n);
              if (!mounted || look == null) return;
              final still =
                  normalizePtPostalCode(_shippingPostalCtrl.text) ?? '';
              if (still != n) return;
              setState(() => _shippingCityCtrl.text = look.locality);
            },
          ),
          _field(
            _shippingCityCtrl,
            'Localidade',
            Icons.location_city_outlined,
            helper:
                'Morada de entrega (não é a localização pública do perfil). '
                'Ao mudar o CP, a localidade actualiza-se automaticamente.',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: dense ? 160 : 220,
            child: _field(
              _shippingCountryCtrl,
              'País (código, ex. PT)',
              Icons.flag_outlined,
              textCapitalization: TextCapitalization.characters,
              hint: 'PT',
            ),
          ),
        ),
      ],
    );
  }

  Widget _contactSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Contacto e verificação', dense: dense),
        _desktopPair(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                _emailCtrl,
                'Email',
                Icons.mail_outline_rounded,
                keyboard: TextInputType.emailAddress,
              ),
              if (!currentUserEmailVerified)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _verifyEmail,
                    icon: const Icon(
                      Icons.mark_email_read_outlined,
                      size: 18,
                    ),
                    label: const Text('Verificar email'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FleaberColors.teal,
                      side: BorderSide(
                        color: FleaberColors.teal.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                _phoneCtrl,
                'Telemóvel',
                Icons.phone_outlined,
                keyboard: TextInputType.phone,
              ),
              if (!_phoneVerified)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _verifyPhone,
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('Verificar telemóvel (SMS)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FleaberColors.teal,
                      side: BorderSide(
                        color: FleaberColors.teal.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reservationsSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _expandableHeader(
          title: 'Reservas no direto',
          subtitle: 'Política de pedidos e durações',
          expanded: _reservationsPolicyOpen,
          onTap: () => setState(
            () => _reservationsPolicyOpen = !_reservationsPolicyOpen,
          ),
        ),
        if (_reservationsPolicyOpen) ...[
          SizedBox(height: dense ? 8 : 12),
          Text(
            'Define o que acontece quando uma cliente pede um artigo '
            'e quanto tempo dura uma reserva garantida. '
            'Mudanças só afectam pedidos novos.',
            style: GoogleFonts.inter(
              fontSize: FleaHubSiteLayout.typeBody,
              color: FleaberColors.muted,
              height: 1.4,
            ),
          ),
          SizedBox(height: dense ? 10 : 14),
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: FleaberPrimaryButton(
                label: 'Configurar reservas',
                height: 44,
                borderRadius: 12,
                fontSize: 14,
                icon: const Icon(Icons.tune_rounded, size: 18),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                onPressed: () async {
                  final current = await SellerReservationPolicyService
                      .fetchForCurrentSeller();
                  if (!mounted) return;
                  await SellerReservationPolicySheet.show(
                    context,
                    initial: current,
                    title: 'Política de reservas',
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _paymentsSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _expandableHeader(
          title: 'Pagamentos fora da app',
          subtitle: _paymentsSummary(),
          expanded: _paymentsOpen,
          onTap: () => setState(() => _paymentsOpen = !_paymentsOpen),
        ),
        if (_paymentsOpen) ...[
          const SizedBox(height: 8),
          Text(
            'Para receberes pagamentos fora da Fleaber (MB Way ou '
            'transferência bancária) quando um comprador escolhe '
            '«Pagamento direto ao vendedor». Não é obrigatório para '
            'vender com pagamento na app.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF57636C),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Aceitar pagamentos fora da app',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: const Color(0xFF101518),
              ),
            ),
            subtitle: Text(
              _externalPaymentsEnabled
                  ? 'Activado — os compradores podem pagar-te directamente.'
                  : 'Desactivado — só pagamento na app.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF57636C),
              ),
            ),
            activeColor: FleaberColors.teal,
            value: _externalPaymentsEnabled,
            onChanged: (v) => setState(() => _externalPaymentsEnabled = v),
          ),
          if (_externalPaymentsEnabled) ...[
            const SizedBox(height: 8),
            _desktopPair(
              _field(
                _mbWayCtrl,
                'MB Way',
                Icons.account_balance_wallet_outlined,
                keyboard: TextInputType.phone,
              ),
              _field(
                _ibanCtrl,
                'IBAN',
                Icons.payments_outlined,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _savingPayments ? null : _saveExternalPayments,
              child: Text(
                _savingPayments ? 'A guardar...' : 'Guardar pagamentos',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _securitySection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _expandableHeader(
          title: 'Alterar palavra-passe',
          subtitle: _securityOpen
              ? 'Introduz a nova palavra-passe'
              : 'Toque para editar',
          expanded: _securityOpen,
          onTap: () => setState(() => _securityOpen = !_securityOpen),
        ),
        if (_securityOpen) ...[
          const SizedBox(height: 10),
          Text(
            'Por segurança, confirma a palavra-passe actual e define uma '
            'nova. Receberás um email de alerta se o teu email estiver '
            'configurado no Supabase Auth.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF57636C),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _field(
            _oldPasswordCtrl,
            'Palavra-passe actual',
            Icons.lock_outline_rounded,
            obscure: true,
          ),
          _desktopPair(
            _field(
              _newPasswordCtrl,
              'Nova palavra-passe',
              Icons.lock_reset_rounded,
              obscure: true,
            ),
            _field(
              _confirmPasswordCtrl,
              'Confirmar nova palavra-passe',
              Icons.lock_rounded,
              obscure: true,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: FleaberPrimaryButton(
                label: 'Alterar palavra-passe',
                height: 44,
                borderRadius: 12,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                loading: _changingPassword,
                onPressed: _changingPassword ? null : _changePassword,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _deleteAccountSection({required bool dense}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Eliminar conta', dense: dense),
        Text(
          'Remove os teus dados pessoais da Fleaber e bloqueia o login. '
          'Histórico financeiro necessário pode ser conservado anonimizado.',
          style: GoogleFonts.inter(
            fontSize: FleaHubSiteLayout.typeSecondary,
            color: FleaberColors.muted,
            height: 1.4,
          ),
        ),
        SizedBox(height: dense ? 10 : 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _deletingAccount ? null : _confirmDeleteAccount,
            icon: _deletingAccount
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: Text(
              _deletingAccount
                  ? 'A eliminar conta...'
                  : 'Eliminar a minha conta',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFEF9A9A)),
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _stagingSection() {
    if (!TestAccountDeletionService.isAvailable) return const [];
    return [
      const SizedBox(height: 32),
      _sectionTitle('Zona de testes (staging)'),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(color: const Color(0xFFEF9A9A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Color(0xFFC62828),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Apagar conta remove todos os dados desta conta '
                'no ambiente de testes. Usa para repetir cenários '
                'como «primeira entrada Facebook». Só staging.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF7F0000),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _deletingTestAccount ? null : _confirmDeleteTestAccount,
        icon: _deletingTestAccount
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_forever_outlined, size: 18),
        label: Text(
          _deletingTestAccount
              ? 'A apagar conta...'
              : 'Apagar conta e todos os dados',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFC62828),
          side: const BorderSide(color: Color(0xFFEF9A9A)),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    ];
  }

  String _paymentsSummary() {
    if (!_externalPaymentsEnabled) {
      return 'Desactivado — toque para configurar';
    }
    final parts = <String>['Activado'];
    final mb = _mbWayCtrl.text.trim();
    final ib = _ibanCtrl.text.trim();
    if (mb.isNotEmpty) parts.add('MB Way');
    if (ib.isNotEmpty) parts.add('IBAN');
    return parts.join(' · ');
  }

  Widget _infoBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E6),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFE8D9A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFF8A6D00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeSecondary,
                color: const Color(0xFF5C4A00),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 14, top: dense ? 0 : 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: FleaHubSiteLayout.typeNavTitle,
          fontWeight: FontWeight.w800,
          color: FleaberColors.text,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _expandableHeader({
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return Material(
      color: FleaberColors.bgTint,
      borderRadius: FleaberRadius.circularMd,
      child: InkWell(
        borderRadius: FleaberRadius.circularMd,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeSection,
                        fontWeight: FontWeight.w800,
                        color: FleaberColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeBody,
                        color: FleaberColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: FleaberColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Desktop H11: campos lado a lado. Em grelha 2-col o pai é ~meia largura —
  /// usar viewport + min. local (não exigir 720 no pai). Mobile: coluna nativa.
  Widget _desktopPair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shellWide =
            widget.embedded && MediaQuery.sizeOf(context).width >= 900;
        final wide = shellWide && constraints.maxWidth >= 360;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    bool obscure = false,
    String? hint,
    String? helper,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          prefixIcon: Icon(icon, color: FleaberColors.teal, size: 22),
          filled: true,
          fillColor: FleaberColors.bgTint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(borderRadius: FleaberRadius.circularMd),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularMd,
            borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
          ),
          labelStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FleaberColors.muted,
          ),
          helperStyle: GoogleFonts.inter(
            fontSize: 12.5,
            color: FleaberColors.muted,
          ),
        ),
        style: GoogleFonts.inter(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF101518),
        ),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}
