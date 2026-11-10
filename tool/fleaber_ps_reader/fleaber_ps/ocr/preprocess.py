"""Pré-processamento de imagem para OCR."""

from __future__ import annotations

import cv2
import numpy as np


def to_gray(img: np.ndarray) -> np.ndarray:
    if len(img.shape) == 2:
        return img
    return cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)


def upscale(img: np.ndarray, factor: float = 2.0) -> np.ndarray:
    if factor <= 1.0:
        return img
    h, w = img.shape[:2]
    return cv2.resize(img, (int(w * factor), int(h * factor)), interpolation=cv2.INTER_CUBIC)


def enhance_contrast(gray: np.ndarray) -> np.ndarray:
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def binarize(gray: np.ndarray) -> np.ndarray:
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    return cv2.adaptiveThreshold(
        blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 8
    )


def sharpen(gray: np.ndarray) -> np.ndarray:
    kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    return cv2.filter2D(gray, -1, kernel)


def preprocess_for_ocr(bgr: np.ndarray, dark_mode_hint: bool = False) -> np.ndarray:
    """Pipeline: upscale → gray → contrast → optional invert → binarize."""
    img = upscale(bgr, 2.0)
    gray = to_gray(img)
    gray = enhance_contrast(gray)
    gray = sharpen(gray)
    if dark_mode_hint:
        gray = cv2.bitwise_not(gray)
    return binarize(gray)


def detect_line_bands(gray: np.ndarray, min_height: int = 28) -> list[tuple[int, int]]:
    """Detecta faixas horizontais prováveis de comentários."""
    h, w = gray.shape[:2]
    row_mean = np.mean(gray, axis=1)
    # Linhas com texto têm variância local
    bands: list[tuple[int, int]] = []
    in_band = False
    start = 0
    threshold = np.mean(row_mean) * 0.85
    for y in range(h):
        val = row_mean[y]
        if val < threshold and not in_band:
            in_band = True
            start = y
        elif val >= threshold and in_band:
            if y - start >= min_height:
                bands.append((start, y))
            in_band = False
    if in_band and h - start >= min_height:
        bands.append((start, h))
    return bands
