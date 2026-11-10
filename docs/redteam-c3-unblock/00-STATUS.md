# C3 Unblock — estado (ZIP 191)

**Branch:** `c1/191-c3-unblock`  
**Base snapshot:** `c1/190-c3-full-snapshot` @ `1d9f7109…`  
**C2:** não tocado (worktree isolado).

| ID | Item | Estado |
|----|------|--------|
| A | BulkGate prep + pedido GO SMS | **PENDENTE GO** (técnico OK; SMS off) |
| B1 | `flutter_webrtc` bootstrap | **RESOLVIDO** (script + prova `flutter test`) |
| B2 | Testes portes Célia | **RESOLVIDO** (testes actualizados; app OK) |
| B3 | Supabase TEST isolado | **BLOQUEADO** (falta GO: Docker engine ou projecto TEST novo) |
| B4 | Contas TEST | **PENDENTE** (scripts prontos; não criadas em cloud) |
| B5 | Dados TEST | **PENDENTE** (SQL seed/cleanup prontos; não aplicados) |
| B6 | Integrações simuladas | **RESOLVIDO** (matriz documentada) |
| B7 | Versões vs PROD | **RESOLVIDO** (documento; sem equivalência sem prova) |
| B8 | Guia arranque C3 | **RESOLVIDO** |
| C | F-001 residual | **RESOLVIDO** (doc + risco residual) |

**C3 NÃO está desbloqueado para auditoria funcional completa** até existir TEST isolado comprovado (B3).
