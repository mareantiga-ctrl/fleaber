"""Pipeline OCR + tracking de comentários."""

from __future__ import annotations

import hashlib
import logging
import re
import time
from dataclasses import dataclass, field, replace

import numpy as np

from fleaber_ps.core.config import PsConfig
from fleaber_ps.core.dedupe import DedupeStore, normalize_text
from fleaber_ps.core.ingest_client import IngestClient
from fleaber_ps.ocr.capture import CaptureRegion, ScreenCapture
from fleaber_ps.ocr.engine import ocr_image
from fleaber_ps.parser.context import LiveContext
from fleaber_ps.parser.name_validation import normalize_ocr_line, strip_ocr_artifacts
from fleaber_ps.parser.parse_pt import ParsedComment, ParseIntent, line_hash, parse_comment_line, pseudo_id
from fleaber_ps.parser.ref_extractor import extract_ref_tokens
from fleaber_ps.parser.session_identity import SessionIdentity
from fleaber_ps.llm.ollama import resolve_ambiguous

log = logging.getLogger("fleaber_ps.pipeline")

_FB_NAME_LINE = re.compile(
    r"^(?P<name>[A-Za-zÀ-ú][\w\sÀ-ú'.-]{1,40}?)\s*[-·•]\s*\d+\s*min\s*$",
    re.IGNORECASE,
)


def _merge_fb_chat_lines(raw_lines: list[str]) -> list[str]:
    """Nome numa linha + comentário na seguinte (padrão Facebook)."""
    merged: list[str] = []
    pending_name: str | None = None
    for text in raw_lines:
        text = text.strip()
        if len(text) < 2 or _is_fb_ui_noise(text):
            pending_name = None
            continue
        nm = _FB_NAME_LINE.match(text)
        if nm:
            pending_name = nm.group("name").strip()
            continue
        if pending_name:
            merged.append(f"{pending_name} {text}")
            pending_name = None
        else:
            merged.append(text)
    return merged


def _human_ingest_error(err: str, parsed: ParsedComment) -> str:
    ref = parsed.ref_slug or parsed.public_slot or "?"
    if err == "item_not_found":
        return (
            f"Artigo «{ref}» não encontrado na live — confirma REF no Studio "
            f"(ex. REF Q1) ou comenta com a ref exacta."
        )
    return err


_FB_UI_NOISE = re.compile(
    r"(gosto|responder|padr[oõ]es|comunidade|activate\s*windows|"
    r"publicar\s*um\s*coment|min\s*$|^\d+\s*min)",
    re.IGNORECASE,
)

_NON_CHAT_NOISE = re.compile(
    r"(\.(py|md|dart|ts|json|yaml|yml|ps1|sql|tsx|jsx|png|jpg|jpeg|gif|pdf)\b|"
    r"^#{1,6}\s|```|"
    r"\\Users\\|\\Desktop\\|/lib/|C:\\\\|"
    r"\b(def |class |import |function |const |return |project )\b|"
    r"live_ended|sheet aberta|fleaber-v)",
    re.IGNORECASE,
)


def _is_fb_ui_noise(text: str) -> bool:
    t = text.strip().lower()
    if _FB_UI_NOISE.search(t):
        return True
    if _NON_CHAT_NOISE.search(t):
        return True
    if t in {"gosto", "responder", "partilhar"}:
        return True
    return False


@dataclass
class PipelineStats:
    frames: int = 0
    ocr_runs: int = 0
    comments_seen: int = 0
    ingested: int = 0
    skipped_dedupe: int = 0
    needs_review: int = 0
    errors: int = 0
    last_lines: list[str] = field(default_factory=list)


class ReaderPipeline:
    def __init__(
        self,
        cfg: PsConfig,
        ctx: LiveContext | None,
        on_event: callable | None = None,
    ) -> None:
        self.cfg = cfg
        self.ctx = ctx
        self.on_event = on_event or (lambda _e, _d: None)
        self.capture = ScreenCapture(cfg.monitor_index)
        self.client = IngestClient(cfg)
        self.dedupe = DedupeStore.from_lists(
            cfg.seen_hashes,
            cfg.seen_comment_keys,
            cfg.seen_reservation_keys,
        )
        self.stats = PipelineStats()
        self._running = False
        self._last_frame_hash = ""
        self._seq = 0
        self._known_lines: dict[str, float] = {}
        self._ref_names: dict[str, str] = {}
        self._last_qty: dict[str, int] = {}
        self._identity = SessionIdentity()

    def stop(self) -> None:
        self._running = False

    def _emit(self, event: str, data: dict | None = None) -> None:
        try:
            self.on_event(event, data or {})
        except Exception:  # noqa: BLE001
            pass

    def process_frame(self) -> None:
        if not self.cfg.roi:
            return
        region = CaptureRegion.from_dict(self.cfg.roi)
        bgr = self.capture.grab_region(region)
        frame_key = hashlib.sha256(bgr.tobytes()).hexdigest()
        self.stats.frames += 1
        if frame_key == self._last_frame_hash:
            return
        self._last_frame_hash = frame_key
        self.stats.ocr_runs += 1

        ocr_result = ocr_image(bgr, self.cfg.tesseract_cmd)
        lines, ocr_conf = ocr_result.lines, ocr_result.confidence
        if not ocr_result.tesseract_ok:
            self._emit("error", {"message": "Tesseract OCR em falta — instala e reinicia."})
            return
        self.stats.last_lines = [ln.text for ln in lines]
        now = time.time()
        chat_lines = _merge_fb_chat_lines([ln.text for ln in lines])

        for text in chat_lines:
            raw_text = text.strip()
            text = normalize_ocr_line(raw_text)
            if len(text) < 2:
                continue
            if _is_fb_ui_noise(text):
                continue
            lh = line_hash(normalize_text(text))
            if self.dedupe.is_duplicate_line(lh):
                self.stats.skipped_dedupe += 1
                continue

            norm = normalize_text(text)
            if norm in self._known_lines and now - self._known_lines[norm] < 8.0:
                continue
            self._known_lines[norm] = now

            parsed = parse_comment_line(text, self.ctx)

            # «tira N REF» claro → reduzir localmente; não deixar a IA pôr qty=N absoluta
            ref_pre = (parsed.ref_slug or str(parsed.public_slot or "")) if parsed else ""
            if parsed and parsed.reason == "reduce_delta" and ref_pre:
                ref_key = ref_pre.upper()
                prev = self._last_qty.get(ref_key)
                if prev and prev > 0:
                    parsed = replace(
                        parsed,
                        quantity=max(1, prev - parsed.quantity),
                        reason="reduce_qty",
                        parser_confidence=0.9,
                    )
                    self._emit("llm", {"parsed": text, "reason": "tira_local", "result": f"qty={parsed.quantity}"})
                else:
                    self._emit("skipped", {"parsed": text, "reason": "reduce_no_prev"})
                    continue
            elif self._should_validate_with_llm(raw_text, text, parsed, ocr_conf):
                llm_reason = self._llm_trigger_reason(raw_text, text, parsed, ocr_conf)
                llm_parsed = self._try_ollama_parse(text)
                if llm_parsed is not None:
                    parsed = self._merge_llm_with_rules(parsed, llm_parsed)
                    self._emit(
                        "llm",
                        {"parsed": text, "reason": llm_reason, "result": llm_parsed.raw_line},
                    )
                elif llm_reason:
                    self._emit(
                        "llm_miss",
                        {"parsed": text, "reason": llm_reason},
                    )
            if parsed is None:
                continue

            parsed = self._identity.apply(parsed)

            ref_part_pre = parsed.ref_slug or str(parsed.public_slot or "")
            if parsed.reason == "reduce_delta" and ref_part_pre:
                ref_key = ref_part_pre.upper()
                prev = self._last_qty.get(ref_key)
                if prev and prev > 0:
                    parsed = replace(
                        parsed,
                        quantity=max(1, prev - parsed.quantity),
                        reason="reduce_qty",
                    )
                else:
                    self._emit("skipped", {"parsed": parsed.raw_line, "reason": "reduce_no_prev"})
                    continue

            if self._skip_stale_supersede(parsed):
                self.stats.skipped_dedupe += 1
                self._emit(
                    "skipped",
                    {"parsed": parsed.raw_line, "reason": "releitura_antiga"},
                )
                continue

            self.stats.comments_seen += 1
            self._handle_parsed(parsed, ocr_conf, lh, norm)

        # Limpar linhas antigas
        cutoff = now - 120
        self._known_lines = {k: v for k, v in self._known_lines.items() if v > cutoff}

    def _extract_ref_hint(self, text: str, parsed: ParsedComment | None) -> str | None:
        if parsed and parsed.ref_slug:
            return parsed.ref_slug.upper()
        refs = extract_ref_tokens(text)
        return refs[0].upper() if refs else None

    def _looks_like_ocr_garbage(self, raw_text: str, cleaned: str) -> bool:
        raw = raw_text.strip()
        if not raw:
            return False
        if raw != cleaned and len(raw) - len(cleaned) >= 2:
            return True
        if re.search(r'^[\W\d_]{2,}', raw):
            return True
        if re.search(r'[<>=€"\(\)]', raw[:10]):
            return True
        if re.search(r'\bjanao\b', raw, re.I):
            return True
        return False

    def _llm_trigger_reason(
        self,
        raw_text: str,
        text: str,
        parsed: ParsedComment | None,
        ocr_conf: float,
    ) -> str:
        if self._looks_like_ocr_garbage(raw_text, text):
            return "ocr_lixo"
        if ocr_conf < 0.72:
            return "ocr_baixa"
        if parsed is None:
            return "sem_parse"
        if parsed.reason in {"reduce_no_prev", "no_ref", "ambiguous_local", "no_identity"}:
            return parsed.reason or "ambiguo"
        if parsed.needs_review:
            return "needs_review"
        ref = parsed.ref_slug or str(parsed.public_slot or "")
        if (
            parsed.intent == ParseIntent.RESERVE
            and ref
            and self._is_qty_regression(parsed)
        ):
            return "qty_regressao"
        if (
            parsed.intent == ParseIntent.CANCEL
            and parsed.quantity > 1
            and re.search(r"\bn[aã]o\s+quero\b", text, re.I)
        ):
            return "cancel_qty_estranha"
        if (
            not parsed.ref_slug
            and parsed.public_slot is None
            and self._identity.has_prior_context()
        ):
            return "continuidade_sem_ref"
        return "continuidade"

    def _is_qty_regression(self, parsed: ParsedComment) -> bool:
        if parsed.reason in {"reduce_delta", "reduce_qty"}:
            return False
        ref = parsed.ref_slug or str(parsed.public_slot or "")
        if not ref:
            return False
        prev = self._last_qty.get(ref.upper())
        if not prev:
            return False
        return parsed.quantity < prev

    def _skip_stale_supersede(self, parsed: ParsedComment) -> bool:
        """Bloqueia re-leituras OCR que fazem supersede «para trás»."""
        if parsed.intent != ParseIntent.RESERVE:
            return False
        if parsed.reason in {"reduce_delta", "reduce_qty"}:
            return False
        ref = parsed.ref_slug or str(parsed.public_slot or "")
        if not ref:
            return False
        prev = self._last_qty.get(ref.upper())
        if not prev or parsed.quantity >= prev:
            return False
        if re.search(r"\b(afinal|so|só|tira|retira)\b", parsed.raw_line, re.I):
            return False
        return True

    def _should_validate_with_llm(
        self,
        raw_text: str,
        text: str,
        parsed: ParsedComment | None,
        ocr_conf: float,
    ) -> bool:
        if not self.cfg.ollama_enabled or not self.ctx:
            return False
        # Continuidade: comprador já activo → quase sempre confirmar com IA
        if self._identity.has_prior_context() and re.search(
            r"\b(afinal|so|só|apenas|tira|retira|ja|já|nao|não|quero|cancela|desisto)\b",
            text,
            re.I,
        ):
            return True
        name = self._identity.last_valid_name
        ref = self._extract_ref_hint(text, parsed)
        if name and ref and self._identity.buyer_touched_ref(name, ref):
            return True
        if self._looks_like_ocr_garbage(raw_text, text):
            return True
        if ocr_conf < 0.72:
            return True
        if parsed is None:
            return self._identity.has_prior_context()
        if parsed.needs_review or parsed.reason in {
            "reduce_no_prev",
            "no_ref",
            "ambiguous_local",
            "no_identity",
            "qty_only_supersede",
            "continuity_last_ref",
            "reduce_delta",
            "reduce_qty",
        }:
            return True
        if self._is_qty_regression(parsed):
            return True
        if parsed.intent == ParseIntent.CANCEL:
            return True
        return False

    def _should_use_continuity_llm(self, text: str, parsed: ParsedComment | None) -> bool:
        """Mantido por compat; a lógica vive em _should_validate_with_llm."""
        return self._should_validate_with_llm(text, text, parsed, 1.0)

    @staticmethod
    def _merge_llm_with_rules(
        rules: ParsedComment | None,
        llm: ParsedComment,
    ) -> ParsedComment:
        # Pedimos IA de propósito → resultado da IA prevalece.
        if rules is None:
            return llm
        return replace(
            llm,
            display_name=rules.display_name or llm.display_name,
        )

    def _try_ollama_parse(self, text: str) -> ParsedComment | None:
        llm = resolve_ambiguous(
            text,
            self.ctx,
            base_url=self.cfg.ollama_url,
            model=self.cfg.ollama_model,
        )
        if not llm:
            return None
        intent_raw = str(llm.get("intent", "")).lower()
        if intent_raw not in {"reserve", "cancel"}:
            return None
        ref = llm.get("ref_slug")
        slot = llm.get("public_slot")
        qty = int(llm.get("quantity") or 1)
        return ParsedComment(
            intent=ParseIntent.CANCEL if intent_raw == "cancel" else ParseIntent.RESERVE,
            display_name=None,
            ref_slug=str(ref).strip() if ref else None,
            public_slot=int(slot) if slot else None,
            title_hint=None,
            quantity=max(1, min(qty, 99)),
            parser_confidence=float(llm.get("confidence") or 0.72),
            raw_line=text,
            needs_review=bool(llm.get("needs_review", False)),
            reason="ollama",
        )

    def _handle_parsed(
        self,
        parsed: ParsedComment,
        ocr_conf: float,
        lh: str,
        norm: str,
    ) -> None:
        ref_part = parsed.ref_slug or str(parsed.public_slot or "")
        if parsed.display_name and ref_part:
            self._ref_names[ref_part.upper()] = parsed.display_name

        identity_name = (
            parsed.display_name
            or self._identity.last_valid_name
            or self._ref_names.get(ref_part.upper())
        )
        if identity_name and not parsed.display_name:
            parsed = replace(parsed, display_name=identity_name)

        if not parsed.display_name:
            parsed = replace(parsed, needs_review=True, reason=parsed.reason or "no_identity")

        name = parsed.display_name or f"anon:{lh[:8]}"
        actor = pseudo_id(self.cfg.live_id, "ocr", name)
        ckey = self.dedupe.comment_key(actor, norm, ref_part)

        if self.dedupe.is_duplicate_comment(ckey):
            self.stats.skipped_dedupe += 1
            return
        if self.dedupe.is_repeat_reservation(actor, norm):
            self.stats.skipped_dedupe += 1
            return

        identity_conf = 0.88 if parsed.display_name else 0.45
        self._seq += 1
        result = self.client.ingest_parsed(
            parsed,
            ocr_confidence=ocr_conf,
            identity_confidence=identity_conf,
            chat_sequence=self._seq,
        )

        if result.get("ok"):
            self.dedupe.register(lh, ckey, actor, norm)
            if ref_part:
                rq = int(result.get("requested_qty") or parsed.quantity or 1)
                self._last_qty[ref_part.upper()] = max(1, rq)
            if parsed.display_name and ref_part:
                self._identity.register_touch(parsed.display_name, ref_part)
            hashes, keys, _ = self.dedupe.to_persist()
            self.cfg.seen_hashes = hashes
            self.cfg.seen_comment_keys = keys
            self.cfg.save()
            action = result.get("action", "created")
            if action == "cancelled":
                self._emit("cancel", {"parsed": parsed.raw_line, "result": result})
            elif action == "superseded":
                self.stats.ingested += 1
                self._emit(
                    "supersede",
                    {"parsed": parsed.raw_line, "result": result},
                )
            elif action in ("cancel_noop",):
                self._emit("noop", {"parsed": parsed.raw_line, "result": result})
            else:
                self.stats.ingested += 1
                if result.get("ingest_status") == "needs_review":
                    self.stats.needs_review += 1
                self._emit("ingest", {"parsed": parsed.raw_line, "result": result})
        else:
            self.stats.errors += 1
            err = result.get("error", "ingest_failed")
            self._emit(
                "error",
                {
                    "parsed": parsed.raw_line,
                    "result": result,
                    "message": _human_ingest_error(err, parsed),
                },
            )

    def run_loop(self) -> None:
        self._running = True
        self._emit("started", {})
        hb_t = 0.0
        while self._running:
            try:
                self.process_frame()
                now = time.time()
                if now - hb_t > 15:
                    self.client.heartbeat(roi_ok=bool(self.cfg.roi))
                    self.client.flush_offline_queue()
                    hb_t = now
            except Exception as exc:  # noqa: BLE001
                self.stats.errors += 1
                log.exception("pipeline error")
                self._emit("error", {"message": str(exc)})
            time.sleep(self.cfg.poll_interval_ms / 1000.0)
        self.client.heartbeat(status="stopped")
        self._emit("stopped", {})

    def test_ocr_once(self):
        if not self.cfg.roi:
            from fleaber_ps.ocr.engine import OcrResult
            return OcrResult([], 0.0, False, None, "no_roi")
        region = CaptureRegion.from_dict(self.cfg.roi)
        bgr = self.capture.grab_region(region)
        return ocr_image(bgr, self.cfg.tesseract_cmd)
