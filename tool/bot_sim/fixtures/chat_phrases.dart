import 'dart:math';

final _rng = Random();

const demoFriendlyNames = [
  'Ana',
  'Bruno',
  'Carla',
  'Diogo',
  'Eva',
  'Filipe',
  'Gina',
  'Hugo',
  'Inês',
  'João',
  'Kika',
  'Luís',
  'Marta',
  'Nuno',
  'Olívia',
  'Pedro',
  'Rita',
  'Sofia',
  'Tiago',
  'Vera',
];

const _chatPhrases = [
  'Boa noite',
  'Olá a todos',
  'Mostra esse outra vez',
  'Quanto é?',
  'Gosto desse',
  'Reserva o azul',
  'Está lindo',
  'Tamanho M?',
  'Enviam para o Porto?',
  'Já reservei',
  'Espera, deixa ver melhor',
  'Qual é a ref?',
  'Tem mais cores?',
  'Boa live',
  'Parabéns pelo directo',
];

const _demoExtraPhrases = [
  'Que peça bonita',
  'Adoro este estilo',
  'Mostra de perto sff',
  'Fica bem contigo',
];

String pickChatPhrase({bool demoMode = false}) {
  final pool = demoMode
      ? [..._chatPhrases, ..._demoExtraPhrases]
      : _chatPhrases;
  return pool[_rng.nextInt(pool.length)];
}

String demoDisplayName(int index) {
  final i = (index - 1).clamp(0, demoFriendlyNames.length - 1);
  return demoFriendlyNames[i];
}

String botInternalTag(int index) =>
    'DEMO_BOT_${index.toString().padLeft(2, '0')}';

String stressRunTag(String runId) => 'STRESS_TEST:$runId';
