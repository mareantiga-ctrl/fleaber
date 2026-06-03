/// Textos legais e informativos (alinhados com website/ e FLEABER_DOCUMENTO.md).

class LegalTexts {

  LegalTexts._();



  static const updatedLabel = 'Última atualização: Maio 2026';



  static const privacyTitle = 'Política de Privacidade';

  static const termsTitle = 'Termos e Condições';

  static const refundsTitle = 'Reembolsos e Disputas';

  static const faqTitle = 'Perguntas Frequentes';

  static const howItWorksTitle = 'Como funciona o Fleaber';

  static const aboutTitle = 'Sobre a Fleaber';



  static const _entity =

      'Mare Antiga Unipessoal Lda\nNIF: 518775364\n'

      'Morada: Estrada Casal da Raposeira, Casa Agostinho, '

      '2600-817 São João dos Montes, Portugal';



  static const _contacts =

      'Suporte: geral@fleaber.pt · +351 937 475 638\n'

      'Legal / RGPD: mareantiga@gmail.com\n'

      'Comercial: geral@fleaber.com';



  static List<LegalSection> get privacy => [

        const LegalSection(

          title: 'Introdução',

          body:

              'A Fleaber respeita a privacidade dos utilizadores e trata dados pessoais '

              'em conformidade com o Regulamento (UE) 2016/679 (RGPD) e a legislação '

              'portuguesa aplicável.\n\n'

              'Este documento aplica-se à aplicação móvel Fleaber e ao website fleaber.pt.',

        ),

        LegalSection(

          title: 'Responsável pelo tratamento',

          body: '$_entity\n\nEmail: geral@fleaber.pt\nLegal / RGPD: mareantiga@gmail.com',

        ),

        const LegalSection(

          title: 'Dados que recolhemos',

          body:

              '• Identificação: nome, email, telefone, foto de perfil\n'

              '• Morada e dados de envio\n'

              '• Histórico de compras, vendas, reservas e mensagens na plataforma\n'

              '• Dados de pagamento processados por terceiros (ex.: Stripe) — '

              'não guardamos números completos de cartão\n'

              '• Conteúdo de lives (vídeo via parceiros de streaming)\n'

              '• Dados técnicos: IP, dispositivo, sistema operativo, logs de segurança\n'

              '• Preferências e notificações na app',

        ),

        const LegalSection(

          title: 'Finalidades e base legal',

          body:

              'Utilizamos os dados para:\n'

              '• Criar e gerir a sua conta\n'

              '• Processar compras, vendas, reservas, propostas e gorjetas\n'

              '• Retenção de pagamentos (proteção ao comprador) e carteira\n'

              '• Chat entre comprador e vendedor\n'

              '• Prevenção de fraude, moderação e segurança\n'

              '• Suporte ao cliente e resolução de disputas\n'

              '• Cumprimento de obrigações legais e fiscais\n'

              '• Melhoria do serviço (analytics agregados)\n\n'

              'Bases legais: execução de contrato, interesse legítimo, '

              'consentimento (quando aplicável) e obrigação legal.',

        ),

        const LegalSection(

          title: 'Subcontratantes e partilha',

          body:

              'Podemos partilhar dados apenas quando necessário com:\n'

              '• Processadores de pagamento (Stripe)\n'

              '• Infraestrutura cloud e base de dados (Supabase, região UE)\n'

              '• Streaming de vídeo (LiveKit, Mux)\n'

              '• Envio de SMS de verificação (ex.: BulkGate)\n'

              '• Transportadoras (CTT, InPost, DPD — conforme integrações activas)\n'

              '• Autoridades, quando exigido por lei\n\n'

              'Não vendemos os seus dados pessoais a terceiros.',

        ),

        const LegalSection(

          title: 'Conservação',

          body:

              'Conservamos os dados enquanto a conta estiver activa e pelo tempo '

              'necessário para obrigações legais, contabilidade e resolução de disputas '

              '(normalmente até 5 anos após a última transacção relevante, salvo prazo legal superior).',

        ),

        const LegalSection(

          title: 'Os seus direitos',

          body:

              'Pode solicitar acesso, rectificação, apagamento, limitação, portabilidade '

              'ou oposição ao tratamento, contactando mareantiga@gmail.com ou geral@fleaber.pt.\n\n'

              'Tem o direito de apresentar reclamação à Comissão Nacional de Protecção de Dados (CNPD): '

              'www.cnpd.pt',

        ),

        const LegalSection(

          title: 'Segurança',

          body:

              'Aplicamos medidas técnicas e organizativas adequadas (encriptação em trânsito, '

              'controlo de acessos, políticas de segurança na base de dados). '

              'Nenhum sistema é 100% seguro — reporte incidentes a geral@fleaber.pt.',

        ),

      ];



  static List<LegalSection> get terms => [

        const LegalSection(

          title: '1. A plataforma',

          body:

              'A Fleaber é um marketplace ao vivo operado em Portugal, que permite a compra '

              'e venda de artigos entre utilizadores registados, incluindo vendas em direto (live shopping) '

              'e listagens no marketplace.\n\n'

              'A Fleaber (Mare Antiga Unipessoal Lda) não é vendedora dos produtos — actua como '

              'intermediária tecnológica entre compradores e vendedores, no espírito de plataformas '

              'de segunda mão como o Vinted.',

        ),

        const LegalSection(

          title: '2. Elegibilidade e conta',

          body:

              '• Utilização reservada a maiores de 18 anos\n'

              '• Conta pessoal e intransmissível\n'

              '• Deve fornecer dados verdadeiros; podemos solicitar verificação de email ou telefone\n'

              '• Reservamo-nos o direito de suspender contas por violação destes termos ou fraude',

        ),

        const LegalSection(

          title: '3. Compras, reservas e propostas',

          body:

              '• Durante lives, o comprador pode reservar artigos do catálogo da live\n'

              '• No marketplace e no chat, pode negociar propostas de preço (validade típica 48 h)\n'

              '• Conjuntos de artigos podem beneficiar de descontos definidos pelo vendedor\n'

              '• Cada transacção fica registada com identificadores de encomenda e, quando aplicável, da live\n'

              '• O pagamento oficial deve ser efectuado na app (Stripe), salvo fluxos de teste acordados',

        ),

        const LegalSection(

          title: '4. Taxa de Protecção Fleaber',

          body:

              'O comprador paga, além do artigo e portes:\n'

              '• Taxa de Protecção: 0,65 € + 5% sobre (valor do artigo + portes de envio)\n\n'

              'Esta taxa financia a protecção ao comprador, suporte e funcionamento da plataforma. '

              'O vendedor não paga comissão separada além desta estrutura (não há comissão extra ao vendedor).\n\n'

              'Exemplo: artigo 15 €, sem portes → taxa ≈ 0,65 + 0,75 = 1,40 €.',

        ),

        const LegalSection(

          title: '5. Pagamentos e retenção (escrow)',

          body:

              'Os pagamentos são processados por prestadores certificados (Stripe). '

              'O valor fica retido na plataforma até:\n'

              '• o comprador confirmar a recepção, ou\n'

              '• passarem 48 horas após a entrega sem disputa aberta — libertação automática ao vendedor.\n\n'

              'O saldo do vendedor fica disponível na carteira Fleaber; levantamentos seguem as regras '

              'do Stripe Connect quando activos.',

        ),

        const LegalSection(

          title: '6. Envio e modo de férias',

          body:

              '• O vendedor envia no prazo máximo de 5 dias úteis após confirmação do pagamento\n'

              '• A Fleaber pode disponibilizar etiquetas via parceiros logísticos (CTT, InPost, etc.)\n'

              '• O vendedor pode activar «modo de férias» — os artigos permanecem visíveis com aviso; '

              'recomendamos não aceitar novas encomendas durante esse período',

        ),

        const LegalSection(

          title: '7. Gorjetas em live',

          body:

              'Compradores podem enviar gorjetas durante lives. O valor é creditado ao vendedor '

              'após dedução de taxas de processamento de pagamento (aprox. 2,9% + 0,40 €, conforme Stripe). '

              'As gorjetas não substituem o pagamento de artigos reservados.',

        ),

        const LegalSection(

          title: '8. Disputas e reembolsos',

          body:

              'Ver documento «Reembolsos e Disputas». Em resumo: o comprador tem 48 h após entrega '

              'para reclamar; a Fleaber pode reter fundos e decidir reembolso total, parcial ou libertação ao vendedor.',

        ),

        const LegalSection(

          title: '9. Conteúdo proibido',

          body:

              'É proibido: produtos ilegais, armas, drogas, falsificações, conteúdo de ódio, '

              'burlas, spam, manipulação de avaliações ou uso da plataforma fora do seu fim comercial.',

        ),

        const LegalSection(

          title: '10. Limitação de responsabilidade',

          body:

              'A Fleaber não garante a qualidade, autenticidade ou legalidade dos artigos vendidos pelos utilizadores. '

              'Não somos parte do contrato de compra e venda entre utilizadores, excepto nos mecanismos '

              'de protecção e mediação previstos nestes termos.\n\n'

              'O serviço é prestado «tal como está»; não nos responsabilizamos por interrupções de live, '

              'atrasos de transportadoras ou falhas de terceiros, dentro dos limites legais.',

        ),

        LegalSection(

          title: '11. Contacto e reclamações',

          body:

              '$_contacts\n\n'

              'Livro de Reclamações electrónico: www.livroreclamacoes.pt',

        ),

      ];



  static List<LegalSection> get refunds => [

        const LegalSection(

          title: 'Protecção ao comprador',

          body:

              'Quando paga na Fleaber com Protecção activa, o valor fica retido até:\n'

              '• confirmar que recebeu o artigo em condições aceitáveis, ou\n'

              '• expirarem 48 horas após a marcação de «entregue» sem disputa.',

        ),

        const LegalSection(

          title: 'Quando pode pedir reembolso',

          body:

              '• Artigo não recebido no prazo razoável\n'

              '• Artigo significativamente diferente da descrição ou da live\n'

              '• Artigo danificado ou defeituoso\n'

              '• Envio em falta ou erro manifesto do vendedor\n\n'

              'Abra a disputa na encomenda dentro de 48 h após a entrega.',

        ),

        const LegalSection(

          title: 'Processo de disputa',

          body:

              '1. Comprador abre disputa → pagamento suspenso\n'

              '2. Vendedor e comprador podem enviar provas (fotos, chat, tracking)\n'

              '3. Vendedor pode propor compensação parcial ou reembolso\n'

              '4. Sem acordo, a Fleaber analisa e decide (reembolso total, parcial ou libertação)\n'

              '5. Decisão vinculativa para efeitos da plataforma e movimentação de saldo',

        ),

        const LegalSection(

          title: 'Portes e devoluções',

          body:

              'Por norma, o comprador paga os portes de envio inicial.\n'

              'Se a disputa for por culpa do vendedor, este pode ser responsabilizado pelos custos '

              'de envio ou devolução.\n'

              'Em devoluções aprovadas, siga as instruções na app (etiqueta ou morada indicada). '

              'O reembolso só é processado após validação, quando aplicável.',

        ),

        const LegalSection(

          title: 'Prazos importantes',

          body:

              '• 48 h — comprador reportar problema após entrega\n'

              '• 5 dias úteis — vendedor enviar após pagamento confirmado\n'

              '• 48 h — propostas de preço expiram se não forem aceites (quando aplicável)',

        ),

        const LegalSection(

          title: 'Fraude',

          body:

              'Tentativas de fraude podem resultar em suspensão imediata, bloqueio de saldo, '

              'banimento permanente e comunicação às autoridades quando legalmente exigido.',

        ),

        LegalSection(

          title: 'Apoio',

          body: _contacts,

        ),

      ];



  static List<LegalSection> get faq => [

        const LegalSection(

          title: 'O que é a Fleaber?',

          body:

              'Marketplace ao vivo para Portugal: compra e vende em direto ou no catálogo, '

              'com reservas registadas, chat, pagamentos protegidos e carteira — pensado para quem '

              'já vende no Facebook Live e quer menos caos nos comentários.',

        ),

        const LegalSection(

          title: 'A app já está disponível?',

          body:

              'Estamos em fase final de testes em Portugal. O lançamento nas lojas (App Store e Google Play) '

              'será anunciado no website e nas redes oficiais.',

        ),

        const LegalSection(

          title: 'Quanto custa usar a Fleaber?',

          body:

              'Registo gratuito. O comprador paga a Taxa de Protecção (0,65 € + 5% sobre artigo + portes) '

              'em compras com protecção activa. O vendedor não paga comissão adicional à plataforma.',

        ),

        const LegalSection(

          title: 'Como funcionam os pagamentos?',

          body:

              'Pagamento na app via Stripe. O dinheiro fica retido até confirmar a entrega ou passarem '

              '48 h sem disputa. O vendedor recebe na carteira Fleaber e pode levantar conforme as regras Connect.',

        ),

        const LegalSection(

          title: 'Posso vender só no Facebook e usar a Fleaber como carrinho?',

          body:

              'Tecnicamente alguns vendedores usam dois telemóveis (Facebook + Fleaber). O ideal é transmitir '

              'na Fleaber para ter reservas e protecção integradas. Quando vende na app, pode receber alerta no chat.',

        ),

        const LegalSection(

          title: 'O que são propostas de preço?',

          body:

              'Como no Vinted: o comprador propõe um valor; o vendedor aceita, recusa ou contra-propõe. '

              'Propostas expiram ao fim de 48 horas se não forem respondidas.',

        ),

        const LegalSection(

          title: 'O que são descontos em conjuntos?',

          body:

              'O vendedor pode criar um conjunto de artigos com desconto automático (ex.: 2, 3 ou 5 peças). '

              'O comprador vê o preço total e pode comprar ou enviar proposta no chat.',

        ),

        const LegalSection(

          title: 'O que é o modo de férias?',

          body:

              'O vendedor activa nas definições para avisar compradores que está ausente. '

              'Os artigos mostram um aviso; recomendamos não enviar encomendas nesse período.',

        ),

        const LegalSection(

          title: 'Gorjetas nas lives',

          body:

              'Pode enviar gorjetas durante um directo. São opcionais e separadas da compra de artigos. '

              'Aplicam-se taxas de processamento de pagamento.',

        ),

        const LegalSection(

          title: 'Como abro uma disputa?',

          body:

              'Na encomenda, dentro de 48 h após marcar como entregue. Descreva o problema e anexe provas. '

              'O pagamento fica suspenso até resolução.',

        ),

        const LegalSection(

          title: 'Que produtos posso vender?',

          body:

              'Artigos legais em categorias permitidas (moda, casa, colecionáveis, etc.). '

              'Proibidos: ilegal, armas, drogas, falsificações e conteúdo ofensivo.',

        ),

        const LegalSection(

          title: 'Os meus dados estão seguros?',

          body:

              'Cumprimos o RGPD. Pagamentos são processados por Stripe; não guardamos dados completos de cartão. '

              'Consulte a Política de Privacidade na app.',

        ),

        LegalSection(

          title: 'Como contacto o suporte?',

          body: _contacts,

        ),

      ];



  static List<LegalSection> get howItWorks => [

        const LegalSection(

          title: 'Para compradores',

          body:

              '1. Segue vendedores e entra nas lives ou explora o marketplace\n'

              '2. Reserva ou compra um artigo; negocia proposta no chat se quiser\n'

              '3. Paga na app (artigo + portes + Taxa de Protecção)\n'

              '4. Acompanha o envio e confirma a recepção\n'

              '5. Se houver problema, abre disputa em 48 h após entrega',

        ),

        const LegalSection(

          title: 'Para vendedores',

          body:

              '1. Cria conta e completa perfil (verificação email/telefone recomendada)\n'

              '2. Publica artigos no marketplace e/ou prepara catálogo para a live\n'

              '3. Faz live na Arena ou vende fora do directo\n'

              '4. Recebe reservas e encomendas no chat — envia em até 5 dias úteis\n'

              '5. Após libertação do pagamento, saldo na carteira; levanta via Stripe Connect',

        ),

        const LegalSection(

          title: 'Lives e replay',

          body:

              'O vendedor transmite em portrait; os espectadores vêem o stream em tempo real. '

              'Após o directo, o replay pode ficar disponível para ver e, conforme definições, comprar artigos.',

        ),

        const LegalSection(

          title: 'Confiança',

          body:

              'Avaliações, chat oficial, histórico de reservas com hora, protecção ao comprador e equipa '

              'de moderação/disputas tornam a experiência mais previsível do que vender só por comentários no Facebook.',

        ),

      ];



  static List<LegalSection> get about => [

        const LegalSection(

          title: 'Fleaber — Marketplace ao Vivo',

          body:

              'O sítio onde os diretos acontecem com pagamentos a sério.\n\n'

              'Combinamos o que as vendedoras portuguesas já fazem no Facebook Live — mostrar, '

              'reservar, conversar — com encomendas, carteira e protecção ao comprador, no espírito do Vinted.\n\n'

              'Público inicial: vendedoras e compradoras em Portugal (roupa, bijuteria, casa e mais).',

        ),

        LegalSection(

          title: 'Operador',

          body: '$_entity',

        ),

        LegalSection(

          title: 'Contactos',

          body: _contacts,

        ),

        const LegalSection(

          title: 'Reclamações',

          body:

              'Para litígios de consumo pode usar o Livro de Reclamações: www.livroreclamacoes.pt\n'

              'Apoio prévio: geral@fleaber.pt',

        ),

      ];

}



class LegalSection {

  const LegalSection({required this.title, required this.body});

  final String title;

  final String body;

}


