#!/usr/bin/env python3
"""Dedupe perceptual de fotografias Amazon (ZIP 161) — para importador e scripts.

Compara conteúdo visual (não só URL/MD5):
- MD5 exacto
- Amazon image id (mesma foto, tamanhos diferentes no CDN)
- dHash + aHash (Hamming)
- MSE após resize 64×64 (mesma cena em resoluções diferentes)
"""
from __future__ import annotations

import hashlib
import io
import re
from typing import Iterable

from PIL import Image, ImageChops, ImageOps


def _pixels(img: Image.Image) -> list[int]:
    if hasattr(img, "get_flattened_data"):
        return list(img.get_flattened_data())
    return list(img.getdata())


def dhash_image(img: Image.Image, size: int = 16) -> int:
    g = ImageOps.exif_transpose(img).convert("L").resize(
        (size + 1, size), Image.Resampling.LANCZOS
    )
    pixels = _pixels(g)
    bits = 0
    bit = 0
    for row in range(size):
        row_start = row * (size + 1)
        for col in range(size):
            if pixels[row_start + col] > pixels[row_start + col + 1]:
                bits |= 1 << bit
            bit += 1
    return bits


def ahash_image(img: Image.Image, size: int = 16) -> int:
    g = ImageOps.exif_transpose(img).convert("L").resize(
        (size, size), Image.Resampling.LANCZOS
    )
    pixels = _pixels(g)
    avg = sum(pixels) / max(1, len(pixels))
    bits = 0
    for i, p in enumerate(pixels):
        if p >= avg:
            bits |= 1 << i
    return bits


def mse64(a: Image.Image, b: Image.Image) -> float:
    a2 = ImageOps.exif_transpose(a).convert("L").resize(
        (64, 64), Image.Resampling.LANCZOS
    )
    b2 = ImageOps.exif_transpose(b).convert("L").resize(
        (64, 64), Image.Resampling.LANCZOS
    )
    diff = ImageChops.difference(a2, b2)
    vals = _pixels(diff)
    return sum(v * v for v in vals) / max(1, len(vals))


def dhash_bytes(data: bytes, size: int = 16) -> int | None:
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        return None
    return dhash_image(img, size=size)


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def is_near_duplicate(a: int, b: int, threshold: int = 8) -> bool:
    return hamming(a, b) <= threshold


def amazon_image_id(url: str) -> str | None:
    m = re.search(r"/images/I/([A-Za-z0-9+\-_]+)", url)
    if not m:
        return None
    return m.group(1).split(".")[0]


def _open(data: bytes) -> Image.Image | None:
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
        return img
    except Exception:
        return None


def is_visual_duplicate(
    img: Image.Image,
    kept_imgs: list[Image.Image],
    kept_d: list[int],
    kept_a: list[int],
    *,
    dhash_threshold: int = 10,
    ahash_threshold: int = 12,
    mse_threshold: float = 900.0,
) -> bool:
    d = dhash_image(img)
    a = ahash_image(img)
    for kd, ka, kim in zip(kept_d, kept_a, kept_imgs):
        if hamming(d, kd) <= dhash_threshold:
            return True
        if hamming(a, ka) <= ahash_threshold:
            return True
        if mse64(img, kim) <= mse_threshold:
            return True
    return False


def dedupe_photo_dicts(
    photos: list[dict],
    *,
    threshold: int = 10,
    ahash_threshold: int = 12,
    mse_threshold: float = 900.0,
    max_keep: int = 12,
) -> list[dict]:
    """
    photos: dicts com pelo menos 'url' e opcionalmente 'bytes'/'md5'.
    Se 'bytes' existir, usa dhash+ahash+MSE; senão dedupe por amazon image id + md5.
    """
    kept: list[dict] = []
    kept_imgs: list[Image.Image] = []
    kept_d: list[int] = []
    kept_a: list[int] = []
    ids: set[str] = set()
    md5s: set[str] = set()

    for ph in photos:
        url = str(ph.get("url") or "")
        data = ph.get("bytes")
        if isinstance(data, (bytes, bytearray)):
            md5 = hashlib.md5(data).hexdigest()
            if md5 in md5s:
                continue
            aid = amazon_image_id(url)
            if aid and aid in ids:
                continue
            img = _open(bytes(data))
            if img is not None and is_visual_duplicate(
                img,
                kept_imgs,
                kept_d,
                kept_a,
                dhash_threshold=threshold,
                ahash_threshold=ahash_threshold,
                mse_threshold=mse_threshold,
            ):
                continue
            md5s.add(md5)
            if aid:
                ids.add(aid)
            if img is not None:
                kept_imgs.append(img)
                kept_d.append(dhash_image(img))
                kept_a.append(ahash_image(img))
            kept.append(ph)
        else:
            aid = amazon_image_id(url)
            if aid:
                if aid in ids:
                    continue
                ids.add(aid)
            kept.append(ph)
        if len(kept) >= max_keep:
            break
    return kept
