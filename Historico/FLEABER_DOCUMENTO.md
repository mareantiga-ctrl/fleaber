# Fleaber — Documento de produto e negócio

**Versão:** 1.2 (Mai 2026) — custos Mux + LiveKit + alternativa MediaMTX  
**Entidade:** Mare Antiga Unipessoal, Lda (NIF 518775364)  
**Fontes:** respostas do fundador (`PERGUNTAS_PARA_FUNDADOR.md`), pasta `Historico/`, código da aplicação, `MERDA.md`  
**Público-alvo deste texto:** vendedoras que já vendem em direto no Facebook; Cláudia (planeamento); parceiros técnicos e comerciais  
**Idioma:** português de Portugal

---

## Sumário executivo

O **Fleaber** é um **marketplace ao vivo** para Portugal (e, no médio prazo, Espanha, França e eventualmente Brasil). Combina o que as vendedoras já fazem no **Facebook Live** — mostrar artigos, reservar por número, conversar com clientes — com uma camada profissional de **pagamentos, encomendas, chat estruturado, carteira e proteção ao comprador**, no espírito do **Vinted**, mas com o **direto** como motor de conversão (referência de UX: Whatnot, sem foco em leilões).

O fundador administra um grupo Facebook de **~10 400 membros** onde se partilham lives; o valor está no **ecossistema de pessoas habituadas a diretos**, não necessariamente na audiência que o grupo gera por si só.

**Estado actual (Mai 2026):** aplicação Flutter + Supabase em fase avançada de MVP — live com **LiveKit → Mux** (viewers em HLS), marketplace, chat com fluxo de reservas/encomendas, taxa de proteção implementada, gorjetas em SQL/UI, admin de disputas e comissões. Faltam peças críticas para lançamento comercial: **fila de reservas no live**, **checkout Stripe completo**, **co-host/helper**, **Google Sign-In**, SMS em produção, e polish de páginas.

**Compromisso de qualidade:** o MVP tem de estar **visualmente premium**; o fundador não aceita vídeo em landscape com barras no telemóvel — requisito de portrait tratado como bloqueante (estado técnico documentado em `MERDA.md`).

---

## 1. Visão e posicionamento

### 1.1 O que é

| Dimensão | Definição |
|----------|-----------|
| **Categoria** | Marketplace ao vivo («Marketplace Ao Vivo» — frase preferida do fundador) |
| **Metáfora interna** | «Armazém digital» (listagens 24/7) + «Palco» (live Arena) |
| **Nome oficial** | **Fleaber** |
| **Pronúncia em PT** | **Fliaber** (anúncios e conversa) |
| **Modelo jurídico desejado** | Intermediário tipo **Vinted** (não agência de pagamentos) |

### 1.2 O que não é (ainda em definição)

O fundador quer evitar ser percebido como «rede social», mas **não listou exclusões concretas** (feed infinito, stories, etc.). Na prática o produto já inclui **seguir vendedores**, **chat**, **notificações** e **perfil público** — ou seja, é **comércio com camada social mínima**, não uma rede genérica.

### 1.3 Relação com o Facebook Live

| Aspeto | Decisão do fundador |
|--------|---------------------|
| Posicionamento | **Substituto** do Facebook Live como canal principal de venda |
| Cenário dual-screen | Vendedora com **dois telemóveis** (um a transmitir para o Fleaber, outro para o Facebook): quando a venda ocorre no Fleaber, deve aparecer **mensagem no chat da vendedora** para ela não perder o evento |
| Preferência económica | Melhor **comissão no Fleaber** do que live só no Facebook (evita custos de transmissão sem receita da plataforma) |
| Flexibilidade | Se o vendedor entender que usar Fleaber só como «carrinho» durante FB é melhor para ele, **não é proibido** — mas não é o ideal para o negócio Fleaber |

### 1.4 Expansão geográfica

1. **Testes:** Portugal  
2. **Oportunidade inicial:** Brasil (se contacto comercial correr bem)  
3. **Expansão «normal»:** Espanha e França  
4. **Espanha:** visão futura; **sem vendedores ES hoje**

### 1.5 Verticais

Estrutura actual do site/app aceita **várias categorias**; foco histórico em **roupa e bijuteria (35–65 anos)**. **Feira online** (câmara fixa na bancada) é possível mas **não está fechada** como segundo pilar — o fundador está aberto a ideias.

---

## 2. Problema e solução

### 2.1 Dores das vendedoras no Facebook (validadas)

1. **Caos nos comentários** — «quero o 3», desistências, dados falsos, impossível saber quem ficou com o quê.  
2. **Pagamentos dispersos** — MBWay, transferências, comprovativos em mensagens privadas.  
3. **Operação pós-live** — vasculhar conversas para imprimir etiquetas e enviar; risco de burlas e faltas de pagamento.  
4. **Medo de mudar** — hábito, audiência no Facebook, custo percebido, curva de aprendizagem.

### 2.2 O que o Fleaber promete

| Promessa | Como a app suporta (hoje / planeado) |
|----------|--------------------------------------|
| Reserva clara por artigo/número | Catálogo `live_items`, botão RESERVAR na Arena — **parcial** (UI existe; fila e checkout in-live incompletos) |
| Pagamento rastreável | Stripe Checkout (produtos), carteira, gorjetas; fluxo **reserva → pagamento externo → confirmação** no chat para quem ainda não paga na app |
| Lista de vendas na hora | Chat estruturado + encomendas — **parcial** |
| Proteção ao comprador | Taxa de Proteção Fleaber (€0,65 + 5% sobre artigo + envio), paga pelo **comprador** |
| Direto profissional | LiveKit + Mux, player Arena, carrossel de produtos, gorjetas |
| Pós-live | Replay Mux/VOD — **duração «comprável» ainda por definir** |

### 2.3 Frase de vendas (interna)

> Acabar com o caos, facilitar pagamentos, ver na hora quem comprou o quê — imprimir etiqueta e enviar em vez de vasculhar o Facebook.

---

## 3. Público-alvo

### 3.1 Vendedoras

- Mulheres **35–65**, Portugal (inicial).  
- Já fazem **Facebook Live** de roupa, bijuteria, ferramentas, brinquedos, material escolar, etc.  
- Ticket médio **não estudado** (€15 foi apenas exemplo em conversas antigas).

### 3.2 Compradoras

- Mesmas comunidades; compras por impulso **€5–30** típicas no segmento.  
- Precisam de **confiança** (proteção, reputação, chat).

### 3.3 Comunidade existente

- Grupo Facebook **~10 400 membros** — função principal: **partilhar e descobrir diretos**, não audiência massiva dentro do grupo.  
- **Riqueza:** adesão de pessoas com interesse em fazer/ver diretos → canal de aquisição a explorar (estratégia de contacto **ainda não fechada**).

### 3.4 Equipa

| Pessoa | Papel actual | Futuro |
|--------|--------------|--------|
| Fundador (Z) | Desenvolvimento ~**6 h/dia**; decisão produto | Continua core |
| Cláudia | Decisão e planeamento; pouco tempo agora | **Tempo inteiro** quando a app estiver pronta |
| Tiago | Mencionado em planos antigos | **Não activo** no dia-a-dia |
| João (teste) | Sem feedback estruturado ainda | — |

---

## 4. Funcionalidades — inventário

Legenda: **Feito** · **Parcial** · **Planeado** · **Não prioritário**

### 4.1 Conta e confiança

| Funcionalidade | Estado | Notas |
|----------------|--------|-------|
| Registo / login / recuperar senha | Feito | Supabase Auth |
| Verificação telefone SMS | Parcial | BulkGate verificado; chaves em integração |
| Google Sign-In | Planeado | Prioritário |
| Perfil vendedor/comprador | Feito | Avatar, localização, seguidores |
| Avaliações | Feito | `reviews` + opiniões gerais |
| Termos / privacidade / livro reclamações | Parcial | Existe hub legal; **verificar produção** |
| Vendedor 18+ | Feito | Política confirmada |

### 4.2 Marketplace (estilo Vinted)

| Funcionalidade | Estado | Notas |
|----------------|--------|-------|
| Listagens com foto, preço, estado | Feito | Toggle marketplace / live no mesmo produto |
| Pesquisa e favoritos | Feito | Home tab Marketplace |
| Detalhe produto + checkout | Parcial | Stripe `create-payment-intent`; proteção no total |
| Taxa de Proteção | Feito | `€0,65 + 5%` em `fee_calculator.dart` |
| Envio / etiquetas | Planeado | Email a InPost/CTT; **sem API ainda** |

### 4.3 Live shopping (Arena)

| Funcionalidade | Estado | Notas |
|----------------|--------|-------|
| Preparar direto (catálogo, refs) | Feito | `PrepararDirecto`, sync `live_items` |
| Transmitir (vendedor) | Feito | LiveKit → egress Mux, portrait pipeline |
| Ver direto (comprador) | Feito | HLS Mux, player `FleaberLivePlayer` |
| Carrossel produtos no player | Feito | Layout a melhorar (fundador) |
| Reservar no live | Parcial | Botão RESERVAR → **ainda snackbar placeholder** |
| Fila / primeiro a clicar | Planeado | **Prioritário MVP** |
| Gorjetas | Parcial | SQL + UI; fundador **não testou** |
| Chat no live | Feito | Banda de mensagens no player |
| Seguir vendedor | Feito | |
| Replay pós-live | Parcial | VOD Mux; janela de compra **por definir** |
| Co-host / Helper backstage | Planeado | Próximo foco se houver tempo |
| Leilão | Não MVP | Possível side feature futuro |

### 4.4 Chat, encomendas e dinheiro

| Funcionalidade | Estado | Notas |
|----------------|--------|-------|
| Lista conversas + notificações | Feito | |
| Chat multimédia | Feito | Storage `chat_media` |
| Fluxo reserva BATATA | Parcial | Reserva → dados pagamento → comprovativo → envio → receção → feedback |
| Encomendas (Minhas Encomendas) | Feito | |
| Disputas + admin | Parcial | Admin a conferir |
| Carteira Fleaber | Parcial | SQL/RPCs; Stripe Connect em curso |
| Comissões admin | Parcial | Tab comissões = **taxa de proteção** (única linha receita confirmada) |

### 4.5 Admin e web

| Funcionalidade | Estado |
|----------------|--------|
| Painel admin (disputas, encomendas, comissões) | Parcial |
| Dashboard web `/diretos-web` | Feito |

### 4.6 Fluxo ideal do comprador no live (alvo = Vinted)

1. Entrar na live (Home ou notificação).  
2. Ver produto no carrossel (número/ref + preço).  
3. **Reservar** (fila justa, confirmação imediata).  
4. **Pagar** (Stripe na app ou fluxo guiado no chat).  
5. Vendedora **envia** (etiqueta futura); compradora **confirma receção**; avaliações.

**Gap actual:** passos 3–4 não fecham no player; muito volume ainda passa pelo **chat estilo reserva manual**.

---

## 5. Arquitectura técnica (resumo)

```
Vendedor (Flutter) ──► LiveKit Cloud (publicar WebRTC)
                              │
                              ▼
                    Edge: livekit-mux-publish (egress)
                              │
                              ▼
                         Mux (HLS / VOD)
                              │
Comprador (Flutter) ◄─────────┘  apenas .m3u8 (sem LiveKit viewer no MVP)

Supabase: Auth, Postgres, Storage, Realtime, Edge Functions
Stripe: Checkout produtos, gorjetas, Connect (vendedores)
```

| Componente | Papel |
|------------|-------|
| **Flutter** | App móvel (export FlutterFlow evoluído em código nativo) |
| **Supabase** | BD, RLS, RPCs `batata_*`, logs `app_logs` |
| **LiveKit** | Publicação; viewers **não** usam WebRTC no MVP |
| **Mux** | Distribuição e gravação |
| **Stripe** | Pagamentos oficiais |

**Stack oficial confirmada:** Supabase (não Firebase). Wireframes antigos com ZegoCloud **obsoletos**.

**Regra BATATA (engenharia):** não remover funcionalidades nem alterar Arena/player/fluxos live sem alinhamento — espelha a regra de negócio do fundador: **não mudar funcionalidades sem combinar**.

**Portrait / Android:** documentação técnica extensa em `MERDA.md` (TCL T775H, egress landscape, preview vendedor, `manual_quarter_turns: 0` no viewer).

---

## 6. Modelo de negócio

### 6.1 Receitas

| Fonte | Quem paga | Valor (código / intenção) |
|-------|-----------|---------------------------|
| **Taxa de Proteção** | Comprador | **€0,65 + 5%** sobre (artigo + envio) |
| **Gorjetas em live** | Comprador | Valor livre; taxa processamento **2,9% + €0,40** (alinhada Stripe; **sem margem Fleaber explícita** hoje) |
| **Comissão vendedor** | — | **Nenhuma** além da proteção paga pelo cliente |

Registo em `fleaber_commissions` com origem `protection_fee` (admin).

### 6.2 Pagamentos — visão do fundador

| Modo | Estado |
|------|--------|
| **Stripe na app** | Caminho oficial para lançamento |
| **Pagamento manual** (MBWay, etc.) | Possível no fluxo reserva/chat; vendedor envia dados; comprador confirma — **útil para testes e confiança inicial** |
| **Carteira interna** | Modelo **Vinted**; saldo na app; levantamentos via Connect |
| **Pagamento nos meios da vendedora** ligados à app | **Ideia em estudo** — se a app confirmar pagamento sem passar fundos, comissão poderia baixar (ex. €0,30 + 3%) — **viabilidade jurídica e técnica por validar** |

### 6.3 Incentivos de lançamento

- **€25–50** às primeiras vendedoras que façam direto e **trouxerem clientes** (para sorteios/mercadoria na live).  
- Não é «meses sem comissão» clássico — quem paga proteção é o **cliente**.  
- Gorjetas podem ser **pequena fonte de rendimento** para vendedoras.

### 6.4 Métricas ano 1

**Não definidas** pelo fundador (GMV, nº transacções, nº vendedoras). Documento futuro deve actualizar quando houver dados reais.

### 6.5 Custos de transmissão — preços públicos e cenários (Mai 2026)

**Fontes:** [Mux Video Pricing](https://www.mux.com/docs/pricing/video) (actualizado na documentação Mux); [LiveKit Cloud Pricing](https://livekit.io/pricing). Valores em **USD** na fatura; conversão para **EUR** com taxa **0,93** (orientativa — usar câmbio real na data da factura).

**Stack Fleaber por minuto de live «no ar»:**

| Etapa | Quem paga | O que conta |
|-------|-----------|-------------|
| Vendedor → LiveKit | LiveKit | Minutos **WebRTC** com o publisher ligado à sala |
| LiveKit → Mux (egress) | LiveKit | Minutos **Track egress** (RTMP para Mux) |
| Entrada live Mux | Mux | Minutos **live input** (Plus, até 720p) |
| Viewers HLS | Mux | Minutos **entregues** (delivery) — inclui buffer do player |
| Gravação VOD | Mux | Minutos **armazenados** após o directo |

**Tarifas usadas nos cálculos (primeiro escalão / MVP):**

| Serviço | Métrica | Preço (USD) | Notas |
|---------|---------|-------------|-------|
| **Mux** | Live input Plus ≤720p | **$0,025 / min** | RTMP do egress LiveKit |
| **Mux** | Delivery Plus ≤720p | **$0,0008 / min** | Primeiros **100 000 min/mês grátis** |
| **Mux** | Storage Plus ≤720p | **$0,0024 / min-mês** | VOD após live (replay) |
| **Mux** | LL-HLS / reduced latency | Igual ao live standard | Sem sobretaxa na doc. Mux |
| **LiveKit** | Track egress | **$0,001 / min** | Após quota do plano (Build: 60 min; Ship: 600 min) |
| **LiveKit** | WebRTC (publisher) | **$0,0005 / min** | Após quota (Ship: 150 000 min incl.) |
| **LiveKit** | Plano Ship (referência) | **$50 / mês** | 600 min egress incl., 150k WebRTC incl. |

**Fórmulas (por mês):**

```
min_publicação = nº_lives × duração_média_live (min)
min_entrega      = Σ (por cada live: espectadores × tempo_médio_visto)
custo_mux_input     = min_publicação × 0,025
custo_mux_delivery  = max(0, min_entrega − 100 000) × 0,0008
custo_lk_egress     = max(0, min_publicação − egress_incluído) × 0,001
custo_lk_webrtc     = max(0, min_publicação − webrtc_incluído) × 0,0005
```

**Premissas alinhadas contigo:** live **~1h30 (90 min)**; viewers só **HLS** (sem WebRTC no MVP).

---

#### Cenário A — Piloto (10 lives/semana)

| Premissa | Valor |
|----------|-------|
| Lives / semana | 10 |
| Duração / live | 90 min |
| Espectadores médios / live | 40 |
| Tempo médio visto / pessoa | 35 min (não vêem o directo todo) |

| Métrica | Cálculo | USD/mês | EUR/mês (~0,93) |
|---------|---------|---------|-----------------|
| Min. publicação | 10 × 4,33 × 90 ≈ **3 870** | — | — |
| Min. entrega | 43 × 40 × 35 ≈ **60 200** | — | — |
| Mux input | 3 870 × $0,025 | **$97** | **~€90** |
| Mux delivery | menos de 100k grátis | **$0** | **€0** |
| Mux storage VOD | 3 870 min × 7 dias (~25% mês) | **~$2** | **~€2** |
| LiveKit egress | 3 870 min (quota Ship cobre) | **~$0** | **€0** |
| LiveKit WebRTC | dentro dos 150k incl. | **$0** | **€0** |
| Plano LiveKit Ship | fixo | **$50** | **~€47** |
| **Total vídeo** | | **~$149** | **~€138** |

---

#### Cenário B — Crescimento (25 vendedoras, 8 lives/mês cada)

| Premissa | Valor |
|----------|-------|
| Lives / mês | 200 |
| Duração / live | 90 min |
| Espectadores / live | 60 |
| Tempo médio visto | 40 min |

| Métrica | Cálculo | USD/mês | EUR/mês |
|---------|---------|---------|---------|
| Min. publicação | 200 × 90 = **18 000** | — | — |
| Min. entrega | 200 × 60 × 40 = **480 000** | — | — |
| Mux input | 18 000 × $0,025 | **$450** | **~€419** |
| Mux delivery | (480k − 100k) × $0,0008 | **$304** | **~€283** |
| Mux storage | ~15% mês médio | **~$65** | **~€60** |
| LiveKit egress | (18k − 600) × $0,001 | **~$17** | **~€16** |
| LiveKit Ship | fixo | **$50** | **~€47** |
| **Total vídeo** | | **~$886** | **~€824** |

---

#### Cenário C — «Pesadelo» histórico (60 vendedoras × 6 h/semana × 200 viewers)

Cenário das conversas antigas que fez o projecto parecer inviável — **não é recomendado**, serve de tecto.

| Premissa | Valor |
|----------|-------|
| Horas publicação / vendedora / semana | 6 h → **360 min** |
| Vendedoras | 60 |
| Espectadores / live (média) | 200 |
| Tempo visto / pessoa | 45 min (média em lives longas) |
| Lives efectivas / vendedora / mês | ~4 (6h ≈ 4×90 min) |

| Métrica | Cálculo | USD/mês | EUR/mês |
|---------|---------|---------|---------|
| Min. publicação | 60 × 4,33 × 360 ≈ **93 500** | — | — |
| Min. entrega | 60 × 4 × 200 × 45 ≈ **2 160 000** | — | — |
| Mux input | 93 500 × ~$0,023* | **~$2 150** | **~€2 000** |
| Mux delivery | (2,16M − 100k) × $0,0008 | **~$1 648** | **~€1 533** |
| Mux storage | ordem grandeza | **~$200** | **~€186** |
| LiveKit egress + WebRTC | | **~$140** | **~€130** |
| LiveKit Scale / bandwidth | provável upgrade | **+$500** plano | **~€465** |
| **Total vídeo** | | **~$4 600+** | **~€4 300+** |

\*Input com desconto por volume após 25k min — valor aproximado.

**Conclusão do cenário C:** com este padrão de uso, só infra vídeo pode passar **€4k+/mês** antes de Supabase, SMS e suporte. O projecto **continua viável** se o tráfego real for o **Cenário A ou B**.

---

#### Cenário D — Alvo interno (recomendado — C8)

| Premissa | Valor |
|----------|-------|
| Lives simultâneas no pico | **5–15** |
| Lives / mês (total plataforma) | **40–80** |
| Espectadores / live | **30–80** |
| Duração | **90 min** |

Estimativa mensal: **€150–500** em vídeo (entre A e B), assumindo tempo visto médio **30–40 min** e entrega Mux muitas vezes dentro dos **100k min grátis** no piloto.

---

### 6.6 Unit economics — vídeo vs taxa de proteção

Taxa de proteção (exemplo **artigo €15**, sem envio): **€0,65 + 5% × 15 = €1,40** por encomenda (toda para Fleaber).

| Cenário vídeo (EUR/mês) | Encomendas/mês para «pagar» só o vídeo* |
|-------------------------|----------------------------------------|
| Piloto ~€138 (Mux+LK) | **~99** encomendas |
| Piloto ~€61 (MediaMTX-1) | **~44** encomendas |
| Crescimento ~€824 (Mux+LK) | **~589** |
| Crescimento ~€77 (MediaMTX-1) | **~55** encomendas |
| Pesadelo ~€4 300 | **~3 071** |

\*Ignora Stripe (~1,5%+€0,25), Supabase, SMS, marketing — só compara **receita proteção vs Mux+LiveKit**.

**Gorjetas:** taxa 2,9% + €0,40 cobre sobretudo Stripe; **margem Fleaber nula ou negativa** em gorjetas pequenas (ex. €1 → fee €0,43).

**Leitura para decisão:**

- Com **ticket ~€15** e poucas encomendas por live, **volume de vendas** tem de acompanhar o número de espectadores — senão o vídeo come-se a proteção.  
- **Alavancas:** menos minutos entregues (espectadores que saem cedo, não autoplay em background), **720p**, lives mais curtas que 6 h, **cron egress**, preview só local até «Iniciar».  
- **Receita:** mais vendedoras com **GMV** alto por live compensa; 10 lives/semana com **~10 vendas protegidas/live** (~430/mês) já cobrem o piloto vídeo.

---

### 6.7 Outros custos fixos (ordem de grandeza)

| Serviço | Estimativa MVP | Notas |
|---------|----------------|-------|
| **Supabase** | €0–25/mês | Free tier; sobe com tráfego BD/storage |
| **SMS** (BulkGate) | ~€14 / 1000 SMS | Twilio PT ~€46 / 1000 |
| **Stripe** | 1,5% + €0,25 / transacção UE | Não é custo Fleaber directo no P&L do comprador |
| **Domínio / lojas** | variável | Fora do âmbito vídeo |

---

### 6.8 Concentração de lives (C8 — operacional)

- **Não impor** regra aos vendedores no lançamento.  
- **Planear infra** para **Cenário D** (€150–500 vídeo), monitorizar dashboard Mux/LiveKit semanalmente.  
- Se aproximar **Cenário B**, rever destaque na Home (menos lives em paralelo) ou Mux Scale ($500/mês com $1000 créditos — pode compensar acima de ~€800 uso Mux).  
- **Evitar** padrão C: muitas vendedoras com lives de **6 h** e **centenas** de viewers sem conversão.

**Incidente histórico:** egress LiveKit órfão ~**$46** — mitigado com teardown, preview local e `livekit-egress-cleanup` (ver `MERDA.md`).

---

### 6.9 Alternativa **MediaMTX** (self-hosted) — custos e trade-offs

**O que é:** [MediaMTX](https://github.com/bluenviron/mediamtx) (ex-rtsp-simple-server) — servidor media **open-source** (RTMP, RTSP, WebRTC/WHIP, HLS, gravação em disco). **Licença:** gratuita; pagas **VPS + tráfego + operação**.

**Nota do projecto (`MERDA.md`):** MediaMTX **não substitui** sozinho o encoder no telemóvel nem o Mux «mágico»; no TCL o RTMP directo (Haishin) falhou — por isso hoje existe **LiveKit no publish**. MediaMTX entra como **destino** ou **CDN caseiro**, não como app de câmara.

#### Arquitecturas possíveis

| Variante | Fluxo | O que deixa de pagar | O que manténs |
|----------|-------|----------------------|---------------|
| **MTX-1** (mínima mudança) | LiveKit publish → egress **RTMP → MediaMTX** → HLS viewers + gravação VPS | **Mux** input + delivery + storage | LiveKit Ship + egress |
| **MTX-2** (total self-host) | App → **RTMP ou WHIP** → MediaMTX → HLS + VOD em disco | **Mux + LiveKit** | VPS forte + FFmpeg se portrait |
| **MTX-3** (híbrido escala) | MTX-1 ou MTX-2 + **CDN** (Bunny/Cloudflare) à frente do HLS | Mux; reduz carga no VPS | VPS + CDN €/GB |

```
Actual:     Telemóvel ──WebRTC──► LiveKit Cloud ──egress RTMP──► Mux ──HLS──► Viewers

MTX-1:      Telemóvel ──WebRTC──► LiveKit Cloud ──egress RTMP──► MediaMTX (VPS) ──HLS──► Viewers
                                                                  └── gravação .mp4 (VOD)

MTX-2:      Telemóvel ──RTMP/WHIP──► MediaMTX (VPS) ──HLS──► Viewers
            (só viável se publish Android estável — hoje incerto no TCL)
```

#### Como se calcula o custo (bandwidth)

MediaMTX factura indirectamente via **GB saídos do VPS** (cada viewer puxa segmentos HLS). Estimativa conservadora **720p ~2 Mbps** médio:

```
GB_entrega ≈ min_entrega × 0,015   (ex.: 60 200 min → ~0,9 TB)
GB_publicação (upload 1× por live) ≈ min_publicação × 0,015
```

**Hosting referência (EU):** Hetzner Cloud **CPX31** (~€13,60/mês, 4 vCPU, 8 GB RAM) com **20 TB tráfego incluído** (UE); acima disso **~€1,19/TB** ([Hetzner traffic](https://docs.hetzner.com/robot/general/traffic/)). Valores **Mai 2026**, podem mudar.

| Item fixo MTX-1 | EUR/mês |
|-----------------|---------|
| VPS CPX31 (1 nó EU) | **~€14** |
| LiveKit Ship | **~€47** |
| LiveKit egress (piloto, dentro quota) | **~€0–16** |
| Disco VOD 100 GB (opcional volume) | **~€5** |
| **Total fixo aprox.** | **~€61–82** |

#### Comparação por cenário (mesmas premissas §6.5)

| Cenário | Stack **Mux + LiveKit** | **MTX-1** (LK → MediaMTX) | **MTX-2** (só MediaMTX)* |
|---------|-------------------------|---------------------------|---------------------------|
| **A Piloto** | **~€138** | **~€61** (−56%) | **~€14–25** |
| **B Crescimento** | **~€824** | **~€77** (−91%) | **~€14–30** (7,2 TB dentro dos 20 TB incl.) |
| **C Pesadelo** | **~€4 300+** | **~€630** (−85%) | **~€45–90**† |
| **D Alvo** | **€150–500** | **~€65–120** | **~€20–40** |

\*MTX-2 assume publish RTMP/WHIP **estável** no Android — **não validado** no TCL (Haishin falhou).  
†Cenário C em MTX-2: ~32 TB entrega → ~12 TB extra × €1,19 ≈ €14 + VPS maior (€26–40) para **15+ lives paralelas** — ainda **muito abaixo** de €4k Mux, mas **1 VPS pode não aguentar** 60 lives pesadas sem cluster/CDN.

#### MTX-3 — CDN à frente (quando passas dos 20 TB ou queres latência PT)

Exemplo **Bunny CDN** Europa ~**$0,01/GB** (ordem de grandeza): 7,2 TB → **~€67/mês** CDN + **€14** VPS = **~€81** (ainda **~90% abaixo** do Mux+LK €824).

#### O que ganhas vs o que perdes

| Ganho | Custo oculto / risco |
|-------|----------------------|
| Conta de vídeo **muito menor** em B e C | **Tu** és NOC: TLS, updates, backups, DDoS, uptime |
| Sem minuto Mux (input+delivery) | Sem player analytics Mux Data; métricas Prometheus + logs |
| VOD em disco teu | Backup, retenção, espaço disco; sem «asset Mux» pronto |
| RGPD EU fácil (Hetzner DE/FI) | IP fixo; escalar = mais nós ou CDN |
| RTMP interno já usado no egress LK | Mudar URL em `livekit-mux-publish` + `resolve-mux-playback` → URLs MTX |

| Risco **BATATA** | Detalhe |
|------------------|---------|
| Publish no TCL | MTX-2 exige reabrir RTMP/WHIP; LiveKit foi escolhido por estabilidade |
| Portrait / letterbox | MTX **não roda** vídeo — FFmpeg no VPS ou manter pipeline actual (`MERDA.md` §9) |
| Latência HLS pura | LL-HLS no MTX existe; tuning diferente do Mux reduced_latency |
| Concorrência | 5–15 lives no **mesmo** VPS: testar CPU/RAM antes do piloto |

#### Recomendação prática (só custos + estado actual do código)

| Fase | Stack sugerido |
|------|----------------|
| **MVP comercial (agora)** | Manter **Mux + LiveKit** — já integrado, portrait afinado, custo piloto **~€138/mês** (Cenário A) |
| **Piloto com 15+ vendedoras** | Avaliar **MTX-1**: egress LiveKit → MediaMTX; viewers apontam para `https://stream…/live/{id}.m3u8`; **poupar Mux** primeiro |
| **Escala PT (TB/mês)** | **MTX-1 + CDN** ou 2.º VPS; só **MTX-2** se RTMP/WHIP no telemóvel estiver **comprovado** em TCL + Redmi |
| **Não fazer só por preço** | Cenário C «pesadelo» em self-host **ainda precisa** CDN/cluster — barato em € mas **complexo** |

#### Unit economics — MTX-1 no piloto

Vídeo **~€61** vs **~€99** encomendas para empatar (protecção €1,40) → **~44 encomendas/mês** (vs 99 com Mux+LK) — **mais margem** para o mesmo tráfego, se a migração não atrasar o MVP.

---

## 7. Vantagens e desvantagens

### 7.1 Vantagens (Fleaber)

| # | Vantagem |
|---|----------|
| 1 | **Foco no hábito PT** — não inventa live shopping; profissionaliza o que já existe no Facebook |
| 2 | **Híbrido marketplace + live** — vende fora do horário do direto |
| 3 | **Proteção ao comprador** — linguagem Vinted, confiança |
| 4 | **Stack moderna** — Mux/LiveKit escalável; sem WebRTC massivo no viewer no MVP (controla custo) |
| 5 | **Comunidade de aquisição** — grupo 10k+ com interesse em diretos |
| 6 | **Gorjetas** — monetização emocional para vendedoras |
| 7 | **Admin disputas** — caminho para escalar confiança |
| 8 | **UX premium exigida** — diferencia de MVPs «feios» |

### 7.2 Desvantagens e riscos

| # | Desvantagem / risco | Mitigação |
|---|---------------------|-----------|
| 1 | **MVP ainda incompleto** (reserva in-live, Stripe, co-host) | Roadmap explícito; 6 h/dia dev |
| 2 | **Mudança de hábito** FB → app | Incentivos €25–50; dual-phone messaging |
| 3 | **Unit economics finos** se ticket ~€15 | Proteção 5%+0,65; gorjetas; volume |
| 4 | **Custos vídeo** se muitas lives paralelas | Concentração + cron egress |
| 5 | **RGPD / alojamento** — fundador precisa apoio | Escolher região Supabase EU; DPA |
| 6 | **Dependência Stripe / Mux** | Contratos; monitorização |
| 7 | **Concorrência futura** (TikTok Shop, Whatnot) | Nicho PT + operações vendedoras |
| 8 | **Complexidade operacional** (reserva + chat + live) | Helper/co-host; simplificar fila |

### 7.3 O que o fundador **não** quer copiar do Whatnot

- **Leilões** como core — no máximo **side business** ou opção pontual no direto.

---

## 8. Concorrência (Portugal, 2026)

| Player | Relação com Fleaber |
|--------|---------------------|
| **Facebook Live** | Concorrente actual de hábito; Fleaber é camada de ordem + pagamento |
| **Vinted / Wallapop** | Referência wallet/proteção; **sem live** integrado ao nível Fleaber |
| **Whatnot** | Referência UX live; leilões, ticket maior, modelo US/UK |
| **TikTok Shop** | Valida live commerce; algoritmo e creators ≠ vendedoras FB 35–65 |
| **Apps de marca única** | Shopify + app; Fleaber é **multi-vendedor** |
| **Nenhum em PT** | Afirmação do fundador: **ninguém oferece o pacote actual** — validar periodicamente |

---

## 9. Go-to-market

| Tema | Decisão |
|------|---------|
| Estratégia DMs pós-live | **Aberta** — 20–30/dia foi ideia antiga, não compromisso |
| Grupo Facebook | Canal de **descoberta/partilha**; explorar sem depender de views no grupo |
| Mensagem | Dor: caos + pagamentos + lista de vendas + etiqueta |
| Orçamento marketing | «Por aí» (~€500 mencionado historicamente) — vouchers, eventos, ads a definir |
| Público do pitch | Vendedoras FB + trazer clientes para a **live Fleaber** |

---

## 10. Roadmap sugerido (alinhado às respostas)

### 10.1 Prioridade imediata (próximas semanas)

1. **Fila / reserva real no live** (D2) — substituir placeholder RESERVAR.  
2. **Google Sign-In** (D10).  
3. **SMS produção** (BulkGate).  
4. **Co-host / Helper** (D8) — «amanhã se houver tempo».  
5. **Checkout Stripe** fecho marketplace + ligação a encomendas (D3, D5).  
6. **Polish páginas** + conferir admin disputas (D15).  
7. **Mensagem dual-phone** quando venda no Fleaber com live FB (A3).

### 10.2 Antes de «10 vendedoras a pagar taxa»

- Testar gorjetas end-to-end.  
- Confirmar legal (termos, livro reclamações, RGPD EU).  
- Definir **replay comprável** (D12) — sugestão: 24–72 h alinhado a urgência live.  
- Piloto com 3–5 vendedoras do grupo + incentivo €25–50.

### 10.3 Médio prazo

- API envios (InPost/CTT).  
- WebRTC viewer **só se** tração justificar custo (E3).  
- Brasil / ES / FR conforme tração.  
- Leilão opcional no direto (discussão produto).

### 10.4 Data MVP comercial

**Não definida** pelo fundador.

---

## 11. Aspectos legais e compliance

| Tema | Estado |
|------|--------|
| Operador | **Mare Antiga Unipessoal, Lda**, NIF **518775364** |
| Modelo | Marketplace intermediário **tipo Vinted** |
| Devoluções / disputas | **Tipo Vinted** + admin |
| Menores | Vendedor **18+** |
| RGPD | **Ajuda necessária** — Supabase região, DPA, política privacidade |
| Pagamentos | Stripe PSD2; wallet — documentar termos de saldo |

---

## 12. Ideias do fundador para melhorar (registo)

- Notificação no chat da vendedora quando vende no Fleaber com live simultânea no Facebook.  
- Facilitar **toda a linha vendedora** (menos fricção que FB) — prioridade se tivesse 2 semanas só de dev.  
- Aberto a sugestões em **reservas pendentes**, **replay**, **pagamentos híbridos**, **leilão opcional**.

---

## 13. Glossário

| Termo | Significado |
|-------|-------------|
| **Arena** | Ecrã fullscreen `FleaberLivePlayer` |
| **BATATA** | Regras de engenharia: mudanças mínimas, não partir live |
| **Taxa de Proteção** | €0,65 + 5% paga pelo comprador |
| **live_items** | Produtos ligados a um `live_id` |
| **Helper** | Painel co-host (reservas, DMs, gatilho pagamento) — planeado |

---

## 14. Anexos e documentos relacionados

| Ficheiro | Conteúdo |
|----------|----------|
| `Historico/PERGUNTAS_PARA_FUNDADOR.md` | Respostas originais |
| `Historico/_extract_all.txt` | Conversas Gemini/GPT exportadas |
| `MERDA.md` | Diário técnico live/portrait |
| `lib/utils/fee_calculator.dart` | Taxa de proteção |
| `supabase/sql/live_tips_batata.sql` | Gorjetas |

---

## 15. Próximas actualizações deste documento

Quando existirem:

- Data MVP e primeiras 10 vendedoras pagantes  
- Facturas Mux/LiveKit/Supabase reais (ajustar cenários §6.5–6.6)  
- Feedback piloto (João e vendedoras)  
- Decisão RGPD (região + textos legais finais)  
- Estratégia GTM fechada (com ou sem DMs)  
- Métricas GMV e ticket médio reais  

---

*Documento gerado com base nas respostas do fundador (Mai 2026) e na análise do repositório Fleaber. Cenários financeiros de infra são orientativos, não previsões garantidas.*
