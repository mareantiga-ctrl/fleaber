import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';

/// Admin — expedições DPD, erros e tarifas (leitura + edição preços).
class AdminDpdTab extends StatefulWidget {
  const AdminDpdTab({super.key});

  @override
  State<AdminDpdTab> createState() => _AdminDpdTabState();
}

class _AdminDpdTabState extends State<AdminDpdTab> {
  static const _teal = Color(0xFF007782);
  late Future<_DpdAdminData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DpdAdminData> _load() async {
    final rates = await SupaFlow.client
        .from('dpd_shipping_rates')
        .select()
        .order('modality')
        .order('weight_band');
    final flags = await SupaFlow.client
        .from('fleaber_feature_flags')
        .select()
        .like('key', 'dpd_%');
    final exp = await SupaFlow.client.rpc(
      'batata_admin_dpd_expeditions',
      params: {'p_limit': 40},
    );
    return _DpdAdminData(
      rates: (rates as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      flags: (flags as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      expeditions: (exp is Map && exp['rows'] is List)
          ? (exp['rows'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : const [],
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _saveRate(String id, double price) async {
    await SupaFlow.client.from('dpd_shipping_rates').update({
      'price_eur': price,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DpdAdminData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }
        final data = snap.data!;
        return RefreshIndicator(
          color: _teal,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Flags DPD (espelho UI — secrets Edge mandam)',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...data.flags.map((f) {
                final on = f['enabled'] == true;
                return ListTile(
                  dense: true,
                  title: Text(f['key']?.toString() ?? ''),
                  subtitle: Text(f['note']?.toString() ?? ''),
                  trailing: Text(
                    on ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: on ? Colors.orange : FleaberColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }),
              const Divider(height: 32),
              Text(
                'Tarifas ao comprador (editáveis)',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Shop→Home só deve activar-se após validar combustível. '
                'Cobrança real gated por dpd_shipping_rates_live.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              ...data.rates.map((r) {
                final id = r['id']?.toString() ?? '';
                final price = (r['price_eur'] as num?)?.toDouble() ?? 0;
                final ctrl = TextEditingController(
                  text: price.toStringAsFixed(2),
                );
                return Card(
                  child: ListTile(
                    title: Text(
                      '${r['modality']} · ${r['weight_band']} (≤${r['max_kg']} kg)',
                    ),
                    subtitle: TextField(
                      controller: ctrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço €',
                        isDense: true,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.save_outlined, color: _teal),
                      onPressed: () {
                        final v = double.tryParse(
                          ctrl.text.trim().replaceAll(',', '.'),
                        );
                        if (v == null || id.isEmpty) return;
                        _saveRate(id, v);
                      },
                    ),
                  ),
                );
              }),
              const Divider(height: 32),
              Text(
                'Expedições / erros recentes',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (data.expeditions.isEmpty)
                Text(
                  'Sem expedições DPD ainda.',
                  style: GoogleFonts.inter(color: Colors.black54),
                ),
              ...data.expeditions.map((e) {
                return Card(
                  child: ListTile(
                    title: Text(
                      (e['dpd_tracking_code'] ?? e['id'] ?? '').toString(),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        'status=${e['status']}',
                        if (e['dpd_service'] != null) 'svc=${e['dpd_service']}',
                        if (e['dpd_last_error'] != null)
                          'err=${e['dpd_last_error']}',
                      ].join('\n'),
                      maxLines: 4,
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _DpdAdminData {
  const _DpdAdminData({
    required this.rates,
    required this.flags,
    required this.expeditions,
  });
  final List<Map<String, dynamic>> rates;
  final List<Map<String, dynamic>> flags;
  final List<Map<String, dynamic>> expeditions;
}
