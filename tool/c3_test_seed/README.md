# C3 TEST seed (não PROD)

Aplicar **só** depois de `GO TEST LOCAL` / `GO TEST CLOUD` / `GO TEST STAGING CLEAN`.

Ordem sugerida:

1. `10_marker_notes.sql` — documentação na BD
2. Contas Auth via Admin API (script operador; passwords fora do git)
3. `20_seed_catalog.sql` — produtos/stock marcados C3_TEST
4. `90_cleanup_c3_test.sql` — limpeza exclusiva

Os `.sql` são **templates** conservadores: ajustar nomes de tabelas/colunas ao schema real do ambiente TEST antes de correr.
