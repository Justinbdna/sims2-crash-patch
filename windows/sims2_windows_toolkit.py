#!/usr/bin/env python3
"""
Sims 2 Crash Patch — Windows Special Edition Toolkit (Standalone, Non-Mac)

Provides safe diagnostics, 4GB/LARGEADDRESSAWARE PE inspection & patching,
display refresh-rate / OneDrive checks, userProps.xml repair, and cache
cleaning for The Sims 2 (Ultimate Collection / Legacy Collection / Disc) on
Windows 10/11 — strictly isolated from the macOS scripts.

Zero external dependencies (Python 3 standard library + built-in Win32 APIs).
"""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass, field
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import xml.etree.ElementTree as ET

# PE header constants
DOS_MAGIC = 0x5A4D  # "MZ"
PE_SIGNATURE = b"PE\x00\x00"
IMAGE_FILE_MACHINE_I386 = 0x014C
IMAGE_FILE_LARGE_ADDRESS_AWARE = 0x0020

KNOWN_EXE_NAMES = (
    "Sims2EP9.exe",
    "Sims2EP9RPC.exe",
    "Sims2RPC.exe",
    "Sims2SC.exe",
    "Sims2LC.exe",
    "Sims2.exe",
    "Sims2SP8.exe",
    "Sims2EP8.exe",
)

WINDOWS_CACHE_FILES = (
    "Groups.cache",
    "Accessory.cache",
    "cigen.package",
    "ContentRegistry",
)

COMMUNITY_ADDONS = (
    "Sims2RPC.exe",
    "Sims2RPCSettings.exe",
    "TS2-Extender.exe",
    "TS2-Extender.asi",
    "d3d9.dll",
    "dxvk.conf",
)


@dataclass
class PEStatus:
    path: Path
    is_valid_pe32: bool
    machine: int
    characteristics: int
    large_address_aware: bool
    checksum: int
    error: str | None = None


@dataclass
class DisplayModeInfo:
    width: int
    height: int
    bpp: int
    refresh_hz: int


@dataclass
class SaveFolderReport:
    path: Path
    inside_onedrive: bool
    caches_present: list[str] = field(default_factory=list)
    userprops_path: Path | None = None
    active_display_mode: str | None = None


def compute_pe_checksum(data: bytes | bytearray, checksum_offset: int) -> int:
    """Compute the standard Win32 PE image checksum (RFC1071-style carry fold)."""
    total = 0
    length = len(data)
    limit = length - (length % 2)

    for offset in range(0, limit, 2):
        if checksum_offset <= offset < checksum_offset + 4:
            continue
        word = data[offset] | (data[offset + 1] << 8)
        total += word
        total = (total & 0xFFFF) + (total >> 16)

    if length % 2:
        total += data[-1]
        total = (total & 0xFFFF) + (total >> 16)

    total = (total & 0xFFFF) + (total >> 16)
    return (total + length) & 0xFFFFFFFF


def inspect_pe(exe_path: Path) -> PEStatus:
    """Inspect a Windows PE executable and report its LARGEADDRESSAWARE state."""
    try:
        raw = exe_path.read_bytes()
    except OSError as exc:
        return PEStatus(exe_path, False, 0, 0, False, 0, f"Cannot read file: {exc}")

    if len(raw) < 0x40:
        return PEStatus(exe_path, False, 0, 0, False, 0, "File too small for DOS header")

    dos_magic = struct.unpack_from("<H", raw, 0)[0]
    if dos_magic != DOS_MAGIC:
        return PEStatus(exe_path, False, 0, 0, False, 0, "Missing MZ DOS signature")

    pe_offset = struct.unpack_from("<I", raw, 0x3C)[0]
    if pe_offset + 24 + 68 > len(raw):
        return PEStatus(exe_path, False, 0, 0, False, 0, "Truncated PE header")

    if raw[pe_offset : pe_offset + 4] != PE_SIGNATURE:
        return PEStatus(exe_path, False, 0, 0, False, 0, "Missing PE\\0\\0 signature")

    machine = struct.unpack_from("<H", raw, pe_offset + 4)[0]
    characteristics = struct.unpack_from("<H", raw, pe_offset + 22)[0]
    opt_magic = struct.unpack_from("<H", raw, pe_offset + 24)[0]
    checksum = struct.unpack_from("<I", raw, pe_offset + 24 + 64)[0]

    is_pe32 = machine == IMAGE_FILE_MACHINE_I386 and opt_magic == 0x010B
    laa = bool(characteristics & IMAGE_FILE_LARGE_ADDRESS_AWARE)
    err = None if is_pe32 else f"Expected 32-bit x86 PE32, got machine=0x{machine:04x}"

    return PEStatus(
        path=exe_path,
        is_valid_pe32=is_pe32,
        machine=machine,
        characteristics=characteristics,
        large_address_aware=laa,
        checksum=checksum,
        error=err,
    )


def atomic_write_bytes(target_path: Path, payload: bytes) -> None:
    """Atomically write bytes to target_path using a same-directory temp file."""
    tmp_path = target_path.with_name(f"{target_path.name}.tmp.{os.getpid()}")
    try:
        with open(tmp_path, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, target_path)
    except Exception:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)
        raise


def set_large_address_aware(exe_path: Path, enable: bool = True) -> tuple[bool, str]:
    """
    Safely enable or disable IMAGE_FILE_LARGE_ADDRESS_AWARE (4GB Patch) on a PE32 binary.

    Creates <exe>.backup only from an inspected valid binary (never overwriting an
    existing backup) and updates the PE header atomically.
    """
    status = inspect_pe(exe_path)
    if not status.is_valid_pe32:
        return False, status.error or "Invalid PE32 executable"

    if status.large_address_aware == enable:
        state_label = "deja applique / already enabled" if enable else "deja desactive / already disabled"
        return True, f"4GB (LARGEADDRESSAWARE) {state_label}: {exe_path.name}"

    backup_path = exe_path.with_name(f"{exe_path.name}.backup")
    if enable and not backup_path.exists():
        shutil.copy2(exe_path, backup_path)

    buf = bytearray(exe_path.read_bytes())
    pe_offset = struct.unpack_from("<I", buf, 0x3C)[0]
    char_offset = pe_offset + 22
    checksum_offset = pe_offset + 24 + 64

    new_characteristics = (
        status.characteristics | IMAGE_FILE_LARGE_ADDRESS_AWARE
        if enable
        else status.characteristics & ~IMAGE_FILE_LARGE_ADDRESS_AWARE
    )
    struct.pack_into("<H", buf, char_offset, new_characteristics)

    if status.checksum != 0:
        new_checksum = compute_pe_checksum(buf, checksum_offset)
        struct.pack_into("<I", buf, checksum_offset, new_checksum)

    atomic_write_bytes(exe_path, bytes(buf))
    action = "applique / enabled" if enable else "retire / disabled"
    return True, f"Patch 4GB (LARGEADDRESSAWARE) {action} sur {exe_path}"


def restore_4gb_backup(exe_path: Path) -> tuple[bool, str]:
    """Restore <exe>.backup over <exe> atomically after validating PE integrity."""
    backup_path = exe_path.with_name(f"{exe_path.name}.backup")
    if not backup_path.is_file():
        return False, f"Aucune sauvegarde trouvee / Backup not found: {backup_path}"

    status = inspect_pe(backup_path)
    if not status.is_valid_pe32:
        return False, f"Sauvegarde invalide / Invalid PE32 backup: {status.error}"

    atomic_write_bytes(exe_path, backup_path.read_bytes())
    return True, f"Binaire restaure depuis / Restored from: {backup_path.name}"


def get_primary_display_mode() -> DisplayModeInfo | None:
    """Query the current Windows primary display resolution and refresh rate."""
    if sys.platform != "win32":
        return None

    class DEVMODEW(ctypes.Structure):
        _fields_ = [
            ("dmDeviceName", ctypes.c_wchar * 32),
            ("dmSpecVersion", ctypes.c_uint16),
            ("dmDriverVersion", ctypes.c_uint16),
            ("dmSize", ctypes.c_uint16),
            ("dmDriverExtra", ctypes.c_uint16),
            ("dmFields", ctypes.c_uint32),
            ("dmPositionX", ctypes.c_int32),
            ("dmPositionY", ctypes.c_int32),
            ("dmDisplayOrientation", ctypes.c_uint32),
            ("dmDisplayFixedOutput", ctypes.c_uint32),
            ("dmColor", ctypes.c_int16),
            ("dmDuplex", ctypes.c_int16),
            ("dmYResolution", ctypes.c_int16),
            ("dmTTOption", ctypes.c_int16),
            ("dmCollate", ctypes.c_int16),
            ("dmFormName", ctypes.c_wchar * 32),
            ("dmLogPixels", ctypes.c_uint16),
            ("dmBitsPerPel", ctypes.c_uint32),
            ("dmPelsWidth", ctypes.c_uint32),
            ("dmPelsHeight", ctypes.c_uint32),
            ("dmDisplayFlags", ctypes.c_uint32),
            ("dmDisplayFrequency", ctypes.c_uint32),
            ("dmICMMethod", ctypes.c_uint32),
            ("dmICMIntent", ctypes.c_uint32),
            ("dmMediaType", ctypes.c_uint32),
            ("dmDitherType", ctypes.c_uint32),
            ("dmReserved1", ctypes.c_uint32),
            ("dmReserved2", ctypes.c_uint32),
            ("dmPanningWidth", ctypes.c_uint32),
            ("dmPanningHeight", ctypes.c_uint32),
        ]

    ENUM_CURRENT_SETTINGS = -1
    devmode = DEVMODEW()
    devmode.dmSize = ctypes.sizeof(DEVMODEW)
    if ctypes.windll.user32.EnumDisplaySettingsW(None, ENUM_CURRENT_SETTINGS, ctypes.byref(devmode)):
        return DisplayModeInfo(
            width=int(devmode.dmPelsWidth),
            height=int(devmode.dmPelsHeight),
            bpp=int(devmode.dmBitsPerPel),
            refresh_hz=int(devmode.dmDisplayFrequency),
        )
    return None


def _is_onedrive_path(path: Path) -> bool:
    parts = [p.lower() for p in path.parts]
    if any(p.startswith("onedrive") for p in parts):
        return True
    onedrive_env = os.environ.get("OneDrive") or os.environ.get("OneDriveConsumer")
    if onedrive_env:
        try:
            path.resolve().relative_to(Path(onedrive_env).resolve())
            return True
        except ValueError:
            pass
    return False


def discover_windows_installs(extra_dirs: list[Path] | None = None) -> list[Path]:
    """Locate Sims 2 executables across Windows standard directories and Registry."""
    candidates: list[Path] = []
    search_roots: list[Path] = list(extra_dirs or [])

    for env_var in ("ProgramFiles(x86)", "ProgramFiles"):
        base = os.environ.get(env_var)
        if not base:
            continue
        base_path = Path(base)
        for sub in (
            "EA Games",
            "Origin Games",
            "Electronic Arts",
            "EA",
            "Mr DJ",
            Path("Steam") / "steamapps" / "common",
        ):
            target = base_path / sub
            if target.is_dir():
                search_roots.append(target)

    if sys.platform == "win32":
        try:
            import winreg

            reg_paths = [
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\EA GAMES\The Sims 2"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\EA GAMES\The Sims 2 Fun with Pets Collection"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\EA GAMES\The Sims 2"),
            ]
            for hive, subkey in reg_paths:
                try:
                    with winreg.OpenKey(hive, subkey) as key:
                        for val_name in ("Install Dir", "DisplayName"):
                            try:
                                val, _ = winreg.QueryValueEx(key, val_name)
                                p = Path(str(val))
                                if p.is_dir():
                                    search_roots.append(p)
                            except OSError:
                                pass
                except OSError:
                    pass
        except ImportError:
            pass

    seen: set[Path] = set()
    for root in search_roots:
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            depth = len(Path(dirpath).relative_to(root).parts)
            # Keep scan fast: only descend into Sims 2 directories beyond depth 1
            if depth == 0:
                dirnames[:] = [d for d in dirnames if "sims" in d.lower() or "ea" in d.lower() or "ts2" in d.lower() or len(search_roots) <= 2]
            elif depth > 4:
                dirnames[:] = []
                continue
            for fname in filenames:
                if fname in KNOWN_EXE_NAMES:
                    resolved = (Path(dirpath) / fname).resolve()
                    if resolved not in seen:
                        seen.add(resolved)
                        candidates.append(resolved)

    return sorted(candidates)


def discover_save_folders(extra_roots: list[Path] | None = None) -> list[SaveFolderReport]:
    """Find The Sims 2 user save folders under Documents/EA Games (including OneDrive)."""
    doc_roots: list[Path] = list(extra_roots or [])
    userprofile = Path(os.environ.get("USERPROFILE", str(Path.home())))

    for candidate in (
        userprofile / "Documents",
        userprofile / "OneDrive" / "Documents",
        Path(os.environ["OneDrive"]) / "Documents" if os.environ.get("OneDrive") else None,
        Path(os.environ["OneDriveConsumer"]) / "Documents" if os.environ.get("OneDriveConsumer") else None,
    ):
        if candidate and candidate.is_dir() and candidate not in doc_roots:
            doc_roots.append(candidate)

    reports: list[SaveFolderReport] = []
    seen: set[Path] = set()

    for doc_root in doc_roots:
        ea_dir = doc_root / "EA Games"
        if not ea_dir.is_dir():
            continue
        for entry in sorted(ea_dir.iterdir()):
            if not entry.is_dir() or "sims 2" not in entry.name.lower():
                continue
            resolved = entry.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)

            caches = [name for name in WINDOWS_CACHE_FILES if (resolved / name).is_file()]
            userprops = resolved / "Config" / "userProps.xml"
            mode_val = read_active_display_mode(userprops) if userprops.is_file() else None
            reports.append(
                SaveFolderReport(
                    path=resolved,
                    inside_onedrive=_is_onedrive_path(resolved),
                    caches_present=caches,
                    userprops_path=userprops if userprops.is_file() else None,
                    active_display_mode=mode_val,
                )
            )
    return reports


def read_active_display_mode(userprops_path: Path) -> str | None:
    """Extract activeDeviceDisplayMode from userProps.xml if present."""
    try:
        tree = ET.parse(userprops_path)
    except (ET.ParseError, OSError):
        return None
    for elem in tree.getroot().iter():
        if elem.attrib.get("key") == "activeDeviceDisplayMode":
            return (elem.text or "").strip()
    return None


def fix_userprops_display_mode(
    userprops_path: Path,
    target_mode: str | None = None,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """
    Safely back up userProps.xml and update activeDeviceDisplayMode to a valid 60 Hz mode.
    """
    if not userprops_path.is_file():
        return False, f"Fichier introuvable / File not found: {userprops_path}"

    raw_text = userprops_path.read_text(encoding="utf-8", errors="replace")
    pattern = re.compile(
        r'(<AnyString\b[^>]*\bkey="activeDeviceDisplayMode"[^>]*>)([^<]*)(</AnyString>)'
    )
    match = pattern.search(raw_text)
    if not match:
        return True, f"Aucune cle activeDeviceDisplayMode bloquee dans {userprops_path.name}"

    if target_mode is None:
        disp = get_primary_display_mode()
        if disp:
            hz = 60 if disp.refresh_hz > 60 or disp.refresh_hz == 0 else disp.refresh_hz
            target_mode = f"{disp.width}x{disp.height}x{disp.bpp or 32}x{hz}"
        else:
            target_mode = "1920x1080x32x60"

    old_mode = match.group(2).strip()
    if old_mode == target_mode:
        return True, f"activeDeviceDisplayMode deja regle sur {target_mode}"

    if dry_run:
        return True, f"[DRY-RUN] {userprops_path}: {old_mode} -> {target_mode}"

    backup = userprops_path.with_name(f"{userprops_path.name}.backup")
    if not backup.exists():
        shutil.copy2(userprops_path, backup)

    updated = pattern.sub(rf"\g<1>{target_mode}\g<3>", raw_text, count=1)
    atomic_write_bytes(userprops_path, updated.encode("utf-8"))
    return True, f"userProps.xml mis a jour ({old_mode} -> {target_mode}), backup: {backup.name}"


def clean_windows_caches(
    save_dir: Path,
    include_thumbnails: bool = False,
    dry_run: bool = False,
) -> list[Path]:
    """Delete corrupted cache files in a Windows Sims 2 save directory."""
    removed: list[Path] = []
    for name in WINDOWS_CACHE_FILES:
        target = save_dir / name
        if target.is_file():
            if not dry_run:
                target.unlink()
            removed.append(target)

    if include_thumbnails:
        thumb_dir = save_dir / "Thumbnails"
        if thumb_dir.is_dir():
            for pkg in sorted(thumb_dir.glob("*.package")):
                if not dry_run:
                    pkg.unlink()
                removed.append(pkg)
    return removed


def run_scan(extra_exe_dirs: list[Path] | None = None, extra_doc_roots: list[Path] | None = None) -> int:
    """Run a read-only Windows diagnostics report and print results."""
    print("========================================================================")
    print("  Sims 2 Crash Patch — Windows Edition Diagnostic (Standalone PC)       ")
    print("========================================================================")

    disp = get_primary_display_mode()
    if disp:
        hz_warn = " [!] > 60 Hz: risque de physique/UI acceleree -> capper a 60 FPS!" if disp.refresh_hz > 60 else " [OK]"
        print(f"[Ecran] Mode actif : {disp.width}x{disp.height} ({disp.bpp}-bit) @ {disp.refresh_hz} Hz{hz_warn}")
    else:
        print("[Ecran] Mode d'affichage non disponible (hors session Windows GUI).")

    installs = discover_windows_installs(extra_exe_dirs)
    print(f"\n[Executables trouves] {len(installs)}")
    if not installs:
        print("  (Aucune installation Sims 2 detectee dans Program Files / Registre.)")
        print("  Astuce : si vous avez seulement l'ISO dans Downloads, montez/installez-la")
        print("  ou passez --exe <chemin> pour inspecter un binaire precis.")
    for exe in installs:
        st = inspect_pe(exe)
        laa_txt = "4GB OK (LAA actif)" if st.large_address_aware else "NON PATCHE 2GB (LAA absent)"
        addons = [name for name in COMMUNITY_ADDONS if (exe.parent / name).is_file()]
        addons_txt = f" | Addons: {', '.join(addons)}" if addons else ""
        print(f"  - {exe} -> {laa_txt}{addons_txt}")

    saves = discover_save_folders(extra_doc_roots)
    print(f"\n[Dossiers de sauvegardes Documents\\EA Games] {len(saves)}")
    if not saves:
        print("  (Aucun dossier de sauvegardes detecte.)")
    for rep in saves:
        od_warn = " [!] SYNCHRO ONEDRIVE DETECTEE (risque de crash/corruption!)" if rep.inside_onedrive else " [OK hors OneDrive]"
        print(f"  - {rep.path}{od_warn}")
        print(f"    Caches presents : {', '.join(rep.caches_present) if rep.caches_present else 'aucun (propre)'}")
        if rep.userprops_path:
            print(f"    userProps.xml   : activeDeviceDisplayMode = {rep.active_display_mode or 'non defini'}")

    print("\nNote : cet outil Windows est 100 % separe du patch macOS (root/*.command).")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sims 2 Crash Patch — Windows Edition Toolkit (non-Mac)"
    )
    sub = parser.add_subparsers(dest="command")

    p_scan = sub.add_parser("scan", help="Diagnostic complet (lecture seule)")
    p_scan.add_argument("--extra-dir", action="append", type=Path, default=[])

    p_clean = sub.add_parser("clean-cache", help="Purger les fichiers cache corrompus")
    p_clean.add_argument("--save-dir", type=Path, help="Dossier cible (sinon auto-detecte)")
    p_clean.add_argument("--include-thumbnails", action="store_true")
    p_clean.add_argument("--dry-run", action="store_true")

    p_4gb = sub.add_parser("patch-4gb", help="Activer le flag 4GB (LARGEADDRESSAWARE) avec backup")
    p_4gb.add_argument("--exe", type=Path, required=True)

    p_restore = sub.add_parser("restore-4gb", help="Restaurer <exe>.backup")
    p_restore.add_argument("--exe", type=Path, required=True)

    p_up = sub.add_parser("fix-userprops", help="Reparer activeDeviceDisplayMode dans userProps.xml")
    p_up.add_argument("--userprops", type=Path, required=True)
    p_up.add_argument("--mode", type=str, default=None)
    p_up.add_argument("--dry-run", action="store_true")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    cmd = args.command or "scan"

    if cmd == "scan":
        return run_scan(extra_exe_dirs=getattr(args, "extra_dir", []))

    if cmd == "clean-cache":
        targets = [args.save_dir] if args.save_dir else [r.path for r in discover_save_folders()]
        if not targets:
            print("[-] Aucun dossier de sauvegardes trouve.")
            return 1
        for folder in targets:
            removed = clean_windows_caches(folder, include_thumbnails=args.include_thumbnails, dry_run=args.dry_run)
            prefix = "[DRY-RUN]" if args.dry_run else "[+]"
            print(f"{prefix} {folder}: {len(removed)} fichier(s) cache supprime(s)")
            for item in removed:
                print(f"    - {item.name}")
        return 0

    if cmd == "patch-4gb":
        ok, msg = set_large_address_aware(args.exe, enable=True)
        print(("[+] " if ok else "[-] ") + msg)
        return 0 if ok else 1

    if cmd == "restore-4gb":
        ok, msg = restore_4gb_backup(args.exe)
        print(("[+] " if ok else "[-] ") + msg)
        return 0 if ok else 1

    if cmd == "fix-userprops":
        ok, msg = fix_userprops_display_mode(args.userprops, target_mode=args.mode, dry_run=args.dry_run)
        print(("[+] " if ok else "[-] ") + msg)
        return 0 if ok else 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
