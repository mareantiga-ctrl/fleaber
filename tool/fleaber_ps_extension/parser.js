/** Parser PT v2 — espelha fleaber_ps/parser (refs, qty, cancel, nomes). */

const NOT_DISPLAY_NAMES = new Set([
  "afinal", "so", "só", "ja", "já", "nao", "não", "quero", "queria", "cancela",
  "cancelar", "desisto", "facebook", "cliente", "comprador", "responder", "gosto",
  "partilhar", "reserva", "reservo", "apenas", "corrigo", "mudo", "py", "ocr",
  "ref", "refs", "saco", "live", "directo", "direto", "mintira", "min",
  // Lixo UI Face que às vezes cola ao nome (Liked by / View N replies)
  "liked", "view", "someone", "replies", "reply", "more",
  // Resíduo OCR/DOM («Ana Silva in Liked by…» / «Ana Silvia in so quero»)
  "in",
  // Início de frase colado ao nome («Mariana Soares pa eu quero…»)
  "pa", "pra", "para", "eu", "mim", "oi", "ola", "olá", "hey", "boas", "alo", "alô",
]);

const RESERVE_VERBS =
  /\b(quero|queria|kero|ker|qero|reservo|reserva|fico com|fico|fica com|fica|leva|lewa|pego|pega|mete|adiciona|saco|para mim|manda|mandar|fecha|bota|poie|p[oó]e|txiga|corrigo|troca|muda|dame|da-me|d[aá]-?me|meve)\b/i;
const CANCEL =
  /\b(cancela|cancelar|desisto|n[aã]o\s+(?:quero|kero|ker|qero)|nao\s+(?:quero|kero)|ja\s+n[aã]o\s+(?:quero|kero|ker|qero)|j[aá]\s+n[aã]o\s+(?:quero|kero|ker|qero)|tira(?:\s+me)?|retira(?:\s+me)?|anula)\b/i;
const SUPERSEDE_PREFIX = /^(?:afinal|so|só|apenas|corrigo|mudo|enganei|errei|troca|muda|na\s+verdade)\b/i;
const QTY_ONLY_SUPERSEDE =
  /\b(?:afinal|apenas|na\s+verdade|corrigo|troca\s+pra|muda\s+pra|troca\s+para|muda\s+para).{0,28}\b(?:quero|queria|kero|ker|qero)?\s*(\d{1,2})\b(?!\s*(?:ref\s*)?[a-z]{1,4}\d)/i;
const QTY_ONLY_SO_KERO =
  /\b(?:so|só)\s+(?:kero|ker|qero)\s+(\d{1,2})\b(?!\s*(?:ref\s*)?[a-z]{1,4}\d)/i;
const QTY_ONLY_SO_QUERO_HI =
  /\b(?:so|só)\s+quero\s+(\d{1,2})\b(?!\s*(?:ref\s*)?[a-z]{1,4}\d)/i;
const TROCA_MUDA_QTY =
  /\b(?:troca|muda)\s+(?:pra|para)\s+(\d{1,2})\b(?!\s*(?:ref\s*)?[a-z]{1,4}\d)/i;
const REF_PATTERN =
  /(?:REF-[0-9a-f]{8}-[0-9a-f-]+\/\d+|#(?:REF[-_]?)?[A-Z0-9]+(?:[/_-][A-Z0-9]+)+|REF[\s_-]+[A-Z]{1,4}\d{1,4}(?:\/\d+)?|[A-Z]{1,4}\d{1,4}(?:\/\d+)?|\d{2,}[/_-]\d+)/gi;
const SHORTHAND = /^(?:ref\s*)?([A-Za-z]{1,4}\d{1,4}|\d{2,}\/\d+)$/i;
const OCR_PREFIX = /^\([A-Za-z0-9]{1,5}\)\s*/;
const LEADING_JUNK = /^[\s"'*+\-€=(<>\[\]/\\;0-9]+/;
const MERGED_TIRA = /\b(tira|retira)(\d{1,2})\b/gi;
const MERGED_JA_NAO = /\bjanao\b/gi;
const MERGED_INQUERO = /\binquero\b/gi;
const MERGED_INAFINAL = /\binafinal\b/gi;
const MERGED_INTIRA = /\bintira(\d{1,2})?\b/gi;
const MERGED_MIN_TIRA = /(\d+)\s*min\s*(tira|retira)/gi;
const REDUCE_QTY =
  /\b(?:tira|retira)(?:\s+|(?=\d))(?:me\s*)?(\d{1,2})\s+(?:ref\s*)?[A-Za-z]{1,4}\d{1,4}\b/i;
const REDUCE_ALT =
  /\b(?:bota\s+menos|diminui|baixa)(?:\s*)?(\d{1,2})\s+(?:ref\s*)?[A-Za-z]{1,4}\d{1,4}\b/i;
/** «o mesmo», «tambem», «mais um» → continuidade (último artigo do comprador). */
const CONTEXT_ECHO =
  /^(?:o\s+mesmo|a\s+mesma|igual(?:\s+(?:ao|à)\s+anterior)?|igualzinho|mesminho|tamb[eé]m|mais\s+um[a]?|esse(?:\s+a[ií])?|essa(?:\s+mesma)?|aquele|aquela|o\s+outro|a\s+outra|o\s+de\s+cima|o\s+[uú]ltimo|idem|dito|repete|de\s+novo|pode\s+ser(?:\s+o\s+mesmo)?|fechou|fechado|combinado(?:\s+o\s+mesmo)?|isso\s+a[ií]|esse\s+mesmo|bora(?:\s+o\s+mesmo)?|manda\s+ver(?:\s+o\s+mesmo)?|mete\s+o\s+mesmo|bota\s+o\s+mesmo|fica\s+esse|leva\s+esse|lewa\s+esse|kero\s+o\s+mesmo|ker\s+o\s+mesmo|qero\s+o\s+mesmo)$/i;
const NAME_LIKE = /^[A-Za-zÀ-ú][a-zà-ú'`.-]*(?:\s+[A-Za-zÀ-ú][a-zà-ú'`.-]+)+$/;
const REF_LIKE_NAME = /^[a-z0-9]{1,4}$|^[a-z]\d{1,2}$/i;
const RESERVE_VERB_WORDS = new Set([
  "quero", "queria", "kero", "ker", "qero", "reservo", "reserva", "fico", "leva", "lewa", "pego", "pega",
  "mete", "adiciona", "afinal", "so", "só", "ja", "já", "apenas", "corrigo", "mudo",
  "manda", "fecha", "bota", "poie", "poe", "põe", "txiga", "troca", "muda", "dame", "meve", "mandar",
]);

function stripOcrArtifacts(text) {
  let t = text.trim();
  // REF com dígito do lado errado (typo Face): «3 3ccc» → «3 ccc3»
  t = t.replace(/\b(\d{1,2})\s+(\d)([A-Za-z]{2,4})\b/g, "$1 $3$2");
  // «3ccc» / «3rrr» sozinho → «ccc3» / «rrr3» (sem qty; qty=1 no parse)
  t = t.replace(/\b(\d{1,2})(ccc|rrr)\b/gi, (_, dig, letters) => `${letters}${dig}`);
  for (let i = 0; i < 3; i += 1) {
    t = t.replace(OCR_PREFIX, "").trim();
    // Não comer qty de «5 ccc3» / «2 AM4»
    if (/^\d{1,2}\s+(?:ref\s*)?[A-Za-z]{1,4}\d{1,4}\b/i.test(t)) break;
    t = t.replace(LEADING_JUNK, "").trim();
  }
  return t;
}

/** Verbos / refs onde o lixo Face deve PARAR (não consumir o pedido). */
const FACE_JUNK_STOP =
  "(?:quero|queria|kero|ker|qero|reservo|reserva|manda|mandar|dame|fico|fica|pega|meve|txiga|o\\s+mesmo|a\\s+mesma|so\\s+|só\\s+|ja\\s+|já\\s+|afinal|tira|cancela|retira|[A-Za-z]{1,4}\\d)";

function stripFaceUiJunk(text) {
  let t = String(text || "");
  // Liked by / Gostou / Reagiu — parar antes do pedido (nunca só em dígito)
  t = t.replace(
    new RegExp(
      `\\b(?:Liked by|Loved by|Reacted by|Gostou|Reagiu)\\b.*?(?=\\s*${FACE_JUNK_STOP}|$)`,
      "gi",
    ),
    " ",
  );
  t = t.replace(/\bView\s+\d+\s+more\s+replies?\s+/gi, " ");
  t = t.replace(/\bView\s+\d+\s+replies?\s+/gi, " ");
  t = t.replace(/\bSee\s+translation\b/gi, " ");
  t = t.replace(/\bVer\s+tradu[cç][aã]o\b/gi, " ");
  t = t.replace(/\bTranslate\s+to\s+\w+\b/gi, " ");
  t = t.replace(/\bWrite\s+a\s+comment[.…]*\b/gi, " ");
  t = t.replace(/\bEscreve(?:r)?\s+um\s+coment[aá]rio[.…]*\b/gi, " ");
  t = t.replace(/\bSend\s+a\s+message[.…]*\b/gi, " ");
  t = t.replace(/\bPinned\s+(?:comment|by\s+[^\s]+)\b/gi, " ");
  t = t.replace(/\bComent[aá]rio\s+fixado\b/gi, " ");
  t = t.replace(/\bMost\s+relevant\b/gi, " ");
  t = t.replace(/\bAll\s+comments\b/gi, " ");
  t = t.replace(/\bTop\s+fan\b/gi, " ");
  t = t.replace(/\bHost\b(?=\s)/gi, " ");
  t = t.replace(/\bModerator\b(?=\s)/gi, " ");
  t = t.replace(/\bFollowing\b(?=\s)/gi, " ");
  t = t.replace(/\bA\s+seguir\b(?=\s)/gi, " ");
  t = t.replace(/\bReply\s+to\s+[A-Za-zÀ-ú][\wÀ-ú'.-]*/gi, " ");
  t = t.replace(/\bResposta\s+a\s+[A-Za-zÀ-ú][\wÀ-ú'.-]*/gi, " ");
  t = t.replace(/\bReplying\s+to\s+[A-Za-zÀ-ú][\wÀ-ú'.-]*(?:\s+[A-Za-zÀ-ú][\wÀ-ú'.-]*)?/gi, " ");
  t = t.replace(/\bReagiu\s+com\s+[❤🔥▶👍😂😮😢😡]+\s*/giu, " ");
  // Emoji a meio (após o nome): «Ana 🔥 quero»
  t = t.replace(/\s+[❤🔥▶👍😂😮😢😡]+\s+/gu, " ");
  t = t.replace(/\s+·\s+/g, " ");
  t = t.replace(/\bSponsored\b/gi, " ");
  t = t.replace(/\bShop now\b/gi, " ");
  t = t.replace(/\bSuggested for you\b/gi, " ");
  t = t.replace(/\bPeople you may know\b/gi, " ");
  t = t.replace(/\bFrom (?:your )?watch party\b/gi, " ");
  t = t.replace(/\bFrom Reels\b/gi, " ");
  t = t.replace(/\bWatching now\b/gi, " ");
  t = t.replace(/\bLive now\b/gi, " ");
  t = t.replace(/\bJoin the live\b/gi, " ");
  t = t.replace(/\bYou'?re live\b/gi, " ");
  t = t.replace(/\bTap to unmute\b/gi, " ");
  t = t.replace(/\bSend a sticker\b/gi, " ");
  t = t.replace(/\bSee who reacted\b/gi, " ");
  t = t.replace(/\bPeople reacted\b/gi, " ");
  t = t.replace(/\b\d+\s+people watching\b/gi, " ");
  t = t.replace(/\bMentioned you\b/gi, " ");
  t = t.replace(/\bTag a friend\b/gi, " ");
  t = t.replace(/\bInvite to watch\b/gi, " ");
  t = t.replace(/\bGo live with\b/gi, " ");
  t = t.replace(/\bSuperfan\b/gi, " ");
  t = t.replace(/\bRising creator\b/gi, " ");
  t = t.replace(/\bVerified\b(?=\s)/gi, " ");
  t = t.replace(/\bFollow\b(?=\s)/gi, " ");
  t = t.replace(/\bMessage\b(?=\s)/gi, " ");
  t = t.replace(/\bView story\b/gi, " ");
  t = t.replace(/\bAdd friend\b/gi, " ");
  t = t.replace(/\bCo-?host\b/gi, " ");
  t = t.replace(/\bGuest\b(?=\s)/gi, " ");
  t = t.replace(/\bNewest\b(?=\s)/gi, " ");
  t = t.replace(/\bFailed to send\b/gi, " ");
  t = t.replace(/\bSending[.…]*\b/gi, " ");
  t = t.replace(/\bA publicar[.…]*\b/gi, " ");
  t = t.replace(/\bBlock\b(?=\s)/gi, " ");
  t = t.replace(/\bRestrict\b(?=\s)/gi, " ");
  t = t.replace(/\bHide comment\b/gi, " ");
  t = t.replace(/\bTranslated from\s+\w+\b/gi, " ");
  t = t.replace(/\bSee translation\b/gi, " ");
  t = t.replace(/\bOriginal\b(?=\s)/gi, " ");
  t = t.replace(/\bNew follower\b/gi, " ");
  t = t.replace(/\bJoined\b(?=\s)/gi, " ");
  t = t.replace(/\bHide\b(?=\s)/gi, " ");
  t = t.replace(/\bReport\b(?=\s)/gi, " ");
  t = t.replace(/\bDenunciar\b(?=\s)/gi, " ");
  t = t.replace(/\bSay something[.…]*\b/gi, " ");
  t = t.replace(/\bEdited\b(?=\s)/gi, " ");
  t = t.replace(/\bEditado\b(?=\s)/gi, " ");
  t = t.replace(/\bShow original\b/gi, " ");
  t = t.replace(/\bSee original\b/gi, " ");
  t = t.replace(/\bLive video\b/gi, " ");
  t = t.replace(/\bPinned by host\b/gi, " ");
  t = t.replace(/\bModerator removed a comment\b/gi, " ");
  t = t.replace(/\b\d+\s*gostos?\b/gi, " ");
  t = t.replace(/\bShared\s+(?:a\s+)?(?:post|live|video)\b/gi, " ");
  t = t.replace(/\bPartilhou\s+(?:uma?\s+)?(?:publica[cç][aã]o|live|v[ií]deo)\b/gi, " ");
  t = t.replace(/\b\d+\s*(?:likes?|gostos?|reactions?|rea[cç][oõ]es?)\b/gi, " ");
  t = t.replace(/\b(?:Just\s+now|Agora\s+mesmo|Agora)\b/gi, " ");
  t = t.replace(/\b\d+[smhd]\b(?=\s|$)/gi, " "); // 2m 5h Face compact
  // Idade Face (PT/EN) — «1 min», «2 min», «1 h», «11 h», «3 hours» (nunca quantidade do pedido)
  t = t.replace(/\b\d+\s*min(?:utos?)?\b/gi, " ");
  t = t.replace(/\b\d+\s*h(?:oras?)?\b/gi, " ");
  t = t.replace(/\b\d+\s*(?:hours?|hrs?|minutes?|mins?|secs?|seconds?|days?)\b/gi, " ");
  t = t.replace(/\b\d+\s*seg(?:undos?)?\b/gi, " ");
  t = t.replace(/\b\d+\s*dias?\b/gi, " ");
  // REF colado à idade: «rrr41 min» / «FX21 h»
  t = t.replace(
    /\b([A-Za-z]{1,4}\d{1,3})(\d{1,2})\s*(min(?:utos?)?|h(?:oras?)?|m|s|seg(?:undos?)?|hrs?|hours?|minutes?)\b/gi,
    "$1",
  );
  t = t.replace(/\s*·\s*/g, " ");
  t = t.replace(new RegExp(`\\s+\\bin\\s+(?=(?:liked\\b|view\\b|loved\\b|reacted\\b|o\\s+mesmo\\b|a\\s+mesma\\b|so\\s+|só\\s+|quero\\b|manda\\b|dame\\b|ja\\s+|já\\s+|afinal\\b|tira\\b))`, "gi"), " ");
  return t;
}

function normalizeOcrLine(text) {
  let t = stripOcrArtifacts(text.replace(/\s+/g, " ").trim());
  // Lixo UI Facebook colado ao comentário (início OU a meio, após o nome)
  t = t.replace(/\s*A publicar[.…]*$/i, "");
  t = t.replace(/\s*Responder$/i, "");
  t = stripFaceUiJunk(t);
  t = t.replace(/^[❤🔥▶👍😂😮😢😡>'"«»]+/gu, "").trim();


  // Aspas em qualquer sítio (Face: 'so quero 3')
  t = t.replace(/['"`«»]/g, "");
  t = t.replace(/^["'«»]+|["'«»]+$/g, "").trim();
  // «· 1 min» / «·1min» / «1min» no início ou fim (UI Face)
  t = t.replace(/^\s*·?\s*\d+\s*min\.?\s*/i, "");
  t = t.replace(/\s*·?\s*\d+\s*min\.?\s*$/i, "");
  t = t.replace(MERGED_MIN_TIRA, "$1 min $2");
  t = t.replace(MERGED_JA_NAO, "ja nao");
  t = t.replace(/\binjanao\b/gi, "ja nao");
  t = t.replace(/\bincancela\b/gi, "cancela");
  // Nome colado a typo/cancel: «Soarescacela» → «Soares cacela» antes do mapa typo
  t = t.replace(
    /([A-Za-zÀ-ú])(cacela|cancela|quero|queria|kero|ker|qero|reservo)\b/gi,
    "$1 $2",
  );
  // Apelido colado a filler PT: «Soarespa eu» → «Soares pa eu»
  t = t.replace(
    /\b([A-ZÀ-Ú][a-zà-ú]{2,20})(para|pra|pa|eu|mim)\b/g,
    "$1 $2",
  );
  // «Soares5 ccc5» → «Soares 5 ccc5»; «Soaresccc3» → «Soares ccc3»
  t = t.replace(/\b([A-ZÀ-Ú][a-zà-ú]{2,20})(\d{1,3})\b/g, (full, name, dig) => {
    if (/^[A-Z]{1,4}\d{1,4}$/i.test(full)) return full;
    // Só peels prefixos de REF conhecidos (ccc/rrr), não sílabas de nomes (es, ar…)
    const peel = name.match(/^(.*[a-zà-ú])((?:ccc|rrr))$/i);
    if (peel && peel[1].length >= 3) {
      return `${peel[1]} ${peel[2]}${dig}`;
    }
    return `${name} ${dig}`;
  });
  // Typo frequente PT: «cacela» → cancela (determinístico; não passa pelo LLM)
  t = t.replace(/\bcacela\b/gi, "cancela");
  t = t.replace(/\binso\b/gi, "so");
  t = t.replace(MERGED_INQUERO, "quero");
  t = t.replace(MERGED_INAFINAL, "afinal");
  t = t.replace(MERGED_INTIRA, (_, n) => (n ? `tira ${n}` : "tira"));
  // Nome colado ao verbo (2.ª passagem após normalizações)
  t = t.replace(/([A-Za-zÀ-ú])(quero|queria|kero|ker|qero|cancela|reservo)\b/gi, "$1 $2");
  t = t.replace(MERGED_TIRA, "$1 $2");
  // «tira me3» / «retira me1» → «tira me 3»
  t = t.replace(/\b(tira|retira)\s*me(\d{1,2})\b/gi, "$1 me $2");
  t = t.replace(/\b(bota\s+menos|diminui|baixa)(\d{1,2})\b/gi, "$1 $2");
  t = t.replace(/\b(\d+)\s*min(?=[a-zà-ú])/gi, "$1 min ");
  // «me vê» / «da-me» / «pode mandar» normalizados para extractQty
  // (não usar \\b no fim — ê não é \\w e o boundary falha)
  t = t.replace(/\bme\s+v[eê](?=\s|$|[0-9])/gi, "meve");
  t = t.replace(/\bd[aá]-?\s*me(?=\s|$|[0-9])/gi, "dame");
  t = t.replace(/\bpode\s+mandar\b/gi, "mandar");
  // frases de desambiguação «X nao Y» → pedido de X
  t = t.replace(/\b(camisola\s+azul)\s+n[aã]o\s+as\s+calcas\b/gi, "quero $1");
  t = t.replace(/\bn[aã]o\s+as\s+calcas\s+a\s+(camisola\s+azul(?:\s+m)?)\b/gi, "quero $1");
  t = t.replace(/\bquero\s+camisola\s+n[aã]o\s+calcas\b/gi, "quero camisola azul m");
  t = t.replace(/\b(adidas)\s+n[aã]o\s+nike\b/gi, "quero $1");
  t = t.replace(/\b(nike)\s+n[aã]o\s+adidas\b/gi, "quero $1");
  // «azul m antiga» → hint vintage
  t = t.replace(/\bazul\s+m\s+antiga\b/gi, "azul m vintage");
  t = t.replace(/\bantiga\s+azul\s+m\b/gi, "azul m vintage");
  // «quero1AM2» / «quero5FX1» colado
  t = t.replace(
    /\b(quero|queria|kero|ker|qero|inquero)\s*(\d{1,2})\s*([A-Za-z]{1,4}\d{1,4})\b/gi,
    "$1 $2 $3",
  );
  t = t.replace(/\b(quero|kero|qero)\s*([A-Za-z]{1,4}\d{1,4})\b/gi, "$1 $2");
  return t.trim();
}

function isPlausibleDisplayName(name) {
  if (!name) return false;
  const raw = stripOcrArtifacts(name.trim());
  if (raw.length < 3) return false;
  const norm = raw.toLowerCase();
  const words = norm.split(/\s+/);
  if (words.some((w) => NOT_DISPLAY_NAMES.has(w))) return false;
  if (words.some((w) => RESERVE_VERB_WORDS.has(w))) return false;
  if (NOT_DISPLAY_NAMES.has(norm)) return false;
  const first = words[0];
  if (NOT_DISPLAY_NAMES.has(first)) return false;
  if (REF_LIKE_NAME.test(norm)) return false;
  if (NAME_LIKE.test(raw)) return true;
  if (norm.length >= 6 && /^[a-zà-ú\s'.-]+$/i.test(norm)) return true;
  return false;
}

function isValidRefToken(token) {
  const t = token.trim().toLowerCase();
  if (t.length < 2) return false;
  if (/^(?:tira|retira)\d+$/.test(t)) return false;
  // Truncado tipo REF-9 (uuid mal cortado)
  if (/^ref-\d{1,4}$/.test(t)) return false;
  if (/^ref$/.test(t)) return false;
  return /\d/.test(t);
}

/**
 * Strict rígido: só conta código com a palavra REF à frente
 * («REF AM4», «REF-AM4», «ref am4»). Bare «AM4» NÃO conta.
 */
function extractWordRefs(text) {
  const found = [];
  for (const m of String(text || "").matchAll(
    /\bREF[\s_-]+([A-Za-z]{1,4}\d{1,4}(?:\/\d+)?)\b/gi,
  )) {
    const token = normalizeRefToken(m[1]);
    if (token && isValidRefToken(token) && !found.includes(token)) found.push(token);
  }
  return found;
}

/** Conta ocorrências REF+código (inclui o mesmo código repetido). */
function countWordRefTokens(text) {
  let n = 0;
  for (const m of String(text || "").matchAll(
    /\bREF[\s_-]+([A-Za-z]{1,4}\d{1,4}(?:\/\d+)?)\b/gi,
  )) {
    const token = normalizeRefToken(m[1]);
    if (token && isValidRefToken(token)) n += 1;
  }
  return n;
}

function extractRefs(text) {
  const found = [];
  for (const m of text.matchAll(REF_PATTERN)) {
    const token = normalizeRefToken(m[0]);
    if (token && isValidRefToken(token) && !found.includes(token)) found.push(token);
  }
  const sm = text.trim().match(SHORTHAND);
  if (sm) {
    const token = normalizeRefToken(sm[1]);
    if (token && isValidRefToken(token) && !found.includes(token)) found.push(token);
  }
  return found;
}

/** Conta ocorrências de REF (inclui o mesmo código repetido). */
function countRefTokens(text) {
  let n = 0;
  for (const m of String(text || "").matchAll(REF_PATTERN)) {
    const token = normalizeRefToken(m[0]);
    if (token && isValidRefToken(token)) n += 1;
  }
  return n;
}

/**
 * «REF AM4» / «REF-AM4» / «#AM4» → AM4.
 * Não tocar em refs longas tipo REF-<uuid>/16.
 */
function normalizeRefToken(token) {
  let t = String(token || "").trim();
  if (!t) return "";
  t = t.replace(/^#/, "");
  // UUID-style live refs
  if (/^REF-[0-9a-f]{8}-/i.test(t)) return t;
  // Palavra REF + código curto (AM4, MV1, KK2…)
  const short = t.match(/^REF[\s_-]+([A-Z]{1,4}\d{1,4}(?:\/\d+)?)$/i);
  if (short) return short[1].toUpperCase();
  return t;
}

function isQtyOnlySupersede(text) {
  if (extractRefs(text).length > 0) return false;
  const lower = text.toLowerCase();
  const hasAfinal = /\b(?:afinal|apenas|na\s+verdade|corrigo)\b/.test(lower);
  // «so quero 3» SEM afinal → slot (não qty). Com afinal → qty.
  if (!hasAfinal) {
    const soQuero = lower.match(/\b(?:so|só)\s+(?:quero|kero|ker|qero)\s+(\d{1,2})\b/);
    if (soQuero) {
      const n = parseInt(soQuero[1], 10);
      if (n >= 1 && n <= 3) return false;
    }
  }
  if (TROCA_MUDA_QTY.test(lower)) return true;
  if (QTY_ONLY_SO_KERO.test(lower)) return true;
  if (QTY_ONLY_SUPERSEDE.test(lower)) return true;
  const soQueroHi = lower.match(QTY_ONLY_SO_QUERO_HI);
  if (soQueroHi) {
    const n = parseInt(soQueroHi[1], 10);
    if (n >= 6) return true;
    if (hasAfinal) return true;
  }
  return false;
}

const ORDINAL_SLOT = {
  primeiro: 1,
  primeira: 1,
  "1º": 1,
  "1ª": 1,
  segundo: 2,
  segunda: 2,
  "2º": 2,
  "2ª": 2,
  terceiro: 3,
  terceira: 3,
  "3º": 3,
  "3ª": 3,
  quarto: 4,
  quarta: 4,
};

/** Slot: «quero o 2», «o primeiro», «só o 3», dígito solto — nunca «quero 2 RF1» (qty). */
function extractSlot(text) {
  if (extractRefs(text).length > 0) return null;
  if (isQtyOnlySupersede(text)) return null;
  const lower = text.toLowerCase();

  let m = lower.match(/\b(?:o|a)\s+(primeir[oa]|segund[oa]|terceir[oa]|quart[oa])\b/);
  if (m && ORDINAL_SLOT[m[1]]) return ORDINAL_SLOT[m[1]];

  for (const [word, num] of Object.entries(ORDINAL_SLOT)) {
    if (lower.includes(word)) return num;
  }

  m = lower.match(
    /\b(?:quero|queria|kero|ker|qero|reservo|reserva|fico com|so|só|apenas|fica|fecha|mete|bota|pega|pego|leva)\s+(?:o|a|os|as)\s+(?:n[úu]mero\s+|nº\s+|#\s*)?(\d{1,3})\b/,
  );
  if (m) {
    const n = parseInt(m[1], 10);
    return n >= 1 && n <= 999 ? n : null;
  }

  // «so qero o 3» / «qero o 1»
  m = lower.match(/\b(?:so|só)\s+(?:quero|kero|ker|qero)\s+o\s+(\d{1,3})\b/);
  if (m && !/\b(?:afinal|apenas|na\s+verdade|corrigo)\b/.test(lower)) {
    const n = parseInt(m[1], 10);
    if (n >= 1 && n <= 3) return n;
  }
  m = lower.match(/\b(?:quero|kero|ker|qero)\s+o\s+(\d{1,3})\b/);
  if (m) {
    const n = parseInt(m[1], 10);
    return n >= 1 && n <= 999 ? n : null;
  }

  // «so quero 3» sem afinal → slot 1–3; «so quero 5+» = qty
  m = lower.match(/\b(?:so|só)\s+quero\s+(\d{1,3})\b/);
  if (m && !/\b(?:afinal|apenas|na\s+verdade|corrigo)\b/.test(lower)) {
    const n = parseInt(m[1], 10);
    if (n >= 1 && n <= 3) return n;
  }
  // OCR: so kero/qero 3 ≈ so quero 3 (slot)
  m = lower.match(/\b(?:so|só)\s+(?:kero|ker|qero)\s+(\d{1,3})\b/);
  if (m && !/\b(?:afinal|apenas|na\s+verdade|corrigo)\b/.test(lower)) {
    const n = parseInt(m[1], 10);
    if (n >= 1 && n <= 3) return n;
  }
  m = lower.match(/\b(?:bota|mete|pega|pego|leva|fecha)\s+(\d{1,3})\b(?!\s*(?:ref\s*)?[a-z])/);
  if (m) {
    const n = parseInt(m[1], 10);
    if (n >= 1 && n <= 3) return n;
  }

  m = lower.match(/\b(?:n[úu]mero|nº|#)\s*(\d{1,3})\b/);
  if (m) {
    const n = parseInt(m[1], 10);
    return n >= 1 && n <= 999 ? n : null;
  }

  m = lower.match(/\b(?:fica|fecha)\s+(?:n[úu]mero\s+)?(\d{1,3})\b/);
  if (m) {
    const n = parseInt(m[1], 10);
    return n >= 1 && n <= 999 ? n : null;
  }

  m = lower.match(/\bquero\s+o\s+(primeir[oa]|segund[oa]|terceir[oa]|quart[oa])\b/);
  if (m && ORDINAL_SLOT[m[1]]) return ORDINAL_SLOT[m[1]];

  m = lower.trim().match(/^(\d{1,3})$/);
  if (m) {
    const n = parseInt(m[1], 10);
    return n >= 1 && n <= 999 ? n : null;
  }
  return null;
}

function buildSlotMap(catalog) {
  const map = new Map();
  if (!Array.isArray(catalog)) return map;
  catalog.forEach((it, idx) => {
    const slot = it.public_slot ?? it.slot ?? idx + 1;
    const ref = String(it.ref_code || it.ref || "")
      .trim()
      .replace(/^#/, "");
    if (slot != null && ref) map.set(Number(slot), ref);
  });
  return map;
}

function normTitleText(s) {
  return String(s || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ç/g, "c")
    .replace(/\bcalcas\b/g, "calcas")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Desambiguação por título/alias do catálogo (Nike Azul M vs Adidas Azul M vs Calças…).
 * Usado quando o comentário não traz ref tipo HS1.
 */
function matchCatalogByTitle(text, catalog) {
  if (!text || !catalog?.length) return null;
  const line = normTitleText(text);
  // se já há ref explícita do catálogo, não adivinhar por título
  for (const it of catalog) {
    const ref = String(it.ref_code || it.ref || "")
      .trim()
      .replace(/^#/, "");
    if (ref && new RegExp(`\\b${ref}\\b`, "i").test(text)) return null;
  }

  const WEIGHT = {
    adidas: 14,
    nike: 10,
    calcas: 14,
    camisola: 7,
    preta: 12,
    preto: 12,
    azul: 6,
    branca: 10,
    branco: 10,
    vintage: 16,
    antiga: 14,
    antigo: 14,
    m: 8,
    l: 8,
    xl: 9,
    s: 7,
  };

  let best = null;
  for (const it of catalog) {
    const ref = String(it.ref_code || it.ref || "")
      .trim()
      .replace(/^#/, "");
    const title = normTitleText(it.title || it.name || "");
    const aliases = (it.aliases || []).map(normTitleText);
    const hay = [title, ...aliases].filter(Boolean).join(" ");
    if (!hay) continue;

    const tokens = hay.split(/[^a-z0-9]+/).filter((t) => t.length >= 1);
    let score = 0;
    const matched = [];
    for (const tok of tokens) {
      const w = WEIGHT[tok] || (tok.length >= 4 ? 3 : 0);
      if (!w) continue;
      // tamanho: palavra isolada (evita «me» em «dame»)
      const re =
        tok.length <= 2
          ? new RegExp(`(?:^|[^a-z0-9])${tok}(?:[^a-z0-9]|$)`)
          : new RegExp(`\\b${tok}\\b`);
      if (re.test(line)) {
        score += w;
        matched.push(tok);
      }
    }
    // bónus se frase contém substring longa do título (≥ 10 chars)
    for (const chunk of [title, ...aliases]) {
      if (chunk.length >= 10 && line.includes(chunk)) score += 20;
      else if (chunk.length >= 6 && line.includes(chunk)) score += 10;
    }
    // penalizar se linha diz calcas mas item é camisola (e vice-versa)
    if (/\bcalcas\b/.test(line) && /\bcamisola\b/.test(hay) && !/\bcalcas\b/.test(hay)) {
      score -= 15;
    }
    if (/\bcamisola\b/.test(line) && /\bcalcas\b/.test(hay) && !/\bcamisola\b/.test(hay)) {
      score -= 15;
    }
    if (/\badidas\b/.test(line) && !/\badidas\b/.test(hay)) score -= 12;
    if (/\bnike\b/.test(line) && !/\bnike\b/.test(hay) && !/\badidas\b/.test(line)) score -= 8;
    if (/\bpreta?\b/.test(line) && !/\bpret[ao]\b/.test(hay)) score -= 10;
    if (/\bazul\b/.test(line) && !/\bazul\b/.test(hay)) score -= 6;
    // «vintage» / «antiga» — só quando pedido; senão penalizar item vintage
    if (/\b(vintage|antiga|antigo)\b/.test(line) && !/\b(vintage|antiga|antigo)\b/.test(hay)) {
      score -= 18;
    }
    if (/\b(vintage|antiga|antigo)\b/.test(line) && /\b(vintage|antiga|antigo)\b/.test(hay)) {
      score += 22;
    }
    if (!/\b(vintage|antiga|antigo)\b/.test(line) && /\b(vintage|antiga|antigo)\b/.test(hay)) {
      score -= 20;
    }
    // «camisola nao calcas» / «nao as calcas»
    if (/\bn[aã]o\s+(?:as\s+)?calcas\b/.test(line) || /\bcamisola\s+n[aã]o\s+calcas\b/.test(line)) {
      if (/\bcalcas\b/.test(hay)) score -= 25;
      if (/\bcamisola\b/.test(hay)) score += 12;
    }

    if (!best || score > best.score) {
      best = { ref, score, matched, title: it.title || title };
    }
  }
  if (!best || best.score < 10) return null;
  return best;
}

/** Converte slot público → ref_slug do catálogo emparelhado (AM1, KK2, 004/21, REF-… — o que o live tiver). */
function resolveSlotToRef(parsed, catalog) {
  if (!parsed || !catalog?.length) return parsed;
  const slotMap = buildSlotMap(catalog);
  let out = { ...parsed };

  if (out.publicSlot != null) {
    const ref = slotMap.get(Number(out.publicSlot));
    if (ref) {
      out = {
        ...out,
        refSlug: ref,
        publicSlot: null,
        parserConfidence: Math.max(out.parserConfidence || 0.7, 0.88),
        reason: out.reason || "slot_resolved",
      };
    }
  }

  // «quero 2» sem letra → se o slug ficou só o número do slot, mapear para a ref do live
  if (out.refSlug && /^\d{1,3}$/.test(String(out.refSlug).trim())) {
    const ref = slotMap.get(Number(out.refSlug));
    if (ref) {
      out = { ...out, refSlug: ref, publicSlot: null, reason: out.reason || "slot_resolved" };
    }
  }

  // Títulos semelhantes: «quero nike azul m» → HS1
  // Só quando NÃO há ref explícita do catálogo; pode corrigir continuidade errada
  const catalogRefs = new Set(
    catalog
      .map((it) =>
        String(it.ref_code || it.ref || "")
          .toUpperCase()
          .replace(/^#/, ""),
      )
      .filter(Boolean),
  );
  const explicit = extractRefs(out.rawLine || "").some((r) =>
    catalogRefs.has(String(r).toUpperCase().replace(/^#/, "")),
  );
  if (!explicit) {
    const hit = matchCatalogByTitle(out.rawLine || "", catalog);
    if (hit && hit.ref) {
      const cur = out.refSlug
        ? String(out.refSlug).toUpperCase().replace(/^#/, "")
        : "";
      const titleBeatsContinuity =
        !cur ||
        out.reason === "continuity_last_ref" ||
        out.reason === "title_resolved" ||
        hit.score >= 16;
      if (titleBeatsContinuity) {
        out = {
          ...out,
          refSlug: hit.ref,
          publicSlot: null,
          parserConfidence: Math.max(out.parserConfidence || 0.7, 0.86),
          reason: "title_resolved",
          needsReview: hit.score < 18,
        };
      }
    }
  }
  return out;
}

function extractQty(text) {
  const lower = text.toLowerCase();
  // «troca pra 6 CM3» / «corrigo para 4 CM1»
  let m = lower.match(
    /\b(?:troca|muda)\s+(?:pra|para)\s+(\d{1,2})\s+(?:ref\s*)?[a-z]{1,4}\d{1,4}\b/,
  );
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  m = lower.match(/\bcorrigo\s+(?:para|pra)\s+(\d{1,2})\s+(?:ref\s*)?[a-z]{1,4}\d{1,4}\b/);
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  // «quero 3 CM1» / «meve 4 CM2» / «dame 2 CM3» / «mandar 4 CM1»
  m = lower.match(
    /\b(?:quero|queria|kero|ker|qero|reservo|reserva|fico|afinal|so|só|apenas|manda|mandar|pega|pego|mete|bota|leva|lewa|fecha|poie|p[oó]e|meve|dame|txiga|corrigo|troca|muda)\s+(\d{1,2})\s+(?:ref\s*)?[a-z]{1,4}\d{1,4}\b/,
  );
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  // Qty + ref só com verbo de reserva («quero 5 T10») — sem verbo → extractQty não inventa
  if (RESERVE_VERBS.test(lower)) {
    m = lower.match(/\b(\d{1,2})\s+(?:ref\s*)?([a-z]{1,4}\d{1,4})\b/);
    if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  }
  if (extractSlot(text) != null && !/\b\d{1,2}\s+(?:ref\s*)?[a-z0-9/\-]{1,12}\b/i.test(text)) {
    if (!/\b(unidades?|pcs?|peças?)\b/.test(lower)) return 1;
  }
  // «quero 5 a preta m» / «dame 2 adidas azul» — qty antes de texto (sem ref)
  m = lower.match(
    /\b(?:quero|queria|kero|ker|qero|reservo|reserva|manda|mandar|pega|pego|mete|bota|leva|meve|dame|txiga|fica|fico)\s+(\d{1,2})\s+(?:a|o|as|os|da|de|do)?\s*[a-zà-ú]/,
  );
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  m = lower.match(/\b(\d{1,2})\s*(?:unidades?|pcs?|peças?)\b/);
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  m = lower.match(TROCA_MUDA_QTY);
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  m = lower.match(/\bapenas\s+(\d{1,2})\b/);
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  // «afinal so quero 2» — dígito solto; NÃO o sufixo de REF («so … t07» ≠ qty 7)
  m = lower.match(
    /\b(?:afinal|so|só|apenas|corrigo|na\s+verdade).{0,28}(?:quero|kero|queria)?\s*(\d{1,2})\b/,
  );
  if (m) {
    const dig = m[1];
    const digAt = lower.indexOf(dig, m.index);
    const prev = digAt > 0 ? lower[digAt - 1] : " ";
    if (!/[a-zà-ú]/i.test(prev)) {
      return Math.max(1, Math.min(parseInt(dig, 10), 99));
    }
  }
  m = lower.match(/\b(?:quero|queria|kero|ker|qero|reserva|reservo)\s+(\d{1,2})\b/);
  if (m) return Math.max(1, Math.min(parseInt(m[1], 10), 99));
  if (/\b(dois|duas)\b/.test(lower)) return 2;
  if (/\b(tr[eê]s)\b/.test(lower)) return 3;
  return 1;
}

function splitNameBody(text) {
  const parts = text.split(/\s+/);
  if (parts.length < 2) return { name: null, body: text };
  const maxNameWords = Math.min(4, parts.length - 1);
  for (let n = maxNameWords; n >= 1; n -= 1) {
    const name = parts.slice(0, n).join(" ");
    const body = parts.slice(n).join(" ");
    if (!body) continue;
    const first = name.split(/\s+/)[0]?.toLowerCase() ?? "";
    if (
      isPlausibleDisplayName(name) &&
      !RESERVE_VERB_WORDS.has(first) &&
      !RESERVE_VERBS.test(name)
    ) {
      return { name, body };
    }
  }
  return { name: null, body: text };
}

function _normCatalogRef(token) {
  return String(token || "")
    .trim()
    .toUpperCase()
    .replace(/^#/, "");
}

/** Refs do catálogo emparelhado (FX1, AM4, #123 → 123) — aceites em strict sem a palavra REF. */
function catalogRefSet(catalog) {
  const out = new Set();
  if (!Array.isArray(catalog)) return out;
  for (const it of catalog) {
    const n = _normCatalogRef(it?.ref_code || it?.ref || "");
    if (n) out.add(n);
  }
  return out;
}

function _escapeRegExp(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Encontra refs do catálogo como tokens na linha (T10, 123, #123).
 * Só activo quando há catálogo — não inventa refs numéricas sem allow-list.
 */
function findBareCatalogRefsInLine(line, allowed) {
  if (!allowed || !allowed.size) return [];
  const text = String(line || "");
  const found = [];
  const refs = Array.from(allowed).sort((a, b) => b.length - a.length);
  for (const ref of refs) {
    if (!ref) continue;
    const re = new RegExp(
      `(^|[^A-Za-z0-9_])#?${_escapeRegExp(ref)}(?![A-Za-z0-9_])`,
      "i",
    );
    if (re.test(text) && !found.includes(ref)) found.push(ref);
  }
  return found;
}

/**
 * Modo REF obrigatório rígido: tem de existir a palavra REF + código
 * OU um código bare que exista no catálogo emparelhado da live.
 * «quero 1 AM4» → chat (sem catálogo). «quero 1 REF AM4» → reserva.
 * «quero 1 FX1» com FX1 no liveCatalog → reserva (Face real / live_only).
 * «quero 123» / «quero #123» com #123 ou 123 no catálogo → reserva.
 * Slots / «o mesmo» / qty-only sem REF+código e fora do catálogo → chat.
 */
function applyStrictRef(parsed, opts = {}) {
  if (!parsed) return null;
  if (parsed.intent === "chat") {
    return { ...parsed, publicSlot: null };
  }
  const line = String(parsed.rawLine || "");
  const allowed = catalogRefSet(opts.catalog);
  const wordRefs = extractWordRefs(line);
  if (!wordRefs.length) {
    const bareInCatalog = extractRefs(line)
      .map(_normCatalogRef)
      .filter((r) => r && allowed.has(r));
    for (const r of findBareCatalogRefsInLine(line, allowed)) {
      if (!bareInCatalog.includes(r)) bareInCatalog.push(r);
    }
    const want = parsed.refSlug ? _normCatalogRef(parsed.refSlug) : "";
    if (want && allowed.has(want)) {
      bareInCatalog.unshift(want);
    }
    const slug = bareInCatalog[0] || null;
    if (slug) {
      return {
        ...parsed,
        publicSlot: null,
        refSlug: slug,
        needsReview: false,
        reason: "strict_catalog_ref",
        parserConfidence: Math.max(parsed.parserConfidence || 0.7, 0.88),
      };
    }
    return {
      ...parsed,
      intent: "chat",
      refSlug: null,
      publicSlot: null,
      needsReview: false,
      reason: "strict_no_ref_word",
      parserConfidence: 0.92,
    };
  }
  const want = parsed.refSlug ? String(parsed.refSlug).trim().toUpperCase() : "";
  let slug =
    want && wordRefs.some((r) => r.toUpperCase() === want)
      ? want
      : wordRefs[0];
  const normSlug = _normCatalogRef(slug);
  // Com catálogo: REF palavra só conta se existir no directo.
  if (allowed.size > 0) {
    if (!allowed.has(normSlug)) {
      return {
        ...parsed,
        intent: "chat",
        refSlug: null,
        publicSlot: null,
        needsReview: false,
        reason: "strict_ref_not_in_catalog",
        parserConfidence: 0.92,
      };
    }
    slug = normSlug;
  }
  return {
    ...parsed,
    publicSlot: null,
    refSlug: slug,
    reason:
      parsed.reason && parsed.reason !== "strict_no_ref"
        ? parsed.reason
        : parsed.reason || "strict_ref_word",
  };
}

function parseCommentLine(text, opts = {}) {
  const strict = !!opts.strictRef;
  const raw = parseCommentLineCore(text);
  if (!raw) return null;
  return strict ? applyStrictRef(raw, opts) : raw;
}

function parseCommentLineCore(text) {
  const line = normalizeOcrLine(text);
  if (!line) return null;
  if (line.length < 2 && !/^\d{1,3}$/.test(line)) return null;

  const jaNaoRefM = line.match(
    /\bja\s+n[aã]o\s+(?:(?:quero|kero|ker|qero|q(?:ue)?ro)\s+)?(?:ref\s*)?([A-Za-z]{1,4}\d{1,4})\b/i,
  );
  if (jaNaoRefM) {
    const { name, body } = splitNameBody(line);
    return {
      intent: "cancel",
      displayName: name,
      refSlug: jaNaoRefM[1],
      publicSlot: null,
      quantity: 1,
      rawLine: line,
      parserConfidence: 0.86,
    };
  }

  const reduceM = line.match(REDUCE_QTY) || line.match(REDUCE_ALT);
  if (reduceM) {
    const { name, body } = splitNameBody(line);
    const work = body || line;
    const refs = extractRefs(work);
    return {
      intent: "reserve",
      displayName: name,
      refSlug: refs[0] || null,
      publicSlot: refs.length ? null : extractSlot(work),
      quantity: Math.max(1, Math.min(parseInt(reduceM[1], 10), 99)),
      rawLine: line,
      parserConfidence: refs.length ? 0.84 : 0.68,
      needsReview: !refs.length,
      reason: "reduce_delta",
    };
  }

  // «o mesmo» / «tambem» sozinhos — NÃO «quero RF3 tambem»
  {
    const echoTail =
      /\b(o\s+mesmo|a\s+mesma|igual(?:\s+(?:ao|à)\s+anterior)?|igualzinho|mesminho|tamb[eé]m|mais\s+um[a]?|mais\s+dois|mais\s+2|mais\s+duas|e\s+mais\s+um(?:\s+desse)?|outro|essa|esse(?:\s+a[ií])?|essa(?:\s+mesma)?|aquele|aquela|o\s+outro|a\s+outra|o\s+de\s+cima|o\s+[uú]ltimo|idem|dito|repete|de\s+novo|pode\s+ser(?:\s+o\s+mesmo)?|fechou|fechado|isso\s+a[ií]|esse\s+mesmo|mete\s+o\s+mesmo|bota\s+o\s+mesmo|fica\s+esse|leva\s+esse|lewa\s+esse|me\s+p[oó]e\s+o\s+mesmo|kero\s+o\s+mesmo|ker\s+o\s+mesmo|qero\s+o\s+mesmo)\s*$/i;
    const em = line.match(echoTail);
    if (em) {
      const before = line.slice(0, em.index).trim();
      const beforeHasRef = extractRefs(before).length > 0;
      const beforeHasVerb = RESERVE_VERBS.test(before) || CANCEL.test(before);
      if (!beforeHasRef && !beforeHasVerb) {
        let name = null;
        if (before) {
          if (isPlausibleDisplayName(before)) {
            name = before;
          } else {
            const split = splitNameBody(`${before} .`);
            name = split.name;
          }
        }
        return {
          intent: "reserve",
          displayName: name,
          refSlug: null,
          publicSlot: null,
          quantity: 1,
          rawLine: line,
          parserConfidence: 0.55,
          needsReview: true,
          reason: "context_echo",
        };
      }
    }
  }

  const isExplicitCancel =
    /\b(j[aá]\s+n[aã]o\s+quero|n[aã]o\s+quero|nao\s+quero|cancela|desisto|tira|retira|anula)\b/i.test(
      line,
    );
  const isCancel =
    CANCEL.test(line) &&
    !(SUPERSEDE_PREFIX.test(line) && RESERVE_VERBS.test(line) && !isExplicitCancel);

  if (isCancel) {
    const { name, body } = splitNameBody(line);
    const work = body || line;
    const refs = extractRefs(work);
    return {
      intent: "cancel",
      displayName: name,
      refSlug: refs[0] || null,
      publicSlot: refs.length ? null : extractSlot(work),
      quantity: 1,
      rawLine: line,
      parserConfidence: refs.length ? 0.82 : 0.68,
    };
  }

  const { name, body } = splitNameBody(line);
  const work = body || line;
  const refs = extractRefs(work);
  const hasVerb = RESERVE_VERBS.test(work);
  const shorthandOnly = SHORTHAND.test(work.trim());
  const qtyOnly = isQtyOnlySupersede(work) || isQtyOnlySupersede(line);
  const slot = refs.length || qtyOnly ? null : extractSlot(work);

  if (!hasVerb && refs.length === 0 && !shorthandOnly && slot == null && !qtyOnly) {
    // Só adivinhar título se há palavras de produto (senão PARSE_NULL)
    if (!/\b(nike|adidas|camisola|calcas|calças|azul|pret[ao]|branc[oa]|m|l|xl)\b/i.test(work)) {
      return null;
    }
    return {
      intent: "reserve",
      displayName: name,
      refSlug: null,
      publicSlot: null,
      quantity: 1,
      rawLine: line,
      parserConfidence: 0.42,
      needsReview: true,
      reason: "title_guess",
    };
  }

  // Contrato Face (obrigatório): reserva só com verbo («quero T10» / «quero 5 T10»).
  // «t10», «2 t09», lixo com REF → chat (não inventar reserva).
  if (!hasVerb && !qtyOnly) {
    if (refs.length || shorthandOnly || slot != null) {
      return {
        intent: "chat",
        displayName: name,
        refSlug: null,
        publicSlot: null,
        quantity: 1,
        rawLine: line,
        parserConfidence: 0.92,
        reason: "reserve_requires_verb",
      };
    }
  }

  return {
    intent: "reserve",
    displayName: name,
    refSlug: refs[0] || (shorthandOnly ? work.trim() : null),
    publicSlot: slot,
    quantity: slot != null ? 1 : extractQty(work),
    rawLine: line,
    parserConfidence: refs.length ? 0.85 : qtyOnly ? 0.55 : slot != null ? 0.8 : 0.75,
    needsReview: qtyOnly || (!hasVerb && !refs.length && slot == null),
    reason: qtyOnly ? "qty_only_supersede" : undefined,
  };
}

class SessionIdentity {
  constructor() {
    this.lastValidName = null;
    this.lastRef = null;
    this.byRef = {};
    /** @type {Record<string, { lastRef: string|null, byRef: Record<string,string> }>} */
    this.byBuyer = {};
    /** @type {Set<string>|null} refs do catálogo live — lastRef só guarda estes */
    this.catalogRefs = null;
  }

  setCatalogRefs(refs) {
    if (!refs || !refs.length) {
      this.catalogRefs = null;
      return;
    }
    this.catalogRefs = new Set(
      refs.map((r) => String(r).toUpperCase().replace(/^#/, "")).filter(Boolean),
    );
  }

  _inCatalog(ref) {
    if (!this.catalogRefs || !this.catalogRefs.size) return true;
    return this.catalogRefs.has(String(ref || "").toUpperCase().replace(/^#/, ""));
  }

  _buyerKey(nameOrRef) {
    const s = (nameOrRef || "").trim().toLowerCase();
    if (/^fb:(\d{5,}|u:[a-z0-9._-]{3,})$/i.test(s)) return s;
    return s;
  }

  _buyerCtx(name) {
    const k = this._buyerKey(name);
    if (!k) return null;
    if (!this.byBuyer[k]) this.byBuyer[k] = { lastRef: null, byRef: {} };
    return this.byBuyer[k];
  }

  getBuyerLastRef(name) {
    const bc = this._buyerCtx(name);
    const ref = bc?.lastRef;
    if (ref && this._inCatalog(ref)) return ref;
    return null;
  }

  apply(parsed) {
    let out = { ...parsed };
    const slugKey = (out.refSlug || "").toUpperCase().replace(/^#/, "");
    // Homónimos: chave de continuidade = fb:* quando existir
    const continuityKey =
      (out.externalBuyerRef && /^fb:/i.test(out.externalBuyerRef)
        ? out.externalBuyerRef
        : null) || out.displayName;

    if (out.displayName && isPlausibleDisplayName(out.displayName)) {
      this.lastValidName = out.displayName;
      const bc = this._buyerCtx(continuityKey);
      if (bc && slugKey && this._inCatalog(slugKey)) {
        bc.byRef[slugKey] = out.displayName;
        bc.lastRef = slugKey;
      }
      if (slugKey && this._inCatalog(slugKey)) {
        this.byRef[slugKey] = out.displayName;
        this.lastRef = slugKey;
      }
    } else if (slugKey && this.byRef[slugKey]) {
      out = { ...out, displayName: this.byRef[slugKey] };
    } else if (out.displayName && !isPlausibleDisplayName(out.displayName)) {
      out = { ...out, displayName: null };
    }
    // NÃO herdar lastValidName de outro comprador (evita «bom dia» → Ana Silva).

    const buyerName = out.displayName;
    const bc = continuityKey
      ? this._buyerCtx(continuityKey)
      : buyerName
        ? this._buyerCtx(buyerName)
        : null;
    // Ref de continuidade: SÓ deste comprador (nunca lastRef global).
    let buyerLastRef = bc?.lastRef || null;
    if (buyerLastRef && !this._inCatalog(buyerLastRef)) {
      buyerLastRef = null;
    }

    if (
      out.intent === "reserve" &&
      !out.refSlug &&
      out.publicSlot == null &&
      buyerLastRef
    ) {
      out = {
        ...out,
        refSlug: buyerLastRef,
        reason: out.reason || "continuity_last_ref",
        needsReview: false,
        parserConfidence: Math.min(out.parserConfidence || 0.7, 0.78),
      };
    } else if (
      (out.reason === "qty_only_supersede" || out.reason === "context_echo") &&
      !out.refSlug &&
      out.publicSlot == null
    ) {
      out = {
        ...out,
        needsReview: true,
        reason: out.reason === "context_echo"
          ? "context_echo_sem_comprador"
          : "qty_only_sem_contexto_comprador",
      };
    }

    if (out.intent === "cancel" && !out.refSlug && buyerLastRef) {
      out = { ...out, refSlug: buyerLastRef };
    }

    if (out.refSlug && this._inCatalog(out.refSlug) && buyerName) {
      const up = String(out.refSlug).toUpperCase().replace(/^#/, "");
      this.lastRef = up;
      const b = this._buyerCtx(buyerName);
      if (b) b.lastRef = up;
    }
    return out;
  }

  hasPriorContext(displayName) {
    if (displayName) {
      const bc = this.byBuyer[this._buyerKey(displayName)];
      if (bc && (bc.lastRef || Object.keys(bc.byRef).length)) return true;
    }
    return !!(this.lastValidName || this.lastRef || Object.keys(this.byRef).length);
  }
}

function pseudoId(liveId, name) {
  const norm = (name || "Facebook").trim().toLowerCase();
  let h = 0;
  const s = `ocr|${norm}`;
  for (let i = 0; i < s.length; i += 1) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `sess:${liveId}:${h.toString(16).padStart(8, "0")}`;
}

/**
 * Identificador estável Facebook a partir da sonda DOM (auditor 2026-08-24).
 * Preferência: fb:{numeric_id} · fallback vanity: fb:u:{username} · senão null.
 */
function facebookBuyerRefFromProbe(probe) {
  if (!probe || typeof probe !== "object") return null;
  const rawId = String(probe.profile_id_guess || "").trim();
  if (/^\d{5,}$/.test(rawId)) return `fb:${rawId}`;

  const href = String(probe.profile_href || "");
  const idFromHref = href.match(/[?&]id=(\d{5,})/) || href.match(/\/profile\.php\?id=(\d{5,})/);
  if (idFromHref) return `fb:${idFromHref[1]}`;

  const people = href.match(/\/people\/[^/]+\/(\d{5,})/);
  if (people) return `fb:${people[1]}`;

  let vanity = rawId;
  if (!vanity || /^\d+$/.test(vanity)) {
    const pathM = href.match(/facebook\.com\/([A-Za-z0-9._-]{3,})(?:\/|\?|$)/i);
    vanity = pathM ? pathM[1] : "";
  }
  vanity = String(vanity || "")
    .replace(/^@/, "")
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, "");
  if (
    vanity.length >= 3 &&
    !/^(profile\.php|people|watch|reel|videos|photo|photos|pages|groups|events|login|sharer)$/i.test(
      vanity,
    )
  ) {
    return `fb:u:${vanity}`;
  }
  return null;
}

/** Preferir fb:* da sonda; senão hash de nome (legacy). */
function resolveExternalBuyerRef(liveId, displayName, authorRef) {
  const fb = String(authorRef || "").trim();
  if (/^fb:(\d{5,}|u:[A-Za-z0-9._-]{3,})$/.test(fb)) return fb;
  return pseudoId(liveId, displayName);
}

/**
 * Hash estável: normaliza o texto (tira idade Face / lixo UI) para
 * «quero rrr4» e «quero rrr4 1 h» colidirem no dedupe.
 * Preserva prefixo uid (`uid\\0texto`) quando existir.
 */
function lineHash(line) {
  let target = String(line || "");
  if (target.includes("\0")) {
    const i = target.indexOf("\0");
    const uid = target.slice(0, i);
    const body = normalizeOcrLine(target.slice(i + 1));
    target = `${uid}\0${body}`;
  } else {
    target = normalizeOcrLine(target);
  }
  let h = 0;
  for (let i = 0; i < target.length; i += 1) {
    h = (h * 31 + target.charCodeAt(i)) >>> 0;
  }
  return h.toString(16).padStart(16, "0");
}

/**
 * «quero CB1 e CB2» / «quero 2 CB1 e 3 CB2» → vários parses.
 * Mesmo REF duas vezes → última qty ganha.
 * Uma só ref → parse normal (lista de 1).
 */
function expandMultiItemParses(text, opts = {}) {
  const strict = !!opts.strictRef;
  const line = normalizeOcrLine(text);
  if (!line) return [];
  const { name, body } = splitNameBody(line);
  const work = body || line;
  const refHits = strict ? countWordRefTokens(work) : countRefTokens(work);
  const hasSep = /\be\b|,|&/i.test(work);
  // refHits conta repetições («1 REF AM1 e 3 REF AM1» = 2); extractRefs deduplica.
  if (!hasSep || refHits < 2) {
    const one = parseCommentLine(text, opts);
    return one ? [one] : [];
  }
  const parts = work
    .split(/\s*(?:,|\be\b|&)\s*/i)
    .map((s) => s.trim())
    .filter(Boolean);
  const out = [];
  for (const part of parts) {
    let chunk = part;
    if (!RESERVE_VERBS.test(chunk) && !CANCEL.test(chunk) && !SUPERSEDE_PREFIX.test(chunk)) {
      chunk = `quero ${chunk}`;
    }
    const full = name ? `${name} ${chunk}` : chunk;
    const p = parseCommentLine(full, opts);
    if (p && p.intent !== "chat" && (p.refSlug || (!strict && p.publicSlot != null))) {
      out.push({
        ...p,
        displayName: p.displayName || name,
        rawLine: line,
        reason: p.reason || "multi_item",
      });
    }
  }
  const collapsed = collapseSameRefLastWins(out);
  if (collapsed.length >= 1 && (collapsed.length >= 2 || refHits >= 2)) {
    return collapsed.length ? collapsed : [];
  }
  const one = parseCommentLine(text, opts);
  return one ? [one] : [];
}

/** Mesmo REF várias vezes na linha → fica a última quantidade. */
function collapseSameRefLastWins(list) {
  if (!list.length) return [];
  const byRef = new Map();
  const order = [];
  for (const p of list) {
    const key = String(p.refSlug || "")
      .toUpperCase()
      .replace(/^#/, "");
    if (!key) continue;
    if (!byRef.has(key)) order.push(key);
    byRef.set(key, p);
  }
  return order.map((k) => byRef.get(k)).filter(Boolean);
}

export {
  parseCommentLine,
  parseCommentLineCore,
  applyStrictRef,
  expandMultiItemParses,
  collapseSameRefLastWins,
  extractWordRefs,
  findBareCatalogRefsInLine,
  catalogRefSet,
  countWordRefTokens,
  pseudoId,
  facebookBuyerRefFromProbe,
  resolveExternalBuyerRef,
  lineHash,
  SessionIdentity,
  isPlausibleDisplayName,
  normalizeOcrLine,
  stripFaceUiJunk,
  isQtyOnlySupersede,
  resolveSlotToRef,
  matchCatalogByTitle,
  buildSlotMap,
  extractSlot,
};
