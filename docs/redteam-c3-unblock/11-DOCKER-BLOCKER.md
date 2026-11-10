# TEST LOCAL — bloqueio Docker/WSL

## Causa raiz

1. Docker Desktop instalado, mas **engine unable to start**.
2. **WSL sem distros** instaladas.
3. Serviço `vmcompute` (Hyper-V Host Compute) **Stopped**.
4. Arranque/serviço exige **elevação**; UAC foi **cancelado** duas vezes nesta sessão (`Acesso negado` / operação cancelada).

## O que NÃO foi feito

- Não se usou staging nem projecto cloud como substituto (sem nova autorização).

## Como desbloquear (1 vez, Admin)

1. Abrir PowerShell **como Administrador**.
2. Correr:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Casa\Desktop\Fleaber\fleaber-c3-unblock\tool\c3_fix_docker_admin.ps1
```

3. Completar setup Ubuntu se pedido.
4. Esperar Docker Engine verde.
5. Responder no chat: **`DOCKER READY`**

C1 continua então: `supabase start` → migrations → seed contas → testes RLS → actualiza guia/ZIP.
