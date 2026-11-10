import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_professional.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/professional_seller_badge.dart';

/// Secção «Dados profissionais» — Definições de conta (app + H11).
class DadosProfissionaisSection extends StatefulWidget {
  const DadosProfissionaisSection({super.key, this.dense = false});

  final bool dense;

  @override
  State<DadosProfissionaisSection> createState() =>
      _DadosProfissionaisSectionState();
}

class _DadosProfissionaisSectionState extends State<DadosProfissionaisSection> {
  SellerTradeProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _docs = [];

  final _tradeName = TextEditingController();
  final _legalName = TextEditingController();
  final _nif = TextEditingController();
  final _address = TextEditingController();
  final _postal = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'PT');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _registry = TextEditingController();
  final _representative = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _tradeName,
      _legalName,
      _nif,
      _address,
      _postal,
      _city,
      _country,
      _phone,
      _email,
      _registry,
      _representative,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = currentUserUid;
      final p = await SellerProfessionalService.loadOwn(uid);
      final docs = await SellerProfessionalService.listOwnDocuments(uid);
      if (!mounted) return;
      _applyControllers(p);
      setState(() {
        _profile = p;
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar dados profissionais: $e')),
      );
    }
  }

  void _applyControllers(SellerTradeProfile p) {
    _tradeName.text = p.tradeName ?? '';
    _legalName.text = p.legalName ?? '';
    _nif.text = p.nif ?? '';
    _address.text = p.addressLine ?? '';
    _postal.text = p.postalCode ?? '';
    _city.text = p.city ?? '';
    _country.text = p.country;
    _phone.text = p.phone ?? '';
    _email.text = p.email ?? '';
    _registry.text = p.companyRegistry ?? '';
    _representative.text = p.representativeName ?? '';
  }

  SellerTradeProfile _fromForm({required bool isTrader}) {
    final base = _profile ?? SellerTradeProfile.empty(currentUserUid);
    return SellerTradeProfile(
      userId: currentUserUid,
      isTrader: isTrader,
      verificationStatus: base.verificationStatus,
      tradeName: _tradeName.text,
      legalName: _legalName.text,
      nif: _nif.text,
      addressLine: _address.text,
      postalCode: _postal.text,
      city: _city.text,
      country: _country.text,
      phone: _phone.text,
      email: _email.text,
      companyRegistry: _registry.text,
      representativeName: _representative.text,
      rejectionReason: base.rejectionReason,
      stripeKycHint: base.stripeKycHint,
      leaveRequestPending: base.leaveRequestPending,
      leaveRequestReason: base.leaveRequestReason,
      leaveRequestedAt: base.leaveRequestedAt,
    );
  }

  Future<void> _save({required bool submit}) async {
    setState(() => _saving = true);
    try {
      final isTrader = _profile?.isTrader == true;
      final draft = _fromForm(isTrader: isTrader);
      if (submit && !draft.hasMinimumTraderFields) {
        throw StateError(
          'Preenche nome comercial, nome legal, NIF, morada, contactos '
          'antes de submeter para análise.',
        );
      }
      final saved = await SellerProfessionalService.saveOwn(
        draft,
        submitForReview: submit,
      );
      if (!mounted) return;
      setState(() => _profile = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submit
                ? 'Pedido enviado — estado: ${saved.verificationStatus.labelPt}'
                : 'Dados profissionais guardados.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleTrader(bool value) async {
    // Verificado: não desactiva — só pedido de alteração (RPC).
    final current = _profile;
    if (current != null &&
        current.isVerifiedProfessional &&
        value == false) {
      await _requestLeaveStatus();
      return;
    }
    setState(() => _saving = true);
    try {
      final draft = _fromForm(isTrader: value);
      final saved = await SellerProfessionalService.saveOwn(draft);
      if (!mounted) return;
      setState(() => _profile = saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestLeaveStatus() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Pedir alteração de estatuto',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se fores profissional verificado, não podes voltar a particular '
              'de imediato. A Fleaber analisa o pedido. Enquanto estiver em '
              'análise, manténs a identificação profissional.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar pedido'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final saved = await SellerProfessionalService.requestLeave(
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      setState(() => _profile = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedido enviado. Manténs o estatuto profissional até a '
            'Fleaber decidir.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadBytes({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Não foi possível ler o ficheiro.');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Ficheiro demasiado grande (máx. 5 MB).');
    }
    final uid = currentUserUid;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await SupaFlow.client.storage.from('seller-trade-docs').uploadBinary(
          path,
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );
    await SellerProfessionalService.registerDocument(
      userId: uid,
      storagePath: path,
      fileName: fileName,
      mimeType: contentType,
      byteSize: bytes.length,
    );
    final docs = await SellerProfessionalService.listOwnDocuments(uid);
    if (!mounted) return;
    setState(() => _docs = docs);
  }

  Future<void> _pickDocImage() async {
    final picked = await FleaberGalleryPicker.pickSingleImage(
      maxWidth: 2000,
      imageQuality: 88,
    );
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await picked.readAsBytes();
      final lower = picked.name.toLowerCase();
      var contentType = 'image/jpeg';
      if (lower.endsWith('.png')) contentType = 'image/png';
      if (lower.endsWith('.webp')) contentType = 'image/webp';
      await _uploadBytes(
        bytes: bytes,
        fileName: picked.name,
        contentType: contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem enviada (privada).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload falhou: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDocPdfOrFile() async {
    setState(() => _saving = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Não foi possível ler o ficheiro (tenta outra vez).');
      }
      final name = f.name;
      final lower = name.toLowerCase();
      String contentType = 'application/octet-stream';
      if (lower.endsWith('.pdf')) contentType = 'application/pdf';
      if (lower.endsWith('.png')) contentType = 'image/png';
      if (lower.endsWith('.webp')) contentType = 'image/webp';
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      }
      await _uploadBytes(
        bytes: bytes,
        fileName: name,
        contentType: contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento enviado (privado).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload falhou: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      border: OutlineInputBorder(borderRadius: FleaberRadius.circularMd),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dense = widget.dense;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = _profile ?? SellerTradeProfile.empty(currentUserUid);
    final status = p.verificationStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dados profissionais',
          style: GoogleFonts.inter(
            fontSize: dense ? 15 : 16,
            fontWeight: FontWeight.w800,
            color: FleaberColors.text,
          ),
        ),
        SizedBox(height: dense ? 6 : 8),
        Text(
          'Se vendes no âmbito de uma actividade comercial, declara-te como '
          'vendedor profissional. Os particulares não precisam de preencher '
          'esta secção. O NIF e os documentos de verificação ficam privados — '
          'não são dados aos compradores.',
          style: GoogleFonts.inter(
            fontSize: FleaHubSiteLayout.typeSecondary,
            color: FleaberColors.muted,
            height: 1.35,
          ),
        ),
        SizedBox(height: dense ? 10 : 12),
        if (p.isVerifiedProfessional) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Vendedor profissional verificado',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              p.leaveRequestPending
                  ? 'Pedido de alteração de estatuto em análise. '
                      'Manténs a identificação profissional até haver decisão.'
                  : status.nextStepPt,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: FleaberColors.muted,
                height: 1.35,
              ),
            ),
          ),
          if (!p.leaveRequestPending)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _saving ? null : _requestLeaveStatus,
                child: const Text('Pedir alteração de estatuto'),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F8F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFC5E0E3)),
              ),
              child: Text(
                'Pedido enviado'
                '${(p.leaveRequestReason ?? '').isNotEmpty ? ': ${p.leaveRequestReason}' : ''}. '
                'Aguarda a decisão da administração.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.35,
                  color: FleaberColors.text,
                ),
              ),
            ),
        ] else
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Sou vendedor profissional',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              p.isTrader
                  ? 'Estado: ${status.labelPt}. ${status.nextStepPt}'
                  : 'Manténs-te como particular (sem distintivo).',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: FleaberColors.muted,
                height: 1.35,
              ),
            ),
            value: p.isTrader,
            activeColor: FleaberColors.teal,
            onChanged: _saving ? null : (v) => _toggleTrader(v),
          ),
        if (p.isTrader) ...[
          const SizedBox(height: 8),
          if (p.showProfessionalBadge)
            Row(
              children: [
                const ProfessionalSellerBadge(),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Verificação concluída. O distintivo aparece no perfil '
                    'e nos anúncios. Os compradores contactam-te pelo chat '
                    'Fleaber — não publicamos o teu telefone nem email.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: FleaberColors.muted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8D4A8)),
              ),
              child: Text(
                p.salesSuspended
                    ? 'Novas vendas suspensas até a Fleaber aprovar a '
                        'verificação (estado: ${status.labelPt}). '
                        'Encomendas e mensagens em curso não são afectadas. '
                        '${status.nextStepPt}'
                    : 'Estado: ${status.labelPt}. ${status.nextStepPt}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.35,
                  color: const Color(0xFF5C4A1F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (status == SellerVerificationStatus.rejected &&
              (p.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Motivo da rejeição: ${p.rejectionReason}\n'
              'Corrige os dados ou documentos e volta a submeter.',
              style: GoogleFonts.inter(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _tradeName,
            decoration: _dec('Nome comercial / denominação social'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _legalName,
            decoration: _dec('Nome legal do empresário / sociedade'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nif,
            decoration: _dec(
              'NIF / NIPC',
              helper: 'Privado — não aparece no perfil público.',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: _dec('Morada profissional'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _postal,
                  decoration: _dec('Código postal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _city,
                  decoration: _dec('Localidade'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _country,
            decoration: _dec('País de estabelecimento'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            decoration: _dec(
              'Telefone profissional',
              helper: 'Só para a Fleaber verificar a conta — não aparece '
                  'aos compradores.',
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            decoration: _dec(
              'Email profissional',
              helper: 'Só para a Fleaber verificar a conta — não aparece '
                  'aos compradores.',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _registry,
            decoration: _dec(
              'Registo comercial (opcional)',
              helper: 'Quando aplicável à tua forma jurídica.',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _representative,
            decoration: _dec(
              'Representante / poderes (opcional)',
              helper: 'Se alguém age em nome da sociedade.',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Documentação comprovativa (privada)',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Imagem ou PDF até 5 MB (CC, certidão ou comprovativo). '
            'Acesso privado — só tu e a administração Fleaber.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: FleaberColors.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDocImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Imagem'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDocPdfOrFile,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF / ficheiro'),
              ),
            ],
          ),
          if (_docs.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._docs.map(
              (d) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline, size: 18),
                title: Text(
                  d['file_name']?.toString() ?? 'Documento',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                subtitle: Text(
                  'Privado · ${d['created_at'] ?? ''}',
                  style: GoogleFonts.inter(fontSize: 11),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(submit: false),
                  child: const Text('Guardar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FleaberPrimaryButton(
                  label: 'Submeter análise',
                  height: 44,
                  borderRadius: 12,
                  loading: _saving,
                  onPressed: _saving ? null : () => _save(submit: true),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
