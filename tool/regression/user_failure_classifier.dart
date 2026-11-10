// ignore_for_file: avoid_print
/// Classificação de falhas para a lista humana (não-programadores).
library;

import 'models.dart';

/// Categorias pedidas para a lista.
enum UserFailureKind {
  infra,
  navegacao,
  dadosBd,
  bugReal,
  none,
}

const userFailureKindLabels = {
  UserFailureKind.infra: 'INFRA',
  UserFailureKind.navegacao: 'NAVEGAÇÃO',
  UserFailureKind.dadosBd: 'DADOS/BD',
  UserFailureKind.bugReal: 'BUG FUNCIONAL REAL',
  UserFailureKind.none: '—',
};

const userFailureKindExplain = {
  UserFailureKind.infra:
      'Emulador, login do robô, timeout, app não abre, ou teste saltado (dedupe)',
  UserFailureKind.navegacao:
      'Robô não encontrou botão/ecrã — tu confirmaste que manualmente funciona',
  UserFailureKind.dadosBd:
      'Dados de teste em falta ou base de dados não bate certo com o esperado',
  UserFailureKind.bugReal:
      'A app parece mesmo estar errada (confirmado em logs/dados, não só no robô)',
};

class UserFailureInfo {
  UserFailureInfo({
    required this.kind,
    required this.shortReason,
    this.auditOverridesRun = false,
    this.likelyFalsePositive = false,
  });

  final UserFailureKind kind;
  final String shortReason;
  final bool auditOverridesRun;
  final bool likelyFalsePositive;
}

/// Dados mínimos de auditoria para cruzar com a corrida.
class UserAuditHint {
  UserAuditHint({
    required this.conclusion,
    this.probableCause = '',
    this.validationType = '',
    this.stockMismatches = const [],
    this.failures = const [],
    this.maestroExitCode = 0,
  });

  final String conclusion;
  final String probableCause;
  final String validationType;
  final List<String> stockMismatches;
  final List<String> failures;
  final int maestroExitCode;

  bool get isPass {
    final c = conclusion.toUpperCase();
    return c == 'PASS' || c.startsWith('PASS_COM') || c.contains('AVISO');
  }

  bool get isFail => conclusion.toUpperCase() == 'FAIL';
}

UserFailureInfo classifyForHuman({
  required TestRunResult? run,
  UserAuditHint? audit,
}) {
  if (run == null || run.status != 'fail') {
    return UserFailureInfo(kind: UserFailureKind.none, shortReason: '');
  }

  final msg = (run.message ?? '').toLowerCase();
  final layers = run.layersRun;

  // Auditoria confirma OK → falha da corrida é falso alarme (robô/infra).
  if (audit != null && audit.isPass) {
    final kind = _kindFromMessage(msg, layers, audit);
    return UserFailureInfo(
      kind: kind,
      shortReason: _shortReason(kind, msg, audit),
      auditOverridesRun: true,
      likelyFalsePositive: kind != UserFailureKind.bugReal,
    );
  }

  // Stock / BD na auditoria.
  if (audit != null && audit.stockMismatches.isNotEmpty) {
    return UserFailureInfo(
      kind: UserFailureKind.dadosBd,
      shortReason:
          'Base de dados não coincide: ${audit.stockMismatches.first}',
    );
  }

  if (audit != null &&
      audit.isFail &&
      _isBdValidation(audit.validationType) &&
      audit.maestroExitCode == 0) {
    return UserFailureInfo(
      kind: UserFailureKind.dadosBd,
      shortReason: audit.probableCause.isNotEmpty
          ? audit.probableCause
          : 'Dados ou query de validação falharam',
    );
  }

  final kind = _kindFromMessage(msg, layers, audit);

  // Maestro / elemento → quase sempre NAVEGAÇÃO, não bug real.
  if (kind == UserFailureKind.navegacao ||
      kind == UserFailureKind.infra) {
    return UserFailureInfo(
      kind: kind,
      shortReason: _shortReason(kind, msg, audit),
      likelyFalsePositive: true,
    );
  }

  return UserFailureInfo(
    kind: kind,
    shortReason: _shortReason(kind, msg, audit),
  );
}

UserFailureKind _kindFromMessage(
  String msg,
  List<String> layers,
  UserAuditHint? audit,
) {
  if (msg.contains('dedupe') ||
      msg.contains('já executado') ||
      msg.contains('unable to launch') ||
      msg.contains('no devices') ||
      msg.contains('adb') ||
      msg.contains('emulador') ||
      msg.contains('grpc') ||
      msg.contains('threadpool') ||
      msg.contains('coroutinescheduler') ||
      msg.contains('tasks.kt') ||
      msg.contains('staging não') ||
      msg.contains('live_id') ||
      msg.contains('maestro/device') ||
      msg.contains('skip_config') ||
      layers.contains('precheck')) {
    return UserFailureKind.infra;
  }

  if (msg.contains('element') ||
      msg.contains('assertion') ||
      msg.contains('not found') ||
      msg.contains('selector') ||
      msg.contains('element state') ||
      msg.contains('maestro exit') ||
      (audit?.maestroExitCode ?? 0) > 0) {
    return UserFailureKind.navegacao;
  }

  if (layers.contains('integration') && !layers.contains('maestro')) {
    return UserFailureKind.dadosBd;
  }
  if (layers.contains('unit') && !layers.contains('maestro')) {
    return UserFailureKind.dadosBd;
  }

  if (msg.contains('híbrido') || msg.contains('hybrid')) {
    if (msg.contains('maestro') ||
        msg.contains('element') ||
        msg.contains('launch')) {
      return UserFailureKind.navegacao;
    }
    return UserFailureKind.dadosBd;
  }

  if (_isBdValidation(audit?.validationType ?? '')) {
    return UserFailureKind.dadosBd;
  }

  return UserFailureKind.bugReal;
}

bool _isBdValidation(String type) {
  final t = type.toUpperCase();
  return t.contains('BD') ||
      t.contains('INTEGRATION') && !t.contains('MAESTRO');
}

String _shortReason(
  UserFailureKind kind,
  String msg,
  UserAuditHint? audit,
) {
  if (msg.contains('dedupe') || msg.contains('já executado')) {
    return 'Robô saltou o teste porque já tinha corrido um parecido na mesma sessão';
  }
  if (msg.contains('unable to launch')) {
    return 'Emulador não conseguiu abrir a app';
  }
  if (msg.contains('element state') || msg.contains('element not found')) {
    return 'Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real)';
  }
  if (msg.contains('maestro exit') || (audit?.maestroExitCode ?? 0) > 0) {
    return 'Fluxo Maestro interrompido antes do fim';
  }
  if (msg.contains('grpc') ||
      msg.contains('coroutine') ||
      msg.contains('tasks.kt')) {
    return 'Crash/timeout do próprio Maestro ou emulador';
  }
  if (kind == UserFailureKind.dadosBd) {
    return audit?.probableCause.isNotEmpty == true
        ? audit!.probableCause
        : 'Validação de dados na base de testes';
  }
  return switch (kind) {
    UserFailureKind.infra => 'Problema de ambiente (emulador, login automático, timeout)',
    UserFailureKind.navegacao => 'Robô não navegou até ao ecrã certo',
    UserFailureKind.dadosBd => 'Dados de staging ou query BD',
    UserFailureKind.bugReal => 'Comportamento inesperado da app',
    UserFailureKind.none => '',
  };
}

/// Classifica a partir dos campos simples da lista (sem importar TestRunResult).
UserFailureInfo classifyFromFields({
  required String? status,
  required String? message,
  required List<String> layersRun,
  UserAuditHint? audit,
}) {
  if (status != 'fail') {
    return UserFailureInfo(kind: UserFailureKind.none, shortReason: '');
  }
  return classifyForHuman(
    run: TestRunResult(
      id: '',
      name: '',
      status: 'fail',
      message: message,
      layersRun: layersRun,
    ),
    audit: audit,
  );
}

String userFailureKindEmoji(UserFailureKind k) => switch (k) {
      UserFailureKind.infra => '🔧',
      UserFailureKind.navegacao => '🧭',
      UserFailureKind.dadosBd => '🗄️',
      UserFailureKind.bugReal => '🐛',
      UserFailureKind.none => '',
    };
