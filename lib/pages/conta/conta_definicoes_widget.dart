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
import '/utils/profile_patch_service.dart';
import '/utils/profile_shipping_requirements.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/account_context_badge.dart';

class ContaDefinicoesWidget extends StatefulWidget {
  const ContaDefinicoesWidget({super.key});

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
  bool _externalPaymentsEnabled = false;
  bool _paymentsOpen = false;
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
    if (saved.isNotEmpty && current.isNotEmpty && saved == current) return true;
    final authPhone = currentPhoneNumber.trim();
    return authPhone.isNotEmpty &&
        current.isNotEmpty &&
        authPhone == current &&
        SupaFlow.client.auth.currentUser?.phoneConfirmedAt != null;
  }

  bool get _hasAnyVerifiedBadge =>
      currentUserEmailVerified || _phoneVerified;

  bool get _shippingComplete => ProfileShippingRequirements.isComplete(_profile);

  void _applyProfileToForm(ProfilesRow? profile) {
    _profile = profile;
    _nameCtrl.text = profile?.fullName ?? '';
    _legalFullNameCtrl.text = profile?.legalFullName ?? '';
    _locationCtrl.text = profile?.location ?? '';
    _phoneCtrl.text = profile?.phoneVerifiedAt != null
        ? (profile?.phone ?? currentPhoneNumber)
        : '';
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
      'shipping_country, mb_way, iban, external_payments_enabled';

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
    if (!_formKey.currentState!.validate()) return;
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
      // Não enviar phone=null — pode falhar constraints e cancelar o UPDATE inteiro.
      if (_phoneVerified && phoneRaw.isNotEmpty) {
        profilePatch['phone'] = phoneRaw;
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
    final ok = await showPhoneVerificationSheet(context, phoneRaw: raw);
    if (ok && mounted) {
      await ProfilePatchService.patchOwnProfile(
        {
          'phone': raw,
          'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
        },
        select: 'id',
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
      final rows = await SupaFlow.client
          .from('profiles')
          .select('id, full_name')
          .ilike('full_name', username.trim());
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] as String?) ?? '';
        final fullName = (map['full_name'] as String?)?.trim().toLowerCase() ?? '';
        if (id != currentUserUid && fullName == normalized) {
          return false;
        }
      }
      return true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
        title: Text(
          'Definições de conta',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF101518),
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  const AccountContextBadge(compact: true),
                  const SizedBox(height: 10),
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _newPhotoBytes != null
                            ? CircleAvatar(
                                radius: 44,
                                backgroundImage: MemoryImage(_newPhotoBytes!),
                              )
                            : FleaberProfileAvatar(
                                userId: currentUserUid,
                                fullName: _nameCtrl.text,
                                photoUrl: _profile?.photoUrl,
                                radius: 44,
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
                  const SizedBox(height: 16),
                  if (_hasAnyVerifiedBadge)
                    FleaberVerificationBadges(
                      emailVerified: currentUserEmailVerified,
                      phoneVerified: _phoneVerified,
                    ),
                  if (!_shippingComplete) ...[
                    const SizedBox(height: 12),
                    _infoBanner(
                      'Para comprar com pagamento na app e envio com etiqueta, '
                      'preenche o nome completo legal e a morada de entrega.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle('Perfil público'),
                  _field(
                    _nameCtrl,
                    'Nome de utilizador',
                    Icons.alternate_email_rounded,
                    hint: 'Como apareces na app (chat, perfil, directos)',
                    helper: _checkingUsername
                        ? 'A verificar disponibilidade...'
                        : _usernameAvailable == false
                            ? 'Já existe. Escolhe outro nome de utilizador.'
                            : _usernameAvailable == true
                                ? 'Disponível.'
                                : 'Obrigatório. Podes usar o mesmo do nome legal, se estiver disponível.',
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Obrigatório.';
                      }
                      if (_usernameAvailable == false) {
                        return 'Nome de utilizador indisponível.';
                      }
                      return null;
                    },
                    onChanged: _onUsernameChanged,
                  ),
                  _field(
                    _locationCtrl,
                    'Localização (cidade)',
                    Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Morada de entrega'),
                  Text(
                    'Usada para receberes encomendas e gerar etiquetas de envio.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    _legalFullNameCtrl,
                    'Nome completo',
                    Icons.person_outline_rounded,
                    hint: 'Nome e apelido legal (como no CC)',
                    helper: 'Obrigatório para etiquetas, envio e pagamentos.',
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Obrigatório.';
                      }
                      return null;
                    },
                  ),
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
                  _field(
                    _shippingPostalCtrl,
                    'Código postal',
                    Icons.markunread_mailbox_outlined,
                    keyboard: TextInputType.text,
                  ),
                  _field(
                    _shippingCityCtrl,
                    'Localidade',
                    Icons.location_city_outlined,
                  ),
                  _field(
                    _shippingCountryCtrl,
                    'País (código, ex. PT)',
                    Icons.flag_outlined,
                    textCapitalization: TextCapitalization.characters,
                    hint: 'PT',
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Contacto e verificação'),
                  _field(
                    _emailCtrl,
                    'Email',
                    Icons.mail_outline_rounded,
                    keyboard: TextInputType.emailAddress,
                  ),
                  if (!currentUserEmailVerified) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _verifyEmail,
                      icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                      label: const Text('Verificar email'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FleaberColors.teal,
                        side: BorderSide(
                          color: FleaberColors.teal.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _field(
                    _phoneCtrl,
                    'Telemóvel',
                    Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                  ),
                  if (!_phoneVerified) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
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
                  ],
                  const SizedBox(height: 20),
                  _expandableHeader(
                    title: 'Pagamentos fora da app',
                    subtitle: _paymentsSummary(),
                    expanded: _paymentsOpen,
                    onTap: () =>
                        setState(() => _paymentsOpen = !_paymentsOpen),
                  ),
                  if (_paymentsOpen) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Para receberes pagamentos fora da Fleaber (MB Way ou '
                      'transferência bancária) quando um comprador escolhe '
                      '«Pagamento directo ao vendedor». Não é obrigatório para '
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
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _savingPayments ? null : _saveExternalPayments,
                      child: Text(
                        _savingPayments ? 'A guardar...' : 'Guardar pagamentos',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _expandableHeader(
                    title: 'Alterar palavra-passe',
                    subtitle: _securityOpen ? 'Introduz a nova palavra-passe' : 'Toque para editar',
                    expanded: _securityOpen,
                    onTap: () =>
                        setState(() => _securityOpen = !_securityOpen),
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
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Alterar palavra-passe',
                      loading: _changingPassword,
                      onPressed: _changingPassword ? null : _changePassword,
                    ),
                  ],
                  const SizedBox(height: 28),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Guardar alterações',
                    loading: _saving,
                    onPressed: _saving ? null : _saveProfile,
                  ),
                ],
              ),
            ),
    );
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E6),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFE8D9A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF8A6D00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF5C4A00),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF57636C),
          letterSpacing: 0.2,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF57636C),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          prefixIcon: Icon(icon, color: FleaberColors.teal, size: 20),
          filled: true,
          fillColor: FleaberColors.bgTint,
          border: OutlineInputBorder(borderRadius: FleaberRadius.circularMd),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularMd,
            borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
          ),
        ),
        style: GoogleFonts.inter(color: const Color(0xFF101518)),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}
