# Acesso SSH seguro — VPS Fleaber DPD (OVH)

**Nunca** colar no chat/git: passwords, chaves **privadas**.

## Servidor correcto (Fleaber)

| Campo | Valor |
|-------|--------|
| Host | `vps-27d76f35.vps.ovh.net` |
| IPv4 | `135.125.254.159` |
| User | `ubuntu` |
| Chave | `%USERPROFILE%\.ssh\fleaber_dpd_ovh` |

**Fora de âmbito:** `vps-b84a0381` / `152.228.173.97` (Biscateiro) — **não** usar nem alterar.

## Um passo no painel OVH (obrigatório se SSH falhar)

1. OVHcloud → VPS **`vps-27d76f35`** → **Consola KVM / VNC**.
2. Login `ubuntu` (password só na consola).
3. Executa (uma linha de chave pública — está em `PUBLIC_KEY_FLEABER_DPD.txt`):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPWdI+DB4nECvumkrfbxrL7gYNZ2bthlzhECJ5Lepz74 fleaber-dpd-proxy-ovh' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

4. No chat: **«chave no VPS Fleaber»** — sem colar chaves.

O agente liga com alias `fleaber-dpd-ovh` (ver `~/.ssh/config` neste PC) → `ubuntu@135.125.254.159`.

## Depois do acesso

Confirmar hostname/IP de saída **antes** de `install.sh`. Não instalar no Biscateiro.
