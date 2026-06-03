import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';



import '/auth/supabase_auth/auth_util.dart';

import '/backend/supabase/supabase.dart';

import '/flutter_flow/flutter_flow_util.dart';

import '/utils/fleaber_colors.dart';

import '/utils/fleaber_radius.dart';
import '/utils/profile_patch_service.dart';
import '/widgets/fleaber_primary_button.dart';



/// Modo de férias — ausência temporária (oculta marketplace + bloqueia compras novas).

class ModoFeriasPageWidget extends StatefulWidget {

  const ModoFeriasPageWidget({super.key});



  static String routeName = 'ModoFerias';

  static String routePath = '/modoFerias';



  @override

  State<ModoFeriasPageWidget> createState() => _ModoFeriasPageWidgetState();

}



class _ModoFeriasPageWidgetState extends State<ModoFeriasPageWidget> {

  bool _loading = true;

  bool _saving = false;

  bool _vacationMode = false;

  String? _loadError;



  @override

  void initState() {

    super.initState();

    _load();

  }



  Future<void> _load() async {

    if (currentUserUid.isEmpty) {

      setState(() => _loading = false);

      return;

    }

    try {

      await ProfilePatchService.ensureOwnProfileRow();

      final row = await SupaFlow.client

          .from('profiles')

          .select('id, vacation_mode')

          .eq('id', currentUserUid)

          .maybeSingle();

      if (!mounted) return;

      setState(() {

        _vacationMode = row != null && row['vacation_mode'] == true;

        _loadError = null;

        _loading = false;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() {

        _loadError = e.toString();

        _loading = false;

      });

    }

  }



  Future<void> _saveVacation(bool value) async {

    if (currentUserUid.isEmpty) return;

    setState(() {

      _saving = true;

      _vacationMode = value;

    });

    try {

      final updated = await ProfilePatchService.patchOwnProfile(
        {'vacation_mode': value},
        select: 'vacation_mode',
      );

      if (updated == null) {

        throw Exception(
          'Não foi possível guardar. Executa supabase/sql/profiles_rls_batata.sql '
          'e profiles_vacation_mode_batata.sql no Supabase.',
        );

      }

      final persisted = updated['vacation_mode'] == true;

      if (persisted != value) {

        throw Exception(

          'O modo de férias não ficou guardado. Executa profiles_vacation_mode_batata.sql no SQL Editor.',

        );

      }



      if (!mounted) return;

      setState(() => _vacationMode = persisted);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(

            persisted

                ? 'Modo de férias ligado. Os teus anúncios e diretos deixam de aparecer no marketplace.'

                : 'Modo de férias desligado. Voltaste a estar disponível para novas compras.',

          ),

        ),

      );

    } catch (e) {

      if (!mounted) return;

      setState(() => _vacationMode = !value);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text(ProfilePatchService.friendlyError(e))),

      );

    } finally {

      if (mounted) setState(() => _saving = false);

    }

  }



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: FleaberColors.bgTint,

      appBar: AppBar(

        backgroundColor: Colors.white,

        elevation: 0,

        iconTheme: const IconThemeData(color: Color(0xFF101518)),

        title: Text(

          'Modo de férias',

          style: GoogleFonts.inter(

            fontWeight: FontWeight.w700,

            fontSize: 18,

            color: const Color(0xFF101518),

          ),

        ),

      ),

      body: _loading

          ? const Center(child: CircularProgressIndicator(color: FleaberColors.teal))

          : ListView(

              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),

              children: [

                if (_loadError != null) ...[

                  Container(

                    width: double.infinity,

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(

                      color: const Color(0xFFFFEBEE),

                      borderRadius: FleaberRadius.circularMd,

                      border: Border.all(color: const Color(0xFFEF9A9A)),

                    ),

                    child: Text(

                      _loadError!,

                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFB71C1C)),

                    ),

                  ),

                  const SizedBox(height: 12),

                ],

                _infoCard(

                  icon: Icons.beach_access_rounded,

                  iconColor: FleaberColors.teal,

                  title: 'Modo de férias',

                  children: [

                    Text(

                      'Quando está ligado:\n'

                      '• Os teus anúncios e diretos ficam ocultos no marketplace e na Home.\n'

                      '• Ninguém pode comprar nem fazer propostas novas contigo.\n'

                      '• As conversas sobre os teus artigos mantêm-se.\n'

                      '• Encomendas já em curso (reservas, envios, pagamentos) continuam normalmente.',

                      style: _bodyStyle,

                    ),

                    const SizedBox(height: 16),

                    Container(

                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),

                      decoration: BoxDecoration(

                        color: Colors.white,

                        borderRadius: FleaberRadius.circularMd,

                        border: Border.all(color: const Color(0xFFE0E3E7)),

                      ),

                      child: SwitchListTile(

                        contentPadding: EdgeInsets.zero,

                        title: Text(

                          _vacationMode ? 'Ligado' : 'Desligado',

                          style: GoogleFonts.inter(

                            fontWeight: FontWeight.w700,

                            fontSize: 15,

                            color: const Color(0xFF101518),

                          ),

                        ),

                        subtitle: Text(

                          _vacationMode

                              ? 'Estas de ferias'

                              : 'Disponível para vender',

                          style: GoogleFonts.inter(

                            fontSize: 13,

                            color: const Color(0xFF57636C),

                          ),

                        ),

                        value: _vacationMode,

                        activeTrackColor: FleaberColors.teal.withValues(alpha: 0.4),

                        activeThumbColor: FleaberColors.teal,

                        onChanged: _saving ? null : _saveVacation,

                      ),

                    ),

                  ],

                ),

                const SizedBox(height: 20),

                FleaberPrimaryButton(

                  width: double.infinity,

                  label: 'Voltar',

                  onPressed: () => context.safePop(),

                ),

              ],

            ),

    );

  }



  TextStyle get _bodyStyle => GoogleFonts.inter(

        fontSize: 14,

        height: 1.45,

        color: const Color(0xFF57636C),

      );



  Widget _infoCard({

    required IconData icon,

    required Color iconColor,

    required String title,

    required List<Widget> children,

  }) {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: FleaberRadius.circularMd,

        boxShadow: const [

          BoxShadow(

            color: Color(0x12000000),

            blurRadius: 12,

            offset: Offset(0, 4),

          ),

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            children: [

              Icon(icon, color: iconColor, size: 26),

              const SizedBox(width: 10),

              Expanded(

                child: Text(

                  title,

                  style: GoogleFonts.inter(

                    fontSize: 17,

                    fontWeight: FontWeight.w800,

                    color: const Color(0xFF101518),

                  ),

                ),

              ),

            ],

          ),

          const SizedBox(height: 12),

          ...children,

        ],

      ),

    );

  }

}


