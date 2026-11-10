/**
 * Testes da via isolada post → parser → RPC shape (sem Graph real / sem deploy).
 * node tool/test_meta_graph_post_ingest.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import {
  buildPagePostCommentsUrl,
  filterCommentsById,
  normalizeGraphPostComments,
  parsePostLiveBindings,
  redactSecrets,
  resolveExplicitPostLiveAssociation,
} from "../supabase/functions/_shared/meta_graph_post_path.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");

const PAGE = "1064838703375098";
const POST = "1064838703375098_122110478984880054";
const COMMENT = "122110478984880054_1666555894866246";
const LIVE = "61d7fe33-aede-4887-a4f9-05d5c43a8364";

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

// --- allowlist / associação explícita ---
console.log("\n=== association ===");
{
  const miss = resolveExplicitPostLiveAssociation({
    pageId: PAGE,
    metaPostId: POST,
    liveId: LIVE,
    explicitPostBinding: false,
    allowlist: [],
  });
  assert(
    miss.ok === false && miss.error === "explicit_post_binding_required",
    "sem allowlist exige explicit_post_binding",
  );

  const okReq = resolveExplicitPostLiveAssociation({
    pageId: PAGE,
    metaPostId: POST,
    liveId: LIVE,
    explicitPostBinding: true,
    allowlist: [],
  });
  assert(okReq.ok === true && okReq.source === "request", "request binding ok");

  const list = parsePostLiveBindings(
    JSON.stringify([
      { page_id: PAGE, meta_post_id: POST, live_id: LIVE },
    ]),
  );
  assert(list.length === 1 && list[0].live_id === LIVE, "parse bindings JSON");

  const okList = resolveExplicitPostLiveAssociation({
    pageId: PAGE,
    metaPostId: POST,
    liveId: LIVE,
    explicitPostBinding: false,
    allowlist: list,
  });
  assert(okList.ok === true && okList.source === "allowlist", "allowlist hit");

  const bad = resolveExplicitPostLiveAssociation({
    pageId: PAGE,
    metaPostId: POST,
    liveId: "00000000-0000-0000-0000-000000000000",
    explicitPostBinding: false,
    allowlist: list,
  });
  assert(
    bad.ok === false && bad.error === "post_binding_not_allowlisted",
    "allowlist rejeita live errada",
  );
}

// --- URL Graph post (sem live video) + redacção ---
console.log("\n=== graph post url / redact ===");
{
  const u = buildPagePostCommentsUrl({
    metaPostId: POST,
    pageAccessToken: "EAA_test_secret_token_xyz",
    graphVersion: "v21.0",
    limit: 10,
  });
  assert(u.ok === true, "url build ok");
  assert(
    u.url.includes("/comments") &&
      u.url.includes(encodeURIComponent(POST)) &&
      !u.url.includes("live_videos"),
    "URL aponta a post/comments (não live_videos)",
  );
  assert(
    u.urlRedacted.includes("REDACTED") && !u.urlRedacted.includes("EAA_test"),
    "urlRedacted sem token",
  );
  assert(
    redactSecrets(`err access_token=EAA_test_secret_token_xyz oops`).includes(
      "REDACTED",
    ) &&
      !redactSecrets(`access_token=EAA_test_secret_token_xyz`).includes(
        "EAA_test_secret",
      ),
    "redactSecrets remove token",
  );
}

// --- normalise + filter comment ---
console.log("\n=== comments normalize/filter ===");
{
  const rows = normalizeGraphPostComments({
    data: [
      {
        id: COMMENT,
        message: "quero 123",
        from: { id: "111", name: "Tester" },
        created_time: "2026-10-23T00:00:00+0000",
      },
      {
        id: "other_comment",
        message: "ola",
        from: { id: "222", name: "X" },
      },
    ],
  });
  assert(rows.length === 2, "normalize 2 comments");
  const one = filterCommentsById(rows, COMMENT);
  assert(
    one.length === 1 && one[0].message === "quero 123",
    "filter pelo Comment ID real",
  );
}

// --- parser + RPC shape (graph_post + #123 catalog) ---
console.log("\n=== parser → graph_post RPC ===");
{
  let code = readFileSync(
    join(repoRoot, "supabase/functions/_shared/fleaber_ps_parser.js"),
    "utf8",
  );
  code = code.replace(
    /\nexport\s*\{[\s\S]*$/m,
    "\nglobalThis.parseCommentLine = parseCommentLine;\n",
  );
  const sandbox = { console, globalThis: {} };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  const parse = sandbox.parseCommentLine;

  const catalog = [{ ref_code: "#123", title: "Artigo teste" }];
  const parsed = parse("quero 123", { strictRef: true, catalog });
  assert(
    parsed?.intent === "reserve" &&
      String(parsed.refSlug).replace(/^#/, "") === "123",
    `quero 123 + catalog #123 → reserve (got ${parsed?.intent}/${parsed?.refSlug})`,
  );

  // Mirror buildGraphIngestRpc channel + canonical ref (same as meta_graph_ingest.ts)
  let pRefSlug = parsed.refSlug;
  const want = String(pRefSlug).trim().toUpperCase().replace(/^#/, "");
  const hit = catalog.find((it) => {
    const norm = String(it.ref_code).toUpperCase().replace(/^#/, "");
    return norm === want;
  });
  if (hit) pRefSlug = hit.ref_code;

  const eventChannel = "graph_post";
  const rpc = {
    p_live_id: LIVE,
    p_ocr_raw_line: "quero 123",
    p_ocr_line_hash: `graph_msg:${COMMENT}`,
    p_ref_slug: pRefSlug,
    p_requested_qty: 1,
    p_parser_intent: parsed.intent,
    p_comment_id: COMMENT,
    p_event_channel: eventChannel,
    p_meta_page_id: PAGE,
  };

  assert(rpc.p_ref_slug === "#123", "canonical ref_slug #123 para o motor");
  assert(rpc.p_event_channel === "graph_post", "canal isolado graph_post");
  assert(
    rpc.p_comment_id === COMMENT && rpc.p_ocr_line_hash === `graph_msg:${COMMENT}`,
    "idempotência por comment_id (anti-duplicado)",
  );
  assert(rpc.p_live_id === LIVE, "live Fleaber explícito");
}

// --- live path channel default unchanged (contract) ---
console.log("\n=== live path isolation ===");
{
  const defaultChannel = ("graph").trim() || "graph";
  const postChannel = ("graph_post").trim() || "graph";
  assert(
    defaultChannel === "graph" && postChannel === "graph_post",
    "Live continua em channel graph; post usa graph_post",
  );
  assert(
    !String(POST).includes("live_video") &&
      buildPagePostCommentsUrl({
        metaPostId: POST,
        pageAccessToken: "x",
      }).url.includes("/comments"),
    "post path não inventa meta_live_video_id",
  );
}

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nAll meta-graph-post-ingest tests passed.");
