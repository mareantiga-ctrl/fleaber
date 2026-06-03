import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/batata_bundle_discounts.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_primary_button.dart';

class DescontosConjuntosWidget extends StatefulWidget {
  const DescontosConjuntosWidget({super.key});

  static String routeName = 'DescontosConjuntos';
  static String routePath = '/descontosConjuntos';

  @override
  State<DescontosConjuntosWidget> createState() =>
      _DescontosConjuntosWidgetState();
}

class _CustomTierDraft {
  _CustomTierDraft({int? minItems, this.pct})
      : minItemsCtrl = TextEditingController(
          text: minItems != null ? '$minItems' : '',
        );

  final TextEditingController minItemsCtrl;
  double? pct;

  void dispose() => minItemsCtrl.dispose();
}

class _DescontosConjuntosWidgetState extends State<DescontosConjuntosWidget> {
  static const _pctOptions = [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0];

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  double? _tier2;
  double? _tier3;
  double? _tier5;
  final List<_CustomTierDraft> _customDrafts = [];

  @override
  void dispose() {
    for (final d in _customDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tiers = await fetchSellerBundleDiscounts(currentUserUid);
    if (!mounted) return;
    for (final d in _customDrafts) {
      d.dispose();
    }
    _customDrafts.clear();
    for (final r in tiers.customRules) {
      _customDrafts.add(_CustomTierDraft(minItems: r.minItems, pct: r.pct));
    }
    setState(() {
      _enabled = tiers.enabled;
      _tier2 = tiers.tier2Pct;
      _tier3 = tiers.tier3Pct;
      _tier5 = tiers.tier5Pct;
      _loading = false;
    });
  }

  List<BundleDiscountRule>? _buildCustomRulesForSave() {
    final rules = <BundleDiscountRule>[];
    final seen = <int>{};
    for (final d in _customDrafts) {
      final min = int.tryParse(d.minItemsCtrl.text.trim());
      final pct = d.pct;
      if (min == null || min < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cada regra personalizada precisa de um número mínimo de artigos (≥ 2).',
            ),
          ),
        );
        return null;
      }
      if (pct == null || pct <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escolhe a percentagem de desconto em cada regra.'),
          ),
        );
        return null;
      }
      if (!seen.add(min)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Já existe uma regra para $min artigos.'),
          ),
        );
        return null;
      }
      rules.add(BundleDiscountRule(minItems: min, pct: pct));
    }
    rules.sort((a, b) => a.minItems.compareTo(b.minItems));
    return rules;
  }

  Future<void> _save() async {
    if (currentUserUid.isEmpty) return;

    final customRules = _buildCustomRulesForSave();
    if (customRules == null) return;

    final hasPreset = (_tier2 ?? 0) > 0 || (_tier3 ?? 0) > 0 || (_tier5 ?? 0) > 0;
    if (_enabled && !hasPreset && customRules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Activa pelo menos um escalão sugerido ou adiciona uma regra personalizada.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await saveSellerBundleDiscounts(
        sellerId: currentUserUid,
        enabled: _enabled,
        tier2Pct: _enabled && (_tier2 ?? 0) > 0 ? _tier2 : null,
        tier3Pct: _enabled && (_tier3 ?? 0) > 0 ? _tier3 : null,
        tier5Pct: _enabled && (_tier5 ?? 0) > 0 ? _tier5 : null,
        customRules: _enabled ? customRules : const [],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descontos guardados.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('custom_tiers')
                ? 'Falta a coluna custom_tiers. Corre supabase/sql/seller_bundle_discounts_custom_tiers_batata.sql'
                : msg.replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addCustomRow() {
    setState(() => _customDrafts.add(_CustomTierDraft()));
  }

  void _removeCustomRow(int index) {
    setState(() {
      _customDrafts[index].dispose();
      _customDrafts.removeAt(index);
    });
  }

  Widget _presetTierRow(
    String label,
    double? value,
    ValueChanged<double?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF101518),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<double>(
              value: _pctOptions.contains(value) ? value : 0.0,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: _pctOptions
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        p == 0 ? 'Ignorar' : '${p.toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 15),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _customTierRow(int index) {
    final draft = _customDrafts[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: draft.minItemsCtrl,
              enabled: _enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Mín. artigos',
                filled: true,
                fillColor: Colors.white,
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              style: GoogleFonts.inter(fontSize: 15),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<double>(
              value: draft.pct != null && _pctOptions.contains(draft.pct)
                  ? draft.pct
                  : null,
              hint: Text(
                'Desconto %',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: const Color(0xFF57636C),
                ),
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: _pctOptions
                  .where((p) => p > 0)
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        '${p.toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 15),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _enabled
                  ? (v) => setState(() => draft.pct = v)
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Remover regra',
            onPressed: _enabled ? () => _removeCustomRow(index) : null,
            icon: const Icon(Icons.close_rounded, color: Color(0xFF57636C)),
          ),
        ],
      ),
    );
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
          'Descontos de conjuntos',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: const Color(0xFF101518),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FleaberColors.teal),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Ativar descontos em conjuntos',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  activeColor: FleaberColors.teal,
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const Divider(height: 24),
                Text(
                  'Sugestões da app (opcional)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Podes ignorar estas linhas e usar só regras personalizadas.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 12),
                _presetTierRow(
                  '2 artigos',
                  _tier2 ?? 0,
                  (v) => setState(() => _tier2 = v == 0 ? null : v),
                ),
                _presetTierRow(
                  '3 artigos',
                  _tier3 ?? 0,
                  (v) => setState(() => _tier3 = v == 0 ? null : v),
                ),
                _presetTierRow(
                  '5+ artigos',
                  _tier5 ?? 0,
                  (v) => setState(() => _tier5 = v == 0 ? null : v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Regras personalizadas',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF57636C),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _enabled ? _addCustomRow : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Adicionar'),
                      style: TextButton.styleFrom(
                        foregroundColor: FleaberColors.teal,
                      ),
                    ),
                  ],
                ),
                if (_customDrafts.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: FleaberColors.bgTint,
                      borderRadius: FleaberRadius.circularMd,
                    ),
                    child: Text(
                      'Ex.: 4 artigos com 12% — toca em Adicionar para criar a tua regra.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.45,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  )
                else
                  ...List.generate(
                    _customDrafts.length,
                    (i) => _customTierRow(i),
                  ),
                const SizedBox(height: 24),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'Guardar',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
