# Emparelhamento PS Reader

## Fluxo

```
Studio Fleaber                    PC Windows
     │                                 │
     │  batata_ps_create_pairing       │
     │  → código 6 dígitos             │
     │                                 │
     │ ─────── mostra código ────────► │  ps-pairing-claim
     │                                 │  → live_id + token
     │                                 │  → catálogo live
     │ ◄──── heartbeat 15s ─────────── │
```

## Passos seller

1. **Studio** → live activa → ⋮ Mais → **Emparelhar PS Reader**
2. Anota o código (ex. `482917`)
3. **PC** → Fleaber PS Reader → **Emparelhar live** → código
4. Confirma título da live

## Validade

- Código expira em **10 minutos**
- Uso **único** — após claim, gera novo código para outro PC

## Nova live

Não precisas reinstalar. Só:

1. Novo código no Studio da nova live
2. Emparelhar no PC

## Segurança

- Token guardado localmente em `%APPDATA%\FleaberReader\`
- Token revogável no Studio (futuro: menu dispositivos)
- Código não reutilizável após claim

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Código inválido | Expirou — gera novo no Studio |
| Erro rede | Verifica Internet; SQL v2 deployado |
| Live errada | Desemparelhar + novo código |
