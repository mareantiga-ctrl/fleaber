# Relatório final — SMS permanente + PROD C3

## Quadro

| Item | Estado |
|------|--------|
| SMS permanentemente ativo | **SIM** (`OPS_SMS=1`) |
| Causa OTP rejeitado | **`otp_expired`** (exp 60s; verify 14 min depois) |
| Causa erro reenvio | Kill-switch `OPS_SMS=0` pós-teste |
| Verificação telemóvel completa | **FAIL** (aguarda OTP novo na app) |
| Contas C3 PROD | **4 criadas**, login 4/4, produtos 2, handles OK |
| C3 desbloqueado auditoria funcional | **PARCIAL** — contas operacionais; falta verificação Cláudia + mais seeds opcionais |
| Stripe LIVE / DPD create | Intocados |

## Provas

- Auth verify log 09:54 `otp_expired`
- Auth hook success 09:40
- `c3_login_smoke.json`, `c3_prod_data_proof.json`, `c3_handles_claim.json`
- Creds: `%TEMP%\fleaber_c3_prod_creds.json` (fora git)
- Recovery Cláudia: `%TEMP%\fleaber_claudia_recovery_link.txt` (se password foi rodada no GO SMS anterior)

## Pedido imediato ao dono

1. Cláudia: app → Verificar telemóvel → **novo** SMS → código em ≤10 min.  
2. Responder `SMS …5912 VERIFICADO` ou falha.  
3. Entregar passwords C3 ao C3 por canal seguro (não no chat público).
