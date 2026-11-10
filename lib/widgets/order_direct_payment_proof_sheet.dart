import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_private_storage.dart';
import '/widgets/fleaber_primary_button.dart';

const Color _kTeal = Color(0xFF007782);

/// Sheet para o comprador confirmar pagamento directo (print + nota).
Future<bool> showOrderDirectPaymentProofSheet(
  BuildContext context, {
  required OrdersRow order,
}) async {
  final notesController = TextEditingController();
  XFile? selectedFile;
  final picker = ImagePicker();

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confirmar pagamento',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: const Color(0xFF101518),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Se já pagaste por MB WAY ou transferência, envia a prova '
                  '(opcional) e uma nota para o vendedor.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.35,
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: GoogleFonts.inter(color: const Color(0xFF101518)),
                  decoration: InputDecoration(
                    labelText: 'Nota (opcional)',
                    hintText: 'Ex.: MB WAY enviado às 10:42',
                    labelStyle: GoogleFonts.inter(
                      color: const Color(0xFF57636C),
                    ),
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF9AA4B2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: FleaberRadius.circularMd,
                      borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: FleaberRadius.circularMd,
                      borderSide: const BorderSide(color: _kTeal, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked == null) return;
                    setSheetState(() => selectedFile = picked);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    selectedFile == null
                        ? 'Anexar print / imagem da prova'
                        : 'Anexo: ${selectedFile!.name}',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTeal,
                    side: const BorderSide(color: _kTeal),
                  ),
                ),
                const SizedBox(height: 16),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'Enviar confirmação',
                  onPressed: () => Navigator.of(sheetCtx).pop(true),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(false),
                  child: Text(
                    'Voltar',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF57636C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  if (ok != true) return false;

  try {
    await submitOrderDirectPaymentProof(
      order: order,
      notes: notesController.text.trim(),
      image: selectedFile,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prova de pagamento enviada.')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao submeter prova de pagamento.')),
      );
    }
    return false;
  } finally {
    notesController.dispose();
  }
}

Future<void> submitOrderDirectPaymentProof({
  required OrdersRow order,
  required String notes,
  XFile? image,
}) async {
  final orderId = order.id?.trim() ?? '';
  final sellerId = order.sellerId?.trim() ?? '';
  if (orderId.isEmpty || sellerId.isEmpty || currentUserUid.isEmpty) {
    throw Exception('Encomenda inválida.');
  }

  String? proofUrl;
  if (image != null) {
    final bytes = await image.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    proofUrl = await FleaberPrivateStorage.uploadOrderProof(
      bytes: bytes,
      fileName: fileName,
      orderId: orderId,
    );
  }

  final orderUpdate = <String, dynamic>{
    'status': 'aguarda_confirmacao',
  };
  if (proofUrl != null && proofUrl.isNotEmpty) {
    orderUpdate['proof_url'] = proofUrl;
  }
  await OrdersTable().update(
    data: orderUpdate,
    matchingRows: (rows) => rows.eqOrNull('id', orderId),
  );

  final chat = await resolveChatForOrder(
    otherUserId: sellerId,
    orderId: orderId,
    productId: order.productId,
  );
  final chatId = chat.id?.trim() ?? '';
  if (chatId.isEmpty) {
    throw Exception('Não foi possível abrir o chat.');
  }

  final payload = <String, dynamic>{
    'kind': 'reservation_payment_submitted',
    'order_id': orderId,
    'notes': notes,
    'v': 1,
  };
  if (proofUrl != null && proofUrl.isNotEmpty) {
    payload['proof_url'] = proofUrl;
  }
  await ChatMessagesTable().insert({
    'sender_id': currentUserUid,
    'receiver_id': sellerId,
    'is_read': false,
    'text': fleaberChatJsonEncode(payload),
    'chat_id': chatId,
    'is_reservation': true,
  });
  await touchChatLastMessage(
    chatId: chatId,
    preview: 'Prova de pagamento enviada',
  );
  requestMarketplaceFeedRefresh();
}
