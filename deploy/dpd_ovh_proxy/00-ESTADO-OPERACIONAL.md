# Proxy DPD — estado operacional (Fleaber VPS)

**Host:** `vps-27d76f35` / `135.125.254.159`  
**HTTPS:** `https://vps-27d76f35.vps.ovh.net`  
**Biscateiro:** não tocado

## Operacional

- UFW: deny in / allow out · 22/80/443
- systemd `fleaber-dpd-proxy` · restart always
- nginx + Let’s Encrypt
- Bearer em `/etc/fleaber-dpd/proxy_bearer` (só servidor)
- `/health` público · `/egress` e `/forward` com Bearer
- Egress medido: **135.125.254.159**

## Estado ZIP 190 (2026-11-10)

1. `FLEABER_DPD_ALLOWED_HOSTS=qabusiness.dpd.pt,business.dpd.pt` (OAuth PROD desbloqueado).
2. OAuth PROD via Edge `dpd-oauth-probe` → **PASS** (`expires_in` ~14400 s). Create comercial continua **OFF** (`OPS_DPD_COMMERCIAL_GO=0`, `DPD_LIVE_CREATE_ENABLED=0`).
3. Edge → `https://vps-27d76f35.vps.ovh.net/forward` com Bearer.
4. Tracking Trace API: activo (ZIP 130).
5. Backup unit: `fleaber-dpd-proxy.service.bak.190.*`.

## Estado ZIP 131 (2026-11-02) — histórico

1. `FLEABER_DPD_ALLOWED_HOSTS=qabusiness.dpd.pt` (QA only; Live host recusado pelo proxy).
2. Secrets Supabase PROD: `DPD_PROXY_*`, `DPD_MYPUDO_KEY`, `DPD_QA_*`, `DPD_MODE=qa`, `DPD_TRACKING_API_KEY`.  
   **`DPD_QA_CREATE_ENABLED` continua OFF** — create QA bloqueado por `Conta invalida` (eeent portal).
3. Edge → `https://vps-27d76f35.vps.ovh.net/forward` com Bearer.
4. Tracking Trace API: activo (ZIP 130).
5. PROD DPD (`business.dpd.pt`): **não** activar (superado no ZIP 190 para OAuth; create ainda off).

## Email à DPD

Podem enviar já o IP **`135.125.254.159`**.
