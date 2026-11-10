#!/usr/bin/env python3
"""
Fleaber Reader — agente PS (OCR comentários Facebook → fila Fleaber).

Uso:
  python reader.py setup
  python reader.py calibrate
  python reader.py run
  python reader.py test-line "Maria quero o 3"
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import sys
import time
from typing import Any

import httpx

from config import ReaderConfig
from parser import line_hash, parse_comment_line, pseudo_id


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def ingest_line(
    cfg: ReaderConfig,
    *,
    raw_line: str,
    ref_number: int,
    display_name: str | None,
    confidence: float,
    avatar_phash: str = "manual",
    chat_sequence: int | None = None,
) -> dict[str, Any]:
    digest = line_hash(raw_line)
    if digest in (cfg.seen_hashes or []):
        return {"ok": True, "skipped": True, "reason": "local_dedupe"}

    name = display_name or "Facebook"
    external_ref = pseudo_id(cfg.live_id, avatar_phash, name)
    url = (
        f"{cfg.supabase_url}/functions/v1/ingest-ocr-reservation"
    )

    payload = {
        "live_id": cfg.live_id,
        "ref_number": ref_number,
        "external_display_name": display_name,
        "external_buyer_ref": external_ref,
        "ocr_raw_line": raw_line,
        "ocr_line_hash": digest,
        "detected_at": _now_iso(),
        "chat_sequence": chat_sequence,
        "avatar_phash": avatar_phash,
        "ingest_confidence": round(confidence, 3),
    }

    with httpx.Client(timeout=20.0) as client:
        res = client.post(
            url,
            json=payload,
            headers={
                "Content-Type": "application/json",
                "X-Device-Token": cfg.device_token,
            },
        )
        data = res.json()
        if res.status_code in (200, 409):
            cfg.remember_hash(digest)
            cfg.save()
        return {"status": res.status_code, **data}


def cmd_setup() -> None:
    print("=== Fleaber Reader — setup ===")
    supabase_url = input("Supabase URL (ex. https://xxx.supabase.co): ").strip()
    live_id = input("Live ID (UUID): ").strip()
    device_token = input("Device token (da app Fleaber): ").strip()
    device_id = input("Device ID [pc-reader-1]: ").strip() or "pc-reader-1"

    cfg = ReaderConfig(
        supabase_url=supabase_url,
        live_id=live_id,
        device_token=device_token,
        device_id=device_id,
        roi={"left": 0, "top": 0, "width": 420, "height": 720},
    )
    cfg.save()
    print(f"Guardado em {cfg.config_path()}")


def cmd_calibrate() -> None:
    try:
        import mss
    except ImportError as exc:
        raise SystemExit("pip install -r requirements.txt") from exc

    cfg = ReaderConfig.load()
    print("Calibração ROI — arrasta janela FB chat para a região visível.")
    print("Captura em 5 segundos…")
    time.sleep(5)
    with mss.mss() as sct:
        monitor = sct.monitors[1]
        shot = sct.grab(monitor)
        cfg.roi = {
            "left": monitor["left"] + 40,
            "top": monitor["top"] + 120,
            "width": min(420, monitor["width"] - 80),
            "height": min(720, monitor["height"] - 160),
        }
        cfg.save()
        out = cfg.config_dir() / "calibration_preview.png"
        mss.tools.to_png(shot.rgb, shot.size, output=str(out))
        print(f"ROI={cfg.roi} · preview={out}")


def _ocr_roi_text(cfg: ReaderConfig) -> list[str]:
    try:
        import mss
        import numpy as np
        import pytesseract
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("pip install -r requirements.txt") from exc

    roi = cfg.roi or {"left": 0, "top": 0, "width": 420, "height": 720}
    with mss.mss() as sct:
        shot = sct.grab(roi)
        img = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
        text = pytesseract.image_to_string(img, lang="por+eng", config="--psm 6")
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return lines


def cmd_run() -> None:
    cfg = ReaderConfig.load()
    print(f"Reader activo · live={cfg.live_id} · ROI={cfg.roi}")
    last_frame_hash = ""
    seq = 0
    while True:
        try:
            lines = _ocr_roi_text(cfg)
            frame_key = hashlib.sha256("\n".join(lines).encode()).hexdigest()
            if frame_key == last_frame_hash:
                time.sleep(cfg.poll_interval_ms / 1000.0)
                continue
            last_frame_hash = frame_key

            for line in lines:
                parsed = parse_comment_line(line)
                if parsed is None:
                    continue
                seq += 1
                result = ingest_line(
                    cfg,
                    raw_line=parsed.raw_line,
                    ref_number=parsed.ref_number,
                    display_name=parsed.display_name,
                    confidence=parsed.confidence,
                    chat_sequence=seq,
                )
                print(f"INGEST {parsed.raw_line!r} -> {result}")
        except KeyboardInterrupt:
            print("\nParado.")
            return
        except Exception as exc:  # noqa: BLE001 — loop operacional
            print(f"WARN: {exc}")
        time.sleep(cfg.poll_interval_ms / 1000.0)


def cmd_test_line(line: str) -> None:
    parsed = parse_comment_line(line)
    if parsed is None:
        print("Sem match")
        return
    print(parsed)
    cfg = ReaderConfig.load()
    print(ingest_line(
        cfg,
        raw_line=parsed.raw_line,
        ref_number=parsed.ref_number,
        display_name=parsed.display_name,
        confidence=parsed.confidence,
    ))


def main() -> None:
    parser = argparse.ArgumentParser(description="Fleaber Reader (PS)")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("setup")
    sub.add_parser("calibrate")
    sub.add_parser("run")
    test = sub.add_parser("test-line")
    test.add_argument("line")

    args = parser.parse_args()
    if args.cmd == "setup":
        cmd_setup()
    elif args.cmd == "calibrate":
        cmd_calibrate()
    elif args.cmd == "run":
        cmd_run()
    elif args.cmd == "test-line":
        cmd_test_line(args.line)


if __name__ == "__main__":
    main()
