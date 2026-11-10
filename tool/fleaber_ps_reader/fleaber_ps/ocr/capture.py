"""Captura de ecrã ROI."""

from __future__ import annotations

from dataclasses import dataclass

import mss
import numpy as np


@dataclass
class CaptureRegion:
    left: int
    top: int
    width: int
    height: int

    def to_mss(self) -> dict[str, int]:
        return {
            "left": self.left,
            "top": self.top,
            "width": max(self.width, 1),
            "height": max(self.height, 1),
        }

    @classmethod
    def from_dict(cls, d: dict[str, int]) -> CaptureRegion:
        return cls(
            left=int(d.get("left", 0)),
            top=int(d.get("top", 0)),
            width=int(d.get("width", 400)),
            height=int(d.get("height", 600)),
        )


class ScreenCapture:
    def __init__(self, monitor_index: int = 1) -> None:
        self.monitor_index = monitor_index

    @staticmethod
    def monitor_info(index: int = 1) -> dict:
        with mss.mss() as sct:
            idx = max(1, min(index, len(sct.monitors) - 1))
            return dict(sct.monitors[idx])

    def list_monitors(self) -> list[dict]:
        with mss.mss() as sct:
            return [dict(m) for m in sct.monitors[1:]]

    def grab_monitor(self, index: int | None = None) -> np.ndarray:
        idx = index if index is not None else self.monitor_index
        with mss.mss() as sct:
            mon = sct.monitors[max(1, min(idx, len(sct.monitors) - 1))]
            shot = sct.grab(mon)
            img = np.frombuffer(shot.bgra, dtype=np.uint8).reshape(shot.height, shot.width, 4)
            return img[:, :, :3].copy()

    def grab_region(self, region: CaptureRegion) -> np.ndarray:
        with mss.mss() as sct:
            shot = sct.grab(region.to_mss())
            img = np.frombuffer(shot.bgra, dtype=np.uint8).reshape(shot.height, shot.width, 4)
            return img[:, :, :3].copy()

    @staticmethod
    def to_absolute_roi(
        rel_left: int,
        rel_top: int,
        width: int,
        height: int,
        monitor_index: int = 1,
    ) -> dict[str, int]:
        """Converte coords do screenshot do monitor para coords absolutas mss."""
        mon = ScreenCapture.monitor_info(monitor_index)
        return {
            "left": int(mon["left"]) + rel_left,
            "top": int(mon["top"]) + rel_top,
            "width": width,
            "height": height,
            "monitor_index": monitor_index,
        }

    @staticmethod
    def to_relative_roi(roi: dict[str, int]) -> tuple[int, int, int, int]:
        """Converte coords absolutas guardadas para relativas ao monitor."""
        idx = int(roi.get("monitor_index", 1))
        mon = ScreenCapture.monitor_info(idx)
        return (
            int(roi["left"]) - int(mon["left"]),
            int(roi["top"]) - int(mon["top"]),
            int(roi["width"]),
            int(roi["height"]),
        )
