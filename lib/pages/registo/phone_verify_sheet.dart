import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/phone_verification_service.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_primary_button.dart';

/// Confirma telemóvel com SMS após registo (Supabase Auth).
Future<bool> showPhoneVerificationSheet(
  BuildContext context, {
  required String phoneRaw,
}) async {
  final e164 = PhoneVerificationService.toE164(phoneRaw);
  if (e164 == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Número inválido. Usa 9 dígitos (PT) ou formato internacional.',
          ),
        ),
      );
    }
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PhoneVerifySheet(phoneE164: e164),
  );
  return result == true;
}

class _PhoneVerifySheet extends StatefulWidget {
  const _PhoneVerifySheet({required this.phoneE164});

  final String phoneE164;

  @override
  State<_PhoneVerifySheet> createState() => _PhoneVerifySheetState();
}

class _PhoneVerifySheetState extends State<_PhoneVerifySheet> {
  static const Color _kTeal = Color(0xFF007782);

  final _codeController = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PhoneVerificationService.sendSmsCode(
        widget.phoneE164,
        resend: _sent,
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PhoneVerificationService.verifySmsCode(
        phoneE164: widget.phoneE164,
        token: _codeController.text,
      );
      if (currentUserUid.isNotEmpty) {
        await ProfilesTable().update(
          data: {
            'phone': widget.phoneE164,
            'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
          },
          matchingRows: (rows) => rows.eqOrNull('id', currentUserUid),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E3E7),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Confirma o teu telemóvel',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF101518),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enviámos um código SMS para ${widget.phoneE164}. '
            'Introduz os 6 dígitos abaixo (válido cerca de 10 minutos).',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF57636C),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: FleaberRadius.circularMd,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 16),
          FleaberPrimaryButton(
            width: double.infinity,
            label: 'Confirmar código',
            loading: _busy,
            fontWeight: FontWeight.w600,
            onPressed: _busy ? null : _verify,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _sendCode,
            child: Text(
              _sent ? 'Reenviar código' : 'Enviar código',
              style: GoogleFonts.inter(color: _kTeal),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(
              'Saltar por agora',
              style: GoogleFonts.inter(color: const Color(0xFF57636C)),
            ),
          ),
        ],
      ),
    );
  }
}
