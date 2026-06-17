/// Política de automação: só estes IDs ficam fora do robô.
library;

/// Checkpoints manuais (23) — Stripe real, staff, 2 devices, Mux/RTMP, etc.
const Set<String> kManualCheckpointIds = {
  'A018',
  'A037',
  'A044',
  'A064',
  'A070',
  'A072',
  'A073',
  'A076',
  'A077',
  'A078',
  'A098',
  'A099',
  'A168',
  'A169',
  'A205',
  'A207',
  'A372',
  'A379',
  'A383',
  'A384',
  'A388',
  'A399',
  'A410',
};

/// Checkpoints guiados (1) — permissões sistema (câmara).
const Set<String> kGuidedCheckpointIds = {'A065'};

const int kExpectedAutomated = 405;
const int kExpectedManual = 23;
const int kExpectedGuided = 1;
const int kTotalTests = 429;

bool isManualCheckpoint(String id) => kManualCheckpointIds.contains(id);

bool isGuidedCheckpoint(String id) => kGuidedCheckpointIds.contains(id);

bool isHumanOnlyCheckpoint(String id) =>
    isManualCheckpoint(id) || isGuidedCheckpoint(id);
