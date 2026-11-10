/// Textos legais e informativos (fonte da app; espelhar em website/).
///
/// Revisão Outubro 2026 (H11 / Informação legal) — alinhada ao produto real.
/// Afirmações jurídicas prudentes; direitos imperativos dos consumidores
/// não são afastados por regras internas da plataforma.
class LegalTexts {
  LegalTexts._();

  static const updatedLabel = 'Última atualização: Outubro 2026';
  /// Páginas informativas revistas em Outubro 2026 (Como funciona / FAQ / Sobre).
  static const updatedLabelInfoOct2026 = 'Última atualização: Outubro 2026';

  static const privacyTitle = 'Política de Privacidade';
  static const termsTitle = 'Termos e Condições';
  static const refundsTitle = 'Reembolsos e Disputas';
  static const faqTitle = 'Perguntas Frequentes';
  static const howItWorksTitle = 'Como funciona o Fleaber';
  static const buySafeTitle = 'Comprar com segurança';
  static const sellTitle = 'Vender na Fleaber';
  static const contactsTitle = 'Contactos e identificação legal';
  static const aboutTitle = 'Sobre a nossa plataforma';
  static const cookiesTitle = 'Política de Cookies';
  static const dataDeletionTitle = 'Eliminação de conta e dados';

  static const publicPrivacyUrl = 'https://fleaber.pt/privacy.html';
  static const publicTermsUrl = 'https://fleaber.pt/terms.html';
  static const publicRefundsUrl = 'https://fleaber.pt/refunds.html';
  static const publicCookiesUrl = 'https://fleaber.pt/cookies.html';
  static const publicDataDeletionUrl = 'https://fleaber.pt/data-deletion.html';
  static const stripePrivacyUrl = 'https://stripe.com/privacy';
  static const metaPrivacyUrl = 'https://www.facebook.com/privacy/policy/';
  static const cnpdUrl = 'https://www.cnpd.pt';

  /// Entidade exploradora (fonte única — rodapé Hub / textos legais).
  static const operatorLegalName = 'Mare Antiga Unipessoal Lda';
  static const operatorNif = '518775364';
  static const operatorAddressLine =
      'Estrada Casal da Raposeira, Casa Agostinho, '
      '2600-817 São João dos Montes, Portugal';
  static const supportEmail = 'geral@fleaber.pt';
  static const legalEmail = 'legal@fleaber.pt';
  static const supportPhoneDisplay = '+351 937 475 638';
  static const supportPhoneTel = 'tel:+351937475638';
  static const livroReclamacoesUrl = 'https://www.livroreclamacoes.pt';
  static const copyrightLine =
      '© 2026 Fleaber. Todos os direitos reservados.';

  static const _entity =
      '$operatorLegalName\nNIF: $operatorNif\n'
      'Morada: $operatorAddressLine';

  static const _contacts =
      'Suporte: $supportEmail · $supportPhoneDisplay\n'
      'Legal / RGPD: $legalEmail (alternativo: mareantiga@gmail.com)\n'
      'Comercial: $supportEmail';

  static List<LegalSection> get privacy => [
        const LegalSection(
          title: 'Introdução',
          body:
              'A Fleaber respeita a privacidade dos utilizadores e trata dados pessoais '
              'em conformidade com o Regulamento (UE) 2016/679 (RGPD) e a legislação '
              'portuguesa aplicável.\n\n'
              'Este documento aplica-se à aplicação móvel Fleaber, ao website fleaber.pt '
              'e ao FleaHub (páginas públicas de vendedores).\n\n'
              'Versão pública: https://fleaber.pt/privacy.html',
        ),
        LegalSection(
          title: 'Responsável pelo tratamento',
          body:
              '$_entity\n\nEmail: $supportEmail\n'
              'Legal / RGPD: $legalEmail · mareantiga@gmail.com',
          linkLabel: 'Contactar suporte',
          linkUrl: 'mailto:$supportEmail',
        ),
        const LegalSection(
          title: 'Dados que recolhemos',
          body:
              '• Identificação: nome, email, telefone, foto de perfil, handle público\n'
              '• Morada e dados de envio (nome do destinatário, morada, código postal, '
              'localidade, país, telefone de contacto), quando necessários para a encomenda\n'
              '• Histórico de compras, vendas, reservas, propostas, gorjetas e mensagens\n'
              '• Dados de pagamento processados por terceiros (Stripe; e, quando activo, '
              'dados de MB WAY/IBAN introduzidos pelo vendedor para pagamento directo) — '
              'não guardamos números completos de cartão\n'
              '• Conteúdo de lives (vídeo via LiveKit/Mux) e, quando aplicável, metadados '
              'técnicos associados à transmissão\n'
              '• Dados técnicos: IP, dispositivo, sistema operativo, logs de segurança, '
              'cookies/sessão e armazenamento local no website e Hub (ver Política de Cookies)\n'
              '• Preferências e notificações na app\n'
              '• Dados provenientes do Facebook/Meta quando utiliza login ou integrações '
              '(ver secção dedicada)',
        ),
        const LegalSection(
          title: 'Menores de idade',
          body:
              'A Fleaber destina-se a utilizadores com 18 ou mais anos. Não recolhemos '
              'intencionalmente dados de menores. Se tomar conhecimento de uma conta de '
              'menor, contacte legal@fleaber.pt para eliminação.',
        ),
        const LegalSection(
          title: 'Finalidades e base legal',
          body:
              'Utilizamos os dados para:\n'
              '• Criar e gerir a sua conta\n'
              '• Processar compras, vendas, reservas, propostas e gorjetas\n'
              '• Retenção operacional de pagamentos protegidos (Protecção Fleaber) e carteira\n'
              '• Onboarding e levantamentos Stripe Connect (KYC do vendedor)\n'
              '• Cumprimento de envios com a transportadora parceira integrada (DPD), '
              'quando aplicável ao fluxo de etiqueta/envio\n'
              '• Gestão do estatuto de vendedor profissional (declaração, verificação '
              'documental e conservação proporcional dos comprovativos)\n'
              '• Chat entre comprador e vendedor\n'
              '• Prevenção de fraude, moderação e segurança\n'
              '• Suporte ao cliente e resolução de disputas\n'
              '• Cumprimento de obrigações legais e fiscais\n'
              '• Melhoria do serviço, apenas com dados agregados ou com base legal adequada\n\n'
              'Bases legais: execução de contrato, interesse legítimo (segurança, prevenção '
              'de fraude, melhoria proporcional do serviço), consentimento (quando exigido) '
              'e obrigação legal.',
        ),
        const LegalSection(
          title: 'Facebook / Meta',
          body:
              'Se iniciar sessão com Facebook ou ligar a sua conta Meta, recebemos '
              'identificadores e dados de perfil que a Meta nos disponibiliza conforme '
              'as permissões que autorizar.\n\n'
              'Se for vendedor e utilizar ferramentas Fleaber para ler comentários do seu '
              'Facebook Live (integrações de leitura de comentários), tratamos o conteúdo '
              'dos comentários e nomes públicos apenas para criar ou actualizar reservas e '
              'mensagens na Fleaber, sob instruções do vendedor e no âmbito do serviço.\n\n'
              'A Meta actua como responsável autónomo pelos dados na sua plataforma. '
              'Consulte também a Política de Privacidade da Meta: '
              'https://www.facebook.com/privacy/policy/\n\n'
              'Pode revogar permissões nas definições da Meta e/ou eliminar a conta Fleaber. '
              'Instruções de eliminação: https://fleaber.pt/data-deletion.html',
        ),
        const LegalSection(
          title: 'Pagamentos (Stripe e pagamento directo)',
          body:
              'Nas compras com «Seguro Fleaber» / pagamento na app, o processamento é '
              'feito pela Stripe. A Fleaber não armazena dados completos de cartão.\n\n'
              'A Stripe trata dados de pagamento e, nos levantamentos, dados de KYC do '
              'vendedor (identidade, conta bancária) conforme a Política de Privacidade '
              'da Stripe: https://stripe.com/privacy\n\n'
              'Quando o vendedor activa pagamentos externos (MB WAY / transferência), '
              'podem ser mostrados ao comprador o número MB WAY e/ou IBAN que o vendedor '
              'configurou. Estes dados são fornecidos pelo vendedor; a Fleaber não processa '
              'esse pagamento como prestador de serviços de pagamento e esse modo '
              'não inclui a Protecção Fleaber.',
        ),
        const LegalSection(
          title: 'Transportadoras (DPD)',
          body:
              'Para etiquetas e entregas integradas na Fleaber, a transportadora parceira '
              'referenciada é a DPD. Não disponibilizamos CTT, InPost ou GLS como serviços '
              'integrados na app.\n\n'
              'Quando o envio o exigir, podemos partilhar com a DPD (ou com o operador '
              'logístico efectivamente usado no fluxo):\n'
              '• nome do destinatário\n'
              '• morada, código postal, localidade e país\n'
              '• telefone de contacto\n'
              '• referência / identificador da encomenda\n\n'
              'A partilha ocorre por necessidade contratual para cumprir o envio. '
              'A transportadora trata esses dados como responsável autónomo ou '
              'subcontratante conforme as suas próprias condições.\n\n'
              'A responsabilidade pelo envio correcto e atempado é do vendedor, salvo '
              'regras específicas de disputa na Fleaber. A Fleaber não é transportadora.',
        ),
        const LegalSection(
          title: 'Subcontratantes e partilha',
          body:
              'Podemos partilhar dados apenas quando necessário com:\n'
              '• Processadores de pagamento (Stripe) — ver https://stripe.com/privacy\n'
              '• Infraestrutura cloud e base de dados (Supabase; dados preferencialmente '
              'na UE; se houver transferência internacional, aplicam-se salvaguardas '
              'adequadas, p.ex. cláusulas contratuais-tipo)\n'
              '• Streaming de vídeo (LiveKit, Mux)\n'
              '• Envio de SMS de verificação (ex.: BulkGate), quando usado\n'
              '• Facebook / Meta (login e integrações de comentários Live, quando usadas)\n'
              '• Transportadora parceira DPD (quando o envio integrado o exigir)\n'
              '• Autoridades, quando exigido por lei\n\n'
              'Não vendemos os seus dados pessoais a terceiros.',
        ),
        const LegalSection(
          title: 'Cookies e tecnologias semelhantes',
          body:
              'No website e no FleaHub usamos mecanismos estritamente necessários à '
              'autenticação, segurança e funcionamento do serviço (incluindo armazenamento '
              'local). Detalhes: https://fleaber.pt/cookies.html',
        ),
        const LegalSection(
          title: 'Eliminar conta e dados',
          body:
              'Pode pedir a eliminação da conta e dos dados pessoais:\n'
              '• na app: Perfil → Definições → Eliminar conta (confirmação escrita '
              '«ELIMINAR CONTA»), ou\n'
              '• por email a geral@fleaber.pt / legal@fleaber.pt\n\n'
              'A eliminação pode ser recusada temporariamente se existirem obrigações '
              'activas (encomendas em curso, disputas abertas, lives activas ou saldo '
              'na carteira). Apagamos ou anonimizamos dados sob reserva de conservação '
              'legal (facturação, disputas, prevenção de fraude) pelos prazos desta política.\n\n'
              'Página dedicada: https://fleaber.pt/data-deletion.html',
        ),
        const LegalSection(
          title: 'Conservação',
          body:
              'Não aplicamos um prazo único a todas as categorias de dados. Em regra:\n'
              '• Dados de conta e perfil — enquanto a conta estiver activa; após '
              'eliminação, anonimização ou apagamento salvo conservação legal\n'
              '• Dados de transacções, facturação e obrigações fiscais/contabilísticas — '
              'pelos prazos legais aplicáveis em Portugal (frequentemente até 10 anos '
              'para documentação contabilística, conforme o regime aplicável)\n'
              '• Disputas, chargebacks e prevenção de fraude — pelo tempo necessário '
              'à resolução e a interesses legítimos de segurança (tipicamente até alguns '
              'anos após o fecho, sem prejuízo de prazos legais superiores)\n'
              '• Logs técnicos de segurança — período limitado e proporcional\n'
              '• Conteúdo de lives / media — conforme a finalidade do serviço e pedidos '
              'de eliminação\n\n'
              'Quando a lei imponha conservação, limitamos o tratamento ao estritamente '
              'necessário para essa obrigação.',
        ),
        LegalSection(
          title: 'Os seus direitos',
          body:
              'Pode solicitar acesso, rectificação, apagamento, limitação, portabilidade '
              'ou oposição ao tratamento, contactando $legalEmail ou $supportEmail.\n\n'
              'Responderemos, em regra, no prazo de um mês (prorrogável nos termos do '
              'RGPD quando o pedido for complexo).\n\n'
              'Tem o direito de apresentar reclamação à Comissão Nacional de Protecção '
              'de Dados (CNPD): https://www.cnpd.pt',
          linkLabel: 'Abrir site da CNPD',
          linkUrl: cnpdUrl,
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
              'e venda de artigos entre utilizadores registados, incluindo vendas em directo '
              '(live shopping) e listagens no marketplace.\n\n'
              'A Fleaber (Mare Antiga Unipessoal Lda) não é, em regra, a vendedora dos '
              'produtos nem o «merchant of record» das vendas celebradas entre utilizadores. '
              'Actua como intermediária tecnológica: disponibiliza a app, reservas, chat, '
              'pagamentos protegidos (quando escolhidos), carteira e mediação de disputas.\n\n'
              'O contrato de compra e venda é celebrado entre comprador e vendedor. '
              'Podem participar particulares (C2C) e, quando o vendedor actue como '
              'profissional, vendas a consumidores (B2C). Os direitos legais obrigatórios '
              'dos consumidores aplicam-se sempre que a lei o determine — as regras '
              'internas da Fleaber não os afastam.',
        ),
        const LegalSection(
          title: '2. Elegibilidade e conta',
          body:
              '• Utilização reservada a maiores de 18 anos\n'
              '• Conta pessoal e intransmissível\n'
              '• Deve fornecer dados verdadeiros; podemos solicitar verificação de email '
              'ou telefone\n'
              '• Reservamo-nos o direito de suspender contas por violação destes termos '
              'ou fraude, sem prejuízo dos direitos legais do utilizador',
        ),
        const LegalSection(
          title: '2-A. Vendedores profissionais',
          body:
              'O vendedor pode declarar em Definições → Dados profissionais que exerce '
              'actividade comercial e fornecer os dados exigíveis (nome comercial, '
              'identificação, NIF/NIPC, morada e contactos profissionais, e '
              'documentação comprovativa). Não existe distintivo «Particular»: por '
              'defeito, quem não está verificado como profissional é tratado como '
              'particular no checkout.\n\n'
              'O distintivo público «Profissional» só aparece após aprovação pela '
              'Fleaber (estado Profissional verificado). Enquanto o pedido estiver '
              'por preencher, em análise ou rejeitado, as novas vendas desse '
              'vendedor ficam temporariamente suspensas — sem cancelar encomendas '
              'existentes nem bloquear mensagens.\n\n'
              'Um profissional já verificado não pode desactivar o estatuto de '
              'imediato: tem de pedir alteração de estatuto, com motivo. Enquanto '
              'o pedido estiver pendente, mantém a identificação profissional. A '
              'alteração só produz efeitos após decisão da administração Fleaber. '
              'O histórico de encomendas e o estatuto aplicável a cada transação '
              'são preservados.\n\n'
              'Estados: Dados por preencher · Pedido em análise · Profissional '
              'verificado · Pedido rejeitado. A aprovação é exclusiva da '
              'administração Fleaber (sem autoaprovação). O distintivo não '
              'certifica a qualidade dos produtos.\n\n'
              'Documentos, NIF, telefone e email profissionais são privados '
              '(verificação administrativa). Aos compradores mostra-se apenas a '
              'identificação comercial necessária (nome comercial e localidade, '
              'quando aplicável). O contacto com o vendedor faz-se pelo chat '
              'Fleaber. No checkout, a informação sobre o estatuto aparece de '
              'forma discreta antes de confirmar a compra.',
        ),
        const LegalSection(
          title: '3. Compras, reservas e propostas',
          body:
              '• Durante lives, o comprador pode reservar artigos do catálogo da live\n'
              '• Os prazos de reserva (TTL) são configuráveis pelo vendedor dentro dos '
              'limites da app (desde cerca de 15 minutos até 5 dias; o valor por omissão '
              'é tipicamente 5 dias). Podem existir modos que exigem aprovação ou pagamento '
              'para confirmar a reserva\n'
              '• No marketplace e no chat, pode negociar propostas de preço; as propostas '
              'expiram tipicamente ao fim de 48 horas se não forem respondidas\n'
              '• Conjuntos de artigos podem beneficiar de descontos definidos pelo vendedor\n'
              '• Cada transacção fica registada com identificadores de encomenda e, quando '
              'aplicável, da live\n'
              '• O pagamento efectua-se pelos métodos disponibilizados na app: pagamento '
              'protegido via Stripe («Seguro Fleaber» / pagamento na app) e, quando o '
              'vendedor o activar, MB WAY ou transferência directa ao vendedor (sem '
              'Protecção Fleaber)',
        ),
        const LegalSection(
          title: '4. Taxa de Protecção Fleaber',
          body:
              'Nas compras com protecção activa, o comprador paga, além do artigo e portes:\n'
              '• Taxa de Protecção: 0,65 € + 5% sobre (valor do artigo + portes de envio)\n\n'
              'Esta taxa financia a protecção contratual ao comprador, suporte e '
              'funcionamento da plataforma. O vendedor não paga comissão de venda '
              'separada à Fleaber além desta estrutura.\n\n'
              'Exemplo: artigo 15,00 € + portes 3,50 € = base 18,50 € → taxa = 0,65 € + '
              '5% × 18,50 € = 0,65 + 0,925 ≈ 1,58 € (arredondamento ao cêntimo).\n'
              'Exemplo sem portes: artigo 15,00 € → taxa ≈ 0,65 + 0,75 = 1,40 €.\n\n'
              'Compras por pagamento directo (MB WAY/transferência) não incluem esta taxa '
              'nem a protecção associada.',
        ),
        const LegalSection(
          title: '5. Pagamentos, retenção operacional e Stripe Connect',
          body:
              'Pagamento protegido (Stripe): o valor pago pelo comprador é processado pela '
              'Stripe e fica retido operacionalmente no ecossistema Fleaber/Stripe (saldo '
              'ainda não disponível na carteira do vendedor) enquanto a encomenda segue o '
              'ciclo (pago → enviado → concluído). Isto não constitui um depósito escrow '
              'bancário autónomo nem uma garantia financeira regulada: é o fluxo de '
              'pagamento e libertação de saldo previsto nestes Termos e na política de '
              'reembolsos.\n\n'
              'Libertação do saldo para a carteira Fleaber do vendedor (compras protegidas):\n'
              '• Vendas entre particulares (C2C): após «concluído», quando o comprador '
              'deixa avaliação positiva (≥ 4 estrelas); ou se, 48 horas após «concluído» '
              'sem disputa activa, a plataforma gerar avaliação automática positiva.\n'
              '• Vendas a consumidor por profissional verificado (B2C): o valor permanece '
              'indisponível para levantamento durante o prazo de livre resolução aplicável '
              '(14 dias de calendário após a recepção do bem), salvo excepções legais '
              'declaradas no anúncio. Se existir livre resolução ou disputa válida em '
              'curso, a retenção prolonga-se até ao fecho desse processo.\n'
              '• Em ambos os canais, disputa Fleaber aberta ou contestação Stripe '
              '(chargeback) sobre o valor em causa bloqueia a libertação desse montante.\n'
              'Confirmar só a recepção marca a encomenda como concluída; o crédito '
              'levantável segue as regras acima. Esta retenção operacional não constitui '
              'escrow bancário autónomo nem garantia financeira regulada.\n\n'
              'Carteira e levantamentos: o saldo disponível (total menos valores retidos '
              'por disputa/chargeback/risco) pode ser levantado via Stripe Connect Express. '
              'O vendedor deve completar o onboarding Connect (KYC e conta bancária). '
              'Em caso de risco financeiro grave documentado, a Fleaber pode suspender '
              'preventivamente levantamentos e novas vendas, com informação dos motivos '
              'e via de reclamação interna.\n\n'
              'Política de privacidade da Stripe: https://stripe.com/privacy\n\n'
              'Pagamento directo (MB WAY / transferência): o comprador paga fora do '
              'processamento Stripe da Fleaber; a plataforma não retém esse valor na '
              'carteira de protecção nem oferece a Protecção Fleaber.',
        ),
        const LegalSection(
          title: '6. Envio e modo de férias',
          body:
              '• O vendedor envia no prazo máximo de 5 dias úteis após confirmação do pagamento\n'
              '• A transportadora parceira integrada na Fleaber é a DPD. A Fleaber não é '
              'transportadora e não disponibiliza CTT, InPost ou GLS como serviços '
              'integrados\n'
              '• O vendedor é responsável por embalar correctamente, escolher o serviço '
              'disponível e cumprir prazos\n'
              '• Extravio, atraso ou dano em trânsito: use o tracking da transportadora e, '
              'se aplicável, abra disputa na Fleaber com provas (compras protegidas)\n'
              '• Modo de férias: quando o vendedor o activa, os anúncios e directos ficam '
              'ocultos no marketplace e na Home — não é possível comprar nem fazer '
              'propostas novas. As conversas e as encomendas já em curso continuam '
              'normalmente',
        ),
        const LegalSection(
          title: '7. Gorjetas em live',
          body:
              'Compradores podem enviar gorjetas durante lives, quando a funcionalidade '
              'estiver disponível na app. O valor é creditado ao vendedor após dedução '
              'das taxas de processamento de pagamento aplicadas pela Stripe ao fluxo '
              'de gorjetas (actualmente 2,9% + 0,40 € no processamento Fleaber). As '
              'gorjetas não substituem o pagamento de artigos reservados.',
        ),
        const LegalSection(
          title: '8. Disputas Fleaber e chargebacks Stripe',
          body:
              'Disputas Fleaber: ver documento «Reembolsos e Disputas». Em resumo, o '
              'comprador tem 48 h após entrega para reclamar no âmbito da Protecção '
              'Fleaber; a Fleaber pode reter fundos e decidir reembolso total, parcial '
              'ou libertação ao vendedor no âmbito da plataforma. Esta decisão interna '
              'não impede o recurso a entidades administrativas ou judiciais competentes.\n\n'
              'Cancelamento antes do envio (compra protegida): o comprador pode pedir '
              'anulação até à expedição; se aceite, o valor retido não é libertado ao '
              'vendedor e a Fleaber inicia automaticamente o reembolso Stripe para o '
              'método de pagamento original (ver «Reembolsos e Disputas»).\n\n'
              'Chargebacks / disputas do cartão junto da Stripe ou do banco do comprador '
              'são processos distintos. A Fleaber retém apenas o valor contestado no '
              'saldo do vendedor (não o saldo inteiro por defeito), pede provas e '
              'coopera com a Stripe. Se o saldo for insuficiente, regista-se o remanescente '
              'como valor a recuperar em créditos futuros. Um chargeback não substitui '
              'automaticamente o fluxo de disputa da app, e vice-versa. A Fleaber não '
              'debita automaticamente cartões pessoais do vendedor nesta versão.',
        ),
        const LegalSection(
          title: '9. Direitos dos consumidores e livre resolução',
          body:
              'A Fleaber permite vendas entre particulares (C2C) e, quando o vendedor '
              'actue como profissional perante um consumidor, vendas B2C.\n\n'
              'Quando compras a um vendedor profissional verificado, podes beneficiar do '
              'direito legal de livre resolução no prazo de 14 dias de calendário a contar '
              'da data em que receberes o bem, nos termos do Decreto-Lei n.º 24/2014 e da '
              'legislação europeia aplicável, salvo as excepções legalmente previstas '
              '(por exemplo bens personalizados ou bens selados que não possam ser '
              'devolvidos por razões de higiene após abertura). Este direito é distinto '
              'da Proteção Fleaber de 48 horas.\n\n'
              'O profissional é responsável perante o consumidor pelo cumprimento das '
              'obrigações de livre resolução e garantia de conformidade. Quando o '
              'pagamento corre na Fleaber/Stripe, a plataforma pode executar o reembolso '
              'no método de pagamento original e exigir ao vendedor a restituição '
              'correspondente, incluindo retenção ou compensação no saldo Connect.\n\n'
              'A garantia legal de conformidade (regime típico de 3 anos) é distinta da '
              'livre resolução e da Proteção Fleaber; não implica retenção plurianual '
              'de fundos.\n\n'
              'Nas vendas entre particulares, o regime de livre resolução de 14 dias '
              'próprio das compras a profissionais pode não se aplicar da mesma forma. '
              'Sem prejuízo, a Protecção Fleaber e o processo de disputa da app aplicam-se '
              'às compras protegidas conforme estes Termos e a política de reembolsos, '
              'e não substituem nem excluem direitos legais imperativos quando existam.',
        ),
        const LegalSection(
          title: '10. Conteúdo proibido',
          body:
              'É proibido: produtos ilegais, armas, drogas, falsificações, conteúdo de ódio, '
              'burlas, spam, manipulação de avaliações ou uso da plataforma fora do seu '
              'fim comercial.',
        ),
        const LegalSection(
          title: '11. Limitação de responsabilidade',
          body:
              'A Fleaber não garante a qualidade, autenticidade ou legalidade dos artigos '
              'vendidos pelos utilizadores. Não somos parte do contrato de compra e venda '
              'entre utilizadores, excepto nos mecanismos de protecção e mediação previstos '
              'nestes termos.\n\n'
              'Dentro dos limites permitidos pela lei aplicável, o serviço é prestado '
              '«tal como está»; não nos responsabilizamos por interrupções de live, atrasos '
              'de transportadoras ou falhas de terceiros.\n\n'
              'Nada nestes Termos exclui ou limita responsabilidade por dolo, culpa grave, '
              'ou quaisquer direitos imperativos dos consumidores que não possam ser '
              'contratualmente afastados.',
        ),
        LegalSection(
          title: '12. Contacto e reclamações',
          body:
              '$_contacts\n\n'
              'Livro de Reclamações electrónico: https://www.livroreclamacoes.pt',
          linkLabel: 'Abrir Livro de Reclamações',
          linkUrl: livroReclamacoesUrl,
        ),
      ];

  static List<LegalSection> get refunds => [
        const LegalSection(
          title: 'Protecção ao comprador',
          body:
              'Quando paga na Fleaber com Protecção activa (Stripe / Seguro Fleaber), o '
              'valor fica retido operacionalmente no ecossistema Fleaber/Stripe durante o '
              'ciclo da encomenda. Não se trata de um escrow bancário autónomo: é o fluxo '
              'de pagamento protegido e libertação de saldo descrito nos Termos.\n\n'
              'O comprador deve confirmar a recepção (encomenda «concluído») ou reportar '
              'problema / abrir disputa nos prazos da app.\n\n'
              'C2C (particulares): o saldo do vendedor fica disponível após avaliação '
              'positiva (≥ 4 estrelas) ou após a avaliação automática gerada 48 horas '
              'depois de «concluído» sem disputa activa.\n\n'
              'B2C (profissional verificado): além da Proteção Fleaber de 48 horas, o '
              'valor permanece retido operacionalmente até ao fim do prazo de livre '
              'resolução de 14 dias (ou até ao fecho de uma livre resolução / disputa '
              'válida aberta). A garantia legal de conformidade não se confunde com '
              'esta retenção.\n\n'
              'Compras por MB WAY / transferência directa ao vendedor não incluem esta '
              'protecção: a Fleaber não processa nem retém esse pagamento.',
        ),
        const LegalSection(
          title: 'Cancelamento e reembolso (antes do envio)',
          body:
              'Até à expedição («enviado»), o comprador pode pedir cancelamento na app. '
              'O vendedor confirma se ainda não enviou. Após «enviado», use disputa / '
              'devolução — não o cancelamento simples.\n\n'
              'A) Compra com Protecção Fleaber (Stripe) já paga\n'
              '• A encomenda é anulada e o artigo pode voltar ao marketplace.\n'
              '• O valor retido não é libertado para a carteira do vendedor.\n'
              '• Ao aceitar o cancelamento (ou anular a venda), a Fleaber inicia '
              'automaticamente o reembolso Stripe para o método de pagamento '
              'original do comprador.\n'
              '• Estimativa típica de disponibilidade no cartão: até 10 dias úteis após o '
              'início do reembolso, sujeita ao banco emissor — não é uma garantia bancária '
              'universal.\n'
              '• Se o crédito não aparecer, contacte geral@fleaber.pt com o ID da '
              'encomenda.\n\n'
              'B) Pagamento directo (MB WAY / transferência) — ainda sem confirmação '
              'do vendedor\n'
              '• O «Já paguei» / prova na app é informativo; o dinheiro saiu da conta '
              'do comprador fora da Fleaber.\n'
              '• A Fleaber não pode reverter MB WAY nem transferências bancárias.\n'
              '• Se a reserva caducar ou for cancelada e já tiver pago, combine a '
              'devolução directamente com o vendedor (ou com o seu banco).\n\n'
              'C) Pagamento directo já confirmado pelo vendedor («pago») e depois anulado\n'
              '• A Fleaber anula a encomenda na plataforma, mas não move o dinheiro '
              'bancário.\n'
              '• O reembolso é obrigação do vendedor perante o comprador, combinado no '
              'chat; a Fleaber pode mediar a conversa, sem garantia de prazo bancário.',
        ),
        const LegalSection(
          title: 'Quando pode pedir reembolso (após entrega)',
          body:
              '• Artigo não recebido no prazo razoável\n'
              '• Artigo significativamente diferente da descrição ou da live\n'
              '• Artigo danificado ou defeituoso\n'
              '• Envio em falta ou erro manifesto do vendedor\n\n'
              'No âmbito contratual da Protecção Fleaber, abra a disputa na encomenda '
              'dentro de 48 h após a entrega. Este prazo contratual não prejudica direitos '
              'legais obrigatórios dos consumidores quando aplicáveis (incluindo prazos '
              'legais distintos de reclamação ou livre resolução em vendas B2C).',
        ),
        const LegalSection(
          title: 'Processo de disputa (Fleaber)',
          body:
              '1. Comprador abre disputa → pagamento suspenso na plataforma\n'
              '2. Vendedor e comprador podem enviar provas (fotos, chat, tracking)\n'
              '3. Vendedor pode propor compensação parcial ou reembolso\n'
              '4. Sem acordo, a Fleaber analisa e emite uma decisão interna '
              '(reembolso total, parcial ou libertação de saldo)\n'
              '5. A decisão interna aplica-se à movimentação de saldo e ao fecho da '
              'disputa na plataforma; não impede reclamação junto de entidades '
              'competentes (ex.: CNPD para dados, Livro de Reclamações, tribunais ou '
              'centros de arbitragem de consumo, quando aplicável)',
        ),
        const LegalSection(
          title: 'Chargebacks bancários / Stripe',
          body:
              'Se o comprador abrir uma contestação junto do banco ou da Stripe '
              '(chargeback), esse processo corre em paralelo. A Fleaber retém apenas o '
              'montante contestado, pede provas ao vendedor e pode contestá-lo junto da '
              'Stripe. Se o saldo for insuficiente, a diferença fica como valor a '
              'recuperar. O resultado de um chargeback pode diferir da decisão da disputa '
              'Fleaber.',
        ),
        const LegalSection(
          title: 'Livre resolução (só B2C)',
          body:
              'Em compras a profissional verificado, podes exercer a livre resolução na '
              'encomenda dentro de 14 dias após receberes o artigo, salvo excepções '
              'legais indicadas no anúncio. Devolves o artigo conforme as instruções da '
              'app; a Fleaber executa o reembolso Stripe quando o fluxo de devolução '
              'estiver concluído, imputando a obrigação ao vendedor profissional. Este '
              'direito é distinto da disputa «Tenho um problema» (Proteção Fleaber, 48 h).',
        ),
        const LegalSection(
          title: 'Portes, transportadoras e devoluções',
          body:
              'Por norma, o comprador paga os portes de envio inicial.\n'
              'Se a disputa for por culpa do vendedor, este pode ser responsabilizado pelos '
              'custos de envio ou devolução.\n\n'
              'A transportadora parceira integrada na Fleaber é a DPD. Em caso de extravio '
              'ou atraso, use o tracking disponível e anexe-o à disputa.\n\n'
              'Em devoluções aprovadas, siga as instruções na app (etiqueta ou morada '
              'indicada). O reembolso só é processado após validação, quando aplicável.',
        ),
        const LegalSection(
          title: 'Prazos importantes',
          body:
              '• 48 h — prazo contratual da Protecção Fleaber para reportar problema após '
              'entrega (sem prejuízo de direitos legais)\n'
              '• 5 dias úteis — vendedor enviar após pagamento confirmado\n'
              '• Até expedição — pedido de cancelamento negociado na app\n'
              '• Até 10 dias úteis — estimativa típica de disponibilidade do reembolso '
              'protegido no cartão após processamento (sujeito ao banco)\n'
              '• 48 h — propostas de preço expiram se não forem aceites (quando aplicável)\n'
              '• Reservas em live — TTL configurável pelo vendedor (limites da app)',
        ),
        const LegalSection(
          title: 'Fraude e medidas de segurança',
          body:
              'Tentativas de fraude ou abuso podem resultar em suspensão de conta, retenção '
              'temporária de saldos, limitação de funcionalidades ou banimento, e comunicação '
              'às autoridades quando legalmente exigido. Estas medidas são proporcionais e '
              'não substituem processos legais externos.',
        ),
        LegalSection(
          title: 'Apoio',
          body: _contacts,
          linkLabel: 'Enviar email a geral@fleaber.pt',
          linkUrl: 'mailto:$supportEmail',
        ),
      ];

  static List<LegalSection> get cookies => [
        const LegalSection(
          title: 'O que são cookies',
          body:
              'Cookies e tecnologias semelhantes (por exemplo localStorage / '
              'SharedPreferences no browser) permitem manter a sessão, segurança e '
              'preferências essenciais ao funcionamento do website e do FleaHub.',
        ),
        const LegalSection(
          title: 'O que utilizamos actualmente',
          body:
              'Na build web actual do Fleaber / FleaHub:\n'
              '• Mecanismos estritamente necessários: autenticação, sessão, segurança e '
              'funcionamento do Hub\n'
              '• Preferência de aviso de cookies (chave local fleaber_cookie_consent_v1) '
              'para recordar que leu o aviso\n\n'
              'Não activamos de momento cookies ou SDKs de analytics, publicidade ou '
              'remarketing de terceiros (por exemplo Google Analytics / Firebase Analytics / '
              'Meta Pixel) no website Fleaber.\n\n'
              'Como apenas utilizamos mecanismos necessários ao serviço, o banner informa '
              'e confirma o aviso; não pedimos consentimento artificial para categorias '
              'não essenciais inexistentes. Se no futuro forem introduzidos cookies não '
              'essenciais, actualizaremos esta política e o banner com consentimento prévio, '
              'opção de recusa e revogação.',
        ),
        const LegalSection(
          title: 'Gestão',
          body:
              'Pode bloquear ou apagar cookies e dados de site nas definições do browser. '
              'Se bloquear armazenamento essencial, o login ou o Hub podem deixar de '
              'funcionar.\n\n'
              'Contacto: legal@fleaber.pt · geral@fleaber.pt',
        ),
      ];

  static List<LegalSection> get dataDeletion => [
        const LegalSection(
          title: 'Como pedir a eliminação',
          body:
              'Na app ou no FleaHub (com sessão iniciada):\n'
              '1. Abre Perfil → Definições de conta.\n'
              '2. Escolhe Eliminar conta.\n'
              '3. Confirma escrevendo exactamente «ELIMINAR CONTA».\n\n'
              'Em alternativa (incluindo pedidos ligados a Facebook/Meta):\n'
              'envia email a geral@fleaber.pt ou legal@fleaber.pt com o assunto '
              '«Eliminar conta» e o email da conta Fleaber.\n\n'
              'Esta página pública (https://fleaber.pt/data-deletion.html) explica o '
              'processo; a acção autenticada na app/Hub é o caminho mais directo.',
        ),
        const LegalSection(
          title: 'O que acontece a seguir',
          body:
              'Verificamos a identidade de forma proporcional (conta autenticada ou '
              'elementos suficientes no pedido por email) e procedemos ao apagamento '
              'ou anonimização dos dados pessoais da conta.\n\n'
              'A eliminação pode ser recusada temporariamente enquanto existirem '
              'obrigações activas, por exemplo:\n'
              '• encomendas ainda não concluídas, canceladas ou devolvidas\n'
              '• disputas abertas\n'
              '• directos activos\n'
              '• saldo na carteira acima de um limiar residual\n\n'
              'Resolve ou liquida essas situações e volta a pedir a eliminação.\n\n'
              'Em pedidos por email, respondemos em regra no prazo de um mês '
              '(prorrogável nos termos do RGPD).',
        ),
        const LegalSection(
          title: 'Dados que podem ter de ser conservados',
          body:
              'Mesmo após a eliminação da conta, podemos conservar o estritamente '
              'necessário para obrigações legais e legítimas, pelos prazos da Política '
              'de Privacidade, nomeadamente:\n'
              '• facturação e obrigações fiscais\n'
              '• disputas e prevenção de fraude\n'
              '• registos necessários a reclamações ou autoridade competente\n\n'
              'Dados já partilhados com transportadoras (DPD), Stripe ou Meta podem '
              'continuar sob as políticas desses responsáveis — podes também exercer '
              'direitos directamente junto deles.\n\n'
              'Detalhes: https://fleaber.pt/privacy.html',
        ),
        LegalSection(
          title: 'Contacto',
          body: _contacts,
          linkLabel: 'Enviar email a legal@fleaber.pt',
          linkUrl: 'mailto:$legalEmail',
        ),
      ];

  /// FAQ única (público H18 + Perfil) — temas na ordem do produto.
  /// Secções com body vazio = cabeçalho de tema (não expansível).
  static List<LegalSection> get faq => [
        const LegalSection(title: 'Conta e perfil', body: ''),
        const LegalSection(
          title: 'O que é a Fleaber?',
          body:
              'A Fleaber é uma plataforma de compra e venda em Portugal: marketplace, '
              'directos, reservas, chat, pagamentos e acompanhamento de encomendas. '
              'O FleaHub é a vitrine pública dos vendedores (loja, gravados e informação).',
        ),
        const LegalSection(
          title: 'A Fleaber já está lançada comercialmente?',
          body:
              'Estamos em fase de testes e preparação. A app e o FleaHub estão '
              'disponíveis para validação em Portugal. Novidades sobre lojas oficiais '
              '(App Store / Google Play) e abertura comercial são anunciadas em '
              'fleaber.pt e nos canais oficiais — não tratamos a plataforma como '
              'lançamento comercial aberto a todos os clientes.',
        ),
        const LegalSection(
          title: 'Como elimino a minha conta?',
          body:
              'Perfil → Definições de conta → Eliminar conta (escreve «ELIMINAR CONTA»). '
              'Ou email a geral@fleaber.pt / legal@fleaber.pt. Pode ser necessário '
              'liquidar encomendas, disputas, directos ou saldo pendentes. '
              'Instruções públicas: https://fleaber.pt/data-deletion.html',
        ),
        const LegalSection(
          title: 'Os meus dados estão seguros?',
          body:
              'Tratamos dados em conformidade com o RGPD. Pagamentos protegidos são '
              'processados pela Stripe; não guardamos números completos de cartão. '
              'Consulta a Política de Privacidade.',
        ),
        const LegalSection(title: 'Comprar', body: ''),
        const LegalSection(
          title: 'Como descubro artigos e directos?',
          body:
              'Na Home vês directos activos, recomendações e o marketplace. No FleaHub '
              'de cada vendedor podes ver a loja e, quando existirem, gravações. '
              'Segue vendedores para acompanhar a actividade deles.',
        ),
        const LegalSection(
          title: 'O que é o saco?',
          body:
              'O saco reúne reservas e artigos que queres concluir na compra '
              '(incluindo em contexto de directo). Aí confirmas quantidades e seguis '
              'para o checkout, quando aplicável.',
        ),
        const LegalSection(
          title: 'O que são propostas de preço?',
          body:
              'O comprador pode propor um valor; o vendedor aceita, recusa ou '
              'contra-propõe. As propostas têm prazo de resposta (48 horas se não '
              'forem respondidas).',
        ),
        const LegalSection(
          title: 'O que são conjuntos?',
          body:
              'O vendedor pode agrupar artigos com desconto (por exemplo 2, 3 ou 5 '
              'peças). Vês o total e podes comprar ou negociar no chat.',
        ),
        const LegalSection(title: 'Vender', body: ''),
        const LegalSection(
          title: 'Quanto custa vender na Fleaber?',
          body:
              'Registo gratuito. A Fleaber não cobra comissões, taxas de plataforma '
              'nem mensalidades aos vendedores. Custos externos (processamento de '
              'pagamentos Stripe, portes DPD, etc.) são à parte, quando existirem.',
        ),
        const LegalSection(
          title: 'Particular ou profissional?',
          body:
              'Por defeito és tratado como particular. Se vendes no âmbito de uma '
              'actividade comercial, declara-te em Definições → Dados profissionais. '
              'O distintivo público só aparece após aprovação. A identificação '
              'obrigatória ao comprador (checkout) usa o estatuto verificado, não '
              'apenas o distintivo. Detalhes nos Termos.',
        ),
        const LegalSection(
          title: 'O que é o modo de férias?',
          body:
              'Nas definições, o vendedor pode activar o modo de férias: anúncios e '
              'directos ficam ocultos e não há compras nem propostas novas. '
              'Conversas e encomendas em curso continuam.',
        ),
        const LegalSection(
          title: 'Que artigos posso vender?',
          body:
              'Artigos legais nas categorias permitidas. Proibidos: ilegal, armas, '
              'drogas, falsificações e conteúdo ofensivo.',
        ),
        const LegalSection(title: 'Reservas e conjuntos', body: ''),
        const LegalSection(
          title: 'Como funcionam as reservas?',
          body:
              'Podes reservar artigos (no marketplace ou durante um directo). A '
              'reserva fica registada com estado e prazo definidos pelo vendedor. '
              'Conclui a compra a partir do saco ou do fluxo indicado na app.',
        ),
        const LegalSection(
          title: 'Posso usar a Fleaber só com Facebook Live?',
          body:
              'Alguns vendedores usam Facebook Live em paralelo. O ideal é transmitir '
              'na Fleaber para reservas e protecção integradas. Há ferramentas de '
              'leitura de comentários Meta para ajudar a captar reservas — a '
              'integração continua a evoluir. Ver Política de Privacidade (Meta).',
        ),
        const LegalSection(title: 'Pagamentos e protecção', body: ''),
        const LegalSection(
          title: 'Como funcionam os pagamentos?',
          body:
              'Com Seguro Fleaber (Stripe na app), o pagamento fica retido '
              'operacionalmente até ao fluxo da encomenda; o vendedor vê o saldo na '
              'carteira conforme as regras de libertação. Se o vendedor activar '
              'pagamento directo (por exemplo MB WAY ou transferência indicados '
              'pelo vendedor), o valor não fica retido pela Fleaber e a Protecção '
              'Fleaber dessa compra não se aplica.\n\n'
              'O MB WAY processado via Stripe no checkout da plataforma ainda não '
              'está activo. Levantamentos do vendedor: Stripe Connect após KYC.',
        ),
        const LegalSection(
          title: 'O que é a Protecção Fleaber?',
          body:
              'Nas compras com Seguro Fleaber, o comprador paga 0,65 € + 5% sobre '
              '(artigo + portes). Em caso de problema, podes abrir disputa na '
              'encomenda nas 48 horas após marcares como entregue, sem prejuízo de '
              'direitos legais. Ver «Comprar com segurança» e Reembolsos.',
        ),
        const LegalSection(
          title: 'Gorjetas nos directos',
          body:
              'São opcionais e separadas da compra de artigos. Aplicam-se taxas de '
              'processamento de pagamento do fluxo Fleaber (actualmente 2,9% + 0,40 €).',
        ),
        const LegalSection(title: 'Envios e encomendas', body: ''),
        const LegalSection(
          title: 'Como funcionam os envios?',
          body:
              'A transportadora integrada referenciada é a DPD. Os custos, quando '
              'aplicáveis, aparecem no checkout. Também pode existir entrega em mão, '
              'quando o vendedor a oferecer. A responsabilidade pelo envio é do '
              'vendedor, salvo regras de disputa aplicáveis.',
        ),
        const LegalSection(
          title: 'Como acompanho a encomenda?',
          body:
              'Em Perfil → Encomendas e Compras (e no chat da compra) vês o estado, '
              'podes confirmar recepção e, se aplicável, deixar avaliação.',
        ),
        const LegalSection(title: 'Problemas, disputas e apoio', body: ''),
        const LegalSection(
          title: 'Como abro uma disputa?',
          body:
              'Na encomenda, dentro de 48 h após marcar como entregue (prazo '
              'contratual da Protecção Fleaber, sem prejuízo de direitos legais). '
              'Descreve o problema e anexa provas. O pagamento protegido fica '
              'suspenso até resolução.',
        ),
        LegalSection(
          title: 'Como contacto o suporte?',
          body: _contacts,
          linkLabel: 'Enviar email a geral@fleaber.pt',
          linkUrl: 'mailto:$supportEmail',
        ),
      ];

  /// H15 textual (fallback LegalDocument). UI canónica = HowItWorksBody (4 passos).
  static List<LegalSection> get howItWorks => [
        const LegalSection(
          title: 'Descobre',
          body: 'Explora vendedores, diretos, gravações e artigos.',
        ),
        const LegalSection(
          title: 'Reserva',
          body:
              'Escolhe os artigos que queres e acompanha o estado das tuas reservas.',
        ),
        const LegalSection(
          title: 'O teu saco',
          body:
              'Consulta os artigos que reservaste e reúne as tuas compras no mesmo '
              'sítio.',
        ),
        const LegalSection(
          title: 'Compra',
          body: 'Confirma os artigos e conclui a compra.',
        ),
        const LegalSection(
          title: 'Mais informação',
          body:
              'Detalhe de pagamentos e protecção: «Comprar com segurança».\n'
              'Como vender sem comissões Fleaber: «Vender na Fleaber».\n'
              'Respostas por tema: Perguntas Frequentes.',
        ),
      ];

  /// Fonte única H16.
  static List<LegalSection> get buySafe => [
        const LegalSection(
          title: 'Pagamentos na plataforma',
          body:
              'Com Seguro Fleaber, o pagamento é processado pela Stripe na app '
              '(Visa e Mastercard). O valor fica retido operacionalmente até ao '
              'fluxo da encomenda.\n\n'
              'MB WAY via Stripe no checkout da Fleaber ainda não está activo.',
        ),
        const LegalSection(
          title: 'Pagamento directo ao vendedor',
          body:
              'Se o vendedor aceitar pagamento directo (por exemplo MB WAY ou '
              'transferência indicados por ele):\n'
              '• o valor não fica retido pela Fleaber;\n'
              '• a Protecção Fleaber dessa compra não se aplica.\n\n'
              'Prefere o chat e o checkout da Fleaber. Não incentivamos pagamentos '
              'fora da aplicação.',
        ),
        const LegalSection(
          title: 'Protecção Fleaber',
          body:
              'Nas compras com Seguro Fleaber, o comprador paga 0,65 € + 5% sobre '
              '(artigo + portes) — a mesma fórmula usada no checkout.\n\n'
              'Podes abrir disputa na encomenda nas 48 horas após marcares como '
              'entregue (prazo contratual da protecção). Isto não limita direitos '
              'legais de consumidor, quando aplicáveis.\n\n'
              'Detalhes em Reembolsos e Disputas e nos Termos.',
        ),
        const LegalSection(
          title: 'Envios (transportadora)',
          body:
              'A transportadora integrada referenciada é a DPD. Os portes, quando '
              'aplicáveis, aparecem no checkout. Também pode existir entrega em mão, '
              'se o vendedor a oferecer. A Fleaber não é a transportadora; a '
              'responsabilidade pelo envio é do vendedor, salvo regras de disputa.',
        ),
        const LegalSection(
          title: 'Reservas e acompanhamento',
          body:
              'Reservas e compras aparecem em Encomendas e no chat: estado, '
              'confirmação de recepção e disputa (quando a compra for protegida).',
        ),
      ];

  /// Fonte única H17.
  static List<LegalSection> get sell => [
        const LegalSection(
          title: 'Começar a vender',
          body:
              '1. Cria conta e completa o perfil.\n'
              '2. Publica artigos (fotos, preço, estado, stock).\n'
              '3. Opcional: prepara catálogo para directos e o teu FleaHub.\n'
              '4. Gere reservas, propostas e encomendas na Conta.\n\n'
              'Verificação de email e telemóvel é recomendada.',
        ),
        const LegalSection(
          title: 'Onde podes vender',
          body:
              '• Marketplace Fleaber — anúncios na app e no Hub.\n'
              '• Directos na Arena Fleaber — tempo real com chat e reservas.\n'
              '• FleaHub — vitrine pública (loja e gravados).\n\n'
              'Alguns vendedores usam Facebook Live em paralelo; reservas e '
              'encomendas centram-se na Fleaber.',
        ),
        const LegalSection(
          title: 'Reservas, propostas e conjuntos',
          body:
              'Define políticas de reserva, responde a propostas e cria conjuntos '
              'com desconto. Tudo fica no chat e nas encomendas.',
        ),
        const LegalSection(
          title: 'Envios e recebimentos',
          body:
              'Após pagamento confirmado, o prazo de referência nos Termos é enviar '
              'em até 5 dias úteis (DPD integrado quando aplicável, ou entrega em '
              'mão). O comprador acompanha o estado; o saldo na carteira segue as '
              'regras de libertação. Para levantar fundos de compras protegidas, '
              'completa o Stripe Connect (KYC).',
        ),
        const LegalSection(
          title: 'Particular e profissional',
          body:
              'Por defeito és particular. Se actuas como profissional, declara-te em '
              'Definições → Dados profissionais.\n\n'
              'A informação legal obrigatória ao comprador (nome comercial, '
              'localidade, aviso de direitos) aparece no checkout quando és '
              'profissional verificado — não depende só do distintivo visual no '
              'perfil. O distintivo «Profissional» é público após aprovação.\n\n'
              'Para deixar de ser profissional, pede alteração à administração '
              '(não há desactivação imediata).',
        ),
        const LegalSection(
          title: 'Sem comissões Fleaber — e custos externos',
          body:
              'A Fleaber não cobra comissões, taxas de plataforma nem subscrições aos '
              'vendedores.\n\n'
              'Custos de serviços externos (processamento Stripe, portes DPD, taxas '
              'de gorjetas) são à parte — não são comissão Fleaber sobre a venda.',
        ),
      ];

  /// Fonte única H19 (texto; contactos oficiais = constantes acima).
  static List<LegalSection> get contactsInfo => [
        LegalSection(
          title: 'Entidade responsável pela plataforma',
          body:
              'Marca: Fleaber / FleaHub\n\n'
              '$_entity\n\n'
              'Estes dados identificam a empresa que explora a plataforma — não são '
              'contactos pessoais de vendedores.',
        ),
        LegalSection(
          title: 'Contactos oficiais',
          body:
              'Suporte / geral: $supportEmail\n'
              'Legal / RGPD: $legalEmail\n'
              'Telefone: $supportPhoneDisplay\n\n'
              'Livro de Reclamações Eletrónico: $livroReclamacoesUrl',
          linkLabel: 'Enviar email a geral@fleaber.pt',
          linkUrl: 'mailto:$supportEmail',
        ),
        const LegalSection(
          title: 'O que não publicamos aqui',
          body:
              'Não divulgamos telefones, emails ou moradas pessoais de vendedores. '
              'Para falar com um vendedor, usa «Contactar» / Mensagens na Fleaber.\n\n'
              'Dados profissionais sujeitos a divulgação legal aparecem no contexto '
              'da compra (checkout) ou do perfil verificado — não nesta página.',
        ),
        LegalSection(
          title: 'Documentos legais e eliminação de conta',
          body:
              'Termos, Privacidade, Cookies e Reembolsos: Informação legal (Conta) '
              'e rodapé de fleaber.pt.\n\n'
              'Eliminação de conta (página pública, sem login): $publicDataDeletionUrl\n'
              'Acção autenticada: Perfil → Definições de conta → Eliminar conta.',
          linkLabel: 'Abrir eliminação de conta',
          linkUrl: publicDataDeletionUrl,
        ),
      ];

  static List<LegalSection> get about => [
        const LegalSection(
          title: 'Fleaber — marketplace ao vivo',
          body:
              'O sítio onde os directos acontecem com pagamentos a sério.\n\n'
              'Combinamos o que as vendedoras portuguesas já fazem no Facebook Live — '
              'mostrar, reservar, conversar — com encomendas, carteira e protecção ao '
              'comprador, no espírito do Vinted.\n\n'
              'Público inicial: vendedoras e compradoras em Portugal (roupa, bijuteria, '
              'casa e mais). Particulars e profissionais podem vender; os direitos dos '
              'consumidores aplicam-se quando a lei o exigir.',
        ),
        LegalSection(
          title: 'Operador',
          body: _entity,
        ),
        LegalSection(
          title: 'Contactos',
          body: _contacts,
          linkLabel: 'Enviar email a geral@fleaber.pt',
          linkUrl: 'mailto:$supportEmail',
        ),
        LegalSection(
          title: 'Reclamações',
          body:
              'Para litígios de consumo pode usar o Livro de Reclamações eletrónico '
              'oficial. Apoio prévio: $supportEmail.',
          linkLabel: 'Abrir Livro de Reclamações',
          linkUrl: livroReclamacoesUrl,
        ),
      ];
}

class LegalSection {
  const LegalSection({
    required this.title,
    required this.body,
    this.linkLabel,
    this.linkUrl,
  });

  final String title;
  final String body;
  final String? linkLabel;
  final String? linkUrl;
}
