import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/utils/fleaber_colors.dart';
import '/utils/seller_professional.dart';
import '/widgets/fleaber_primary_button.dart';

/// Separador Admin — fila de verificação profissional.
class AdminSellerTradeTab extends StatefulWidget {
  const AdminSellerTradeTab({super.key});

  @override
  State<AdminSellerTradeTab> createState() => _AdminSellerTradeTabState();
}

class _AdminSellerTradeTabState extends State<AdminSellerTradeTab> {
  String _filter = 'pending';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return SellerProfessionalService.adminListQueue(
      status: _filter,
      limit: 80,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openReview(Map<String, dynamic> row) async {
    final uid = row['user_id']?.toString() ?? '';
    if (uid.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AdminTradeReviewSheet(
        row: row,
        onDone: () {
          Navigator.pop(ctx);
          _refresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filter,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Filtro',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Em análise (+ alteração)'),
                    ),
                    DropdownMenuItem(
                      value: 'leave',
                      child: Text('Alteração de estatuto'),
                    ),
                    DropdownMenuItem(
                      value: 'incomplete',
                      child: Text('Dados por preencher'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Pedido rejeitado'),
                    ),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text('Profissional verificado'),
                    ),
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _filter = v;
                      _future = _load();
                    });
                  },
                ),
              ),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: FleaberColors.teal),
                );
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    'Sem pedidos neste filtro.',
                    style: GoogleFonts.inter(color: FleaberColors.muted),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final name = (r['trade_name'] ?? r['full_name'] ?? '—')
                      .toString();
                  final status = (r['verification_status'] ?? '').toString();
                  final docs = r['doc_count'] ?? 0;
                  final leavePending = r['leave_request_pending'] == true;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      onTap: () => _openReview(r),
                      title: Text(
                        leavePending ? '$name · alteração de estatuto' : name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        leavePending
                            ? '${r['full_name'] ?? ''} · pedido para deixar '
                                'de ser profissional\n'
                                'Motivo: ${r['leave_request_reason'] ?? '—'}'
                            : '${r['full_name'] ?? ''} · $status · $docs doc(s)\n'
                                'NIF: ${r['nif'] ?? '—'} · ${r['city'] ?? ''}',
                        style: GoogleFonts.inter(fontSize: 12, height: 1.35),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AdminTradeReviewSheet extends StatefulWidget {
  const _AdminTradeReviewSheet({required this.row, required this.onDone});

  final Map<String, dynamic> row;
  final VoidCallback onDone;

  @override
  State<_AdminTradeReviewSheet> createState() => _AdminTradeReviewSheetState();
}

class _AdminTradeReviewSheetState extends State<_AdminTradeReviewSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  List<Map<String, dynamic>> _docs = [];

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    final uid = widget.row['user_id']?.toString() ?? '';
    if (uid.isEmpty) return;
    try {
      final docs = await SellerProfessionalService.adminListDocs(uid);
      if (mounted) setState(() => _docs = docs);
    } catch (_) {}
  }

  Future<void> _openDoc(Map<String, dynamic> doc) async {
    final path = doc['storage_path']?.toString() ?? '';
    if (path.isEmpty) return;
    try {
      final url = await SellerProfessionalService.createSignedDocUrl(path);
      if (url == null || url.isEmpty) return;
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o documento: $e')),
      );
    }
  }

  Future<void> _review({required bool approve}) async {
    final uid = widget.row['user_id']?.toString() ?? '';
    if (uid.isEmpty) return;
    final leavePending = widget.row['leave_request_pending'] == true;
    if (!approve && _reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            leavePending
                ? 'Indica o motivo da rejeição do pedido de alteração.'
                : 'Indica o motivo da rejeição.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (leavePending) {
        await SellerProfessionalService.adminDecideLeave(
          userId: uid,
          approve: approve,
          reason: approve ? null : _reason.text.trim(),
        );
      } else {
        await SellerProfessionalService.adminReview(
          userId: uid,
          approve: approve,
          reason: approve ? null : _reason.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            leavePending
                ? (approve
                    ? 'Alteração aprovada — passa a particular.'
                    : 'Pedido de alteração rejeitado — mantém profissional.')
                : (approve ? 'Vendedor aprovado.' : 'Pedido rejeitado.'),
          ),
        ),
      );
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              r['leave_request_pending'] == true
                  ? 'Pedido de alteração de estatuto'
                  : 'Revisão profissional',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${r['trade_name'] ?? '—'}\n'
              '${r['legal_name'] ?? ''}\n'
              'NIF ${r['nif'] ?? '—'} · ${r['address_line'] ?? ''}, '
              '${r['postal_code'] ?? ''} ${r['city'] ?? ''} '
              '(${r['country'] ?? 'PT'})\n'
              '${r['email'] ?? ''} · ${r['phone'] ?? ''}\n'
              'Estado: ${r['verification_status']}'
              '${r['leave_request_pending'] == true ? '\nPedido para deixar de ser profissional\nMotivo: ${r['leave_request_reason'] ?? '—'}' : ''}',
              style: GoogleFonts.inter(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Documentos',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            if (_docs.isEmpty)
              Text(
                'Sem documentos carregados.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: FleaberColors.muted,
                ),
              )
            else
              ..._docs.map(
                (d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.lock_outline, size: 18),
                  title: Text(
                    d['file_name']?.toString() ?? 'Documento',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  trailing: TextButton(
                    onPressed: () => _openDoc(d),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo (obrigatório se rejeitar)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _review(approve: false),
                    child: Text(
                      r['leave_request_pending'] == true
                          ? 'Manter profissional'
                          : 'Rejeitar',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FleaberPrimaryButton(
                    label: r['leave_request_pending'] == true
                        ? 'Aprovar → particular'
                        : 'Aprovar',
                    height: 44,
                    borderRadius: 12,
                    loading: _busy,
                    onPressed: _busy ? null : () => _review(approve: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
