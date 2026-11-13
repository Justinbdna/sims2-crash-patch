#!/usr/bin/env python3
"""
Cross-platform QA verifier & release archive builder for sims2-crash-patch.

Works identically on Windows, macOS, and Linux (Python 3 stdlib only):
  - Enforces LF line endings and #!/bin/bash shebang on all macOS .command/.sh scripts
  - Runs `bash -n` and `perl -c` syntax validation on embedded Perl blocks
  - Runs the cross-platform unit/integration test suite (`tests/`)
  - Builds separated macOS (with UNIX 0755 permissions & LF) and Windows release ZIPs
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import py_compile
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT_DIR = Path(__file__).resolve().parent.parent

MAC_UNIX_SCRIPTS = (
    Path("patch_sims2.command"),
    Path("clean_sims2_cache.command"),
    Path("restore_sims2.command"),
    Path("trackpad_mod/build_trackpad.sh"),
    Path("legacy/patch_sims2.sh"),
)

MAC_RELEASE_FILES = (
    Path("patch_sims2.command"),
    Path("clean_sims2_cache.command"),
    Path("restore_sims2.command"),
    Path("README.txt"),
    Path("trackpad_mod/libsims2_trackpad.dylib"),
    Path("trackpad_mod/sims2_trackpad.m"),
)

WINDOWS_RELEASE_DIR = Path("windows")


def find_unix_tool(name: str, windows_candidates: tuple[str, ...]) -> str | None:
    """Locate bash or perl across PATH and standard Git for Windows paths."""
    found = shutil.which(name)
    if found:
        # Avoid Windows WSL shim bash.exe when no WSL distro is installed
        if sys.platform == "win32" and found.lower().endswith(r"\system32\bash.exe"):
            found = None
    if found:
        return found
    if sys.platform == "win32":
        for candidate in windows_candidates:
            if Path(candidate).is_file():
                return candidate
    return None


def find_bash() -> str | None:
    return find_unix_tool(
        "bash",
        (
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files\Git\usr\bin\bash.exe",
            r"C:\Program Files (x86)\Git\bin\bash.exe",
        ),
    )


def find_perl() -> str | None:
    return find_unix_tool(
        "perl",
        (
            r"C:\Program Files\Git\usr\bin\perl.exe",
            r"C:\Strawberry\perl\bin\perl.exe",
        ),
    )


def extract_perl_blocks(script_text: str) -> list[str]:
    """Extract heredoc Perl blocks (`<<'PERLEOF' ... PERLEOF`) from a shell script."""
    pattern = re.compile(r"<<'PERLEOF'\r?\n(.*?)\r?\nPERLEOF", re.DOTALL)
    return pattern.findall(script_text)


def verify_mac_scripts() -> list[str]:
    """Verify LF line endings, shebangs, bash syntax, and embedded Perl syntax."""
    errors: list[str] = []
    bash_bin = find_bash()
    perl_bin = find_perl()

    for rel in MAC_UNIX_SCRIPTS:
        full_path = ROOT_DIR / rel
        if not full_path.is_file():
            errors.append(f"Missing Mac script: {rel}")
            continue

        raw = full_path.read_bytes()
        if b"\r" in raw:
            errors.append(f"CRLF/CR detected in {rel} (macOS requires pure LF)")
        if not (raw.startswith(b"#!/bin/bash\n") or raw.startswith(b"#!/usr/bin/env bash\n")):
            errors.append(f"Missing #!/bin/bash or #!/usr/bin/env bash LF shebang in {rel}")

        if bash_bin:
            res = subprocess.run([bash_bin, "-n", str(full_path)], capture_output=True, text=True)
            if res.returncode != 0:
                errors.append(f"bash -n failed for {rel}: {res.stderr.strip()}")

        if perl_bin:
            text = raw.decode("utf-8")
            for idx, block in enumerate(extract_perl_blocks(text), start=1):
                with tempfile.NamedTemporaryFile("w", suffix=".pl", encoding="utf-8", delete=False) as tf:
                    tf.write(block)
                    tmp_pl = Path(tf.name)
                try:
                    res = subprocess.run([perl_bin, "-c", str(tmp_pl)], capture_output=True, text=True)
                    if res.returncode != 0:
                        errors.append(f"perl -c failed for {rel} block #{idx}: {res.stderr.strip()}")
                finally:
                    tmp_pl.unlink(missing_ok=True)

    return errors


def verify_python_syntax() -> list[str]:
    """Compile all Python files in scripts/, tests/, windows/, and legacy/."""
    errors: list[str] = []
    for folder in ("scripts", "tests", "windows", "legacy"):
        base = ROOT_DIR / folder
        if not base.is_dir():
            continue
        for py_file in sorted(base.rglob("*.py")):
            try:
                py_compile.compile(str(py_file), doraise=True)
            except py_compile.PyCompileError as exc:
                errors.append(f"py_compile failed for {py_file.relative_to(ROOT_DIR)}: {exc}")
    return errors


def run_unit_tests() -> bool:
    loader = unittest.TestLoader()
    suite = loader.discover(str(ROOT_DIR / "tests"), pattern="test_*.py")
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result.wasSuccessful()


def _zip_write_bytes(
    zf: zipfile.ZipFile,
    arcname: str,
    data: bytes,
    posix_mode: int,
) -> None:
    info = zipfile.ZipInfo(arcname)
    info.create_system = 3  # UNIX so macOS unzip preserves executable permissions
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = ((stat.S_IFREG | posix_mode) & 0xFFFF) << 16
    zf.writestr(info, data)


def package_releases(version: str, out_dir: Path) -> tuple[Path, Path]:
    """Build clean separated macOS and Windows release ZIP archives."""
    out_dir.mkdir(parents=True, exist_ok=True)
    safe_ver = re.sub(r'[\\/:*?"<>|\s]+', "-", version).strip("-") or "dev"
    clean_ver = f"v{safe_ver}" if safe_ver[0].isdigit() else safe_ver

    mac_zip = out_dir / f"sims2-crash-patch-{clean_ver}.zip"
    with zipfile.ZipFile(mac_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for rel in MAC_RELEASE_FILES:
            src = ROOT_DIR / rel
            data = src.read_bytes()
            if rel.suffix not in (".dylib", ".so", ".dll", ".exe"):
                data = data.replace(b"\r\n", b"\n")
            mode = 0o755 if rel.suffix in (".command", ".sh", ".dylib") else 0o644
            _zip_write_bytes(zf, rel.as_posix(), data, mode)

    win_zip = out_dir / f"sims2-crash-patch-windows-{clean_ver}.zip"
    win_root = ROOT_DIR / WINDOWS_RELEASE_DIR
    with zipfile.ZipFile(win_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for item in sorted(win_root.rglob("*")):
            if not item.is_file() or "__pycache__" in item.parts or item.suffix == ".pyc":
                continue
            rel_arc = item.relative_to(ROOT_DIR).as_posix()
            raw = item.read_bytes()
            if item.suffix in (".bat", ".cmd", ".ps1"):
                raw = raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            elif item.suffix in (".py", ".md", ".txt"):
                raw = raw.replace(b"\r\n", b"\n")
            _zip_write_bytes(zf, rel_arc, raw, 0o644)

    return mac_zip, win_zip


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify repo & build release archives")
    parser.add_argument("--package", action="store_true", help="Build Mac & Windows release ZIPs in dist/")
    parser.add_argument("--version", default="v1.3.1", help="Release version tag (default: v1.3.1)")
    parser.add_argument("--out-dir", type=Path, default=ROOT_DIR / "dist")
    args = parser.parse_args(argv)

    print("[1/3] Checking macOS script EOLs, bash -n, and Perl syntax...")
    mac_errors = verify_mac_scripts()
    if mac_errors:
        for err in mac_errors:
            print(f"[-] {err}", file=sys.stderr)
        return 1
    print("[+] macOS scripts verified clean.")

    print("[2/3] Checking Python compilation across scripts/, tests/, windows/...")
    py_errors = verify_python_syntax()
    if py_errors:
        for err in py_errors:
            print(f"[-] {err}", file=sys.stderr)
        return 1
    print("[+] Python syntax verified clean.")

    print("[3/3] Running cross-platform test suite...")
    if not run_unit_tests():
        return 1

    if args.package:
        mac_zip, win_zip = package_releases(args.version, args.out_dir)
        print(f"[+] Built Mac release ZIP     : {mac_zip} ({mac_zip.stat().st_size} bytes)")
        print(f"[+] Built Windows release ZIP : {win_zip} ({win_zip.stat().st_size} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
