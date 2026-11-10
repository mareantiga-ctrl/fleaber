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

  const ModoFeriasPageWidget({super.key, this.embedded = false});

  final bool embedded;



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
    // Web/shell: UID pode chegar depois do mount.
    for (var i = 0; i < 30 && currentUserUid.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (currentUserUid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'Sessão em falta. Volta a iniciar sessão para gerir o modo de férias.';
      });
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



  String? _saveError;

  void _showToast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: widget.embedded
            ? const EdgeInsets.only(left: 24, right: 24, bottom: 24)
            : const EdgeInsets.fromLTRB(16, 0, 16, 16),
        width: widget.embedded ? 420 : null,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveVacation(bool value) async {
    if (currentUserUid.isEmpty) {
      setState(() {
        _saveError = 'Sessão em falta. Volta a iniciar sessão e tenta outra vez.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _vacationMode = value;
      _saveError = null;
    });

    try {
      final updated = await ProfilePatchService.patchOwnProfile(
        {'vacation_mode': value},
        select: 'vacation_mode',
      );

      if (updated == null) {
        throw Exception(
          'Não foi possível guardar o modo de férias. Tenta outra vez.',
        );
      }

      // Confirmação efectiva na BD (não confiar só no eco do patch).
      final verify = await SupaFlow.client
          .from('profiles')
          .select('vacation_mode')
          .eq('id', currentUserUid)
          .maybeSingle();
      final persisted = verify != null && verify['vacation_mode'] == true;
      if (persisted != value) {
        throw Exception(
          'O modo de férias não ficou guardado. Tenta outra vez daqui a um momento.',
        );
      }

      if (!mounted) return;
      setState(() => _vacationMode = persisted);
      _showToast(
        persisted
            ? 'Modo de férias ligado. Os teus anúncios e diretos deixam de aparecer no marketplace.'
            : 'Modo de férias desligado. Voltaste a estar disponível para novas compras.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vacationMode = !value;
        _saveError = ProfilePatchService.friendlyError(e);
      });
      _showToast(_saveError!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }



  @override

  Widget build(BuildContext context) {

    const bg = FleaberColors.bgTint;

    final body = _loading

          ? const Center(child: CircularProgressIndicator(color: FleaberColors.teal))

          : ListView(

              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 4 : 16,
                12,
                widget.embedded ? 4 : 16,
                28,
              ),

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

                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.embedded ? 720 : double.infinity,
                    ),
                    child: _infoCard(

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

                    Material(
                      color: Colors.white,
                      borderRadius: FleaberRadius.circularMd,
                      child: InkWell(
                        borderRadius: FleaberRadius.circularMd,
                        onTap: _saving
                            ? null
                            : () => _saveVacation(!_vacationMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: FleaberRadius.circularMd,
                            border: Border.all(
                              color: const Color(0xFFE0E3E7),
                            ),
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
                                  ? 'Estás de férias — anúncios e diretos ocultos no marketplace'
                                  : 'Disponível para vender',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF57636C),
                              ),
                            ),
                            value: _vacationMode,
                            activeTrackColor:
                                FleaberColors.teal.withValues(alpha: 0.4),
                            activeThumbColor: FleaberColors.teal,
                            onChanged: _saving ? null : _saveVacation,
                          ),
                        ),
                      ),
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(
                        color: FleaberColors.teal,
                        minHeight: 2,
                      ),
                    ],
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _saveError!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFFB00020),
                          height: 1.35,
                        ),
                      ),
                    ],

                  ],

                ),
                  ),
                ),

                const SizedBox(height: 20),

                if (!widget.embedded)
                  FleaberPrimaryButton(

                    width: double.infinity,

                    label: 'Voltar',

                    onPressed: () => context.safePop(),

                  ),

              ],

            );

    if (widget.embedded) {

      return ColoredBox(color: bg, child: body);

    }

    return Scaffold(

      backgroundColor: bg,

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

      body: body,

    );

  }



  TextStyle get _bodyStyle => GoogleFonts.inter(
        fontSize: 14.5,
        height: 1.55,
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


