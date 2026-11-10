#!/usr/bin/env python3
"""Gera website/*.html e deploy/fleaber_pt/*.html a partir dos textos legais H11 (Out 2026)."""
from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "website", ROOT / "deploy" / "fleaber_pt"]

UPDATED = "Última atualização: Outubro 2026"

# Conteúdo alinhado a lib/legal/legal_texts.dart (revisão H11 legal).
DOCS: dict[str, dict] = {
    "privacy": {
        "file": "privacy.html",
        "title": "Política de Privacidade — Fleaber",
        "h1": "Política de Privacidade",
        "desc": "Política de Privacidade da Fleaber — RGPD, Stripe, Meta, DPD.",
        "nav_extra": "",
        "sections": [
            (
                None,
                "A Fleaber respeita a privacidade dos utilizadores e trata dados pessoais em conformidade "
                "com o Regulamento (UE) 2016/679 (RGPD) e a legislação portuguesa aplicável. Este documento "
                "aplica-se à aplicação móvel Fleaber, ao website fleaber.pt e ao FleaHub.",
            ),
            (
                "1. Responsável pelo tratamento",
                "<strong>Mare Antiga Unipessoal Lda</strong><br/>"
                "NIF: 518775364<br/>"
                "Morada: Estrada Casal da Raposeira, Casa Agostinho, 2600-817 São João dos Montes, Portugal<br/>"
                'Email: <a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a><br/>'
                'Legal / RGPD: <a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> '
                '(alternativo: <a href="mailto:mareantiga@gmail.com">mareantiga@gmail.com</a>)',
            ),
            (
                "2. Dados que recolhemos",
                "<ul>"
                "<li>Identificação: nome, email, telefone, foto de perfil, handle público</li>"
                "<li>Morada e dados de envio quando necessários para a encomenda</li>"
                "<li>Histórico de compras, vendas, reservas, propostas, gorjetas e mensagens</li>"
                "<li>Dados de pagamento processados por terceiros (Stripe; MB WAY/IBAN do vendedor quando activo) — sem números completos de cartão</li>"
                "<li>Conteúdo de lives (LiveKit/Mux) e metadados técnicos associados</li>"
                "<li>Dados técnicos: IP, dispositivo, logs, cookies/sessão e armazenamento local</li>"
                "<li>Dados do Facebook/Meta quando utiliza login ou integrações</li>"
                "</ul>",
            ),
            (
                "3. Menores de idade",
                "A Fleaber destina-se a utilizadores com 18 ou mais anos. Não recolhemos intencionalmente "
                'dados de menores. Contacte <a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> se '
                "tomar conhecimento de uma conta de menor.",
            ),
            (
                "4. Finalidades e base legal",
                "<ul>"
                "<li>Criar e gerir a conta</li>"
                "<li>Processar compras, vendas, reservas, propostas e gorjetas</li>"
                "<li>Retenção operacional de pagamentos protegidos e carteira</li>"
                "<li>Onboarding e levantamentos Stripe Connect (KYC)</li>"
                "<li>Envios com a transportadora parceira integrada (DPD), quando aplicável</li>"
                "<li>Gestão do estatuto de vendedor profissional (declaração, verificação documental e conservação proporcional dos comprovativos)</li>"
                "<li>Chat, suporte, prevenção de fraude e disputas</li>"
                "<li>Obrigações legais e melhoria proporcional do serviço</li>"
                "</ul>"
                "<p>Bases legais: execução de contrato, interesse legítimo, consentimento (quando exigido) e obrigação legal.</p>"
                "<p>Os comprovativos de identidade profissional são armazenados em espaço privado, com acesso restrito. "
                "Não são publicados no perfil nem nos anúncios. O distintivo «Profissional» só aparece após verificação "
                "adequada; a ausência de verificação não é apresentada como «profissional verificado».</p>",
            ),
            (
                "5. Facebook / Meta",
                "<p>Se iniciar sessão com Facebook ou ligar a conta Meta, recebemos identificadores e dados "
                "de perfil conforme as permissões autorizadas.</p>"
                "<p>Ferramentas de leitura de comentários de Facebook Live tratam comentários e nomes "
                "públicos apenas para reservas e mensagens na Fleaber, sob instruções do vendedor.</p>"
                '<p>Política da Meta: <a href="https://www.facebook.com/privacy/policy/" target="_blank" rel="noopener noreferrer">facebook.com/privacy/policy</a>. '
                'Eliminação: <a href="data-deletion.html">data-deletion.html</a>.</p>',
            ),
            (
                "6. Pagamentos (Stripe e pagamento directo)",
                "<p>Nas compras com Seguro Fleaber, o processamento é feito pela Stripe. A Fleaber não "
                'armazena dados completos de cartão. Ver <a href="https://stripe.com/privacy" target="_blank" rel="noopener noreferrer">stripe.com/privacy</a>.</p>'
                "<p>Pagamentos MB WAY/transferência configurados pelo vendedor não incluem a Protecção Fleaber; "
                "a Fleaber não actua como PSP nesse modo.</p>",
            ),
            (
                "7. Transportadoras (DPD)",
                "<p>A transportadora parceira referenciada para envios integrados na Fleaber é a <strong>DPD</strong>. "
                "Não disponibilizamos CTT, InPost ou GLS como serviços integrados na app.</p>"
                "<p>Quando o envio o exigir, podemos partilhar nome, morada, contactos e referência da encomenda "
                "com a DPD. A Fleaber não é transportadora; a responsabilidade pelo envio é do vendedor, "
                "salvo regras de disputa aplicáveis.</p>",
            ),
            (
                "8. Subcontratantes e partilha",
                "<ul>"
                '<li>Stripe — <a href="https://stripe.com/privacy" target="_blank" rel="noopener noreferrer">stripe.com/privacy</a></li>'
                "<li>Supabase (infraestrutura; preferência UE)</li>"
                "<li>LiveKit e Mux (streaming)</li>"
                "<li>BulkGate ou equivalente (SMS), quando usado</li>"
                "<li>Facebook / Meta</li>"
                "<li>DPD (quando o envio integrado o exigir)</li>"
                "<li>Autoridades, quando exigido por lei</li>"
                "</ul>"
                "<p><strong>Não vendemos</strong> os seus dados pessoais a terceiros.</p>",
            ),
            (
                "9. Cookies",
                'No website e no FleaHub usamos mecanismos estritamente necessários. Detalhes em '
                '<a href="cookies.html">Política de Cookies</a>.',
            ),
            (
                "10. Eliminar conta e dados",
                "<p>Na app: Perfil → Definições → Eliminar conta (confirmação «ELIMINAR CONTA»), ou por email a "
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> / '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a>. '
                'Página: <a href="data-deletion.html">data-deletion.html</a>.</p>'
                "<p>Pode haver bloqueio temporário se existirem encomendas, disputas, lives activas ou saldo "
                "na carteira. Conservação legal conforme esta política.</p>",
            ),
            (
                "11. Conservação",
                "<p>Não aplicamos um prazo único a todas as categorias. Em regra: dados de conta enquanto activa; "
                "transacções/facturação pelos prazos legais (frequentemente até 10 anos para documentação "
                "contabilística, conforme o regime aplicável); disputas e fraude pelo tempo necessário; "
                "logs de segurança por período limitado.</p>",
            ),
            (
                "12. Direitos do utilizador",
                "<ul>"
                "<li>Acesso, rectificação, apagamento, limitação, portabilidade e oposição</li>"
                "<li>Resposta em regra no prazo de um mês (RGPD)</li>"
                '<li>Reclamação à CNPD: <a href="https://www.cnpd.pt" target="_blank" rel="noopener noreferrer">www.cnpd.pt</a></li>'
                "</ul>",
            ),
            (
                "13. Segurança",
                'Medidas técnicas e organizativas adequadas. Incidentes: '
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a>.',
            ),
            (
                "14. Contacto",
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> · '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> · '
                '<a href="tel:+351937475638">+351 937 475 638</a>',
            ),
        ],
    },
    "terms": {
        "file": "terms.html",
        "title": "Termos e Condições — Fleaber",
        "h1": "Termos e Condições",
        "desc": "Termos e Condições da Fleaber — compras, Protecção Fleaber, Stripe Connect, DPD.",
        "sections": [
            (
                "1. A plataforma",
                "<p>A Fleaber é um marketplace ao vivo em Portugal. Mare Antiga Unipessoal Lda actua como "
                "intermediária tecnológica e, em regra, não é merchant of record das vendas entre utilizadores.</p>"
                "<p>Podem existir vendas C2C e B2C. Direitos legais obrigatórios dos consumidores não são "
                "afastados por regras internas da plataforma.</p>",
            ),
            (
                "2. Elegibilidade",
                "Maiores de 18 anos; conta pessoal; dados verdadeiros; possível suspensão por fraude ou violação.",
            ),
            (
                "2-A. Vendedores profissionais",
                "<p>Declaração em Definições → Dados profissionais. O distintivo público «Profissional» só aparece "
                "após aprovação (Verificado). Sem distintivo «Particular» permanente — por defeito trata-se como "
                "particular. Enquanto Por preencher / Em análise / Rejeitado, novas vendas ficam suspensas "
                "(encomendas e mensagens em curso não são canceladas). NIF e documentos privados; aprovação só "
                "pela administração Fleaber. Checkout informa estatuto e direitos (livre resolução/garantia quando "
                "aplicável a profissionais).</p>",
            ),
            (
                "3. Compras, reservas e propostas",
                "<ul>"
                "<li>Reservas em live com TTL configurável pelo vendedor (cerca de 15 min a 5 dias; omissão típica 5 dias)</li>"
                "<li>Propostas de preço com validade típica de 48 horas</li>"
                "<li>Pagamento protegido (Stripe / Seguro Fleaber) ou, se activado, MB WAY/transferência directa sem Protecção Fleaber</li>"
                "</ul>",
            ),
            (
                "4. Taxa de Protecção Fleaber",
                "<p>0,65 € + 5% sobre (artigo + portes). O vendedor não paga comissão de venda separada.</p>"
                "<p>Exemplo: 15,00 € + 3,50 € portes → base 18,50 € → taxa ≈ 1,58 €. Sem portes: 15,00 € → ≈ 1,40 €.</p>",
            ),
            (
                "5. Pagamentos e Stripe Connect",
                "<p>O valor protegido fica retido <strong>operacionalmente</strong> no ecossistema Fleaber/Stripe. "
                "Não constitui escrow bancário autónomo nem garantia financeira regulada.</p>"
                "<p>Libertação do saldo: avaliação ≥ 4★ após «concluído», ou auto-avaliação 48 h sem disputa. "
                "Levantamentos via Stripe Connect após KYC.</p>",
            ),
            (
                "6. Envio e modo de férias",
                "<ul>"
                "<li>Envio em até 5 dias úteis após pagamento confirmado</li>"
                "<li>Transportadora parceira integrada: DPD (sem CTT/InPost/GLS como opção activa)</li>"
                "<li>Modo de férias: anúncios e directos ocultos; encomendas e conversas em curso continuam</li>"
                "</ul>",
            ),
            (
                "7. Gorjetas",
                "Quando disponíveis: creditadas ao vendedor após taxas de processamento (actualmente 2,9% + 0,40 € no fluxo Fleaber).",
            ),
            (
                "8. Disputas e chargebacks",
                "Ver «Reembolsos e Disputas». Decisão interna da plataforma não impede recurso a entidades competentes. "
                "Chargebacks bancários são processos distintos.",
            ),
            (
                "9. Direitos dos consumidores",
                "<p>C2C e B2C. Em B2C à distância podem aplicar-se livre resolução e garantias legais, com excepções "
                "admitidas por lei. A Protecção Fleaber é contratual e não exclui direitos imperativos.</p>",
            ),
            (
                "10. Conteúdo proibido",
                "Ilegal, armas, drogas, falsificações, ódio, burlas, spam, manipulação de avaliações.",
            ),
            (
                "11. Limitação de responsabilidade",
                "Dentro dos limites legais; nada nestes Termos exclui dolo, culpa grave ou direitos imperativos dos consumidores.",
            ),
            (
                "12. Contacto e reclamações",
                '<p><a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> · '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> · '
                '<a href="tel:+351937475638">+351 937 475 638</a></p>'
                '<p><a href="https://www.livroreclamacoes.pt" target="_blank" rel="noopener noreferrer">Livro de Reclamações</a></p>',
            ),
        ],
    },
    "refunds": {
        "file": "refunds.html",
        "title": "Reembolsos e Disputas — Fleaber",
        "h1": "Reembolsos e Disputas",
        "desc": "Reembolsos e disputas Fleaber — Protecção Fleaber, Stripe, DPD.",
        "sections": [
            (
                "Protecção ao comprador",
                "Pagamento protegido: retenção operacional Fleaber/Stripe (não escrow bancário). "
                "Saldo do vendedor após avaliação ≥ 4★ ou auto-avaliação 48 h. Pagamento directo sem protecção.",
            ),
            (
                "Cancelamento antes do envio",
                "<p><strong>A)</strong> Protegido: reembolso Stripe automático ao aceitar cancelamento; estimativa típica até 10 dias úteis no cartão (sujeito ao banco).</p>"
                "<p><strong>B/C)</strong> Pagamento directo: a Fleaber não reverte MB WAY/transferências; combine com o vendedor.</p>",
            ),
            (
                "Após entrega",
                "Prazo contratual de 48 h para disputa Protecção Fleaber, sem prejuízo de direitos legais obrigatórios.",
            ),
            (
                "Processo de disputa",
                "Decisão interna da plataforma sobre saldo/reembolso; não impede reclamação a entidades competentes.",
            ),
            (
                "Portes e DPD",
                "Transportadora parceira integrada: DPD. Extravio/atraso: tracking + disputa quando aplicável.",
            ),
            (
                "Prazos",
                "48 h disputa contratual; 5 dias úteis envio; até 10 dias úteis estimativa reembolso cartão; 48 h propostas; TTL reservas configurável.",
            ),
            (
                "Apoio",
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> · '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> · '
                '<a href="tel:+351937475638">+351 937 475 638</a>',
            ),
        ],
    },
    "cookies": {
        "file": "cookies.html",
        "title": "Política de Cookies — Fleaber",
        "h1": "Política de Cookies",
        "desc": "Política de Cookies Fleaber — mecanismos essenciais, sem analytics de publicidade na build actual.",
        "sections": [
            (
                "O que são",
                "Cookies e tecnologias semelhantes (localStorage / SharedPreferences) para sessão, segurança e preferências essenciais.",
            ),
            (
                "Utilização actual",
                "<p>Na build web actual: apenas mecanismos estritamente necessários (autenticação, sessão, segurança, "
                "funcionamento do Hub) e a preferência local do aviso de cookies (<code>fleaber_cookie_consent_v1</code>).</p>"
                "<p>Não activamos de momento analytics, publicidade ou remarketing de terceiros. O banner informa; "
                "não pedimos consentimento artificial para categorias inexistentes. Se forem introduzidos cookies "
                "não essenciais, actualizaremos esta política e o banner.</p>",
            ),
            (
                "Gestão",
                'Pode limpar dados do site no browser. Contacto: '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> · '
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a>.',
            ),
        ],
    },
    "data_deletion": {
        "file": "data-deletion.html",
        "title": "Eliminação de conta e dados — Fleaber",
        "h1": "Eliminação de conta e dados",
        "desc": "Como eliminar a conta e os dados pessoais na Fleaber (RGPD / Meta).",
        "sections": [
            (
                None,
                "<p>Esta página pública explica como pedir a eliminação da conta e dos dados "
                "pessoais na Fleaber. Não exige login — é útil para pedidos externos "
                "(incluindo Facebook/Meta). A acção autenticada continua em "
                "Perfil → Definições de conta.</p>",
            ),
            (
                "1. Como pedir na app ou no FleaHub",
                "<ol>"
                "<li>Inicia sessão na app ou em <a href=\"fleahub/\">fleaber.pt/fleahub</a>.</li>"
                "<li>Abre <strong>Perfil → Definições de conta</strong>.</li>"
                "<li>Escolhe <strong>Eliminar conta</strong>.</li>"
                "<li>Confirma escrevendo exactamente <strong>ELIMINAR CONTA</strong>.</li>"
                "</ol>",
            ),
            (
                "2. Como pedir por email",
                "<p>Envia mensagem a "
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> ou '
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> com o assunto '
                "«Eliminar conta» e o email da conta Fleaber.</p>",
            ),
            (
                "3. O que acontece a seguir",
                "<p>Verificação proporcional de identidade; apagamento ou anonimização.</p>"
                "<p>Pode ser recusada temporariamente se houver encomendas activas, disputas, "
                "directos activos ou saldo na carteira.</p>"
                "<p>Resposta a pedidos por email em regra no prazo de um mês (RGPD).</p>",
            ),
            (
                "4. Dados que podem ter de ser conservados",
                "<p>Facturação, disputas, prevenção de fraude e obrigações fiscais — "
                'pelos prazos da <a href="privacy.html">Política de Privacidade</a>. '
                "Dados já partilhados com DPD, Stripe ou Meta podem continuar sob as "
                "políticas desses responsáveis.</p>",
            ),
            (
                "5. Contacto",
                '<a href="mailto:legal@fleaber.pt">legal@fleaber.pt</a> · '
                '<a href="mailto:geral@fleaber.pt">geral@fleaber.pt</a> · '
                '<a href="tel:+351937475638">+351 937 475 638</a>',
            ),
        ],
    },
}


def render(doc: dict) -> str:
    parts = []
    for title, body in doc["sections"]:
        if title:
            parts.append(f"      <h2>{html.escape(title)}</h2>")
        # body may contain intentional HTML
        if body.strip().startswith("<"):
            parts.append(f"      {body}")
        else:
            parts.append(f"      <p>{body}</p>")
    article = "\n\n".join(parts)
    return f"""<!DOCTYPE html>
<html lang="pt">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="description" content="{html.escape(doc['desc'])}" />
  <title>{html.escape(doc['title'])}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="css/styles.css" />
  <link rel="icon" href="assets/logo.png" type="image/png" />
</head>
<body>
  <header class="site-header">
    <div class="container inner">
      <a href="index.html" class="logo-link">
        <img src="assets/logo.png" alt="Fleaber" width="140" height="40" />
      </a>
      <button class="nav-toggle" type="button" aria-label="Menu">☰</button>
      <nav class="nav">
        <a href="index.html">Início</a>
        <a href="hub.html">FleaHub</a>
        <a href="terms.html">Termos</a>
        <a href="refunds.html">Reembolsos</a>
        <a href="cookies.html">Cookies</a>
        <a href="index.html#contacto">Contacto</a>
      </nav>
    </div>
  </header>

  <main>
    <div class="legal-hero">
      <div class="container">
        <h1>{html.escape(doc['h1'])}</h1>
        <p class="updated">{html.escape(UPDATED)}</p>
      </div>
    </div>

    <article class="legal-content container">
{article}
    </article>
  </main>

  <footer class="site-footer">
    <div class="container">
      <div class="footer-bottom">
        <p>
          <a href="index.html">← Início</a> ·
          <a href="privacy.html">Privacidade</a> ·
          <a href="terms.html">Termos</a> ·
          <a href="cookies.html">Cookies</a> ·
          <a href="data-deletion.html">Eliminar dados</a>
        </p>
        <p><a href="https://www.livroreclamacoes.pt" target="_blank" rel="noopener noreferrer">Livro de Reclamações</a></p>
        <p>© 2026 Fleaber · Mare Antiga Unipessoal Lda · NIF 518775364</p>
      </div>
    </div>
  </footer>
  <script src="js/main.js"></script>
</body>
</html>
"""


def main() -> None:
    for doc in DOCS.values():
        content = render(doc)
        for base in TARGETS:
            if not base.exists():
                continue
            path = base / doc["file"]
            path.write_text(content, encoding="utf-8", newline="\n")
            print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
