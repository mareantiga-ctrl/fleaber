# Perguntas para o fundador — documento Fleaber

**Objetivo:** Com as tuas respostas, preparo um trabalho completo sobre o Fleaber (funcionalidades, vantagens/desvantagens, modelo de negócio, concorrência, riscos, roadmap).

**O que já li:** pasta `Historico` (31 ficheiros `.rtf` — conversas Gemini/GPT, plano Vinted, custos, GTM Facebook, etc.) + código da app (`lib/`, `supabase/`, `MERDA.md`).  
**Nota:** Os RTFs grandes estão truncados na extração; onde a resposta for vaga, podes apontar o ficheiro/conversa exacta.

Responde por baixo de cada pergunta (ou num ficheiro à parte com o mesmo número). Podes responder em tópicos curtos — não precisa de redação formal.

---

## A. Visão, marca e posicionamento

**A1.** Frase oficial que queres usar hoje (escolhe uma ou escreve outra):
- «O sítio onde os diretos acontecem»
- «Se em direto, Fleaber»
- «Clica, vê, compra»
- Outra: Marketplace Ao Vivo_______________

**A2.** Pronúncia para anúncios: **Fleaber** ou **Fliaber** — qual é a regra definitiva? Em portugues de portugal Lesse Fliaber, mas o nome oficial ~e Fleaber

**A3.** Em uma frase: o Fleaber é substituto do Facebook Live, complemento (dual-publish), ou ambos consoante o vendedor? ~E suvstituto,mas quero que quando uma venda seja feita na flieaber apareca uma mensagem no chat da vendedora caso ela esteja com 2 telemoveis, um a filmar em directo para o Fleaber outro para o Facebook

**A4.** «Não é uma rede social» — o que queres **excluir** explicitamente (feed infinito, stories, DMs públicas, seguir sem comprar, etc.)?
Nao te sei responder

**A5.** Prioridade geográfica nos próximos 12 meses: só **Portugal**, **PT+ES**, ou outro? Diria que para comecar os testes ~e portugal, se correr bem,e o contacto que estou a trabalhar no brasil correr bem quero ir para o brasil logo no inicio, mas sim, o normal sera primeiro espanha e franca

**A6.** Vertical principal confirmada: roupa/bijuteria (35–65) — ou já incluis **feira online** (bancada fixa) como segundo pillar igual?
ainda nao sei bem, mas ~e para ser por enquanto como esta extruturado no site, mas aceito ideias

---

## B. Público, comunidade e go-to-market

**B1.** Grupo Facebook ~10 200 membros: nome do grupo, regras de promoção da app, e quantos vendedores activos em live por semana (ordem de grandeza)?
o grupo que tenho basicamente as pessoas partilham directos la, como fazem muito nesse circulo de vendas em directo, depois na pratica nao tem muita gente a ver os directos a partir do grupo que actualmente ja tem 10400 membros, mas a riquesa dele e essa ~e que as pessoas que la foram aderir tem algum interesse em partilhar directos, fazer directos, ou assistir directos, por isso ~e um mundo a explorar e aproveitar

**B2.** Meta de outreach: ainda **20–30 DMs/dia** pós-live? Quem envia (tu, Klaudia, ambos)? ainda nao pensamos bem na estrategia, que pode ate nem passar por ai.. nao sei.. mais uma vez estamos abertos a ideias

**B3.** Oferta de beta actual: «meses grátis / sem comissão» + **voucher €5** — valores exactos e duração?
Estava a pensar oferecer uns 25 euros as primeiras vendedoras ou 50 euros, que facam directo e tragam as suas clientes, para elas surtearem em mercadoria aos clientes que vierem para o fleaber, ou algo mais ou menos assim, pk na pratica quem paga comissao sao os clientes, aqui na app ate podem receber grogetas que ate pode ser uma pequena fonte de rendimento

**B4.** Primeiro utilizador de teste (João e outros): o que validaram e o que falhou? Lista 3 coisas que disseram «isto impede-me de usar».
neste momento nao tenho nada a dizer, ainda falta fazer umas paginas, ainda temos muita pequena coisa a alteral, polish, mas o que ta feito esta TOP

**B5.** Tiago e Cláudia: papéis concretos (produto, comercial, suporte)? O «Plano Diretor» em `fleaber tipo vinted.rtf` continua válido ou mudou?
De momento trabalho sozinho, com ajuda da claudia a decidir e planear

**B6.** Klaudia: percentagem de tempo em dev vs apoio a vendedores vs marketing?
de momento muito pouco, mas quando a app tiver pronta passa a ser trabalho a tempo inteiro praticamente
---

## C. Modelo de negócio e números

**C1.** **Taxa de Proteção** (código: €0,65 + 5% sobre artigo+envio) — confirma que é **só para o comprador** e que o vendedor **não** paga comissão separada além disto?
correto

**C2.** Em compras **directas** (sem proteção no checkout) — quando acontece e porquê?
tnes de ver como esta na estrotura do site, pooruqe basicamente fazem uma reserva, depois o vendedor enviar os dados para pagamento fora o site, depois o comprador diz que pagou e manda comprovativo opcionalmente, depois o vendedor confirma que enviou, depois o comprador confirma que recebeu e trocam feedback, e algum desses passos falhar a compra fica pendente no sistema, talvez no futuro devessemos resolver melhor, estou aberto a sugestoes

**C3.** **Gorjetas em live:** a taxa 2,9% + €0,40 cobre custos Stripe/Mux ou também margem Fleaber? Quem vê o breakdown (vendedor / viewer)? so cobra a taxa stripe por alto ne../ nao sei.. aberto a sugestoes

**C4.** **Pagamento manual / MBWay** no início: ainda é requisito de produto ou já abandonado? ainda nao sei bem, mas acho que isso era para os testes, porque vamos usar o stipe para pagamentos oficiais, os nao oficias seram fornecidos pelos vendedores e pode ser o que eles quiserem dentro da lei obvio..

**C5.** Ticket médio real que usas nos cálculos: **€15** fixo ou intervalo (ex. €8–25)?
foi apenas um numero, nao foi estudado

**C6.** Modelo de receita ano 1: GMV alvo, nº de transacções/mês, ou nº de vendedores activos — qual métrica te importa mais? Nao sei..

**C7.** Orçamento mensal infra (Mux, LiveKit, Supabase, SMS): tecto aceitável hoje? Já tens factura real pós-cron egress? O menos possivel, se me ofereceres cenarios para eu estudar conseguia responder melhor

**C8.** Estratégia de **concentração de lives** (poucas lives grandes vs muitas pequenas): regra operacional que vais impor aos vendedores ou só economia interna?
O que sugeres?

**C9.** Stripe Connect: todos os vendedores obrigados a ligar conta ou há vendedores só com wallet interna? eu acho que deve ser wallet interna nao, como no vinted, depois o resto sera a app a gerir certo,
mas se as vendedoras quiserem usar os meios de pagamentos delas, e assossiarem a app, e a app conseguir confirmar que o pagamento foi efectuado, nao sei se da pk o dinheiro nao passa pela app proppriamento dita, mas no minimo se desse para pagarem directamente na app com os meios de pagamente dos vendedores a minha comissao podia baixar para sei la .30centimos +3% para o cliente pagar, nao sei se ~e viavel, fala comigo

---

## D. Produto — o que está feito vs o que é «must have»

Responde **Feito / Parcial / Não / Não prioritário** e notas curtas.

| # | Funcionalidade | Estado (tu) | Prioridade MVP comercial |
|---|----------------|-------------|---------------------------|
| D1 | Reserva por número no live (RESERVAR no player) | | |Parcial, ainda nao esta terminado 
| D2 | Fila / primeiro a clicar ganha | | | Prioritario a ser ffeito
| D3 | Checkout Stripe produto → encomenda | | | mais perto do lancamento
| D4 | Fluxo reserva BATATA no chat (lembretes, confirmar, cancelar) | | |Mais ou menos feito
| D5 | Carteira + libertação ao vendedor | | |Mais perto do fim, quando tiver as api do stipe
| D6 | Gorjetas live (Stripe + wallet) | | |Acho que ta feito mas ainda nao testei
| D7 | Catálogo live (`live_items`) sincronizado com prep | | |Esta alinhavado mas quero trocar  a forma como estao no llayout
| D8 | Co-host / painel Helper backstage | | |Proximos passos ~e isso
| D9 | InPost / CTT / etiquetas automáticas | | | Ja enviei email a pedir api mas ainda nao obtive resposta
| D10 | Google Sign-In | | |Prioritario a ser feito
| D11 | Verificação telefone SMS (Twilio/BulkGate) | | | Ja fui verificado no bulkgate, amanha dou te as chaves
| D12 | Replay pós-live — quanto tempo fica «comprável»? | | |Ainda nao decidi, aceito ideias
| D13 | Marketplace sem live (só Vinted-style) | | |Tambem ~e, temos as duas coisas
| D14 | Leilão / licitação | | | Por enquanto nao, ou melhor, ate podiamos colocar essa opcao, se as vendedoras no meio do directo fazer uma peca a leilao ou mais que uma, temos de falar disso, mas talvez nao para o MVP
| D15 | Admin disputas + comissões | | | Mais ou menos, falta conferir para ter a certeza

**D16.** Qual é o **fluxo ideal** em 5 passos (comprador no live): ver produto → ? → pagar → ? → envio?
Tipo o Vinted
**D17.** O que significa «complicado com encomendas e chat» (frase dos vendedores) — 3 exemplos reais? Nao sei do que falas

---

## E. Live, vídeo e experiência Arena

**E1.** Portrait «tipo TikTok» no telemóvel: requisito **bloqueante** para lançamento ou aceitas landscape com barras até segunda fase? o MVP tem de estar TOP, nao aceito landscape, mas ja resolvemos isso

**E2.** Vendedor pode continuar a fazer live **só no Facebook** e usar Fleaber só como «carrinho» durante o FB? Se ele entender que ~e a melhor solucao para ele.. para mim melhor recebo a comissao ser ter os custos de transmissao

**E3.** Espectador: só HLS Mux (actual) — confirmas que **nunca** WebRTC para viewers?
no MVP nao, Mas muito brevemente teremos de modar, se a app correr bem ne.. para controlar os custos

**E4.** Duração típica de live que desenhas (minutos)? Máximo?
eu espero com 1 e 30 digo eu

**E5.** Thumbnail/home: crop vs letterbox — preferência final para cards «A decorrer»?
Ainda vamos ver isso mais a frente 
**E6.** Dispositivos alvo de teste: só TCL T775H ou lista completa? por enquanto estou a usar esse mas posso amanha tertar em mais

---

## F. Confiança, legal e risco

**F1.** Entidade legal que opera o Fleaber (nome, NIF, morada) — já existe ou só planeada?
por enquanto pertence a MARE ANTIGA UNIPESSOAL, LDA
518775364

**F2.** Livro de reclamações, termos, privacidade: quem redigiu? URL final em produção?
Temos online acho eu, mas sim temos de verificar isso
**F3.** Idade mínima vendedor: **18+** obrigatório? Conta em nome dos pais para menores? Sim 18

**F4.** Fleaber é **marketplace** (intermediário) ou **agência de pagamentos** na tua visão jurídica?
Vou ser como o vinted

**F5.** Política de devoluções/disputas: copia Vinted, regras próprias, ou caso a caso no admin?
vou ser tipo vinted

**F6.** Dados pessoais: onde estão alojados (Supabase região)? RGPD — DPO ou auto-gestão?
de momento nao estao em lado nenhum, nao faco a minima de quais as opcoes, e quais as melhores, vais ter de me ajudar nisso

---

## G. Concorrência e diferenciação (para o texto final)

**G1.** Top 3 razões para um vendedor **deixar** Facebook Live pelo Fleaber.
Acabar com o caos, facilitar os pagamentos, conseguirem ver na hora quam comprou o que, so tem de imprimir etiqueta e enviar ao inves de ter de estar a vasculhar a confusao de mensagem do face, sabes as dificuldades que elas tem, se tiveres ideias para eu melhorar a app nesse sentido agradeco
**G2.** Top 3 razões para **não** mudar (medo, hábito, custo, audiência).
Essas todas
**G3.** Concorrente que mais te preocupa em PT em 2026: TikTok Shop, Whatnot, Vinted, app de uma marca, outro?
De momento nenhuma oferece o que estou a oferecer
**G4.** Algo que o Whatnot faz e **nunca** queres no Fleaber?
nao me quero focar em leiloes, podes ser um sidebusiness
---

## H. Roadmap e recursos

**H1.** Data alvo de «MVP comercial» (primeiros 10 vendedores a pagar taxa): ___/2026
Nao sei
**H2.** Horas/semana que dedicas ao projeto (média últimos 3 meses)?
Quase 6h diarias medias
**H3.** Orçamento marketing confirmado (ex. €500) — para quê (ads, eventos, vouchers)?
Por ai
**H4.** Próximas 3 features **tu** escolherias se tivesses 2 semanas só de dev?
Facilitar a venda as vendedoras
**H5.** O que está **proibido** mudar sem combinar contigo (além do BATATA no código): lista em linguagem de negócio.
Funcionalidades 
---

## I. Métricas de sucesso do documento

**I1.** Público do trabalho final: investidores, vendedores, parceiros técnicos, equipa interna, concurso/academia?
Vendedores que ja vendam no face e que tragam os cliente para a LIVE do fleaber,para mim principalemte, para a claudia, para os parceiros que tento trazer para a app
**I2.** Tom: pitch comercial, relatório técnico, ou misto?
misto
**I3.** Extensão desejada: ~5 páginas, ~15 páginas, ou sem limite?
NAo sei, nao queria limite,mas nao sei
**I4.** Incluir **números financeiros** reais (GMV, custos) ou cenários hipotéticos claramente marcados?
O mais real que conseguires
**I5.** Idioma final do documento: PT-PT apenas?
sim
---

## J. Lacunas que encontrei (confirma ou corrige)

1. **ZegoCloud** aparece em wireframes antigos; produção é **LiveKit→Mux** — documento deve ignorar Zego?
sim
2. **Firebase** para chat foi sugerido; app usa **Supabase** — confirma stack oficial. 
Supabase
3. **Comissão** no admin vs **taxa de proteção** ao utilizador — mesma coisa ou duas linhas de receita?
so tenho a comissao de taxa de proteccao
4. **Co-host/Helper** está no histórico mas não na app — ainda faz parte da visão 2026?
Sim faz, vaio ser o que vamos fazer amanha se houver tempo
5. **Espanha** no texto histórico — já há vendedores ou só visão futura?
Visao futura

---

## Ficheiros de apoio (para ti)

| Ficheiro | Uso |
|----------|-----|
| `Historico/_extract_all.txt` | Texto extraído dos RTF (gerado por `_extract_rtf.py`) |
| `MERDA.md` | Estado técnico live/portrait (Mai 2026) |
| `lib/utils/fee_calculator.dart` | Taxa de proteção actual |
| `supabase/sql/live_tips_batata.sql` | Gorjetas e taxas |

---

**Próximo passo (meu):** Quando responderes (mesmo que incompleto), crio `Historico/FLEABER_DOCUMENTO.md` (ou nome que preferires) com visão completa do produto.

*Gerado em 24 Mai 2026 — Cursor, após leitura Historico + codebase.*
