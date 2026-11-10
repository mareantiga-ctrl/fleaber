import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/live_director/data/live_director_repository.dart';
import '/live_director/engine/live_director_engine.dart';
import '/live_director/models/director_beat.dart';
import '/live_director/models/director_manifest.dart';
import '/live_director/models/director_run.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';
import '/live_director/replay/director_replay_reader.dart';
import '/live_director/services/director_dry_run_service.dart';
import '/live_director/services/director_heat_map_service.dart';
import '/live_director/services/director_script_preview_service.dart';
import '/live_director/services/director_script_validator.dart';
import '/live_director/services/director_template_service.dart';
import '/utils/batata_admin_util.dart';
import '/utils/fleaber_colors.dart';

/// Admin — Live Director Platform (`/admin/live-director`).
class AdminLiveDirectorPageWidget extends StatefulWidget {
  const AdminLiveDirectorPageWidget({super.key});

  static const String routeName = 'AdminLiveDirector';
  static const String routePath = '/admin/live-director';

  @override
  State<AdminLiveDirectorPageWidget> createState() =>
      _AdminLiveDirectorPageState();
}

class _AdminLiveDirectorPageState extends State<AdminLiveDirectorPageWidget> {
  static const _teal = Color(0xFF007782);
  int _section = 0;
  final _repo = LiveDirectorRepository();
  late LiveDirectorEngine _engine;

  DirectorScript? _selectedScript;
  DirectorRun? _activeRun;
  List<DirectorScript> _scripts = const [];
  List<DirectorRun> _runs = const [];
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _engine = LiveDirectorEngine(repository: _repo);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final rows = await ProfilesTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', currentUserUid),
      limit: 1,
    );
    final me = rows.isEmpty ? null : rows.first;
    final admin = batataIsAdminUserType(me?.userType);
    if (!admin) {
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
      return;
    }
    await _refreshLists();
    setState(() {
      _isAdmin = true;
      _loading = false;
    });
  }

  Future<void> _refreshLists() async {
    _scripts = await _repo.listScripts();
    _runs = await _repo.listRuns();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Director')),
        body: const Center(child: Text('Acesso reservado a administradores.')),
      );
    }

    return ChangeNotifierProvider.value(
      value: _engine,
      child: Scaffold(
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          title: Text(
            'Live Director',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _section,
              onDestinationSelected: (i) => setState(() => _section = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.list_alt),
                  label: Text('Scripts'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.edit_note),
                  label: Text('Editor'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.fact_check),
                  label: Text('Pre-flight'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text('Console'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.play_circle),
                  label: Text('Runs'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.timeline),
                  label: Text('Timeline'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.replay),
                  label: Text('Replay'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.copy_all),
                  label: Text('Templates'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.summarize),
                  label: Text('Relatórios'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case 0:
        return _ScriptsSection(
          scripts: _scripts,
          onSelect: (s) => setState(() {
            _selectedScript = s;
            _section = 1;
          }),
          onRefresh: () async {
            await _refreshLists();
            setState(() {});
          },
          onNew: () => setState(() {
            _selectedScript = DirectorScript(
              name: 'Novo script',
              operatorId: currentUserUid,
              operatorLabel: 'Admin',
            );
            _section = 1;
          }),
        );
      case 1:
        return _ScriptEditorSection(
          script: _selectedScript,
          repo: _repo,
          onSaved: (s) async {
            _selectedScript = s;
            await _refreshLists();
            setState(() {});
          },
        );
      case 2:
        return _PreflightSection(
          script: _selectedScript,
          repo: _repo,
          onRunCreated: (run) {
            _activeRun = run;
            setState(() => _section = 3);
          },
        );
      case 3:
        return _ConsoleSection(
          engine: _engine,
          run: _activeRun,
          onSelectRun: (r) => setState(() => _activeRun = r),
          runs: _runs.where((r) => r.status == 'running').toList(),
        );
      case 4:
        return _RunsSection(
          runs: _runs,
          onRefresh: () async {
            await _refreshLists();
            setState(() {});
          },
          onOpenConsole: (r) {
            _activeRun = r;
            setState(() => _section = 3);
          },
        );
      case 5:
        return _TimelineSection(repo: _repo, run: _activeRun);
      case 6:
        return _ReplayDebugSection(repo: _repo, run: _activeRun);
      case 7:
        return _TemplatesSection(
          scripts: _scripts,
          repo: _repo,
          onDuplicated: (s) {
            _selectedScript = s;
            setState(() => _section = 1);
          },
        );
      case 8:
        return _ReportsSection(runs: _runs);
      default:
        return const SizedBox.shrink();
    }
  }
}

// --- Scripts list ---
class _ScriptsSection extends StatelessWidget {
  const _ScriptsSection({
    required this.scripts,
    required this.onSelect,
    required this.onRefresh,
    required this.onNew,
  });

  final List<DirectorScript> scripts;
  final ValueChanged<DirectorScript> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Scripts', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
              const Spacer(),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add),
                label: const Text('Novo'),
              ),
              IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: scripts.isEmpty
                ? const Center(child: Text('Sem scripts. Cria o primeiro.'))
                : ListView.builder(
                    itemCount: scripts.length,
                    itemBuilder: (_, i) {
                      final s = scripts[i];
                      return ListTile(
                        title: Text('${s.name} v${s.version}'),
                        subtitle: Text('${s.mode.name} · ${s.beats.length} beats · ${s.status}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onSelect(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Editor (simplified table) ---
class _ScriptEditorSection extends StatefulWidget {
  const _ScriptEditorSection({
    required this.script,
    required this.repo,
    required this.onSaved,
  });

  final DirectorScript? script;
  final LiveDirectorRepository repo;
  final ValueChanged<DirectorScript> onSaved;

  @override
  State<_ScriptEditorSection> createState() => _ScriptEditorSectionState();
}

class _ScriptEditorSectionState extends State<_ScriptEditorSection> {
  late TextEditingController _name;
  late TextEditingController _liveId;
  DirectorScriptMode _mode = DirectorScriptMode.demo;
  List<DirectorBeat> _beats = [];
  PreflightResult? _preview;
  DryRunResult? _dryRun;

  @override
  void initState() {
    super.initState();
    final s = widget.script;
    _name = TextEditingController(text: s?.name ?? '');
    _liveId = TextEditingController(text: s?.liveId ?? '');
    _mode = s?.mode ?? DirectorScriptMode.demo;
    _beats = List.of(s?.beats ?? []);
  }

  @override
  void dispose() {
    _name.dispose();
    _liveId.dispose();
    super.dispose();
  }

  DirectorScript _buildScript() => DirectorScript(
        id: widget.script?.id,
        name: _name.text.trim(),
        version: widget.script?.version ?? 1,
        mode: _mode,
        liveId: _liveId.text.trim(),
        sellerId: widget.script?.sellerId,
        operatorId: currentUserUid,
        operatorLabel: widget.script?.operatorLabel ?? 'Admin',
        targetProducts: widget.script?.targetProducts ?? const [],
        castPool: widget.script?.castPool ?? const [],
        beats: _beats,
        policy: widget.script?.policy ?? const DirectorScriptPolicy(),
        status: widget.script?.status ?? 'draft',
      );

  @override
  Widget build(BuildContext context) {
    if (widget.script == null) {
      return const Center(child: Text('Selecciona ou cria um script.'));
    }
    final previewLines = DirectorScriptPreviewService().buildPreview(_buildScript());
    final heatMap = DirectorHeatMapService().buildFromScript(_buildScript());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Script Editor', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
          TextField(controller: _liveId, decoration: const InputDecoration(labelText: 'Live ID')),
          DropdownButton<DirectorScriptMode>(
            value: _mode,
            items: DirectorScriptMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                .toList(),
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () async {
                  final saved = await widget.repo.upsertScript(_buildScript());
                  widget.onSaved(saved);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Script guardado.')),
                    );
                  }
                },
                child: const Text('Guardar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _preview = null;
                  _dryRun = null;
                }),
                child: const Text('Preview'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final script = _buildScript();
                  final live = await widget.repo.getLive(script.liveId ?? '');
                  final items = await widget.repo.getLiveItems(script.liveId ?? '');
                  final sim = await widget.repo.listSimProfiles();
                  final dry = await DirectorDryRunService().run(
                    script: script,
                    liveRow: live,
                    liveItems: items,
                    simProfiles: sim,
                  );
                  setState(() => _dryRun = dry);
                },
                child: const Text('Dry Run'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _beats.add(DirectorBeat(
                      beatId: 'beat_${_beats.length + 1}',
                      momentType: DirectorMomentType.approx,
                      action: DirectorActionType.chat,
                      approxSec: 60 * (_beats.length + 1),
                      messageText: 'Olá! Os portes ficam juntos?',
                      actorPersona: 'curious',
                    ));
                  });
                },
                child: const Text('+ Beat'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Preview temporal (${previewLines.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          ...previewLines.take(20).map((l) => Text(
                '${formatOffsetMmSs(l.offsetSec)} — ${l.label} (conf ${l.confidence.toStringAsFixed(2)})',
              )),
          const SizedBox(height: 12),
          Text('Heat map', style: const TextStyle(fontWeight: FontWeight.w600)),
          Wrap(
            spacing: 4,
            children: heatMap.take(30).map((seg) {
              final color = seg.level == 'green'
                  ? Colors.green.shade200
                  : seg.level == 'red'
                      ? Colors.red.shade200
                      : Colors.amber.shade200;
              return Container(
                width: 24,
                height: 24,
                color: color,
                child: Tooltip(message: '${seg.startMin}m: ${seg.label}', child: const SizedBox()),
              );
            }).toList(),
          ),
          if (_dryRun != null) ...[
            const SizedBox(height: 12),
            Text(
              'Dry run: ${_dryRun!.passed ? "PASS" : "FAIL"} — '
              '${_dryRun!.beats.where((b) => b.status == "executable").length} executáveis, '
              '${_dryRun!.beats.where((b) => b.status == "blocked").length} bloqueados',
              style: TextStyle(
                color: _dryRun!.passed ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Beats (${_beats.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          ..._beats.map((b) => ListTile(
                dense: true,
                title: Text('${b.beatId} · ${b.action.name} · ${b.momentType.name}'),
                subtitle: Text(b.messageText ?? b.actorTag ?? b.actorPersona ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _beats.remove(b)),
                ),
              )),
        ],
      ),
    );
  }
}

// --- Pre-flight ---
class _PreflightSection extends StatefulWidget {
  const _PreflightSection({
    required this.script,
    required this.repo,
    required this.onRunCreated,
  });

  final DirectorScript? script;
  final LiveDirectorRepository repo;
  final ValueChanged<DirectorRun> onRunCreated;

  @override
  State<_PreflightSection> createState() => _PreflightSectionState();
}

class _PreflightSectionState extends State<_PreflightSection> {
  PreflightResult? _result;
  bool _c1 = false, _c2 = false, _c3 = false, _c4 = false;

  @override
  Widget build(BuildContext context) {
    final script = widget.script;
    if (script == null) {
      return const Center(child: Text('Selecciona um script no Editor.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pre-flight', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          FilledButton(
            onPressed: () async {
              final live = await widget.repo.getLive(script.liveId ?? '');
              final items = await widget.repo.getLiveItems(script.liveId ?? '');
              final sim = await widget.repo.listSimProfiles();
              final killOk = !(await widget.repo.killSwitchActive('global'));
              final r = await DirectorScriptValidator().validate(
                script: script,
                liveRow: live,
                liveItems: items,
                simProfiles: sim,
                killSwitchOk: killOk,
                confirmations: {
                  'products_stock': _c1,
                  'intentional_commerce': _c2,
                  'affect_stock': _c3,
                  'real_payments': _c4,
                },
              );
              setState(() => _result = r);
            },
            child: const Text('Validar'),
          ),
          CheckboxListTile(
            value: _c1,
            onChanged: (v) => setState(() => _c1 = v == true),
            title: const Text('Revisei produtos e stock'),
          ),
          CheckboxListTile(
            value: _c2,
            onChanged: (v) => setState(() => _c2 = v == true),
            title: const Text('Reservas/compras são intencionais'),
          ),
          CheckboxListTile(
            value: _c3,
            onChanged: (v) => setState(() => _c3 = v == true),
            title: const Text('Percebo que pode afectar stock real'),
          ),
          CheckboxListTile(
            value: _c4,
            onChanged: (v) => setState(() => _c4 = v == true),
            title: const Text('Pagamentos reais autorizados (se aplicável)'),
          ),
          if (_result != null) ...[
            Text(_result!.passed ? 'VALIDAÇÃO OK' : 'VALIDAÇÃO FALHOU',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _result!.passed ? Colors.green : Colors.red,
                )),
            ..._result!.issues.map((i) => Text('${i.level}: ${i.message}')),
            Text('Resumo: ${_result!.summary.totalBeats} beats, '
                '${_result!.summary.messages} msgs, '
                '${_result!.summary.reservations} reservas, '
                '${_result!.summary.purchases} compras'),
            if (_result!.passed)
              FilledButton(
                onPressed: () async {
                  var s = script;
                  if (s.id == null || s.id!.isEmpty) {
                    s = await widget.repo.upsertScript(s);
                  }
                  final checksum =
                      _result!.checksum ?? DirectorManifest.computeChecksum(s);
                  final manifest = DirectorManifest(
                    scriptId: s.id ?? '',
                    scriptName: s.name,
                    version: s.version,
                    checksum: checksum,
                    mode: s.mode,
                    liveId: s.liveId ?? '',
                    sellerId: s.sellerId ?? '',
                    operatorId: currentUserUid,
                    operatorLabel: s.operatorLabel ?? 'Admin',
                    targetProducts: s.targetProducts,
                    castPool: s.castPool,
                    beats: s.beats,
                    policy: s.policy,
                    lockedAt: DateTime.now().toUtc(),
                    validationToken: _result!.validationToken,
                    confirmations: {
                      'products_stock': _c1,
                      'intentional_commerce': _c2,
                      'affect_stock': _c3,
                      'real_payments': _c4,
                    },
                  );
                  final run = await widget.repo.createRun(
                    manifest: manifest,
                    scriptId: s.id ?? '',
                    checksum: checksum,
                    operatorId: currentUserUid,
                  );
                  widget.onRunCreated(run);
                },
                child: const Text('Bloquear Manifest e criar Run'),
              ),
          ],
        ],
      ),
    );
  }
}

// --- Console ---
class _ConsoleSection extends StatelessWidget {
  const _ConsoleSection({
    required this.engine,
    required this.run,
    required this.onSelectRun,
    required this.runs,
  });

  final LiveDirectorEngine engine;
  final DirectorRun? run;
  final ValueChanged<DirectorRun> onSelectRun;
  final List<DirectorRun> runs;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final c = engine.console;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Director Console', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
              if (run != null) Text('Run: ${run!.id.substring(0, 8)}… · ${run!.status}'),
              if (runs.isNotEmpty && run == null)
                DropdownButton<DirectorRun>(
                  hint: const Text('Seleccionar run'),
                  items: runs
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.id.substring(0, 8))))
                      .toList(),
                  onChanged: (r) {
                    if (r != null) onSelectRun(r);
                  },
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _chip('Viewers', '${c.viewersTotal}'),
                  _chip('Bots online', '${c.botsOnline}'),
                  _chip('Seller', c.sellerMode),
                  _chip('Progresso', '${c.progressPct.toStringAsFixed(0)}%'),
                  _chip('Rifa', c.raffleActive ? 'activa' : 'off'),
                ],
              ),
              const SizedBox(height: 12),
              if (c.nextBeat != null)
                Text('Próximo: ${c.nextBeat!.actionLabel} em ${c.secondsToNext ?? "?"}s'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: run == null
                        ? null
                        : () async {
                            await engine.startRun(run!);
                          },
                    child: const Text('Iniciar Director'),
                  ),
                  OutlinedButton(onPressed: () => engine.executeNextNow(), child: const Text('Executar agora')),
                  OutlinedButton(onPressed: () => engine.delayNext(seconds: 30), child: const Text('+30s')),
                  OutlinedButton(onPressed: () => engine.delayNext(seconds: 60), child: const Text('+1min')),
                  OutlinedButton(onPressed: () => engine.cancelNext(), child: const Text('Cancelar beat')),
                  OutlinedButton(onPressed: () => engine.pause(), child: const Text('Pausar')),
                  OutlinedButton(onPressed: () => engine.resume(), child: const Text('Retomar')),
                  OutlinedButton(onPressed: () => engine.complete(), child: const Text('Terminar')),
                  TextButton(
                    onPressed: () => engine.kill('manual_kill'),
                    child: const Text('KILL', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _listPanel('Executados', c.executed)),
                    Expanded(child: _listPanel('Pendentes', c.pending)),
                    Expanded(child: _listPanel('Atrasados', c.delayed)),
                    Expanded(child: _listPanel('Bloqueados', c.blocked)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, String value) => Chip(label: Text('$label: $value'));

  Widget _listPanel(String title, List<ConsoleBeatState> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
              child: ListView(
                children: items
                    .map((b) => Text('${b.beatId} · ${b.status}'))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunsSection extends StatelessWidget {
  const _RunsSection({
    required this.runs,
    required this.onRefresh,
    required this.onOpenConsole,
  });

  final List<DirectorRun> runs;
  final VoidCallback onRefresh;
  final ValueChanged<DirectorRun> onOpenConsole;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('Runs', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
              IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: runs.length,
              itemBuilder: (_, i) {
                final r = runs[i];
                return ListTile(
                  title: Text('${r.status} · ${r.id.substring(0, 8)}'),
                  subtitle: Text('Live ${r.liveId.substring(0, 8)} · ${r.mode}'),
                  trailing: TextButton(
                    onPressed: () => onOpenConsole(r),
                    child: const Text('Console'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineSection extends StatefulWidget {
  const _TimelineSection({required this.repo, required this.run});
  final LiveDirectorRepository repo;
  final DirectorRun? run;

  @override
  State<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<_TimelineSection> {
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.run == null) return;
    final audit = await widget.repo.listAudit(widget.run!.id);
    setState(() => _rows = audit);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timeline / Audit', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                return Text(
                  '${r['outcome']} · ${r['event_type']} · beat ${r['beat_id']} · ${r['reason'] ?? ""}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayDebugSection extends StatefulWidget {
  const _ReplayDebugSection({required this.repo, required this.run});
  final LiveDirectorRepository repo;
  final DirectorRun? run;

  @override
  State<_ReplayDebugSection> createState() => _ReplayDebugSectionState();
}

class _ReplayDebugSectionState extends State<_ReplayDebugSection> {
  List<ReplayTimelineEntry> _entries = const [];

  Future<void> _load() async {
    final liveId = widget.run?.liveId;
    if (liveId == null) return;
    final entries = await DirectorReplayReader().loadForLive(liveId, repo: widget.repo);
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replay debug (só leitura)', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          FilledButton(onPressed: _load, child: const Text('Carregar timeline')),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (_, i) {
                final e = _entries[i];
                return Text(
                  '${formatOffsetMmSs(e.liveOffsetMs ~/ 1000)} · ${e.kind} · ${e.origin}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplatesSection extends StatelessWidget {
  const _TemplatesSection({
    required this.scripts,
    required this.repo,
    required this.onDuplicated,
  });

  final List<DirectorScript> scripts;
  final LiveDirectorRepository repo;
  final ValueChanged<DirectorScript> onDuplicated;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Templates / Duplicar', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          Expanded(
            child: ListView.builder(
              itemCount: scripts.length,
              itemBuilder: (_, i) {
                final s = scripts[i];
                return ListTile(
                  title: Text(s.name),
                  trailing: TextButton(
                    onPressed: () async {
                      final dup = DirectorTemplateService().duplicate(
                        source: s,
                        newName: '${s.name} (cópia)',
                      );
                      final saved = await repo.upsertScript(dup);
                      onDuplicated(saved);
                    },
                    child: const Text('Duplicar'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({required this.runs});
  final List<DirectorRun> runs;

  @override
  Widget build(BuildContext context) {
    final completed = runs.where((r) => r.report != null || r.status == 'completed').toList();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Relatórios pós-run', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600)),
          Expanded(
            child: ListView.builder(
              itemCount: completed.length,
              itemBuilder: (_, i) {
                final r = completed[i];
                final rep = r.report;
                return ListTile(
                  title: Text(r.id.substring(0, 8)),
                  subtitle: Text(rep?.toString() ?? r.status),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
