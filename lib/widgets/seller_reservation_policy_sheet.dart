import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/seller_reservation_policy_service.dart';
import '/widgets/fleaber_primary_button.dart';

/// First-live gate + settings: configure reservation policy in plain PT-PT.
class SellerReservationPolicySheet extends StatefulWidget {
  const SellerReservationPolicySheet({
    super.key,
    this.initial,
    this.requireSaveToDismiss = false,
    this.title,
  });

  final SellerReservationPolicy? initial;
  final bool requireSaveToDismiss;
  final String? title;

  /// Returns true if policy was saved successfully.
  static Future<bool> show(
    BuildContext context, {
    SellerReservationPolicy? initial,
    bool requireSaveToDismiss = false,
    String? title,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: !requireSaveToDismiss,
      enableDrag: !requireSaveToDismiss,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SellerReservationPolicySheet(
        initial: initial,
        requireSaveToDismiss: requireSaveToDismiss,
        title: title,
      ),
    );
    return result == true;
  }

  @override
  State<SellerReservationPolicySheet> createState() =>
      _SellerReservationPolicySheetState();
}

class _SellerReservationPolicySheetState
    extends State<SellerReservationPolicySheet> {
  late String _untrustedMode;
  late int _normalTtl;
  late int _trustedTtl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _untrustedMode = i?.untrustedMode == 'pay_required'
        ? 'pay_required'
        : 'approval';
    _normalTtl = SellerReservationPolicyService.clampTtl(
      i?.normalTtlSeconds ?? 86400,
    );
    _trustedTtl = SellerReservationPolicyService.clampTtl(
      i?.trustedTtlSeconds ?? 259200,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await SellerReservationPolicyService.save(
      untrustedMode: _untrustedMode,
      normalTtlSeconds: _normalTtl,
      trustedTtlSeconds: _trustedTtl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['ok'] != true) {
      setState(() => _error = 'Não foi possível guardar. Tenta outra vez.');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5D8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title ?? 'Como queres gerir as reservas?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF101518),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Escolhe o que acontece quando uma cliente pede um artigo. '
              'Podes mudar isto mais tarde — só afecta pedidos novos.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.35,
                color: const Color(0xFF57636C),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Clientes sem confiança',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF101518),
              ),
            ),
            const SizedBox(height: 8),
            _modeCard(
              selected: _untrustedMode == 'approval',
              title: 'Pedir autorização',
              body:
                  'A cliente pede o artigo. Ficas a decidir se aceitas ou '
                  'recusas. Enquanto aguarda, o stock não fica bloqueado. '
                  'O pedido caduca em 45 minutos.',
              onTap: () => setState(() => _untrustedMode = 'approval'),
            ),
            const SizedBox(height: 8),
            _modeCard(
              selected: _untrustedMode == 'pay_required',
              title: 'Só o pagamento garante',
              body:
                  'A cliente adiciona o artigo ao saco sem pedir autorização. '
                  'O artigo só fica garantido quando fizer o pagamento.',
              onTap: () => setState(() => _untrustedMode = 'pay_required'),
            ),
            const SizedBox(height: 18),
            Text(
              'Duração da reserva',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF101518),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Depois de aceitares, escolhe durante quanto tempo o artigo '
              'fica reservado.',
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.3,
                color: const Color(0xFF57636C),
              ),
            ),
            const SizedBox(height: 10),
            _ttlDropdown(
              label: 'Duração normal',
              value: _normalTtl,
              onChanged: (v) => setState(() => _normalTtl = v),
            ),
            const SizedBox(height: 12),
            _ttlDropdown(
              label: 'Clientes de confiança',
              value: _trustedTtl,
              onChanged: (v) => setState(() => _trustedTtl = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFFC62828),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FleaberPrimaryButton(
              label: 'Guardar e continuar',
              loading: _saving,
              onPressed: _saving ? null : _save,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            if (!widget.requireSaveToDismiss) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required bool selected,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? FleaberColors.teal.withValues(alpha: 0.08)
          : const Color(0xFFF5F7F8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? FleaberColors.teal
                  : const Color(0xFFE0E4E6),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? FleaberColors.teal
                    : const Color(0xFF9AA5AB),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ttlDropdown({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final presets = SellerReservationPolicyService.ttlPresetsSeconds;
    final safeValue = presets.contains(value)
        ? value
        : SellerReservationPolicyService.clampTtl(value);
    final current = presets.contains(safeValue) ? safeValue : presets.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF101518),
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: const Color(0xFFF5F7F8),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await _pickTtlSeconds(
                current: current,
                presets: presets,
              );
              if (picked != null) onChanged(picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE0E4E6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE0E4E6)),
                ),
                suffixIcon: const Icon(
                  Icons.expand_more_rounded,
                  color: Color(0xFF57636C),
                ),
              ),
              child: Text(
                SellerReservationPolicyService.formatTtl(current),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF101518),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<int?> _pickTtlSeconds({
    required int current,
    required List<int> presets,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Text(
                    'Escolher duração',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF101518),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in presets)
                          ListTile(
                            key: s == current
                                ? const Key('ttl_selected')
                                : null,
                            title: Text(
                              SellerReservationPolicyService.formatTtl(s),
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: s == current
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: const Color(0xFF101518),
                              ),
                            ),
                            trailing: s == current
                                ? const Text(
                                    '✓',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: FleaberColors.teal,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.pop(ctx, s),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
