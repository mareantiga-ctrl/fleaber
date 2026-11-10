import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_staff_service.dart';

/// Destaque para convites de colaborador pendentes (aceitar/rejeitar).
class HelperPendingInvitesBanner extends StatelessWidget {
  const HelperPendingInvitesBanner({super.key});

  static void openPendingInvites(BuildContext context) {
    final pending = SellerStaffContext.instance.myPendingInvitations;
    if (pending.isEmpty) return;
    if (pending.length == 1) {
      final id = pending.first.id;
      context.pushNamed(
        HelperInvitationPageWidget.routeName,
        queryParameters: {
          if (id != null && id.isNotEmpty)
            'helperLinkId': serializeParam(id, ParamType.String),
        }.withoutNulls,
      );
      return;
    }
    context.pushNamed(HelperAccessPageWidget.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SellerStaffContext.instance,
      builder: (context, _) {
        final pending = SellerStaffContext.instance.myPendingInvitations;
        if (pending.isEmpty) return const SizedBox.shrink();

        final count = pending.length;
        final first = pending.first;
        final storeLabel = first.displayName?.trim().isNotEmpty == true
            ? first.displayName!.trim()
            : 'uma loja';

        return Material(
          color: const Color(0xFFFFF8E6),
          borderRadius: FleaberRadius.circularMd,
          child: InkWell(
            onTap: () => openPendingInvites(context),
            borderRadius: FleaberRadius.circularMd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: FleaberRadius.circularMd,
                border: Border.all(color: const Color(0xFFFFE0A8)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.group_add_outlined,
                    color: FleaberColors.teal,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 1
                              ? 'Convite para ser colaborador'
                              : '$count convites de colaborador',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: const Color(0xFF101518),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count == 1
                              ? 'De $storeLabel — aceita ou rejeita o convite'
                              : 'Toca para ver todos os convites',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF57636C),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => openPendingInvites(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: FleaberColors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Ver convite',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
