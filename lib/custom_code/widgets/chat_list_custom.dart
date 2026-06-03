// Automatic FlutterFlow imports
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

// import '/backend/supabase/supabase.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatListCustom extends StatefulWidget {
  const ChatListCustom({
    super.key,
    this.width,
    this.height,
    required this.mensagens,
  });

  final double? width;
  final double? height;
  final List<ChatMessagesRow> mensagens;

  @override
  State<ChatListCustom> createState() => _ChatListCustomState();
}

class _ChatListCustomState extends State<ChatListCustom> {
  String getDisplayDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Hoje';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Ontem';
    }
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: widget.mensagens.length,
        itemBuilder: (context, index) {
          final msg = widget.mensagens[index];
          final date = msg.createdAt ?? DateTime.now();

          // Lógica do Separador
          bool showSeparator = false;
          if (index == 0) {
            showSeparator = true;
          } else {
            final prevDate = widget.mensagens[index - 1].createdAt;
            if (prevDate != null && date.day != prevDate.day) {
              showSeparator = true;
            }
          }

          return Column(
            children: [
              if (showSeparator)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        getDisplayDate(date),
                        style: const TextStyle(
                            color: Color(0xFF777777), fontSize: 11),
                      ),
                    ),
                  ),
                ),

              // Balão de Mensagem (Simplificado para o layout)
              Align(
                alignment: msg.senderId == currentUserUid
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  child: Column(
                    crossAxisAlignment: msg.senderId == currentUserUid
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: msg.senderId == currentUserUid
                              ? const Color(0xFF007782)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          msg.text ?? '',
                          style: TextStyle(
                              color: msg.senderId == currentUserUid
                                  ? Colors.white
                                  : Colors.black),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm').format(date),
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFAAAAAA)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Set your widget name, define your parameter, and then add the
// boilerplate code using the green button on the right!
