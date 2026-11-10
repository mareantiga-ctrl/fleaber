# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec — Fleaber PS Reader."""

import sys
from pathlib import Path

root = Path(SPECPATH)
pkg = root / "fleaber_ps"

a = Analysis(
    [str(root / "fleaber_ps" / "__main__.py")],
    pathex=[str(root)],
    binaries=[],
    datas=[],
    hiddenimports=[
        "customtkinter",
        "PIL._tkinter_finder",
        "fleaber_ps",
        "fleaber_ps.app.main_window",
        "fleaber_ps.core.config",
        "fleaber_ps.ocr.pipeline",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="FleaberPSReader",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,
)
