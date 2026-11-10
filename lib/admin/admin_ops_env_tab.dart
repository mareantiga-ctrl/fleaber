import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

/// ZIP 171/172 — ambientes Stripe/DPD para Red Teams (admin only).
/// Default TEST+QA. LIVE/COMERCIAL exigem confirmação e ficam bloqueados
/// na execução até GO + secrets dual. Sticky por encomenda; imutável após
/// pagamento/expedição. Não altera comportamento de clientes reais.
class AdminOpsEnvTab extends StatefulWidget {
  const AdminOpsEnvTab({super.key});

  @override
  State<AdminOpsEnvTab> createState() => _AdminOpsEnvTabState();
}

class _AdminOpsEnvTabState extends State<AdminOpsEnvTab> {
  static const _teal = Color(0xFF007782);
  late Future<Map<String, dynamic>?> _statusFuture;
  String _stripe = 'test';
  String _dpd = 'qa';
  final _reasonCtrl = TextEditingController(text: 'Red Team / QA');
  bool _confirmReal = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadStatus() async {
    final raw = await SupaFlow.client.rpc('batata_admin_ops_env_status');
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  Future<void> _refresh() async {
    setState(() {
      _statusFuture = _loadStatus();
      _message = null;
    });
    await _statusFuture;
  }

  bool get _needsConfirm => _stripe == 'live' || _dpd == 'commercial';

  Future<void> _openSession() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final raw = await SupaFlow.client.rpc(
        'batata_admin_ops_env_open',
        params: {
          'p_stripe_mode': _stripe,
          'p_dpd_mode': _dpd,
          'p_reason': _reasonCtrl.text.trim(),
          'p_confirm_real': _confirmReal,
        },
      );
      final map = raw is Map ? Map<String, dynamic>.from(raw) : {};
      setState(() {
        _message = (map['note'] ?? map['ok'] ?? 'OK').toString();
      });
      await _refresh();
    } catch (e) {
      setState(() => _message = 'Falha: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    setState(() => _busy = true);
    try {
      await SupaFlow.client.rpc('batata_admin_ops_env_close');
      setState(() => _message = 'Sessão fechada. Novas encomendas ficam TEST+QA.');
      await _refresh();
    } catch (e) {
      setState(() => _message = 'Falha ao fechar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _statusFuture,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }
        final status = snap.data;
        final active = status?['active_session'];
        final matrix = status?['matrix'] is Map
            ? Map<String, dynamic>.from(status!['matrix'] as Map)
            : const <String, dynamic>{};

        return RefreshIndicator(
          color: _teal,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Ambientes Stripe / DPD',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Predefinição para compradores reais: Stripe TEST + DPD QA. '
                'A sessão activa só afecta encomendas de teste que o admin '
                'ligar explicitamente (sticky). Não altera secrets Edge.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  title: const Text('Predefinição plataforma'),
                  subtitle: const Text('stripe=test · dpd=qa'),
                  trailing: Text(
                    'SEGURO',
                    style: GoogleFonts.inter(
                      color: FleaberColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (active is Map) ...[
                const SizedBox(height: 8),
                Card(
                  color: const Color(0xFFE8F5F6),
                  child: ListTile(
                    title: Text(
                      'Sessão activa: ${active['stripe_mode']}+${active['dpd_mode']}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${active['reason'] ?? ''}\n${active['note'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: TextButton(
                      onPressed: _busy ? null : _closeSession,
                      child: const Text('Fechar'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Abrir sessão de teste',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _stripe,
                decoration: const InputDecoration(
                  labelText: 'Stripe',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'test', child: Text('TEST')),
                  DropdownMenuItem(value: 'live', child: Text('LIVE')),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _stripe = v ?? 'test';
                          if (!_needsConfirm) _confirmReal = false;
                        }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _dpd,
                decoration: const InputDecoration(
                  labelText: 'DPD',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'qa', child: Text('QA')),
                  DropdownMenuItem(
                    value: 'commercial',
                    child: Text('COMERCIAL'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _dpd = v ?? 'qa';
                          if (!_needsConfirm) _confirmReal = false;
                        }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonCtrl,
                enabled: !_busy,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_needsConfirm) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmReal,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _confirmReal = v ?? false),
                  title: const Text(
                    'Confirmo operação REAL (LIVE e/ou DPD comercial). '
                    'Execução continua bloqueada até GO + credenciais dual.',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FleaberPrimaryButton(
                onPressed: _busy ? null : _openSession,
                label: _busy ? 'A guardar…' : 'Abrir sessão',
                loading: _busy,
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: GoogleFonts.inter(fontSize: 13)),
              ],
              const SizedBox(height: 24),
              Text(
                'Matriz de combinações',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...[
                ('test_qa', 'TEST + QA'),
                ('live_qa', 'LIVE + QA'),
                ('test_commercial', 'TEST + COMERCIAL'),
                ('live_commercial', 'LIVE + COMERCIAL'),
              ].map((e) {
                final state = (matrix[e.$1] ?? '—').toString();
                final ok = state == 'functional';
                return ListTile(
                  dense: true,
                  title: Text(e.$2),
                  trailing: Text(
                    state,
                    style: TextStyle(
                      color: ok ? FleaberColors.success : Colors.orange.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Text(
                'Para ligar uma encomenda de teste à sessão activa, usar a RPC '
                'batata_admin_ops_env_bind_order(order_id) (encomenda ainda sem pagamento).',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
      },
    );
  }
}
