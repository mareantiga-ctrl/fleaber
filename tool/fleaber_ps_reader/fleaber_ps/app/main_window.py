"""Janela principal Fleaber PS Reader."""

from __future__ import annotations

import threading
import tkinter as tk
from tkinter import messagebox
from typing import Any
import urllib.error
import urllib.request

import customtkinter as ctk
from PIL import Image, ImageTk

from fleaber_ps.core.config import PsConfig
from fleaber_ps.core.hub_links import hub_link_from_pairing
from fleaber_ps.core.ingest_client import IngestClient
from fleaber_ps.diagnostic.export import export_diagnostic
from fleaber_ps.ocr.capture import CaptureRegion, ScreenCapture
from fleaber_ps.ocr.pipeline import ReaderPipeline
from fleaber_ps.ocr.tesseract_locate import tesseract_status
from fleaber_ps.parser.context import LiveContext
from fleaber_ps.version import __version__


ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")

ACCENT = "#007782"


class MainWindow(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"Fleaber PS Reader v{__version__}")
        self.geometry("920x640")
        self.minsize(780, 520)

        self.cfg = PsConfig.load()
        self.ctx: LiveContext | None = None
        self.pipeline: ReaderPipeline | None = None
        self._thread: threading.Thread | None = None

        self._build_ui()
        self._refresh_status()
        self._check_tesseract_on_start()
        self.after(500, self._refresh_ollama_status)

    def _ollama_online(self) -> bool:
        url = (self.cfg.ollama_url or "http://127.0.0.1:11434").rstrip("/") + "/api/tags"
        try:
            with urllib.request.urlopen(url, timeout=2.5) as resp:
                return resp.status == 200
        except (urllib.error.URLError, TimeoutError, OSError):
            return False

    def _refresh_ollama_status(self) -> None:
        online = self._ollama_online()
        if online:
            self.ollama_status.configure(
                text=f"IA: ligada ({self.cfg.ollama_model})",
                text_color="#6fcf97",
            )
        else:
            self.ollama_status.configure(
                text="IA: desligada — corre setup_ollama.ps1",
                text_color="#e07a7a",
            )

    def _toggle_ollama(self) -> None:
        self.cfg.ollama_enabled = bool(self.ollama_var.get())
        self.cfg.save()
        if self.cfg.ollama_enabled and not self._ollama_online():
            messagebox.showinfo(
                "Ollama em falta",
                "A caixa IA ficou activa, mas o Ollama nao esta a correr.\n\n"
                "Clica «Instalar / activar Ollama» ou corre setup_ollama.ps1",
            )
        self._refresh_ollama_status()

    def _open_ollama_setup(self) -> None:
        from pathlib import Path
        import subprocess
        import sys

        script = Path(__file__).resolve().parents[2] / "setup_ollama.ps1"
        if not script.exists():
            messagebox.showerror("Script em falta", f"Nao encontrei:\n{script}")
            return
        subprocess.Popen(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
            ],
            creationflags=getattr(subprocess, "CREATE_NEW_CONSOLE", 0),
        )
        self._log("A abrir instalador Ollama — segue as instrucoes na janela nova.")
        self.after(8000, self._refresh_ollama_status)

    def _check_tesseract_on_start(self) -> None:
        ok, msg = tesseract_status(self.cfg.tesseract_cmd)
        if ok:
            self._log(f"Tesseract OK: {msg}")
            if self.cfg.tesseract_cmd != msg:
                self.cfg.tesseract_cmd = msg
                self.cfg.save()
        else:
            self._log("⚠ TESSERACT EM FALTA — OCR nao funciona ate instalar.")
            messagebox.showwarning("Tesseract em falta", msg)

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(self, fg_color="transparent")
        header.grid(row=0, column=0, sticky="ew", padx=16, pady=(12, 4))
        ctk.CTkLabel(
            header,
            text="Fleaber PS Reader",
            font=ctk.CTkFont(size=22, weight="bold"),
        ).pack(side="left")
        self.status_chip = ctk.CTkLabel(header, text="● Desligado", text_color="#888")
        self.status_chip.pack(side="right")

        body = ctk.CTkFrame(self)
        body.grid(row=1, column=0, sticky="nsew", padx=16, pady=8)
        body.grid_columnconfigure(1, weight=1)
        body.grid_rowconfigure(0, weight=1)

        # Left — actions
        left = ctk.CTkFrame(body, width=220)
        left.grid(row=0, column=0, sticky="ns", padx=(8, 8), pady=8)
        ctk.CTkLabel(left, text="Acções", font=ctk.CTkFont(weight="bold")).pack(anchor="w", pady=(4, 8))

        ctk.CTkButton(left, text="Emparelhar live", command=self._pair, fg_color=ACCENT).pack(fill="x", pady=4)
        ctk.CTkButton(left, text="Seleccionar zona chat", command=self._calibrate).pack(fill="x", pady=4)
        ctk.CTkButton(left, text="Testar leitura OCR", command=self._test_ocr).pack(fill="x", pady=4)

        self.ollama_var = tk.BooleanVar(value=self.cfg.ollama_enabled)
        self.ollama_check = ctk.CTkCheckBox(
            left,
            text="IA local (Ollama)",
            variable=self.ollama_var,
            command=self._toggle_ollama,
        )
        self.ollama_check.pack(anchor="w", pady=(12, 2), padx=4)
        self.ollama_status = ctk.CTkLabel(
            left,
            text="IA: a verificar…",
            font=ctk.CTkFont(size=11),
            text_color="#888",
            anchor="w",
        )
        self.ollama_status.pack(anchor="w", padx=8, pady=(0, 4))
        ctk.CTkButton(
            left,
            text="Instalar / activar Ollama",
            command=self._open_ollama_setup,
            fg_color="#333",
            hover_color="#444",
        ).pack(fill="x", pady=2)

        self.btn_start = ctk.CTkButton(left, text="▶ Iniciar", command=self._start, fg_color=ACCENT)
        self.btn_start.pack(fill="x", pady=(16, 4))
        ctk.CTkButton(left, text="⏸ Pausar", command=self._pause).pack(fill="x", pady=4)
        ctk.CTkButton(left, text="⏹ Parar", command=self._stop).pack(fill="x", pady=4)
        ctk.CTkButton(left, text="Exportar diagnóstico", command=self._export_diag).pack(fill="x", pady=(16, 4))
        ctk.CTkButton(left, text="Desemparelhar", command=self._unpair).pack(fill="x", pady=4)

        # Right — info + feed
        right = ctk.CTkFrame(body)
        right.grid(row=0, column=1, sticky="nsew", padx=8, pady=8)
        right.grid_rowconfigure(3, weight=1)
        right.grid_columnconfigure(0, weight=1)

        self.info_live = ctk.CTkLabel(right, text="Live: —", anchor="w")
        self.info_live.grid(row=0, column=0, sticky="ew", padx=8, pady=4)
        self.info_roi = ctk.CTkLabel(right, text="Zona chat: —", anchor="w")
        self.info_roi.grid(row=1, column=0, sticky="ew", padx=8, pady=4)

        self.hub_link_frame = ctk.CTkFrame(right, fg_color="#1a2226")
        self.hub_link_frame.grid(row=2, column=0, sticky="ew", padx=8, pady=(4, 8))
        self.hub_link_frame.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(
            self.hub_link_frame,
            text="Link FleaHub (cola nos comentários do Facebook):",
            font=ctk.CTkFont(size=12, weight="bold"),
            anchor="w",
        ).grid(row=0, column=0, columnspan=2, sticky="ew", padx=10, pady=(8, 4))
        self.hub_link_var = tk.StringVar(value="")
        self.hub_link_entry = ctk.CTkEntry(
            self.hub_link_frame,
            textvariable=self.hub_link_var,
            height=36,
        )
        self.hub_link_entry.grid(row=1, column=0, sticky="ew", padx=(10, 6), pady=(0, 8))
        self.hub_link_entry.configure(state="disabled")
        ctk.CTkButton(
            self.hub_link_frame,
            text="Copiar",
            width=72,
            fg_color=ACCENT,
            command=self._copy_hub_link,
        ).grid(row=1, column=1, padx=(0, 10), pady=(0, 8))
        self.hub_link_frame.grid_remove()

        self.feed = ctk.CTkTextbox(right, height=300)
        self.feed.grid(row=3, column=0, sticky="nsew", padx=8, pady=8)

        stats = ctk.CTkFrame(right, fg_color="transparent")
        stats.grid(row=4, column=0, sticky="ew", padx=8, pady=4)
        self.stats_label = ctk.CTkLabel(stats, text="Reservas: 0 · Rever: 0 · OCR: 0")
        self.stats_label.pack(anchor="w")

    def _log(self, msg: str) -> None:
        self.feed.insert("end", msg + "\n")
        self.feed.see("end")

    def _copy_hub_link(self) -> None:
        url = (self.cfg.hub_live_url or self.hub_link_var.get() or "").strip()
        if not url:
            messagebox.showinfo(
                "Link FleaHub",
                "Emparelha primeiro — ou configura o handle FleaHub no Studio.",
            )
            return
        self.clipboard_clear()
        self.clipboard_append(url)
        self._log("📋 Link FleaHub copiado.")
        messagebox.showinfo("Link copiado", "Cola no Facebook Live ou nos comentários.")

    def _apply_hub_link(self, url: str, handle: str) -> None:
        url = url.strip()
        handle = handle.strip()
        self.cfg.hub_live_url = url
        self.cfg.seller_handle = handle
        if url:
            self.hub_link_var.set(url)
            self.hub_link_frame.grid()
        else:
            self.hub_link_var.set("")
            self.hub_link_frame.grid_remove()

    def _refresh_status(self) -> None:
        if self.cfg.is_paired():
            self.info_live.configure(
                text=f"Live: {self.cfg.live_title or self.cfg.live_id[:8]}…"
            )
            self._apply_hub_link(self.cfg.hub_live_url, self.cfg.seller_handle)
        else:
            self.info_live.configure(text="Live: não emparelhada")
            self._apply_hub_link("", "")
        if self.cfg.roi:
            r = self.cfg.roi
            self.info_roi.configure(
                text=f"Zona chat: {r['width']}×{r['height']} @ ({r['left']},{r['top']})"
            )
        else:
            self.info_roi.configure(text="Zona chat: não definida")

    def _pair(self) -> None:
        dlg = ctk.CTkInputDialog(
            text="Introduz o código de 6 dígitos mostrado no Studio Fleaber:",
            title="Emparelhar",
        )
        code = (dlg.get_input() or "").strip()
        if len(code) != 6:
            messagebox.showwarning("Emparelhar", "Código inválido.")
            return
        try:
            client = IngestClient(self.cfg)
            data = client.claim_pairing(code)
            client.close()
            self.cfg.supabase_url = str(data.get("supabase_url", self.cfg.supabase_url)).rstrip("/")
            self.cfg.live_id = str(data.get("live_id", ""))
            self.cfg.device_token = str(data.get("device_token", ""))
            self.cfg.device_id = str(data.get("device_id", "ps-reader-pc"))
            ctx_data = data.get("live_context") or {}
            self.cfg.live_title = str(ctx_data.get("live_title", "Live"))
            self.ctx = IngestClient.live_context_from_pairing(data)
            hub_url, seller_handle = hub_link_from_pairing(data)
            # Nova sessão — limpar dedupe local (evita bloquear após falha anterior)
            self.cfg.seen_hashes = []
            self.cfg.seen_comment_keys = []
            self.cfg.seen_reservation_keys = []
            self.cfg.hub_live_url = hub_url
            self.cfg.seller_handle = seller_handle
            self.cfg.save()
            self._log(f"✓ Emparelhado com {self.cfg.live_title}")
            self._refresh_status()
            if hub_url:
                self.clipboard_clear()
                self.clipboard_append(hub_url)
                self._log(f"🔗 Link FleaHub: {hub_url}")
                self._log("📋 Link copiado — cola no Facebook Live.")
                messagebox.showinfo(
                    "Emparelhar",
                    f"Ligado à live «{self.cfg.live_title}».\n\n"
                    "O link FleaHub foi copiado — cola nos comentários do Facebook.",
                )
            else:
                messagebox.showwarning(
                    "Emparelhar",
                    f"Ligado à live «{self.cfg.live_title}».\n\n"
                    "Não foi possível gerar o link — publica o FleaHub no Studio "
                    "(handle obrigatório).",
                )
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Emparelhar", str(exc))

    def _unpair(self) -> None:
        if messagebox.askyesno("Desemparelhar", "Remover ligação a esta live?"):
            self._stop()
            self.cfg.clear_pairing()
            self.ctx = None
            self._refresh_status()
            self._log("Desemparelhado.")

    def _calibrate(self) -> None:
        CalibrateDialog(self, self.cfg, on_done=self._refresh_status)

    def _test_ocr(self) -> None:
        if not self.cfg.roi:
            messagebox.showwarning("OCR", "Define primeiro a zona do chat.")
            return
        ok, tmsg = tesseract_status(self.cfg.tesseract_cmd)
        if not ok:
            messagebox.showerror("Tesseract em falta", tmsg)
            self._log("⚠ " + tmsg.replace("\n", " "))
            return
        pipe = ReaderPipeline(self.cfg, self.ctx)
        result = pipe.test_ocr_once()
        pipe.client.close()
        preview = PsConfig.config_dir() / "calibration_preview.png"
        self._log(f"— Teste OCR (conf={result.confidence:.0%}) —")
        if result.lines:
            for ln in result.lines[:20]:
                self._log(f"  {ln.text}")
        else:
            self._log("  (nenhum texto detectado)")
            self._log(
                "  Dicas: recalibra a zona (so comentarios); "
                "aumenta zoom do Facebook; confirma preview em:"
            )
            self._log(f"  {preview}")
            if not result.tesseract_ok:
                self._log(f"  Erro: {result.error or tmsg}")

    def _on_pipeline_event(self, event: str, data: dict[str, Any]) -> None:
        def ui() -> None:
            if event == "ingest":
                r = data.get("result", {})
                self._log(f"→ Reserva: {data.get('parsed')} (#{r.get('queue_position', '?')})")
            elif event == "supersede":
                r = data.get("result", {})
                qty = r.get("requested_qty", "?")
                self._log(f"↻ Actualizado: {data.get('parsed')} (qty={qty})")
            elif event == "cancel":
                self._log(f"✕ Cancelado: {data.get('parsed')}")
            elif event == "llm":
                self._log(
                    f"🤖 IA ({data.get('reason', '?')}): {data.get('parsed')}"
                )
            elif event == "llm_miss":
                self._log(
                    f"🤖 IA falhou ({data.get('reason', '?')}): {data.get('parsed')}"
                )
            elif event == "skipped":
                self._log(
                    f"○ Ignorado ({data.get('reason', '?')}): {data.get('parsed')}"
                )
            elif event == "noop":
                self._log(f"○ Ignorado (sem reserva aberta): {data.get('parsed')}")
            elif event == "error":
                msg = data.get("message") or data.get("result")
                parsed = data.get("parsed")
                if parsed:
                    self._log(f"⚠ [{parsed}] {msg}")
                else:
                    self._log(f"⚠ {msg}")
            if self.pipeline:
                s = self.pipeline.stats
                self.stats_label.configure(
                    text=f"Reservas: {s.ingested} · Rever: {s.needs_review} · OCR: {s.ocr_runs}"
                )
        self.after(0, ui)

    def _start(self) -> None:
        if not self.cfg.is_paired():
            messagebox.showwarning("Iniciar", "Emparelha primeiro com a live.")
            return
        if not self.cfg.roi:
            messagebox.showwarning("Iniciar", "Selecciona a zona do chat.")
            return
        if self._thread and self._thread.is_alive():
            return
        self.pipeline = ReaderPipeline(self.cfg, self.ctx, on_event=self._on_pipeline_event)
        self._thread = threading.Thread(target=self.pipeline.run_loop, daemon=True)
        self._thread.start()
        self.status_chip.configure(text="● A ler comentários", text_color="#00A3AD")
        self._log("▶ Reader iniciado.")
        self._log(
            "  Mantém o chat do Facebook visível na zona calibrada — "
            "o OCR lê pixels fixos do ecrã, não a janela."
        )

    def _pause(self) -> None:
        if self.pipeline:
            self.pipeline.stop()
            self.status_chip.configure(text="● Pausado", text_color="#E6A817")
            self._log("⏸ Pausado.")

    def _stop(self) -> None:
        if self.pipeline:
            self.pipeline.stop()
            self.pipeline.client.close()
            self.pipeline = None
        self.status_chip.configure(text="● Desligado", text_color="#888")
        self._log("⏹ Parado.")

    def _export_diag(self) -> None:
        try:
            path = export_diagnostic()
            self._log(f"Diagnóstico: {path}")
            messagebox.showinfo("Diagnóstico", f"Exportado:\n{path}")
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Diagnóstico", str(exc))

    def on_close(self) -> None:
        self._stop()
        self.destroy()


class CalibrateDialog(tk.Toplevel):
    """Seleccionar ROI arrastando rectângulo sobre screenshot."""

    def __init__(self, parent: MainWindow, cfg: PsConfig, on_done: callable) -> None:
        super().__init__(parent)
        self.cfg = cfg
        self.on_done = on_done
        self.title("Seleccionar zona do chat")
        self.geometry("1000x700")

        self.capture = ScreenCapture(cfg.monitor_index)
        self._mon_index = cfg.monitor_index
        mon = ScreenCapture.monitor_info(cfg.monitor_index)
        self._mon_left = int(mon["left"])
        self._mon_top = int(mon["top"])

        bgr = self.capture.grab_monitor(cfg.monitor_index)
        self.scale = min(960 / bgr.shape[1], 600 / bgr.shape[0], 1.0)
        w, h = int(bgr.shape[1] * self.scale), int(bgr.shape[0] * self.scale)
        rgb = bgr[:, :, ::-1]
        pil = Image.fromarray(rgb).resize((w, h), Image.Resampling.LANCZOS)
        self.photo = ImageTk.PhotoImage(pil)
        self.off_x = self.off_y = 0

        bar = ctk.CTkFrame(self)
        bar.pack(fill="x", padx=8, pady=4)
        ctk.CTkLabel(bar, text="Arrasta para seleccionar o chat. Guardar quando estiver correcto.").pack(side="left")
        ctk.CTkButton(bar, text="Guardar", command=self._save, fg_color=ACCENT).pack(side="right")

        self.canvas = tk.Canvas(self, width=w, height=h, cursor="cross")
        self.canvas.pack(padx=8, pady=8)
        self.canvas.create_image(0, 0, anchor="nw", image=self.photo)

        self.start_x = self.start_y = 0
        self.rect_id: int | None = None
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)

        if cfg.roi:
            r = cfg.roi
            rl, rt, rw, rh = ScreenCapture.to_relative_roi(r)
            sx = rl * self.scale
            sy = rt * self.scale
            ex = sx + rw * self.scale
            ey = sy + rh * self.scale
            self.rect_id = self.canvas.create_rectangle(sx, sy, ex, ey, outline=ACCENT, width=2)

        self._orig_shape = bgr.shape

    def _on_press(self, event: tk.Event) -> None:
        self.start_x, self.start_y = event.x, event.y
        if self.rect_id:
            self.canvas.delete(self.rect_id)
        self.rect_id = self.canvas.create_rectangle(
            self.start_x, self.start_y, event.x, event.y, outline=ACCENT, width=2
        )

    def _on_drag(self, event: tk.Event) -> None:
        if self.rect_id:
            self.canvas.coords(self.rect_id, self.start_x, self.start_y, event.x, event.y)

    def _on_release(self, event: tk.Event) -> None:
        self.end_x, self.end_y = event.x, event.y

    def _save(self) -> None:
        if not self.rect_id:
            messagebox.showwarning("Guardar", "Desenha um rectângulo.")
            return
        x1, y1, x2, y2 = self.canvas.coords(self.rect_id)
        inv = 1.0 / self.scale
        left = int(min(x1, x2) * inv)
        top = int(min(y1, y2) * inv)
        width = int(abs(x2 - x1) * inv)
        height = int(abs(y2 - y1) * inv)
        if width < 80 or height < 80:
            messagebox.showwarning("Guardar", "Região demasiado pequena.")
            return
        self.cfg.roi = ScreenCapture.to_absolute_roi(
            left, top, width, height, self._mon_index
        )
        self.cfg.monitor_index = self._mon_index
        self.cfg.save()
        preview = self.capture.grab_region(CaptureRegion.from_dict(self.cfg.roi))
        from PIL import Image as PILImage

        prev_path = PsConfig.config_dir() / "calibration_preview.png"
        PILImage.fromarray(preview[:, :, ::-1]).save(prev_path)
        # Validar: preview deve parecer o chat (nao wallpaper/preto)
        mean_px = float(preview.mean())
        if mean_px < 8 or mean_px > 250:
            messagebox.showwarning(
                "Guardar",
                "A zona capturada parece vazia ou errada.\n"
                f"Abre e verifica: {prev_path}\n"
                "Volta a desenhar o rectangulo so sobre os comentarios.",
            )
        self.on_done()
        self.destroy()


def run_app() -> None:
    app = MainWindow()
    app.protocol("WM_DELETE_WINDOW", app.on_close)
    app.mainloop()
