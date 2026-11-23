#!/usr/bin/env python3
"""
Cross-platform unit & integration test suite for sims2-crash-patch.

Tests both:
  1. macOS v1.3.0 patch/restore/cache integrity (EOLs, syntax, Perl binary & userProps engines, CC/maxfiles, UX)
  2. Windows Special Edition toolkit & trackpad state machine (PE32 4GB patch, userProps, caches, camera)
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from scripts import verify_and_package as vp
from windows import sims2_trackpad_camera as tc
from windows import sims2_windows_toolkit as wt

# Exact v1.2.1 binary fingerprints from patch_sims2.command
ORIG1 = bytes.fromhex("f20f1045d0f2440f2cf84889df")
REPL1 = bytes.fromhex("41bf3c000000909090904889df")
ORIG2 = bytes.fromhex("41bf3c000000440f45f8c70300000000")
REPL2 = bytes.fromhex("41bf3c00000090909090c70300000000")


def make_synthetic_pe32(characteristics: int = 0x0102, checksum: int = 0x12345678) -> bytes:
    """Create a minimal valid 32-bit x86 PE binary header in memory."""
    buf = bytearray(512)
    struct.pack_into("<H", buf, 0, 0x5A4D)  # MZ
    pe_off = 0x80
    struct.pack_into("<I", buf, 0x3C, pe_off)
    buf[pe_off : pe_off + 4] = b"PE\x00\x00"
    struct.pack_into("<H", buf, pe_off + 4, 0x014C)  # i386
    struct.pack_into("<H", buf, pe_off + 22, characteristics)
    struct.pack_into("<H", buf, pe_off + 24, 0x010B)  # PE32 optional header
    struct.pack_into("<I", buf, pe_off + 24 + 64, checksum)
    return bytes(buf)


class TestMacScriptsIntegrity(unittest.TestCase):
    def test_mac_scripts_have_lf_only(self) -> None:
        errors = vp.verify_mac_scripts()
        self.assertEqual(errors, [], f"Mac script verification errors: {errors}")

    def test_release_packager_sets_unix_executable_bits(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            mac_zip, win_zip = vp.package_releases("v1.2.1-test", Path(tmp))
            self.assertTrue(mac_zip.is_file())
            self.assertTrue(win_zip.is_file())

            root_dir = "sims2-crash-patch-v1.2.1-test"
            with zipfile.ZipFile(mac_zip, "r") as zf:
                names = set(zf.namelist())
                self.assertEqual(
                    names,
                    {
                        f"{root_dir}/patch_sims2.command",
                        f"{root_dir}/clean_sims2_cache.command",
                        f"{root_dir}/restore_sims2.command",
                        f"{root_dir}/README.txt",
                        f"{root_dir}/LICENSE",
                        f"{root_dir}/trackpad_mod/libsims2_trackpad.dylib",
                        f"{root_dir}/trackpad_mod/sims2_trackpad.m",
                        f"{root_dir}/trackpad_mod/build_trackpad.sh",
                    },
                )
                for info in zf.infolist():
                    raw = zf.read(info.filename)
                    if not info.filename.endswith(".dylib"):
                        self.assertNotIn(b"\r", raw, f"CR found inside {info.filename} in release zip")
                    mode = (info.external_attr >> 16) & 0o777
                    if info.filename.endswith((".command", ".sh", ".dylib")):
                        self.assertEqual(mode, 0o755, f"{info.filename} must be 0755 in zip")
                    else:
                        self.assertEqual(mode, 0o644)

    def test_release_zip_root_folder_matches_exact_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            for raw_ver, expected_ver in (("v1.5.0", "v1.5.0"), ("1.5.0", "v1.5.0"), ("v2.3.4-beta1", "v2.3.4-beta1")):
                mac_zip, win_zip = vp.package_releases(raw_ver, tmp_dir)
                expected_mac_root = f"sims2-crash-patch-{expected_ver}"
                expected_win_root = f"sims2-crash-patch-windows-{expected_ver}"
                self.assertEqual(mac_zip.name, f"{expected_mac_root}.zip")
                self.assertEqual(win_zip.name, f"{expected_win_root}.zip")

                with zipfile.ZipFile(mac_zip, "r") as zf:
                    mac_names = zf.namelist()
                    self.assertTrue(mac_names)
                    mac_roots = {name.split("/", 1)[0] for name in mac_names}
                    self.assertEqual(mac_roots, {expected_mac_root})
                    self.assertNotIn("sims2-crash-patch-v1", mac_roots)
                    self.assertTrue(all(name.startswith(f"{expected_mac_root}/") for name in mac_names))

                with zipfile.ZipFile(win_zip, "r") as zf:
                    win_names = zf.namelist()
                    self.assertTrue(win_names)
                    win_roots = {name.split("/", 1)[0] for name in win_names}
                    self.assertEqual(win_roots, {expected_win_root})
                    self.assertNotIn("sims2-crash-patch-v1", win_roots)
                    self.assertTrue(all(name.startswith(f"{expected_win_root}/") for name in win_names))

    def _extract_binary_patch_perl(self) -> str:
        patch_blocks = vp.extract_perl_blocks((ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8"))
        self.assertEqual(len(patch_blocks), 2)
        return next(b for b in patch_blocks if "f20f1045d0f2440f2cf84889df" in b)

    def test_perl_patch_and_restore_engines_on_synthetic_binary(self) -> None:
        perl_bin = vp.find_perl()
        if not perl_bin:
            self.skipTest("perl not available on PATH")

        patch_pl = self._extract_binary_patch_perl()

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            pl_path = tmp_dir / "patch.pl"
            pl_path.write_text(patch_pl, encoding="utf-8")

            exe = tmp_dir / "Sims2XP_Exe"
            bak = tmp_dir / "Sims2XP_Exe.backup"
            alt_bak = tmp_dir / "Sims2XP_Exe.backup_original"

            pristine_bytes = b"\x00" * 64 + ORIG1 + b"\x90" * 32 + ORIG2 + b"\xff" * 64
            exe.write_bytes(pristine_bytes)

            # First run: creates pristine backup + patches binary
            res1 = subprocess.run([perl_bin, str(pl_path), str(exe), str(bak), str(alt_bak)], capture_output=True, text=True)
            self.assertEqual(res1.returncode, 0, res1.stderr)
            self.assertTrue(bak.is_file())
            self.assertEqual(bak.read_bytes(), pristine_bytes)
            patched = exe.read_bytes()
            self.assertIn(REPL1, patched)
            self.assertIn(REPL2, patched)
            self.assertNotIn(ORIG1, patched)
            self.assertNotIn(ORIG2, patched)

            # Second run: strictly idempotent
            res2 = subprocess.run([perl_bin, str(pl_path), str(exe), str(bak), str(alt_bak)], capture_output=True, text=True)
            self.assertEqual(res2.returncode, 0, res2.stderr)
            self.assertEqual(exe.read_bytes(), patched)
            self.assertEqual(bak.read_bytes(), pristine_bytes)

            # Ambiguous/corrupt binary must abort cleanly without modifying file
            bad_exe = tmp_dir / "BadExe"
            bad_exe.write_bytes(b"\xCC" * 256)
            res_bad = subprocess.run([perl_bin, str(pl_path), str(bad_exe), str(tmp_dir / "bad.bak"), str(alt_bak)], capture_output=True, text=True)
            self.assertNotEqual(res_bad.returncode, 0)
            self.assertFalse((tmp_dir / "bad.bak").exists())
            self.assertEqual(bad_exe.read_bytes(), b"\xCC" * 256)

            # Verify restore_sims2.command's is_pristine_binary Perl logic
            restore_blocks = vp.extract_perl_blocks((ROOT_DIR / "restore_sims2.command").read_text(encoding="utf-8"))
            self.assertEqual(len(restore_blocks), 1)
            restore_pl = tmp_dir / "check_pristine.pl"
            restore_pl.write_text(restore_blocks[0], encoding="utf-8")

            ok_res = subprocess.run([perl_bin, str(restore_pl), str(bak)], capture_output=True, text=True)
            self.assertEqual(ok_res.returncode, 0)

            bad_bak = tmp_dir / "PatchedBak"
            bad_bak.write_bytes(patched)
            fail_res = subprocess.run([perl_bin, str(restore_pl), str(bad_bak)], capture_output=True, text=True)
            self.assertNotEqual(fail_res.returncode, 0)

    def _run_bash_lib(self, script_name: str, body: str, *args: str) -> subprocess.CompletedProcess[str]:
        bash_bin = vp.find_bash()
        if not bash_bin:
            self.skipTest("bash not available on PATH")
        env = dict(os.environ)
        env["SIMS2_LIB_ONLY"] = "1"
        cmd = [bash_bin, "-c", f'set -u; source "./{script_name}"; {body}', "_", *args]
        return subprocess.run(
            cmd,
            cwd=str(ROOT_DIR),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def test_a1_dir_has_real_entries_ignores_finder_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            missing = base / "DoesNotExist"
            empty_dir = base / "Empty"
            meta_only = base / "MetaOnly"
            real_dir = base / "RealData"
            empty_dir.mkdir()
            meta_only.mkdir()
            (meta_only / ".DS_Store").write_bytes(b"finder")
            (meta_only / ".localized").write_bytes(b"")
            (meta_only / "._AppleDouble").write_bytes(b"ad")
            real_dir.mkdir()
            (real_dir / ".DS_Store").write_bytes(b"finder")
            (real_dir / "Neighborhoods").mkdir()

            r_missing = self._run_bash_lib("patch_sims2.command", 'dir_has_real_entries "$1"', missing.as_posix())
            self.assertNotEqual(r_missing.returncode, 0)

            r_empty = self._run_bash_lib("patch_sims2.command", 'dir_has_real_entries "$1"', empty_dir.as_posix())
            self.assertNotEqual(r_empty.returncode, 0)

            r_meta = self._run_bash_lib("patch_sims2.command", 'dir_has_real_entries "$1"', meta_only.as_posix())
            self.assertNotEqual(r_meta.returncode, 0, "Finder metadata files must not trigger BACKUP mode")

            r_real = self._run_bash_lib("patch_sims2.command", 'dir_has_real_entries "$1"', real_dir.as_posix())
            self.assertEqual(r_real.returncode, 0)

    def test_a2_osascript_capture_and_default_branches(self) -> None:
        patch_text = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")
        clean_text = (ROOT_DIR / "clean_sims2_cache.command").read_text(encoding="utf-8")
        self.assertIn('/usr/bin/osascript - "$dest_folder_name" 2>&1', patch_text)
        self.assertIn('MIGRATE_RESULT="$(run_finder_migration_osascript "$DEST_FOLDER_NAME")"', patch_text)
        self.assertIn("/usr/bin/osascript 2>&1", patch_text)
        self.assertIn("/usr/bin/osascript 2>&1", clean_text)

        # Empty stdout with non-zero rc AND unexpected rc=0 output must both populate MIGRATION_STATUS
        # and flag MIGRATION_FAILED=1 so main() does not invite the user to launch an empty profile.
        for raw_out, rc in (("", 1), ("UNEXPECTED_TOKEN", 0)):
            r1 = self._run_bash_lib(
                "patch_sims2.command",
                'handle_migration_result "$1" "$2" "DIRECT" 0 "The Sims 2"; printf "STATUS=%s\\nFAILED=%s\\n" "$MIGRATION_STATUS" "$MIGRATION_FAILED"',
                raw_out,
                str(rc),
            )
            self.assertEqual(r1.returncode, 0)
            status_lines = [ln for ln in r1.stdout.splitlines() if ln.startswith("STATUS=")]
            self.assertEqual(len(status_lines), 1)
            self.assertGreater(len(status_lines[0]), len("STATUS="))
            self.assertIn("FAILED=1", r1.stdout)

        # TCC -1743 Finder Automation denial must surface explicit System Settings guidance and flag MIGRATION_FAILED=1
        r2 = self._run_bash_lib(
            "patch_sims2.command",
            'handle_migration_result "execution error: Not authorized to send Apple events to Finder. (-1743)" 1 "DIRECT" 0 "The Sims 2"; printf "STATUS=%s\\nFAILED=%s\\n" "$MIGRATION_STATUS" "$MIGRATION_FAILED"',
        )
        self.assertEqual(r2.returncode, 0)
        self.assertIn("Automatisation", r2.stdout)
        self.assertIn("-1743", r2.stdout)
        self.assertIn("FAILED=1", r2.stdout)

        # Successful or no-op migration states must keep MIGRATION_FAILED=0 (and reset any prior failure state)
        for ok_token in ("OK", "NO_SOURCE"):
            r_ok = self._run_bash_lib(
                "patch_sims2.command",
                'MIGRATION_FAILED=1; handle_migration_result "$1" 0 "DIRECT" 0 "The Sims 2"; printf "FAILED=%s\\n" "$MIGRATION_FAILED"',
                ok_token,
            )
            self.assertEqual(r_ok.returncode, 0)
            self.assertIn("FAILED=0", r_ok.stdout)

        r3 = self._run_bash_lib(
            "patch_sims2.command",
            'handle_sandbox_cache_result "" 1; printf "CACHE=%s\\n" "$CACHE_STATUS"',
        )
        self.assertEqual(r3.returncode, 0)
        cache_line = [ln for ln in r3.stdout.splitlines() if ln.startswith("CACHE=")][0]
        self.assertGreater(len(cache_line), len("CACHE="))

        r4 = self._run_bash_lib(
            "clean_sims2_cache.command",
            'handle_clean_sandbox_result "Not authorized to send Apple events (-1743)" 1; printf "FAILED=%s\\n" "$SANDBOX_FAILED"',
        )
        self.assertEqual(r4.returncode, 0)
        self.assertIn("FAILED=1", r4.stdout)
        self.assertIn("Automatisation", r4.stdout)

        r5 = self._run_bash_lib(
            "clean_sims2_cache.command",
            'handle_clean_sandbox_result "UNEXPECTED" 0; printf "FAILED=%s\\n" "$SANDBOX_FAILED"',
        )
        self.assertEqual(r5.returncode, 0)
        self.assertIn("FAILED=1", r5.stdout)

    def test_a3_a7_user_context_and_no_unused_file_copy(self) -> None:
        patch_text = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")
        clean_text = (ROOT_DIR / "clean_sims2_cache.command").read_text(encoding="utf-8")

        self.assertNotIn("File::Copy", patch_text)
        self.assertIn("launchctl asuser", patch_text)
        self.assertIn("launchctl asuser", clean_text)
        self.assertIn('REAL_HOME/Library/Application Support/Aspyr/The Sims 2', clean_text)
        self.assertNotIn('"$HOME/Library/Application Support/Aspyr/The Sims 2"', clean_text)

        if sys.platform == "darwin":
            for script in ("patch_sims2.command", "clean_sims2_cache.command"):
                res = self._run_bash_lib(
                    script,
                    'resolve_real_user && printf "USER=%s\\nUID=%s\\nHOME=%s\\n" "$REAL_USER" "$REAL_UID" "$REAL_HOME"',
                )
                self.assertEqual(res.returncode, 0, res.stderr or res.stdout)
                self.assertNotIn("USER=root", res.stdout)
                self.assertNotIn("HOME=/var/root", res.stdout)

    def test_a4_perl_write_atomic_cleans_temp_on_failure(self) -> None:
        perl_bin = vp.find_perl()
        if not perl_bin:
            self.skipTest("perl not available on PATH")

        patch_pl = self._extract_binary_patch_perl()

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            exe = tmp_dir / "Sims2XP_Exe"
            bak = tmp_dir / "Sims2XP_Exe.backup"
            alt_bak = tmp_dir / "Sims2XP_Exe.backup_original"
            pristine_bytes = b"\x00" * 64 + ORIG1 + b"\x90" * 32 + ORIG2 + b"\xff" * 64
            exe.write_bytes(pristine_bytes)

            # Force both chmod() and rename() failures via CORE::GLOBAL overrides
            for hook_name, hook_code in (
                ("chmod", "BEGIN { *CORE::GLOBAL::chmod = sub { $! = 1; return 0; }; }\n"),
                ("rename", "BEGIN { *CORE::GLOBAL::rename = sub { $! = 28; return 0; }; }\n"),
            ):
                failing_pl = tmp_dir / f"fail_{hook_name}.pl"
                failing_pl.write_text(hook_code + patch_pl, encoding="utf-8")
                res = subprocess.run([perl_bin, str(failing_pl), str(exe), str(bak), str(alt_bak)], capture_output=True, text=True)
                self.assertNotEqual(res.returncode, 0, f"Expected failure for {hook_name}")
                leftovers = [p.name for p in tmp_dir.iterdir() if ".tmp." in p.name]
                self.assertEqual(leftovers, [], f"Temp files left behind on {hook_name} failure: {leftovers}")

    def test_a5_perl_repairs_corrupted_backup_from_pristine_exe(self) -> None:
        perl_bin = vp.find_perl()
        if not perl_bin:
            self.skipTest("perl not available on PATH")

        patch_pl = self._extract_binary_patch_perl()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            pl_path = tmp_dir / "patch.pl"
            pl_path.write_text(patch_pl, encoding="utf-8")

            exe = tmp_dir / "Sims2XP_Exe"
            bak = tmp_dir / "Sims2XP_Exe.backup"
            alt_bak = tmp_dir / "Sims2XP_Exe.backup_original"

            pristine_bytes = b"\x00" * 64 + ORIG1 + b"\x90" * 32 + ORIG2 + b"\xff" * 64
            already_patched = b"\x00" * 64 + REPL1 + b"\x90" * 32 + REPL2 + b"\xff" * 64

            exe.write_bytes(pristine_bytes)
            bak.write_bytes(already_patched)

            res = subprocess.run([perl_bin, str(pl_path), str(exe), str(bak), str(alt_bak)], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(bak.read_bytes(), pristine_bytes, "Corrupted .backup was not repaired from pristine exe")
            self.assertEqual(exe.read_bytes(), already_patched)

    def test_a6_codesign_verify_and_detritus_cleanup(self) -> None:
        for script_name in ("patch_sims2.command", "restore_sims2.command"):
            text = (ROOT_DIR / script_name).read_text(encoding="utf-8")
            self.assertIn("codesign --verify --deep --strict", text)
            self.assertIn("com.apple.FinderInfo", text)
            self.assertIn("com.apple.ResourceFork", text)

        if sys.platform != "darwin":
            self.skipTest("macOS codesign/xattr integration check only")

        with tempfile.TemporaryDirectory() as tmp:
            app_dir = Path(tmp) / "Dummy.app"
            macos_dir = app_dir / "Contents" / "MacOS"
            macos_dir.mkdir(parents=True)
            exe = macos_dir / "DummyExe"
            exe.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            exe.chmod(0o755)
            (app_dir / "Contents" / "Info.plist").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0"><dict>'
                '<key>CFBundleExecutable</key><string>DummyExe</string>'
                '<key>CFBundleIdentifier</key><string>com.example.dummy</string>'
                '</dict></plist>\n',
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/xattr", "-w", "com.apple.appstore.metadata", "keepme", str(app_dir)], check=True)

            for script in ("patch_sims2.command", "restore_sims2.command"):
                subprocess.run(["/usr/bin/xattr", "-w", "com.apple.ResourceFork", "fake_res_fork", str(exe)], check=True)
                res = self._run_bash_lib(script, 'sign_and_verify_app "$1"', app_dir.as_posix())
                self.assertEqual(res.returncode, 0, res.stderr or res.stdout)
                self.assertIn("detritus", res.stdout)

            verify_res = subprocess.run(
                ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app_dir)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(verify_res.returncode, 0, verify_res.stderr)

            xattr_out = subprocess.run(["/usr/bin/xattr", "-l", str(app_dir)], capture_output=True, text=True, check=True)
            self.assertIn("com.apple.appstore.metadata", xattr_out.stdout)

            # Broken bundle (missing Info.plist) must fail sign_and_verify_app cleanly
            broken_app = Path(tmp) / "Broken.app"
            (broken_app / "Contents" / "MacOS").mkdir(parents=True)
            res_fail = self._run_bash_lib("patch_sims2.command", 'sign_and_verify_app "$1"', broken_app.as_posix())
            self.assertNotEqual(res_fail.returncode, 0)

    def test_v13_userprops_xml_repair_and_backup_idempotency(self) -> None:
        if not vp.find_perl():
            self.skipTest("perl not available on PATH")

        sample_tmpl = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<cGZPersistDBSegment>\n"
            '  <AnyString key="activeDeviceDisplayMode" type="0x0c000000">{mode}</AnyString>\n'
            "</cGZPersistDBSegment>\n"
        )

        for script in ("patch_sims2.command", "clean_sims2_cache.command"):
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)

                # 1. Missing userProps.xml must initialize activeDeviceDisplayMode to native resolution without .backup
                missing_xml = base / "missing.xml"
                r_missing = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169" 0',
                    missing_xml.as_posix(),
                )
                self.assertEqual(r_missing.returncode, 0, r_missing.stderr or r_missing.stdout)
                self.assertTrue(missing_xml.exists())
                self.assertIn('key="activeDeviceDisplayMode"', missing_xml.read_text(encoding="utf-8"))
                self.assertIn("1800x1169x32x60", missing_xml.read_text(encoding="utf-8"))
                self.assertFalse(missing_xml.with_suffix(".xml.backup").exists())

                # 2. Valid 60 Hz mode in supported list must remain untouched without creating .backup
                valid_xml = base / "valid.xml"
                valid_text = sample_tmpl.format(mode="1800x1169x32x60")
                valid_xml.write_text(valid_text, encoding="utf-8")
                r_valid = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1280x800" 0',
                    valid_xml.as_posix(),
                )
                self.assertEqual(r_valid.returncode, 0, r_valid.stderr or r_valid.stdout)
                self.assertEqual(valid_xml.read_text(encoding="utf-8"), valid_text)
                self.assertFalse(Path(str(valid_xml) + ".backup").exists())

                # 3. Supported resolution at 120 Hz preserves 1280x800, locks x32x60, creates .backup once
                hz_xml = base / "hz120.xml"
                orig_hz = sample_tmpl.format(mode="1280x800x32x120")
                hz_xml.write_text(orig_hz, encoding="utf-8")
                r_hz = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1280x800" 0',
                    hz_xml.as_posix(),
                )
                self.assertEqual(r_hz.returncode, 0, r_hz.stderr or r_hz.stdout)
                self.assertIn(">1280x800x32x60<", hz_xml.read_text(encoding="utf-8"))
                hz_bak = Path(str(hz_xml) + ".backup")
                self.assertTrue(hz_bak.is_file())
                self.assertEqual(hz_bak.read_text(encoding="utf-8"), orig_hz)

                # Subsequent force_reset=1 resets resolution to current display WITHOUT overwriting .backup
                r_force = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1280x800" 1',
                    hz_xml.as_posix(),
                )
                self.assertEqual(r_force.returncode, 0, r_force.stderr or r_force.stdout)
                self.assertIn(">1800x1169x32x60<", hz_xml.read_text(encoding="utf-8"))
                self.assertEqual(hz_bak.read_text(encoding="utf-8"), orig_hz)

                # 4. Unplugged external monitor resolution (e.g. 3840x2160x32x60) falls back to live CUR
                ext_xml = base / "external.xml"
                orig_ext = sample_tmpl.format(mode="3840x2160x32x60")
                ext_xml.write_text(orig_ext, encoding="utf-8")
                r_ext = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1280x800" 0',
                    ext_xml.as_posix(),
                )
                self.assertEqual(r_ext.returncode, 0, r_ext.stderr or r_ext.stdout)
                self.assertIn(">1800x1169x32x60<", ext_xml.read_text(encoding="utf-8"))
                self.assertEqual(Path(str(ext_xml) + ".backup").read_text(encoding="utf-8"), orig_ext)

                # 5. Malformed display mode & missing key handling
                bad_xml = base / "malformed.xml"
                bad_xml.write_text(sample_tmpl.format(mode="broken_value"), encoding="utf-8")
                r_bad = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169" 0',
                    bad_xml.as_posix(),
                )
                self.assertEqual(r_bad.returncode, 0)
                self.assertIn(">1800x1169x32x60<", bad_xml.read_text(encoding="utf-8"))

                # 6a. Known Sims 2 root XML without activeDeviceDisplayMode gets initialized to native resolution
                nokey_xml = base / "nokey.xml"
                nokey_text = '<?xml version="1.0"?><cGZPersistDBSegment></cGZPersistDBSegment>\n'
                nokey_xml.write_text(nokey_text, encoding="utf-8")
                r_nokey = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169" 0',
                    nokey_xml.as_posix(),
                )
                self.assertEqual(r_nokey.returncode, 0, r_nokey.stderr or r_nokey.stdout)
                nokey_updated = nokey_xml.read_text(encoding="utf-8")
                self.assertIn('key="activeDeviceDisplayMode"', nokey_updated)
                self.assertIn("1800x1169x32x60", nokey_updated)
                self.assertTrue(Path(str(nokey_xml) + ".backup").exists())
                self.assertEqual(Path(str(nokey_xml) + ".backup").read_text(encoding="utf-8"), nokey_text)

                # 6b. Unrecognized XML without known root tag must stay untouched (NO_KEY, no .backup)
                unknown_xml = base / "unknown.xml"
                unknown_text = '<?xml version="1.0"?><UnknownRoot></UnknownRoot>\n'
                unknown_xml.write_text(unknown_text, encoding="utf-8")
                r_unknown = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169" 0',
                    unknown_xml.as_posix(),
                )
                self.assertEqual(r_unknown.returncode, 0, r_unknown.stderr or r_unknown.stdout)
                self.assertEqual(unknown_xml.read_text(encoding="utf-8"), unknown_text)
                self.assertFalse(Path(str(unknown_xml) + ".backup").exists())

    def test_v13_count_cc_and_maxfiles_warnings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dl = Path(tmp) / "Downloads"
            sub = dl / "Hair"
            sub.mkdir(parents=True)
            (dl / "mod1.package").write_bytes(b"DBPF")
            (sub / "mod2.package").write_bytes(b"DBPF")
            (sub / "._mod2.package").write_bytes(b"appledouble")
            (dl / "unpacked.zip").write_bytes(b"PK")
            (sub / "archive.rar").write_bytes(b"Rar!")

            for script in ("patch_sims2.command", "clean_sims2_cache.command"):
                res = self._run_bash_lib(
                    script,
                    'count_cc_and_check_maxfiles "$1" 0',
                    dl.as_posix(),
                )
                self.assertEqual(res.returncode, 0, res.stderr or res.stdout)
                self.assertIn("2 fichier(s) .package", res.stdout)
                self.assertIn("2 archive(s) (.zip/.rar/.7z)", res.stdout)

    def test_v13_locate_app_bundle_and_managed_daemon_safety(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            sys_app = base / "SysApps" / "The Sims 2.app"
            user_app = base / "UserApps" / "The Sims 2.app"
            (user_app / "Contents" / "MacOS").mkdir(parents=True)
            user_exe = user_app / "Contents" / "MacOS" / "Sims2XP_Exe"
            user_exe.write_bytes(b"dummy")

            for script in ("patch_sims2.command", "restore_sims2.command"):
                r_fallback = self._run_bash_lib(
                    script,
                    'locate_app_bundle "$1" "$2" && printf "APP=%s\\nSUDO=%s\\n" "$APP_PATH" "$APP_REQUIRES_SUDO"',
                    sys_app.as_posix(),
                    user_app.as_posix(),
                )
                self.assertEqual(r_fallback.returncode, 0, r_fallback.stderr or r_fallback.stdout)
                self.assertIn(f"APP={user_app.as_posix()}", r_fallback.stdout)
                self.assertIn("SUDO=0", r_fallback.stdout)

                (sys_app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
                (sys_app / "Contents" / "MacOS" / "Sims2XP_Exe").write_bytes(b"sys")
                r_prefer = self._run_bash_lib(
                    script,
                    'locate_app_bundle "$1" "$2" && printf "APP=%s\\n" "$APP_PATH"',
                    sys_app.as_posix(),
                    user_app.as_posix(),
                )
                self.assertEqual(r_prefer.returncode, 0)
                self.assertIn(f"APP={sys_app.as_posix()}", r_prefer.stdout)
                # Remove sys_app dummy exe before next loop iteration
                (sys_app / "Contents" / "MacOS" / "Sims2XP_Exe").unlink()

            # Managed LaunchDaemon cleanup must remove ONLY plists with our marker
            managed_plist = base / "managed.plist"
            managed_plist.write_text("<!-- Managed by sims2-crash-patch -->\n<plist/>\n", encoding="utf-8")
            foreign_plist = base / "foreign.plist"
            foreign_plist.write_text("<!-- Custom user maxfiles -->\n<plist/>\n", encoding="utf-8")

            r_clean_managed = self._run_bash_lib(
                "restore_sims2.command",
                'cleanup_managed_maxfiles_daemon "$1"',
                managed_plist.as_posix(),
            )
            self.assertEqual(r_clean_managed.returncode, 0, r_clean_managed.stderr or r_clean_managed.stdout)
            self.assertFalse(managed_plist.exists())

            r_keep_foreign = self._run_bash_lib(
                "restore_sims2.command",
                'cleanup_managed_maxfiles_daemon "$1"',
                foreign_plist.as_posix(),
            )
            self.assertEqual(r_keep_foreign.returncode, 0, r_keep_foreign.stderr or r_keep_foreign.stdout)
            self.assertTrue(foreign_plist.is_file())

            # Windows-style temporary paths must also bypass sudo under SIMS2_LIB_ONLY=1
            for script in ("patch_sims2.command", "clean_sims2_cache.command", "restore_sims2.command"):
                r_win = self._run_bash_lib(
                    script,
                    'run_privileged "C:/Users/runneradmin/AppData/Local/Temp/managed.plist" true',
                )
                self.assertEqual(r_win.returncode, 0, f"{script} Windows temp bypass failed: {r_win.stderr or r_win.stdout}")

    def test_v13_zero_clt_and_ux_docs_and_clean_menu_exit(self) -> None:
        clt_tools_rx = re.compile(r"(?<![#\w/.-])(python3|swift|git|clang|xcodebuild|objdump|cc)\b")
        for script_name in ("patch_sims2.command", "clean_sims2_cache.command", "restore_sims2.command"):
            text = (ROOT_DIR / script_name).read_text(encoding="utf-8")
            self.assertIn("Version: 1.5.0", text)
            non_comment = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith("#"))
            # Remove heredoc text/URLs isn't needed if no CLT tool word appears in code lines
            for line in non_comment.splitlines():
                if "echo" in line or "cat " in line:
                    continue
                self.assertIsNone(
                    clt_tools_rx.search(line),
                    f"Potential Xcode CLT shim invocation in {script_name}: {line}",
                )

        readme_txt = (ROOT_DIR / "README.txt").read_text(encoding="utf-8")
        readme_md = (ROOT_DIR / "README.md").read_text(encoding="utf-8")
        changelog = (ROOT_DIR / "CHANGELOG.md").read_text(encoding="utf-8")
        for doc_text in (readme_txt, readme_md):
            self.assertIn("v1.5.0", doc_text)
            self.assertIn("Gatekeeper", doc_text)
            self.assertIn("userProps.xml.backup", doc_text)
            self.assertIn("Autoriser", doc_text)
        self.assertIn("[1.5.0]", changelog)
        self.assertIn("[1.5.0-rc2]", changelog)
        self.assertIn("[1.5.0-rc1]", changelog)
        self.assertIn("[1.4.1]", changelog)
        self.assertIn("[1.4.0]", changelog)
        self.assertIn("[1.3.1]", changelog)
        self.assertIn("[1.3.0]", changelog)

        if sys.platform == "darwin":
            bash_bin = vp.find_bash()
            self.assertIsNotNone(bash_bin)
            with tempfile.TemporaryDirectory() as tmp:
                env = dict(os.environ)
                env["SIMS2_NONINTERACTIVE"] = "1"
                env["SIMS2_SKIP_RUNNING_CHECK"] = "1"
                env["SIMS2_LOG_DIR"] = tmp
                res_quit = subprocess.run(
                    [bash_bin, "./clean_sims2_cache.command"],
                    cwd=str(ROOT_DIR),
                    env=env,
                    input="4\n",
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(res_quit.returncode, 0, res_quit.stderr or res_quit.stdout)
                self.assertIn("[1]", res_quit.stdout)
                self.assertIn("[4]", res_quit.stdout)

    def test_v13_container_permission_error_and_diagnostic_logs(self) -> None:
        # 1. Container access (-5000 / autorisations requises) with existing active saves -> MIGRATION_FAILED=2 (non-blocking)
        r_soft = self._run_bash_lib(
            "patch_sims2.command",
            'handle_migration_result "$1" 0 "BACKUP" 1 "The Sims 2 (Sandbox Backup 2026-11-13)"; printf "FAILED=%s\\nKIND=%s\\nSTATUS=%s\\n" "$MIGRATION_FAILED" "$MIGRATION_ERROR_KIND" "$MIGRATION_STATUS"',
            "ERROR:Impossible d’effectuer l’opération car vous ne disposez pas des autorisations requises. (-5000)",
        )
        self.assertEqual(r_soft.returncode, 0, r_soft.stderr or r_soft.stdout)
        self.assertIn("FAILED=2", r_soft.stdout)
        self.assertIn("KIND=CONTAINER_ACCESS", r_soft.stdout)
        self.assertNotIn("Automatisation", r_soft.stdout)

        # 2. Container access (-5000) when target_nonempty=0 -> MIGRATION_FAILED=1 + CONTAINER_ACCESS + manual Finder guidance
        r_hard = self._run_bash_lib(
            "patch_sims2.command",
            'handle_migration_result "$1" 0 "DIRECT" 0 "The Sims 2"; printf "FAILED=%s\\nKIND=%s\\n" "$MIGRATION_FAILED" "$MIGRATION_ERROR_KIND"',
            "ERROR:Impossible d’effectuer l’opération car vous ne disposez pas des autorisations requises. (-5000)",
        )
        self.assertEqual(r_hard.returncode, 0, r_hard.stderr or r_hard.stdout)
        self.assertIn("FAILED=1", r_hard.stdout)
        self.assertIn("KIND=CONTAINER_ACCESS", r_hard.stdout)
        self.assertIn("Accès complet au disque", r_hard.stdout)

        # 3. Partial copy when active saves already exist -> MIGRATION_FAILED=2
        r_partial = self._run_bash_lib(
            "patch_sims2.command",
            'handle_migration_result "PARTIAL:2|Music|err (-5000)" 0 "BACKUP" 1 "Sandbox Backup"',
        )
        self.assertEqual(r_partial.returncode, 0, r_partial.stderr or r_partial.stdout)
        self.assertIn("partielle", r_partial.stdout)

        # 4. Lightweight diagnostic log creation & rotation across all 3 .command scripts
        for script in ("patch_sims2.command", "clean_sims2_cache.command", "restore_sims2.command"):
            with tempfile.TemporaryDirectory() as tmp:
                r_log = self._run_bash_lib(
                    script,
                    'REAL_USER="tester"; REAL_UID="$(id -u)"; REAL_HOME="$1"; SIMS2_LOG_DIR="$1/logs"; init_diagnostic_log "test-run-1"; log_diag "STEP_ONE"; finish_diagnostic_log 0; LOG_FINALIZED=0; init_diagnostic_log "test-run-2"; log_diag "STEP_TWO"; finish_diagnostic_log 0',
                    Path(tmp).as_posix(),
                )
                self.assertEqual(r_log.returncode, 0, f"{script} log failed: {r_log.stderr or r_log.stdout}")
                latest = Path(tmp) / "logs" / "latest.log"
                prev = Path(tmp) / "logs" / "previous.log"
                self.assertTrue(latest.is_file(), f"Missing latest.log for {script}")
                self.assertTrue(prev.is_file(), f"Missing rotated previous.log for {script}")
                self.assertIn("STEP_TWO", latest.read_text(encoding="utf-8"))
                self.assertIn("STEP_ONE", prev.read_text(encoding="utf-8"))

    def test_v14_graphics_rules_sgr_patch_and_restore(self) -> None:
        if not vp.find_perl():
            self.skipTest("perl not available on PATH")

        sample_grules = (
            "# Synthetic Graphics Rules.sgr\n"
            "seti textureMemory       32\n"
            "option ScreenModeResolution\n"
            "   setting $Low\n"
            "      uintProp maxResWidth      2048\n"
            "      uintProp maxResHeight     2048\n"
            "   setting $High\n"
            "      uintProp maxResWidth      2048\n"
            "      uintProp maxResHeight     2048\n"
            "end\n"
            "# Override defaults (SIM-281,416)\n"
            "setOption EffectsQuality        $Medium\n"
            "setOption LightingQuality       $Medium\n"
            "# inline hardware note\n"
            "setOption Shadows               $Medium\n"
            "setOption MaterialDetail        $Medium\n"
            "endif\n"
        )

        with tempfile.TemporaryDirectory() as tmp:
            app_dir = Path(tmp) / "The Sims 2.app"
            cfg_dir = app_dir / "Contents" / "Resources" / "Config"
            macos_dir = app_dir / "Contents" / "MacOS"
            cfg_dir.mkdir(parents=True)
            macos_dir.mkdir(parents=True)

            grules = cfg_dir / "Graphics Rules.sgr"
            grules_bak = cfg_dir / "Graphics Rules.sgr.backup"
            dylib_dest = macos_dir / "libsims2_trackpad.dylib"
            grules.write_text(sample_grules, encoding="utf-8")
            dylib_dest.write_bytes(b"dummy-dylib")

            r1 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2"',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r1.returncode, 0, r1.stderr or r1.stdout)
            self.assertTrue(grules_bak.is_file())
            self.assertEqual(grules_bak.read_text(encoding="utf-8"), sample_grules)

            patched_text = grules.read_text(encoding="utf-8")
            self.assertIn("1024", patched_text)
            self.assertIn("2560", patched_text)
            self.assertIn("1600", patched_text)
            self.assertIn("$High", patched_text)
            self.assertNotIn("seti textureMemory       32", patched_text)
            self.assertNotIn("2048", patched_text)
            self.assertNotIn("5120", patched_text)
            self.assertNotIn("3200", patched_text)
            self.assertNotIn("$Medium", patched_text)

            # Second call must be strictly idempotent and keep original backup intact
            r2 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2"',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r2.returncode, 0, r2.stderr or r2.stdout)
            self.assertEqual(grules.read_text(encoding="utf-8"), patched_text)
            self.assertEqual(grules_bak.read_text(encoding="utf-8"), sample_grules)

            # Phase 1/2 already-patched 5120x3200 must upgrade cleanly to 2560x1600
            legacy_phase2 = patched_text.replace("2560", "5120").replace("1600", "3200")
            grules.write_text(legacy_phase2, encoding="utf-8")
            r_upgrade = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2"',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r_upgrade.returncode, 0, r_upgrade.stderr or r_upgrade.stdout)
            self.assertEqual(grules.read_text(encoding="utf-8"), patched_text)
            self.assertEqual(grules_bak.read_text(encoding="utf-8"), sample_grules)

            # Restore via restore_auxiliary_files
            r_rest = self._run_bash_lib(
                "restore_sims2.command",
                'restore_auxiliary_files "$1"',
                app_dir.as_posix(),
            )
            self.assertEqual(r_rest.returncode, 0, r_rest.stderr or r_rest.stdout)
            self.assertEqual(grules.read_text(encoding="utf-8"), sample_grules)
            self.assertFalse(dylib_dest.exists())

    def test_v14_macho_weak_dylib_injection_and_binary_zip_integrity(self) -> None:
        if not vp.find_perl():
            self.skipTest("perl not available on PATH")

        orig_sizeofcmds = 72 + 80  # 1 LC_SEGMENT_64 (72) + 1 section_64 (80)
        macho = bytearray(10240)
        # mach_header_64 (32 bytes): MH_MAGIC_64=0xfeedfacf, CPU_TYPE_X86_64=0x01000007, MH_EXECUTE=2, ncmds=1
        struct.pack_into("<IIIIIIII", macho, 0, 0xFEEDFACF, 0x01000007, 3, 2, 1, orig_sizeofcmds, 0, 0)
        # LC_SEGMENT_64 at offset 32
        struct.pack_into(
            "<II16sQQQQIIII",
            macho,
            32,
            0x19,
            orig_sizeofcmds,
            b"__TEXT",
            0x100000000,
            10240,
            0,
            10240,
            7,
            5,
            1,
            0,
        )
        # section_64 (__text) at offset 104, file offset 9984
        struct.pack_into(
            "<16s16sQQIIIIIIII",
            macho,
            104,
            b"__text",
            b"__TEXT",
            0x100000000 + 9984,
            256,
            9984,
            4,
            0,
            0,
            0x80000400,
            0,
            0,
            0,
        )

        dylib_name = "@executable_path/libsims2_trackpad.dylib"
        expected_cmdsize = (24 + len(dylib_name.encode("ascii")) + 1 + 7) & ~7

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            exe = tmp_dir / "Sims2XP_Exe"
            exe.write_bytes(bytes(macho))

            r1 = self._run_bash_lib(
                "patch_sims2.command",
                'inject_weak_dylib_macho "$1" "$2"',
                exe.as_posix(),
                dylib_name,
            )
            self.assertEqual(r1.returncode, 0, r1.stderr or r1.stdout)

            patched = exe.read_bytes()
            ncmds, sizeofcmds = struct.unpack_from("<II", patched, 16)
            self.assertEqual(ncmds, 2)
            self.assertEqual(sizeofcmds, orig_sizeofcmds + expected_cmdsize)

            new_cmd_off = 32 + orig_sizeofcmds
            cmd, cmdsize, str_off = struct.unpack_from("<III", patched, new_cmd_off)
            self.assertEqual(cmd, 0x80000018)
            self.assertEqual(cmdsize, expected_cmdsize)
            self.assertEqual(str_off, 24)
            cmd_payload = patched[new_cmd_off + str_off : new_cmd_off + cmdsize]
            self.assertIn(dylib_name.encode("ascii"), cmd_payload)

            # Second call must report ALREADY_INJECTED without modifying ncmds or bytes
            r2 = self._run_bash_lib(
                "patch_sims2.command",
                'inject_weak_dylib_macho "$1" "$2"',
                exe.as_posix(),
                dylib_name,
            )
            self.assertEqual(r2.returncode, 0, r2.stderr or r2.stdout)
            self.assertIn("ALREADY_INJECTED", r2.stdout)
            self.assertEqual(exe.read_bytes(), patched)
            ncmds_after, _ = struct.unpack_from("<II", exe.read_bytes(), 16)
            self.assertEqual(ncmds_after, 2)

            # Verify binary dylib is preserved byte-for-byte in Mac release ZIP with 0755 permissions
            dylib_src = ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib"
            self.assertTrue(dylib_src.is_file(), "Missing trackpad_mod/libsims2_trackpad.dylib")
            expected_dylib = dylib_src.read_bytes()
            mac_zip, _ = vp.package_releases("v1.4.0-test", tmp_dir)
            with zipfile.ZipFile(mac_zip, "r") as zf:
                dylib_arc = "sims2-crash-patch-v1.4.0-test/trackpad_mod/libsims2_trackpad.dylib"
                info = zf.getinfo(dylib_arc)
                mode = (info.external_attr >> 16) & 0o777
                self.assertEqual(mode, 0o755)
                self.assertEqual(zf.read(dylib_arc), expected_dylib)

            # Branch names with '/' (e.g. feat/v1.4-audit) must sanitize cleanly to flat ZIP paths
            branch_mac_zip, branch_win_zip = vp.package_releases("feat/test-branch", tmp_dir)
            self.assertEqual(branch_mac_zip.parent, tmp_dir)
            self.assertEqual(branch_mac_zip.name, "sims2-crash-patch-feat-test-branch.zip")
            self.assertEqual(branch_win_zip.name, "sims2-crash-patch-windows-feat-test-branch.zip")
            self.assertTrue(branch_mac_zip.is_file())
            self.assertTrue(branch_win_zip.is_file())

    def test_v14_trackpad_dylib_sdl2_azerty_and_orbit_fixes(self) -> None:
        build_sh = (ROOT_DIR / "trackpad_mod" / "build_trackpad.sh").read_text(encoding="utf-8")
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")
        dylib = ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib"

        self.assertIn("-arch x86_64", build_sh)
        self.assertIn("-framework Carbon", build_sh)
        self.assertIn("-framework CoreGraphics", build_sh)

        # Brique 2 SDL2 Space/Dock/focus hints & cursor warp protection
        for hint in (
            "SDL_VIDEO_MAC_FULLSCREEN_SPACES",
            "SDL_HINT_ALLOW_FULLSCREEN_NOTIFICATIONS",
            "SDL_ALLOW_TOPMOST",
            "SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS",
        ):
            self.assertIn(hint, src_m)
        self.assertIn('setenv("SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS", "0", 1);', src_m)
        self.assertIn("swizzled_mouseMoved", src_m)
        self.assertIn("![NSApp isActive]", src_m)
        self.assertIn("![win isKeyWindow]", src_m)

        # Brique 3 layout-independent pinch zoom, Carbon AZERTY/QWERTY rotation, Control-orbit & Cmd+Tab anti-bounce
        self.assertIn("CGEventCreateScrollWheelEvent", src_m)
        self.assertIn("gForceScrollNonInverted", src_m)
        self.assertIn("TISCopyCurrentKeyboardLayoutInputSource", src_m)
        self.assertIn("UCKeyTranslate", src_m)
        self.assertIn("kc >= 65 && kc <= 92", src_m)
        self.assertIn("75 * NSEC_PER_MSEC", src_m)
        self.assertIn("NSEventTypeFlagsChanged", src_m)
        self.assertIn("NSEventModifierFlagControl", src_m)
        self.assertIn("NSEventModifierFlagOption", src_m)
        self.assertIn("rightMouseDown:", src_m)
        self.assertIn("rightMouseDragged:", src_m)
        self.assertIn("mouseDragged:", src_m)
        self.assertIn("gCtrlMiddleDragActive", src_m)
        self.assertIn("!gCtrlMiddleDragActive", src_m)
        self.assertIn("isRight == gCtrlDragWasRight", src_m)
        self.assertNotIn("gOptionHandPanActive", src_m)
        self.assertIn("swizzled_setFullscreenSpace", src_m)
        self.assertIn("swizzled_miniaturize", src_m)
        self.assertIn("swizzled_activateIgnoringOtherApps", src_m)
        self.assertIn("swizzled_focusSomeWindow", src_m)
        self.assertIn("swizzled_canBecomeKeyWindow", src_m)
        self.assertIn("is_secondary_orphan_game_window", src_m)
        self.assertIn("neutralize_secondary_orphan_windows", src_m)
        self.assertIn("NSEventTypeKeyDown", src_m)
        self.assertIn("is_sdl_game_window", src_m)
        self.assertIn("raw_event_modifier_flags", src_m)
        self.assertIn("gSuppressedScrollEvent", src_m)
        self.assertIn("gForcedNonInvertedEvent", src_m)
        self.assertIn("resolve_window_listener", src_m)

        # Real hardware CoreGraphics __DATA,__la_symbol_ptr hooks + dynamic visibleFrame clamp (no synthetic modes or experimental hooks)
        self.assertNotIn("Sims2SyntheticDisplayMode", src_m)
        self.assertIn("hook_coregraphics_la_symbol_ptrs", src_m)
        self.assertIn("S_LAZY_SYMBOL_POINTERS", src_m)
        self.assertIn("--------RRRRRRRRGGGGGGGGBBBBBBBB", src_m)
        self.assertIn("clamp_fullscreen_window_to_visible_frame", src_m)
        self.assertIn("update_cached_screen_geometry", src_m)
        self.assertIn("SIMS2_PATCH_VERSION \"1.5.0\"", src_m)
        self.assertIn("_CGDisplayCopyAllDisplayModes", src_m)
        self.assertIn("_CGDisplayCopyDisplayMode", src_m)
        self.assertIn("_CGDisplayModeGetHeight", src_m)
        self.assertIn("_CGDisplayModeGetPixelHeight", src_m)
        self.assertIn("_CGDisplayPixelsHigh", src_m)
        self.assertIn("_CGDisplayBounds", src_m)
        self.assertIn("_sscanf", src_m)
        self.assertIn("___cxa_throw", src_m)

        # Experimental hot-resolution hooks, Upscaling, Option display shortcuts, direct userProps.xml / cross-container access & GL viewport/scissor hooks must be completely absent
        for removed_sym in (
            "_CGAcquireDisplayFadeReservation",
            "_CGDisplayFade",
            "_CGReleaseDisplayFadeReservation",
            "_CGConfigureDisplayFadeEffect",
            "_CGDisplaySetDisplayMode",
            "_glViewport",
            "_glScissor",
            "_CGLSetParameter",
            "_CGLEnable",
            "_CGLDisable",
            "refresh_userprops_target_resolution",
            "sync_userprops_display_mode_for_next_launch",
            "userProps.xml",
            "Library/Containers",
            "initWithSuiteName:",
            "gTargetRenderWidth",
            "gTargetRenderHeight",
            "launch_boot.log",
            "trackpad_events.log",
            "fallback-1800x1169",
            "1800x1130",
            "S2PatchFullscreenUpscaling",
            "gFullscreenUpscaling",
            "gFullscreenUpscalingEnabled",
            "toggle_fullscreen_upscaling",
            "toggle_fullscreen_upscaling_ex",
            "onToggleFullscreenUpscaling",
            "gSims2UpscaleMenuItem",
            "Upscaling",
            "S2PatchWindowedMode",
            "S2PatchTargetWidth",
            "S2PatchTargetHeight",
            "S2PatchPrefsConfigured",
            "Option + Return",
            "Option + R",
            "Option + U",
            "kc == 32",
            "cleanMods == NSEventModifierFlagOption",
            "setKeyEquivalentModifierMask:NSEventModifierFlagOption",
        ):
            self.assertNotIn(removed_sym, src_m)

        # Silent default logging + automatic crash_report.log + on-demand debug_boot.log
        for crash_tok in (
            "crash_report.log",
            "debug_boot.log",
            ".debug_enabled",
            "SIMS2_DEBUG",
            "SIGSEGV",
            "SIGABRT",
            "SIGBUS",
            "SIGILL",
            "SIGFPE",
            "_ZSt13set_terminatePFvvE",
            "backtrace_symbols_fd",
            "hw.model",
        ):
            self.assertIn(crash_tok, src_m)

        # Autonomous minimal single-native display mode selection + strict SDLWindow borderless/windowed state machine
        self.assertNotIn("kSims2ResolutionWhitelist", src_m)
        for guard_tok in (
            "find_optimal_mode_in_array",
            "is_better_display_mode",
            "hook_sscanf",
            "va_copy",
            "vsscanf",
            "gLastExposedModeWidth",
            "gLastExposedModeHeight",
            "swizzle_target_class_method",
            "swizzled_sdlSetStyleMask",
            "swizzled_sdlSetLevel",
            "swizzled_sdlSetFrameDisplay",
            "swizzled_sdlSetFrameOrigin",
            "swizzled_sdlSetFrameTopLeftPoint",
            "sanitize_sdl_style_mask",
            "sanitize_mission_control_collection_behavior",
            "NSNormalWindowLevel",
            "NSWindowCollectionBehaviorManaged",
            "NSWindowCollectionBehaviorParticipatesInCycle",
            "NSWindowStyleMaskBorderless",
            "NSWindowStyleMaskTitled",
            "NSWindowStyleMaskClosable",
            "NSWindowStyleMaskMiniaturizable",
            "NSWindowTitleVisible",
            "setTitlebarAppearsTransparent:NO",
            "apply_borderless_presentation_options",
            "compute_primary_game_frame",
            "safeAreaInsets.top",
            "gNotchTopInset",
            "gModeTransitionInProgress",
            "sync_content_view_to_window_bounds",
            "enforce_primary_window_borderless_fullscreen",
            "restore_game_window_focus_and_input",
            "makeFirstResponder:",
            "setAcceptsMouseMovedEvents:YES",
            "NSWindowDidBecomeMainNotification",
            "NSWorkspaceActiveSpaceDidChangeNotification",
            "NSWindowWillMoveNotification",
            "swizzled_mouseLocationOutsideOfEventStream",
            "sync_sdl_cursor_position_before_click",
            "Command + Return",
            "Command + R",
            "cleanMods == NSEventModifierFlagCommand",
            "setKeyEquivalentModifierMask:NSEventModifierFlagCommand",
            "kc == 36 || kc == 76 || kc == 15",
            "NSMenu",
            "NSUserDefaults",
            "standardUserDefaults",
            "NSApplicationDidBecomeActiveNotification",
            "frameRectForContentRect:",
            "contentRectForFrameRect:",
            "convertPoint:rawLoc fromView:nil",
            "tProjectMouseLocationForSDL",
            "swizzled_nsglSetView",
            "gGameOpenGLContext",
            "CGLContextObj",
            "CGLLockContext",
            "kCGLCPSurfaceBackingSize",
            "S2PatchWindowedWidth",
            "S2PatchWindowedHeight",
            "build_windowed_resolution_list",
            "NSControlStateValueOn",
            "NSControlStateValueOff",
            "setHasShadow:YES",
            "Les Sims™ 2 : Super Collection",
        ):
            self.assertIn(guard_tok, src_m)

        # Verify Windowed -> Fullscreen order: setStyleMask:NSWindowStyleMaskBorderless BEFORE setFrame:display:
        fs_section = src_m.split("/* === BORDERLESS FULLSCREEN (gWindowedModeActive == NO) ===")[1]
        style_idx = fs_section.index("setStyleMask:")
        frame_idx = fs_section.index("setFrame:display:")
        self.assertLess(style_idx, frame_idx, "Borderless styleMask must be applied before setFrame:display:")

        # Compiled dylib header check (Mach-O 64-bit x86_64 MH_DYLIB)
        raw = dylib.read_bytes()
        magic, cputype, _, filetype = struct.unpack_from("<IIII", raw, 0)
        self.assertEqual(magic, 0xFEEDFACF)
        self.assertEqual(cputype, 0x01000007)
        self.assertEqual(filetype, 6)
        for cg_sym in (
            b"CGDisplayCopyAllDisplayModes",
            b"CGDisplayCopyDisplayMode",
            b"CGDisplayModeCopyPixelEncoding",
            b"CGDisplayModeGetWidth",
            b"CGDisplayModeGetHeight",
            b"CGDisplayModeGetPixelWidth",
            b"CGDisplayModeGetPixelHeight",
            b"CGDisplayModeGetRefreshRate",
            b"CGDisplayPixelsHigh",
            b"CGDisplayBounds",
            b"vsscanf",
            b"S2PatchWindowedWidth",
            b"S2PatchWindowedHeight",
            b"__cxa_throw",
            b"backtrace_symbols_fd",
            b"crash_report.log",
            b"debug_boot.log",
        ):
            self.assertIn(cg_sym, raw)
        for absent_bin_sym in (
            b"Sims2SyntheticDisplayMode",
            b"CGDisplayFade",
            b"CGAcquireDisplayFadeReservation",
            b"CGDisplaySetDisplayMode",
            b"glScissor",
            b"glViewport",
            b"userProps.xml",
            b"Library/Containers",
            b"launch_boot.log",
            b"trackpad_events.log",
            b"S2PatchFullscreenUpscaling",
            b"S2PatchWindowedMode",
            b"S2PatchTargetWidth",
            b"S2PatchTargetHeight",
            b"S2PatchPrefsConfigured",
        ):
            self.assertNotIn(absent_bin_sym, raw)
        if sys.platform == "darwin":
            cs = subprocess.run(["codesign", "--verify", "--strict", dylib.as_posix()], capture_output=True, text=True)
            self.assertEqual(cs.returncode, 0, cs.stderr)

    def test_window_mode_mouse_projection_zero_error(self) -> None:
        def project_mouse_for_sdl(
            raw_x: float,
            raw_y: float,
            content_w: float,
            content_h: float,
            fb_w: float,
            fb_h: float,
            windowed: bool = False,
            sdl_w: float | None = None,
            sdl_h: float | None = None,
        ) -> tuple[float, float, bool]:
            eff_sdl_w = fb_w if sdl_w is None else sdl_w
            eff_sdl_h = fb_h if sdl_h is None else sdl_h
            # 1. Immediate integral pass-through in 1:1 Native Fullscreen
            if (
                not windowed
                and abs(content_w - fb_w) <= 2.0
                and abs(content_h - fb_h) <= 2.0
                and abs(eff_sdl_w - fb_w) <= 2.0
                and abs(eff_sdl_h - fb_h) <= 2.0
            ):
                return (raw_x, raw_y, False)
            # 2. convertPoint:fromView:nil with contentView at (0, 0, content_w, content_h)
            pt_x, pt_y = raw_x, raw_y
            # Pass-through on titlebar or outside contentView
            if pt_y >= content_h or pt_y < 0.0 or pt_x < 0.0 or pt_x > content_w:
                return (raw_x, raw_y, True)
            # 3. Inside contentView: proportional projection to SDL/engine framebuffer (fb_w, fb_h)
            x_sdl = pt_x * (fb_w / content_w)
            y_sdl = (eff_sdl_h - fb_h) + pt_y * (fb_h / content_h)
            return (x_sdl, y_sdl, False)

        # 0. Usable native height on notched MacBook (1800x1169 with 38 px safeAreaInsets.top -> 1800x1131)
        #    and on non-notched / external display (1920x1080 with 0 px safeAreaInsets.top -> 1920x1080)
        notch_raw_w, notch_raw_h, safe_top_inset = 1800.0, 1169.0, 38.0
        native_w, native_h = notch_raw_w, notch_raw_h - safe_top_inset
        self.assertEqual((native_w, native_h), (1800.0, 1131.0))
        ext_w, ext_h = 1920.0, 1080.0 - 0.0
        self.assertEqual((ext_w, ext_h), (1920.0, 1080.0))

        # 1. Native Fullscreen 1:1 (including <= 2 pt notch menu bar rounding 1130 vs 1131): 0.0 px error
        for space_h in (native_h, native_h - 1.0):
            for px, py in ((0.0, 0.0), (900.0, 565.5), (1799.0, 1129.0)):
                xs, ys, passthrough_outside = project_mouse_for_sdl(px, py, native_w, space_h, native_w, native_h, windowed=False)
                self.assertFalse(passthrough_outside)
                self.assertEqual(abs(xs - px), 0.0)
                self.assertEqual(abs(ys - py), 0.0)

        # 2. Centered Windowed mode with 28 px titlebar and GPU downscale 1800x1131 -> 1280x800
        titlebar_height = 28.0
        outer_w, outer_h = 1280.0, 800.0 + titlebar_height
        vis_w, vis_h = native_w, native_h
        centered_x = (vis_w - outer_w) // 2
        centered_y = (vis_h - outer_h) // 2
        self.assertGreater(centered_x, 0.0)
        self.assertGreater(centered_y, 0.0)
        self.assertLessEqual(centered_y + outer_h, vis_h)
        self.assertEqual(outer_h - titlebar_height, 800.0)

        # Content points in 1280x800 (4 corners + center + bottom-left Options panel + top-left Montsimpa icons)
        # project with exact 0.0 px error onto 1800x1131 engine framebuffer
        windowed_samples = (
            # Bottom-left corner
            ((0.0, 0.0), (0.0, 0.0)),
            # Bottom-left Options (...) button panel
            ((64.0, 40.0), (90.0, 56.55)),
            # Top-left Montsimpa icons
            ((64.0, 760.0), (90.0, 1074.45)),
            # Center
            ((640.0, 400.0), (900.0, 565.5)),
            # Bottom-right corner
            ((1280.0, 0.0), (1800.0, 0.0)),
            # Top-right inside contentView (y = 799)
            ((1280.0, 799.0), (1800.0, 799.0 * (1131.0 / 800.0))),
        )
        for (raw_x, raw_y), (exp_x, exp_y) in windowed_samples:
            xs, ys, in_titlebar = project_mouse_for_sdl(raw_x, raw_y, 1280.0, 800.0, native_w, native_h, windowed=True)
            self.assertFalse(in_titlebar)
            self.assertAlmostEqual(xs, exp_x, places=9)
            self.assertAlmostEqual(ys, exp_y, places=9)
            # Verify SDL top-down conversion (sdl_h - ys) matches exact normalized engine Y with 0.0 px error
            sdl_top_down_y = native_h - ys
            expected_top_down_y = (1.0 - (raw_y / 800.0)) * native_h
            self.assertAlmostEqual(abs(sdl_top_down_y - expected_top_down_y), 0.0, places=9)

        # Even if SDL window->h temporarily drifted to 800 while engine FB is 1800x1131,
        # SDL top-down Y (sdl_h - ys) must still equal expected engine Y with 0.0 px error
        for (raw_x, raw_y), _ in (((64.0, 40.0), None), ((64.0, 760.0), None), ((640.0, 400.0), None)):
            xs, ys, in_titlebar = project_mouse_for_sdl(
                raw_x, raw_y, 1280.0, 800.0, native_w, native_h, windowed=True, sdl_w=1280.0, sdl_h=800.0
            )
            self.assertFalse(in_titlebar)
            self.assertAlmostEqual(xs, raw_x * (native_w / 1280.0), places=9)
            self.assertAlmostEqual(800.0 - ys, (1.0 - (raw_y / 800.0)) * native_h, places=9)

        # Click inside the 28 px titlebar (y in [800, 828]) must pass through untouched to Cocoa
        for tb_y in (800.0, 814.0, 828.0):
            xs, ys, in_titlebar = project_mouse_for_sdl(640.0, tb_y, 1280.0, 800.0, native_w, native_h, windowed=True)
            self.assertTrue(in_titlebar)
            self.assertEqual((xs, ys), (640.0, tb_y))

    def test_exp_boot_sigsegv_fix_native_fullscreen_command_shortcuts_and_diag_telemetry(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")

        # 1. Boot SIGSEGV (0x1006ea404 / nGZGraphic::cError) fix: safe variadic _sscanf wrapper
        #    using va_start + va_copy + vsscanf + va_end, strictly gated on ret == 4, non-NULL pointers,
        #    and gLastExposedModeWidth > 0 && gLastExposedModeHeight > 0.
        sscanf_section = src_m.split("static int hook_sscanf(const char *str, const char *fmt, ...) {")[1].split("typedef void (*Sims2CxaThrowFn)")[0]
        for tok in (
            "va_start(ap, fmt);",
            "va_copy(apScan, ap);",
            "int ret = vsscanf(str, fmt, apScan);",
            "va_end(apScan);",
            "ret == 4",
            'strcmp(fmt, "%ux%ux%ux%u") == 0',
            "gLastExposedModeWidth > 0 && gLastExposedModeHeight > 0",
            "va_copy(apExtract, ap);",
            "outW && outH && outBpp && outHz",
            "va_end(apExtract);",
            "va_end(ap);",
        ):
            self.assertIn(tok, sscanf_section)
        self.assertIn('{ "_sscanf",                       (void *)hook_sscanf },', src_m)

        # 2. Always boot in native macOS Fullscreen Space (never auto-launch windowed)
        load_prefs_section = src_m.split("static void load_display_preferences_from_defaults(void) {")[1].split("static size_t build_windowed_resolution_list")[0]
        self.assertIn("gWindowedModeActive = NO;", load_prefs_section)
        self.assertNotIn("gWindowedModeActive = [defaults boolForKey:", load_prefs_section)
        self.assertIn("kSims2PrefWindowedWidthKey", load_prefs_section)
        self.assertIn("kSims2PrefWindowedHeightKey", load_prefs_section)

        # 3. 48s boot freeze fix & native macOS Fullscreen Space
        beh_section = src_m.split("static NSWindowCollectionBehavior sanitize_mission_control_collection_behavior(NSWindowCollectionBehavior behavior) {")[1].split("return clean;")[0]
        self.assertIn("NSWindowCollectionBehaviorFullScreenPrimary", beh_section)
        clean_or_part = beh_section.split("clean |=")[1]
        self.assertIn("NSWindowCollectionBehaviorFullScreenPrimary", clean_or_part)
        self.assertNotIn("NSWindowCollectionBehaviorFullScreenNone", clean_or_part)
        self.assertIn("Skipped setFullscreenSpace:YES", src_m)
        self.assertIn("swizzled_windowDidFailToEnterFullScreen", src_m)
        self.assertIn('setenv("SDL_ALLOW_TOPMOST", "0", 1);', src_m)
        self.assertIn("NSWindowStyleMaskResizable", src_m)
        self.assertIn("swizzled_sdlValidateMenuItem", src_m)
        self.assertIn("try_accept_shortcut_trigger", src_m)
        exit_fs_section = src_m.split("static void swizzled_windowDidExitFullScreen")[1].split("static BOOL swizzled_setFullscreenSpace")[0]
        self.assertNotIn("gPrimaryFullscreenWindow = nil;", exit_fs_section)

        # 4. Strictly separated Command shortcuts (Cmd+Return toggles Fullscreen<->Windowed,
        #    Cmd+R cycles windowed resolutions ONLY and is a strict no-op + disabled menu item in Fullscreen,
        #    zero Option display shortcuts, zero interference with Cmd+Q/H/M/W/Tab).
        next_ev_section = src_m.split("static NSEvent *swizzled_nextEventMatchingMask")[1].split("static void swizzled_scrollWheel")[0]
        self.assertIn("BOOL isOurShortcutKey = (kc == 36 || kc == 76 || kc == 15);", next_ev_section)
        self.assertIn("if (isOurShortcutKey && cleanMods == NSEventModifierFlagCommand)", next_ev_section)
        self.assertIn("Command + R ignored in Fullscreen", next_ev_section)
        self.assertNotIn("cleanMods == NSEventModifierFlagOption", next_ev_section)
        cycle_section = src_m.split("static void cycle_next_resolution_ex(NSTimeInterval eventTs, const char *source) {")[1].split("static void cycle_next_resolution(void)")[0]
        self.assertIn("if (!gWindowedModeActive)", cycle_section)
        self.assertIn("build_windowed_resolution_list", cycle_section)
        self.assertNotIn("gNativeScreenWidth", cycle_section)
        self.assertNotIn("toggleFullScreen", cycle_section)
        validate_section = src_m.split("- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {")[1].split("- (void)onToggleWindowedMode:")[0]
        self.assertIn("@selector(onCycleResolution:)", validate_section)
        self.assertIn("return gWindowedModeActive;", validate_section)

        # 5. 1280x800 mouse/trackpad/keyboard controls alignment & responder chain
        for tok in (
            "ensure_sdl_responder_chain",
            "safe_set_sdl_window_style_mask",
            "sync_sdl_window_logical_size_to_engine_fb",
            "tInMouseDownHandler",
            "tInMouseUpHandler",
            "tInMouseMotionHandler",
            "swizzled_sdlViewMouseDownCanMoveWindow",
            "flush_stuck_modifier_state_to_sdl",
            "NSMenuDidEndTrackingNotification",
            "describe_keyboard_source",
            "x_sdl > sdlW - 1.0",
            "y_sdl < 1.0",
            "<NSMenuDelegate>",
            "menuNeedsUpdate:",
            "menuDidClose:",
            "CFPreferencesAppSynchronize",
            "S2PatchDiagLog",
            "NSApplicationWillTerminateNotification",
        ):
            self.assertIn(tok, src_m)

        # 6. Atomic display transition generation guard, Space geometry check & dynamic multi-screen tolerance
        for tok in (
            "gDisplayTransitionGen",
            "bump_display_transition_gen",
            "current_display_transition_gen",
            "compute_expected_fullscreen_space_frame",
            "ensure_fullscreen_space_geometry",
            "should_clamp_stale_windowed_frame_during_fullscreen",
            "safeAreaInsets.top",
            "return sf;",
            "1024, 640",
            "abs(curW - targetW) <= 2 && abs(curH - targetH) <= 2",
        ):
            self.assertIn(tok, src_m)

        # 7. Anti-glitch idempotent CGL backing check + opt-in sandbox-safe diagnostic telemetry
        for tok in (
            "CGLIsEnabled",
            "CGLGetParameter",
            "apply_opengl_surface_backing_size_ex",
            "sims2_patch_diag.log",
            "sims2_patch_diag.prev.log",
            "SIMS2_DIAG_LOG",
            "SIMS2_DIAG_OSLOG",
            "kSims2DiagLogMaxBytes",
            "CLOCK_UPTIME_RAW",
            "os_log_create",
        ):
            self.assertIn(tok, src_m)

        # 8. Runtime tests on macOS:
        #    (a) opt-in diagnostic telemetry OFF by default, ON with SIMS2_DIAG_LOG=1, OFF with SIMS2_DIAG_LOG=0
        #    (b) live x86_64 hook_sscanf ABI & normalization check (before/after CGDisplayCopyAllDisplayModes,
        #        ret != 4 untouched, non-matching variadic formats with ints/doubles/strings untouched)
        if sys.platform == "darwin" and shutil.which("clang"):
            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)
                src_c = tmp_p / "diag_probe.c"
                exe = tmp_p / "diag_probe"
                src_c.write_text("int main(void) { return 0; }\n", encoding="utf-8")
                rc = subprocess.run(
                    ["clang", "-arch", "x86_64", "-O0", str(src_c), "-o", str(exe)],
                    capture_output=True,
                    text=True,
                )
                if rc.returncode == 0:
                    dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()

                    # 1. Default OFF (opt-in only -> zero disk I/O during normal gameplay)
                    h0 = tmp_p / "h0"
                    t0 = tmp_p / "t0"
                    h0.mkdir()
                    t0.mkdir()
                    env0 = {
                        **os.environ,
                        "HOME": str(h0),
                        "SIMS2_DIAG_LOG_DIR": str(t0),
                        "DYLD_INSERT_LIBRARIES": dylib_path,
                    }
                    env0.pop("SIMS2_DEBUG", None)
                    env0.pop("SIMS2_DIAG_LOG", None)
                    r0 = subprocess.run([str(exe)], env=env0, capture_output=True, text=True)
                    self.assertEqual(r0.returncode, 0, r0.stderr)
                    self.assertFalse((t0 / "sims2_patch_diag.log").exists(), "Diag log must be opt-in (OFF by default)")
                    self.assertFalse((h0 / "Library" / "Logs" / "Sims2-Crash-Patch").exists())

                    # 2. Explicitly enabled via SIMS2_DIAG_LOG=1
                    h1 = tmp_p / "h1"
                    t1 = tmp_p / "t1"
                    h1.mkdir()
                    t1.mkdir()
                    env1 = {
                        **os.environ,
                        "HOME": str(h1),
                        "SIMS2_DIAG_LOG_DIR": str(t1),
                        "SIMS2_DIAG_LOG": "1",
                        "DYLD_INSERT_LIBRARIES": dylib_path,
                    }
                    env1.pop("SIMS2_DEBUG", None)
                    r1 = subprocess.run([str(exe)], env=env1, capture_output=True, text=True)
                    self.assertEqual(r1.returncode, 0, r1.stderr)
                    diag_log = t1 / "sims2_patch_diag.log"
                    self.assertTrue(diag_log.is_file(), "Expected sims2_patch_diag.log when SIMS2_DIAG_LOG=1")
                    diag_txt = diag_log.read_text(encoding="utf-8")
                    self.assertIn("[BOOT]", diag_txt)
                    self.assertIn("v1.5.0", diag_txt)
                    self.assertIn("[INIT]", diag_txt)
                    self.assertIn("[+0", diag_txt)
                    self.assertFalse((h1 / "Library" / "Logs" / "Sims2-Crash-Patch").exists())

                    # 3. Explicitly disabled via SIMS2_DIAG_LOG=0
                    h2 = tmp_p / "h2"
                    t2 = tmp_p / "t2"
                    h2.mkdir()
                    t2.mkdir()
                    env2 = {
                        **os.environ,
                        "HOME": str(h2),
                        "SIMS2_DIAG_LOG_DIR": str(t2),
                        "SIMS2_DIAG_LOG": "0",
                        "DYLD_INSERT_LIBRARIES": dylib_path,
                    }
                    env2.pop("SIMS2_DEBUG", None)
                    r2 = subprocess.run([str(exe)], env=env2, capture_output=True, text=True)
                    self.assertEqual(r2.returncode, 0, r2.stderr)
                    self.assertFalse((t2 / "sims2_patch_diag.log").exists())
                    self.assertFalse((h2 / "Library" / "Logs" / "Sims2-Crash-Patch").exists())

                # 4. Dedicated live runtime unit test for hook_sscanf (variadic va_copy ABI + stale mode normalization)
                sscanf_c = tmp_p / "sscanf_probe.c"
                sscanf_exe = tmp_p / "sscanf_probe"
                sscanf_c.write_text(
                    "#include <CoreGraphics/CoreGraphics.h>\n"
                    "#include <math.h>\n"
                    "#include <stdio.h>\n"
                    "#include <string.h>\n"
                    "int main(void) {\n"
                    "    unsigned int w = 0, h = 0, bpp = 0, hz = 0;\n"
                    "    /* Before CGDisplayCopyAllDisplayModes: gLastExposedModeWidth == 0 -> must NOT overwrite */\n"
                    "    int r_pre = sscanf(\"1512x982x32x120\", \"%ux%ux%ux%u\", &w, &h, &bpp, &hz);\n"
                    "    if (r_pre != 4 || w != 1512 || h != 982 || bpp != 32 || hz != 120) return 10;\n"
                    "\n"
                    "    /* Populate gLastExposedModeWidth/Height via hooked CGDisplayCopyAllDisplayModes */\n"
                    "    CFArrayRef modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), NULL);\n"
                    "    if (!modes || CFArrayGetCount(modes) < 1) return 11;\n"
                    "    CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, 0);\n"
                    "    unsigned int expW = (unsigned int)CGDisplayModeGetWidth(m);\n"
                    "    unsigned int expH = (unsigned int)CGDisplayModeGetHeight(m);\n"
                    "    CFRelease(modes);\n"
                    "    if (expW < 800 || expH < 600) return 12;\n"
                    "\n"
                    "    /* After exposure: stale activeDeviceDisplayMode (ret == 4) must normalize to exposed native mode */\n"
                    "    w = h = bpp = hz = 0;\n"
                    "    int r_stale = sscanf(\"1512x982x32x120\", \"%ux%ux%ux%u\", &w, &h, &bpp, &hz);\n"
                    "    if (r_stale != 4 || w != expW || h != expH || bpp != 32 || hz != 60) return 13;\n"
                    "\n"
                    "    /* Partial scan (ret != 4) must NOT overwrite parsed values */\n"
                    "    w = h = 0; bpp = 77; hz = 88;\n"
                    "    int r_part = sscanf(\"1440x900\", \"%ux%ux%ux%u\", &w, &h, &bpp, &hz);\n"
                    "    if (r_part != 2 || w != 1440 || h != 900 || bpp != 77 || hz != 88) return 14;\n"
                    "\n"
                    "    /* Non-display variadic scan with int, double (XMM), string, int -> proves zero x86_64 ABI corruption */\n"
                    "    int a = 0, b = 0; double dv = 0.0; char tok[32] = {0};\n"
                    "    int r_var = sscanf(\"42 3.25 sims2 -7\", \"%d %lf %31s %d\", &a, &dv, tok, &b);\n"
                    "    if (r_var != 4 || a != 42 || fabs(dv - 3.25) > 1e-9 || strcmp(tok, \"sims2\") != 0 || b != -7) return 15;\n"
                    "    printf(\"OK:%ux%u\\n\", expW, expH);\n"
                    "    return 0;\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_ss = subprocess.run(
                    [
                        "clang",
                        "-arch",
                        "x86_64",
                        "-mmacosx-version-min=10.13",
                        "-O0",
                        "-framework",
                        "CoreGraphics",
                        "-framework",
                        "CoreFoundation",
                        str(sscanf_c),
                        "-o",
                        str(sscanf_exe),
                    ],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_ss.returncode, 0, rc_ss.stderr)
                h_ss = tmp_p / "h_ss"
                h_ss.mkdir()
                env_ss = {
                    **os.environ,
                    "HOME": str(h_ss),
                    "SIMS2_DIAG_LOG": "0",
                    "DYLD_INSERT_LIBRARIES": (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix(),
                }
                env_ss.pop("SIMS2_DEBUG", None)
                r_ss = subprocess.run([str(sscanf_exe)], env=env_ss, capture_output=True, text=True)
                self.assertEqual(r_ss.returncode, 0, f"sscanf_probe failed rc={r_ss.returncode} out={r_ss.stdout} err={r_ss.stderr}")
                self.assertIn("OK:", r_ss.stdout)

    def test_exp_windowed_inverse_warp_sdl_origin_resync_and_camera_guards(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")
        dylib_raw = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").read_bytes()

        # 1. Pure mathematical verification of inverse WarpMouse projection (fb -> content -> real CG screen)
        #    and SDL_Window->x/y resync across centered, displaced-left, notched Fullscreen, and non-notched displays.
        def compute_sdl_origin(content_x: float, content_y: float, content_h: float, hooked_display_h: float) -> tuple[int, int]:
            return (round(content_x), round(hooked_display_h - (content_y + content_h)))

        def compute_inverse_warp(
            sdl_global_x: float,
            sdl_global_y: float,
            sdl_win_x: float,
            sdl_win_y: float,
            fb_w: float,
            fb_h: float,
            content_x: float,
            content_y: float,
            content_w: float,
            content_h: float,
            raw_primary_h: float,
        ) -> tuple[float, float, float, float]:
            fb_x = max(0.0, min(fb_w - 1.0, sdl_global_x - sdl_win_x))
            fb_y = max(0.0, min(fb_h - 1.0, sdl_global_y - sdl_win_y))
            half_x = 0.5 if content_w < fb_w - 2.0 else 0.0
            half_y = 0.5 if content_h < fb_h - 2.0 else 0.0
            cx = max(0.0, min(content_w - 1.0, (fb_x + half_x) * (content_w / fb_w)))
            cy_td = max(0.0, min(content_h - 1.0, (fb_y + half_y) * (content_h / fb_h)))
            cg_origin_x = content_x
            cg_origin_y = raw_primary_h - (content_y + content_h)
            return (cg_origin_x + cx, cg_origin_y + cy_td, cx, cy_td)

        # Case A: Pie menu click on chair at right side of 1280x800 centered window on notched MBP (1800x1169, notch=38 -> 1800x1131)
        fb_w, fb_h = 1800.0, 1131.0
        raw_h, hooked_h = 1169.0, 1131.0
        sdl_x, sdl_y = compute_sdl_origin(260.0, 150.0, 800.0, hooked_h)
        self.assertEqual((sdl_x, sdl_y), (260, 181))
        # Engine requests SetCursorPos(1450, 707) -> Cocoa_WarpMouse adds (260, 181) = (1710, 888) (170 pt OUTSIDE window!)
        cg_x, cg_y, cx, cy_td = compute_inverse_warp(
            sdl_x + 1450.0, sdl_y + 707.0, sdl_x, sdl_y, fb_w, fb_h, 260.0, 150.0, 1280.0, 800.0, raw_h
        )
        # Physical cursor MUST remain strictly inside contentScreenRect [260, 1540) x [219, 1019)
        self.assertGreaterEqual(cg_x, 260.0)
        self.assertLess(cg_x, 260.0 + 1280.0)
        self.assertGreaterEqual(cg_y, raw_h - (150.0 + 800.0))
        self.assertLess(cg_y, raw_h - 150.0)
        # Forward projection back into SDL/engine coords must round-trip with 0 px error on 2x Retina (0.5 pt grid)
        cx_snap = round(cx * 2.0) / 2.0
        cy_snap = round(cy_td * 2.0) / 2.0
        self.assertEqual(int(cx_snap * (fb_w / 1280.0)), 1450)
        self.assertEqual(int(cy_snap * (fb_h / 800.0)), 707)

        # Case B: Window dragged far left on Desktop to (20, 120) -> sdlWin->x/y resync + Option/Control camera anchor roundtrip
        moved_sdl_x, moved_sdl_y = compute_sdl_origin(20.0, 120.0, 800.0, hooked_h)
        self.assertEqual((moved_sdl_x, moved_sdl_y), (20, 211))
        cg_x2, cg_y2, cx2, cy2_td = compute_inverse_warp(
            moved_sdl_x + 900.0, moved_sdl_y + 565.0, moved_sdl_x, moved_sdl_y, fb_w, fb_h, 20.0, 120.0, 1280.0, 800.0, raw_h
        )
        self.assertAlmostEqual(cg_x2 - 20.0, cx2, places=9)
        self.assertAlmostEqual(cg_y2 - (raw_h - 920.0), cy2_td, places=9)
        self.assertEqual(int((round(cx2 * 2.0) / 2.0) * (fb_w / 1280.0)), 900)
        self.assertEqual(int((round(cy2_td * 2.0) / 2.0) * (fb_h / 800.0)), 565)

        # Case C: Exhaustive 0-drift 2x Retina roundtrip across all Y pixels in 1512x982, 1440x900, 1280x800 & 1800x1131
        for cw, ch in ((1512.0, 982.0), (1440.0, 900.0), (1280.0, 800.0), (1800.0, 1131.0)):
            sx, sy = compute_sdl_origin(80.0, 60.0, ch, hooked_h)
            for fb_y_i in range(0, int(fb_h), 7):
                _, _, _, c_td = compute_inverse_warp(
                    sx + 900.0, sy + float(fb_y_i), sx, sy, fb_w, fb_h, 80.0, 60.0, cw, ch, raw_h
                )
                snapped = round(c_td * 2.0) / 2.0
                self.assertEqual(int(snapped * (fb_h / ch)), fb_y_i, f"drift at {cw}x{ch} fbY={fb_y_i}")

        # Case D: Native Fullscreen Space on notched MacBook (1800x1131 below 38pt notch): cgY includes +38pt notch offset
        fs_sx, fs_sy = compute_sdl_origin(0.0, 0.0, 1131.0, hooked_h)
        self.assertEqual((fs_sx, fs_sy), (0, 0))
        fs_cg_x, fs_cg_y, _, _ = compute_inverse_warp(
            900.0, 565.0, fs_sx, fs_sy, fb_w, fb_h, 0.0, 0.0, 1800.0, 1131.0, raw_h
        )
        self.assertEqual((fs_cg_x, fs_cg_y), (900.0, 38.0 + 565.0))

        # 2. Source & Mach-O symbol verification: inverse WarpMouse hooks + SDL_Window origin resync
        for tok in (
            "compute_inverse_warp_point",
            "resolve_inverse_warp_target_cg_point",
            "hook_CGWarpMouseCursorPosition",
            "hook_CGDisplayMoveCursorToPoint",
            '{ "_CGWarpMouseCursorPosition",    (void *)hook_CGWarpMouseCursorPosition },',
            '{ "_CGDisplayMoveCursorToPoint",   (void *)hook_CGDisplayMoveCursorToPoint },',
            "query_window_content_screen_rect",
            "sync_sdl_window_origin_to_frame",
            "raw_event_location_in_window",
            "tClampDragProjectionForSDL",
            "gNativeOptionCamHeld",
            "gPostingSyntheticFlagsEvent",
            "[NSApp postEvent:flagsEv atStart:YES]",
            'debuglog_write("WARP",',
            'debuglog_write("CTRL_ORBIT",',
            'debuglog_write("OPTION_CAM",',
            '"DidMove winFrame=',
            "matchesReducedWindowedTarget",
            "nsglSetView-async",
            "nsglMakeCurrent-async",
        ):
            self.assertIn(tok, src_m)

        # Ensure flush_stuck_modifier_state_to_sdl no longer calls the empty SDL2 no-op [listener flagsChanged:]
        flush_section = src_m.split("static void flush_stuck_modifier_state_to_sdl(NSWindow *win, const char *reason) {")[1].split("static BOOL try_accept_shortcut_trigger(")[0]
        self.assertNotIn("[listener flagsChanged:", flush_section)
        self.assertIn("[NSApp postEvent:flagsEv atStart:YES]", flush_section)

        # Ensure handle_camera_mouse_up handles Control+click left/right polarity mismatch cleanly
        up_section = src_m.split("static void handle_camera_mouse_up(")[1].split("static void swizzled_mouseDown(")[0]
        self.assertIn("isRight == gCtrlDragWasRight || ([NSEvent pressedMouseButtons] & 0x3) == 0", up_section)

        # Ensure NSWindowDidMoveNotification always syncs SDL_Window origin in windowed mode
        did_move_section = src_m.split("NSWindowDidMoveNotification")[1].split("NSWindowDidEnterFullScreenNotification")[0]
        self.assertIn('sync_sdl_window_origin_to_frame(win, "didMove");', did_move_section)
        self.assertLess(
            did_move_section.index("sync_sdl_window_origin_to_frame"),
            did_move_section.index("if (gWindowedModeActive)"),
        )

        # Compiled Mach-O dylib contains both hooked CoreGraphics cursor warp symbols
        self.assertIn(b"CGWarpMouseCursorPosition", dylib_raw)
        self.assertIn(b"CGDisplayMoveCursorToPoint", dylib_raw)

    def test_exp_boot_init_guard_and_numbered_crash_diag_reporter(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")

        # 1. Anti-crash boot protection during -[NSWindow initWithContentRect:...] (0x1001019c3)
        self.assertNotIn("@selector(findSDLWindow)", src_m)
        for tok in (
            "is_sdl_window_fully_attached",
            "safe_get_sdl_window_for_nswindow",
            'class_getInstanceVariable(listenerCls, "_data")',
            "if (!driverData)",
            "boundWin != (__bridge const void *)win",
        ):
            self.assertIn(tok, src_m)
        for swz in (
            "swizzled_sdlSetStyleMask",
            "swizzled_sdlSetLevel",
            "swizzled_sdlSetCollectionBehavior",
            "swizzled_sdlConstrainFrameRect",
            "swizzled_sdlSetFrameOrigin",
            "swizzled_sdlSetFrameTopLeftPoint",
            "swizzled_sdlSetFrameDisplay",
            "swizzled_sdlSetFrameDisplayAnimate",
            "swizzled_sdlSetContentSize",
        ):
            fn_body = src_m.split(f"{swz}(")[1][:420]
            self.assertIn("if (!win || ![win delegate])", fn_body, f"Missing early-init delegate guard in {swz}")

        # 2. Automatic crash reporter: sigaltstack, SA_ONSTACK|SA_NODEFER, dladdr, NSSetUncaughtExceptionHandler,
        #    SIG_DFL restoration without _exit() so macOS ReportCrash still generates native .ips reports.
        for tok in (
            "sigaltstack(&altStack, NULL)",
            "SA_SIGINFO | SA_ONSTACK | SA_NODEFER",
            "NSSetUncaughtExceptionHandler(&sims2_uncaught_objc_exception_handler)",
            "dladdr(frames[i], &dli)",
            "--- Symbolized Backtrace ---",
            "Signal Code   : ",
            "Patch State   : windowed=",
            "kSims2MaxNumberedLogs = 20",
            "scan_and_prune_numbered_logs",
            "sims2_crash_%03d.log",
            "sims2_patch_diag_%03d.log",
            "fsync(fd);",
        ):
            self.assertIn(tok, src_m)
        sig_handler_section = src_m.split("static void sims2_crash_signal_handler(")[1].split("static void sims2_uncaught_objc_exception_handler(")[0]
        self.assertIn("dfl.sa_handler = SIG_DFL;", sig_handler_section)
        self.assertIn("sigprocmask(SIG_UNBLOCK, &unblock, NULL);", sig_handler_section)
        self.assertIn("raise(sig);", sig_handler_section)
        self.assertNotIn("_exit(", sig_handler_section)

        # 3. Live x86_64 runtime tests on macOS:
        #    (a) Early -[SDLWindow initWithContentRect:...] with delegate == nil & crashing findSDLWindow -> exit 0
        #    (b) Cumulative numbered crash logs (sims2_crash_001.log -> sims2_crash_002.log + crash_report.log symlink +
        #        SIG_DFL signal exit code -11 for .ips + symbolized dladdr frames + fault address 0x8 + 20-file soft-prune)
        #    (c) Cumulative numbered opt-in diag logs (OFF by default; sims2_patch_diag_001.log -> 002.log + symlink + cap 20)
        if sys.platform == "darwin" and shutil.which("clang"):
            import signal as py_signal

            dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()
            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)

                # (a) Live ObjC probe simulating SDLWindow initWithContentRect: before delegate/driverdata attachment
                init_m = tmp_p / "init_probe.m"
                init_exe = tmp_p / "init_probe"
                init_m.write_text(
                    "#import <Cocoa/Cocoa.h>\n"
                    "@interface SDLWindow : NSWindow\n"
                    "- (void *)findSDLWindow;\n"
                    "@end\n"
                    "@implementation SDLWindow\n"
                    "- (void *)findSDLWindow {\n"
                    "    volatile char *bad = (volatile char *)0x8;\n"
                    "    return (void *)(uintptr_t)(*bad);\n"
                    "}\n"
                    "@end\n"
                    "int main(void) {\n"
                    "    @autoreleasepool {\n"
                    "        [NSApplication sharedApplication];\n"
                    "        SDLWindow *w = [[SDLWindow alloc] initWithContentRect:NSMakeRect(100, 100, 800, 600)\n"
                    "                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)\n"
                    "                                                      backing:NSBackingStoreBuffered\n"
                    "                                                        defer:NO];\n"
                    "        [w setReleasedWhenClosed:NO];\n"
                    "        [w setFrameOrigin:NSMakePoint(120, 120)];\n"
                    "        [w setContentSize:NSMakeSize(800, 600)];\n"
                    "        [w close];\n"
                    "    }\n"
                    "    return 0;\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_init = subprocess.run(
                    ["clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fobjc-arc", "-framework", "Cocoa", str(init_m), "-o", str(init_exe)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_init.returncode, 0, rc_init.stderr)
                h_init = tmp_p / "h_init"
                d_init = tmp_p / "d_init"
                h_init.mkdir()
                d_init.mkdir()
                env_init = {
                    **os.environ,
                    "HOME": str(h_init),
                    "SIMS2_DIAG_LOG_DIR": str(d_init),
                    "DYLD_INSERT_LIBRARIES": dylib_path,
                }
                env_init.pop("SIMS2_DEBUG", None)
                env_init.pop("SIMS2_DIAG_LOG", None)
                r_init = subprocess.run([str(init_exe)], env=env_init, capture_output=True, text=True)
                self.assertEqual(r_init.returncode, 0, f"SDLWindow init crashed rc={r_init.returncode} err={r_init.stderr}")
                self.assertFalse((h_init / "Library" / "Logs" / "Sims2-Crash-Patch").exists())

                # (b) & (c) Live crash & diag numbering probe
                probe_c = tmp_p / "crash_diag_probe.c"
                probe_exe = tmp_p / "crash_diag_probe"
                probe_c.write_text(
                    "#include <string.h>\n"
                    "__attribute__((noinline)) static int trigger_segv_at_0x8(void) {\n"
                    "    volatile unsigned long *p = (volatile unsigned long *)0x8;\n"
                    "    return (int)(*p);\n"
                    "}\n"
                    "int main(int argc, char **argv) {\n"
                    "    if (argc > 1 && strcmp(argv[1], \"segv8\") == 0) return trigger_segv_at_0x8();\n"
                    "    return 0;\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_p = subprocess.run(
                    ["clang", "-arch", "x86_64", "-O0", str(probe_c), "-o", str(probe_exe)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_p.returncode, 0, rc_p.stderr)

                h_cr = tmp_p / "h_cr"
                d_cr = tmp_p / "d_cr"
                h_cr.mkdir()
                d_cr.mkdir()
                crash_dir = h_cr / "Library" / "Logs" / "Sims2-Crash-Patch"
                base_env = {
                    **os.environ,
                    "HOME": str(h_cr),
                    "SIMS2_DIAG_LOG_DIR": str(d_cr),
                    "DYLD_INSERT_LIBRARIES": dylib_path,
                }
                base_env.pop("SIMS2_DEBUG", None)
                base_env.pop("SIMS2_DIAG_LOG", None)

                # Crash #1 -> sims2_crash_001.log + symlink crash_report.log + SIG_DFL death (-SIGSEGV)
                r_c1 = subprocess.run([str(probe_exe), "segv8"], env=base_env, capture_output=True, text=True)
                self.assertEqual(r_c1.returncode, -int(py_signal.SIGSEGV), f"Expected SIG_DFL death (-SIGSEGV), got rc={r_c1.returncode}")
                c1 = crash_dir / "sims2_crash_001.log"
                clink = crash_dir / "crash_report.log"
                self.assertTrue(c1.is_file(), "Missing sims2_crash_001.log")
                self.assertTrue(clink.is_symlink(), "crash_report.log should be a symlink to latest numbered crash log")
                self.assertEqual(os.readlink(clink), "sims2_crash_001.log")
                c1_txt = c1.read_text(encoding="utf-8")
                for expected in (
                    "Timestamp     :",
                    "Crash Log #   : 1 ",
                    "Patch Version : 1.5.0",
                    "SIGSEGV",
                    "Signal Code   :",
                    "Fault Address : 0x8",
                    "Patch State   : windowed=",
                    "--- Symbolized Backtrace ---",
                    "#0  0x",
                    " + 0x",
                ):
                    self.assertIn(expected, c1_txt)

                # Crash #2 -> sims2_crash_002.log without overwriting sims2_crash_001.log
                r_c2 = subprocess.run([str(probe_exe), "segv8"], env=base_env, capture_output=True, text=True)
                self.assertEqual(r_c2.returncode, -int(py_signal.SIGSEGV))
                c2 = crash_dir / "sims2_crash_002.log"
                self.assertTrue(c1.is_file(), "sims2_crash_001.log must never be overwritten")
                self.assertTrue(c2.is_file(), "Missing sims2_crash_002.log")
                self.assertEqual(os.readlink(clink), "sims2_crash_002.log")
                self.assertIn("Crash Log #   : 2 ", c2.read_text(encoding="utf-8"))

                # Soft-prune cap 20 on crash logs: create 003..022 (total 22), boot clean -> prunes 001 & 002 to 20
                for idx in range(3, 23):
                    (crash_dir / f"sims2_crash_{idx:03d}.log").write_text(f"dummy {idx}\n", encoding="utf-8")
                r_prune = subprocess.run([str(probe_exe)], env=base_env, capture_output=True, text=True)
                self.assertEqual(r_prune.returncode, 0)
                remaining_crashes = sorted(p.name for p in crash_dir.glob("sims2_crash_*.log"))
                self.assertEqual(len(remaining_crashes), 20)
                self.assertEqual(remaining_crashes[0], "sims2_crash_003.log")
                self.assertEqual(remaining_crashes[-1], "sims2_crash_022.log")

                # Opt-in diag logs: OFF by default -> 0 files
                self.assertEqual(list(d_cr.glob("sims2_patch_diag*.log")), [])

                # Opt-in diag logs ON: Run 1 -> sims2_patch_diag_001.log, Run 2 -> sims2_patch_diag_002.log + symlink
                env_diag = {**base_env, "SIMS2_DIAG_LOG": "1"}
                self.assertEqual(subprocess.run([str(probe_exe)], env=env_diag, capture_output=True, text=True).returncode, 0)
                d1 = d_cr / "sims2_patch_diag_001.log"
                dlink = d_cr / "sims2_patch_diag.log"
                self.assertTrue(d1.is_file())
                self.assertTrue(dlink.is_symlink())
                self.assertEqual(os.readlink(dlink), "sims2_patch_diag_001.log")

                self.assertEqual(subprocess.run([str(probe_exe)], env=env_diag, capture_output=True, text=True).returncode, 0)
                d2 = d_cr / "sims2_patch_diag_002.log"
                self.assertTrue(d1.is_file(), "sims2_patch_diag_001.log must be preserved")
                self.assertTrue(d2.is_file(), "Missing sims2_patch_diag_002.log")
                self.assertEqual(os.readlink(dlink), "sims2_patch_diag_002.log")

                # Cap 20 on diag logs: create 003..022, run with SIMS2_DIAG_LOG=1 -> creates 023 and prunes to <= 20
                for idx in range(3, 23):
                    (d_cr / f"sims2_patch_diag_{idx:03d}.log").write_text(f"diag {idx}\n", encoding="utf-8")
                self.assertEqual(subprocess.run([str(probe_exe)], env=env_diag, capture_output=True, text=True).returncode, 0)
                remaining_diags = sorted(p.name for p in d_cr.glob("sims2_patch_diag_*.log"))
                self.assertEqual(len(remaining_diags), 20)
                self.assertEqual(remaining_diags[0], "sims2_patch_diag_004.log")
                self.assertEqual(remaining_diags[-1], "sims2_patch_diag_023.log")
                self.assertEqual(os.readlink(dlink), "sims2_patch_diag_023.log")

    def test_exp_rc1_fail_enter_fullscreen_multiscreen_and_installer(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")
        patch_sh = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")

        # 1. Source guards: NSWindow* delegate extractor, _objc_msgForward guard, failEnter/failExit swizzles,
        #    deferred Affichage menu dispatch, multi-screen screens[0] CG height, live screen params observer,
        #    compact screen presets, and external mouse wheel bypass.
        for sym in (
            '#import <objc/message.h>',
            'SIMS2_PATCH_VERSION "1.5.0"',
            "extract_nswindow_from_delegate_arg",
            "is_callable_orig_imp",
            "_objc_msgForward",
            "swizzled_windowDidFailToEnterFullScreen",
            "swizzled_windowDidFailToExitFullScreen",
            "gOrigWindowDidFailToExitFullScreenIMP",
            "failEnterFullScreenRollback",
            "query_primary_screen_height_for_cg",
            "NSApplicationDidChangeScreenParametersNotification",
            "rebuild_sims2_display_menu_resolution_items",
            "hasPreciseScrollingDeltas",
            "gCtrlMiddleDragActive",
        ):
            self.assertIn(sym, src_m, f"Missing v1.5.0-rc1 safeguard in sims2_trackpad.m: {sym}")

        # Deferred dispatch inside Affichage menu actions so NSMenu exits tracking before toggleFullScreen:
        impl_idx = src_m.find("@implementation Sims2DisplayMenuHandler")
        self.assertNotEqual(impl_idx, -1, "Missing @implementation Sims2DisplayMenuHandler")
        for menu_sel in ("- (void)onToggleWindowedMode:", "- (void)onCycleResolution:", "- (void)onSelectResolution:"):
            idx = src_m.find(menu_sel, impl_idx)
            self.assertNotEqual(idx, -1, f"Missing {menu_sel} in @implementation Sims2DisplayMenuHandler")
            body = src_m[idx : idx + 600]
            self.assertIn("dispatch_async(dispatch_get_main_queue()", body, f"{menu_sel} must defer action via dispatch_async")

        # 2. Multi-screen & non-Retina math: secondary monitor at origin=(1800, 0), size 1920x1080 (scale=1.0, safeTop=0)
        #    next to notched primary screens[0] 1800x1169 -> CoreGraphics Y MUST use screens[0] height (1169), not 1080.
        primary_h = 1169.0
        sec_origin_x, sec_origin_y, sec_w, sec_h = 1800.0, 0.0, 1920.0, 1080.0
        win_w, win_h = 1280.0, 800.0
        content_x = sec_origin_x + (sec_w - win_w) / 2.0  # 2120
        content_y = sec_origin_y + (sec_h - win_h) / 2.0  # 140
        cg_origin_y = primary_h - (content_y + win_h)     # 1169 - 940 = 229
        self.assertEqual(cg_origin_y, 229.0)
        self.assertNotEqual(cg_origin_y, sec_h - (content_y + win_h))
        # Center of 1280x800 content maps cleanly inside secondary monitor CG rect
        warp_cg_x = content_x + (win_w / 2.0)
        warp_cg_y = cg_origin_y + (win_h / 2.0)
        self.assertEqual((warp_cg_x, warp_cg_y), (2760.0, 629.0))
        self.assertTrue(content_x <= warp_cg_x <= content_x + win_w)
        self.assertTrue(cg_origin_y <= warp_cg_y <= cg_origin_y + win_h)

        # 3. Small screens (1512x982 default MBP14 scale, 1440x900, 1280x800) must always get >= 2 valid windowed presets
        base_presets = [
            (2048, 1280), (1920, 1200), (1920, 1080), (1728, 1080),
            (1680, 1050), (1600, 1000), (1512, 982), (1440, 900), (1280, 800),
        ]
        small_presets = [(1152, 720), (1024, 640), (960, 600)]
        for vis_w, vis_h in ((1512, 949), (1440, 868), (1280, 768)):
            max_w = max(800, vis_w - 24)
            max_h = max(600, vis_h - 40)
            choices = [(w, h) for (w, h) in base_presets if w <= max_w and h <= max_h]
            if len(choices) < 2:
                for (w, h) in small_presets:
                    if w <= max_w and h <= max_h and (w, h) not in choices:
                        choices.append((w, h))
            self.assertGreaterEqual(len(choices), 2, f"Expected >= 2 windowed presets for visibleFrame {vis_w}x{vis_h}")
            for (w, h) in choices:
                self.assertLessEqual(w, vis_w)
                self.assertLessEqual(h, vis_h)

        # 4. patch_sims2.command v1.5.0-rc1 checks: version, obsolete prefs cleanup, ad-hoc sign WITHOUT --deep,
        #    strict --verify --deep --strict, Command shortcuts, crash log path, zero Upscaling / Option+U / Option+R.
        self.assertIn('PATCH_VERSION="1.5.0"', patch_sh)
        self.assertIn("cleanup_obsolete_experimental_prefs", patch_sh)
        for obsolete_key in (
            "S2PatchFullscreenUpscaling",
            "S2PatchWindowedMode",
            "S2PatchTargetWidth",
            "S2PatchTargetHeight",
            "S2PatchPrefsConfigured",
        ):
            self.assertIn(obsolete_key, patch_sh, f"Missing obsolete pref cleanup for {obsolete_key}")
        self.assertIn("xattr -cr", patch_sh)
        self.assertIn("codesign --force --sign -", patch_sh)
        self.assertNotIn("codesign --force --deep", patch_sh, "Signing must NOT use deprecated --deep flag")
        self.assertIn("codesign --verify --deep --strict", patch_sh)
        # sign_and_verify_app must sign inside-out: dylib -> Sims2XP_Exe -> .app bundle (because CFBundleExecutable is the Aspyr launcher)
        sv_idx = patch_sh.find("sign_and_verify_app() {")
        self.assertNotEqual(sv_idx, -1)
        sv_body = patch_sh[sv_idx : sv_idx + 1800]
        pos_dylib = sv_body.find('codesign --force --sign - "$target_dylib"')
        pos_bin = sv_body.find('codesign --force --sign - "$target_bin"')
        pos_app = sv_body.find('codesign --force --sign - "$target_app"')
        self.assertIn('target_bin="$target_app/Contents/MacOS/Sims2XP_Exe"', sv_body)
        self.assertTrue(0 <= pos_dylib < pos_bin < pos_app, "Must sign dylib -> Sims2XP_Exe -> .app inside-out")
        if sys.platform == "darwin":
            with tempfile.TemporaryDirectory() as tmp_cs:
                sub_app = Path(tmp_cs) / "SimsLauncherTest.app"
                sub_macos = sub_app / "Contents" / "MacOS"
                sub_macos.mkdir(parents=True)
                launcher = sub_macos / "The Sims 2"
                launcher.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                launcher.chmod(0o755)
                sub_exe = sub_macos / "Sims2XP_Exe"
                sub_exe.write_text("#!/bin/sh\n# v1\nexit 0\n", encoding="utf-8")
                sub_exe.chmod(0o755)
                shutil.copy2(ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib", sub_macos / "libsims2_trackpad.dylib")
                (sub_app / "Contents" / "Info.plist").write_text(
                    '<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                    '<plist version="1.0"><dict>'
                    '<key>CFBundleExecutable</key><string>The Sims 2</string>'
                    '<key>CFBundleIdentifier</key><string>com.example.sims2test</string>'
                    '</dict></plist>\n',
                    encoding="utf-8",
                )
                r_s1 = self._run_bash_lib("patch_sims2.command", 'sign_and_verify_app "$1"', sub_app.as_posix())
                self.assertEqual(r_s1.returncode, 0, r_s1.stderr or r_s1.stdout)
                # Modify Sims2XP_Exe subcomponent (like a binary patch) -> sign_and_verify_app must re-sign it cleanly without --deep
                sub_exe.write_text("#!/bin/sh\n# v2 patched\nexit 0\n", encoding="utf-8")
                sub_exe.chmod(0o755)
                r_s2 = self._run_bash_lib("patch_sims2.command", 'sign_and_verify_app "$1"', sub_app.as_posix())
                self.assertEqual(r_s2.returncode, 0, r_s2.stderr or r_s2.stdout)
                v_sub = subprocess.run(
                    ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(sub_app)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(v_sub.returncode, 0, v_sub.stderr)
        for summary_tok in ("⌘ + Entrée", "⌘ + R", "Affichage", "sims2_crash_XXX.log"):
            self.assertIn(summary_tok, patch_sh)
        patch_sh_without_cleanup_key = patch_sh.replace("S2PatchFullscreenUpscaling", "")
        for forbidden_tok in ("Upscaling", "Option + U", "Option + R"):
            self.assertNotIn(forbidden_tok, patch_sh_without_cleanup_key)

        # 5. Live x86_64 ObjC runtime test: invoke windowDidFailToEnterFullScreen:(NSWindow *) directly
        #    on swizzled Cocoa_WindowListener with a real SDLWindow* (NOT NSNotification*) -> zero exception,
        #    original IMP invoked, and clean rollback to windowed=1 / inSpace=0.
        if sys.platform == "darwin" and vp.find_unix_tool("clang", ()):
            dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()
            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)
                probe_m = tmp_p / "fail_fs_probe.m"
                probe_exe = tmp_p / "fail_fs_probe"
                probe_m.write_text(
                    "#import <Cocoa/Cocoa.h>\n"
                    "#import <stdio.h>\n"
                    "static int gOrigEnterFailCalls = 0;\n"
                    "static int gOrigExitFailCalls = 0;\n"
                    "@interface SDLWindow : NSWindow\n"
                    "@end\n"
                    "@implementation SDLWindow\n"
                    "@end\n"
                    "@interface Cocoa_WindowListener : NSObject <NSWindowDelegate>\n"
                    "@end\n"
                    "@implementation Cocoa_WindowListener\n"
                    "- (void)windowDidFailToEnterFullScreen:(NSWindow *)window {\n"
                    "    if ([window isKindOfClass:[NSWindow class]]) gOrigEnterFailCalls++;\n"
                    "}\n"
                    "- (void)windowDidFailToExitFullScreen:(NSWindow *)window {\n"
                    "    if ([window isKindOfClass:[NSWindow class]]) gOrigExitFailCalls++;\n"
                    "}\n"
                    "@end\n"
                    "int main(void) {\n"
                    "    @autoreleasepool {\n"
                    "        [NSApplication sharedApplication];\n"
                    "        Cocoa_WindowListener *listener = [[Cocoa_WindowListener alloc] init];\n"
                    "        SDLWindow *w = [[SDLWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1280, 800)\n"
                    "                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)\n"
                    "                                                      backing:NSBackingStoreBuffered\n"
                    "                                                        defer:NO];\n"
                    "        [w setReleasedWhenClosed:NO];\n"
                    "        [w setDelegate:listener];\n"
                    "        /* Trigger exact AppKit NSWindowDelegate signature: NSWindow* (NOT NSNotification*) */\n"
                    "        [listener windowDidFailToEnterFullScreen:w];\n"
                    "        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];\n"
                    "        [listener windowDidFailToExitFullScreen:w];\n"
                    "        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];\n"
                    "        [w setDelegate:nil];\n"
                    "        [w close];\n"
                    "        printf(\"enterFail=%d exitFail=%d style=0x%lx\\n\", gOrigEnterFailCalls, gOrigExitFailCalls, (unsigned long)[w styleMask]);\n"
                    "        /* When stillInSpace == NO, swizzled_windowDidFailToExitFullScreen MUST skip Aspyr's bogus\n"
                    "           orig IMP (which called [self windowDidEnterFullScreen:nil] and corrupted styleMask -> 0x0). */\n"
                    "        return (gOrigEnterFailCalls == 1 && gOrigExitFailCalls == 0 && (([w styleMask] & NSWindowStyleMaskTitled) != 0)) ? 0 : 42;\n"
                    "    }\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_build = subprocess.run(
                    ["clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fobjc-arc", "-framework", "Cocoa", str(probe_m), "-o", str(probe_exe)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_build.returncode, 0, rc_build.stderr)

                h_fs = tmp_p / "h_fs"
                d_fs = tmp_p / "d_fs"
                h_fs.mkdir()
                d_fs.mkdir()
                env_fs = {
                    **os.environ,
                    "HOME": str(h_fs),
                    "SIMS2_DIAG_LOG_DIR": str(d_fs),
                    "SIMS2_DIAG_LOG": "1",
                    "DYLD_INSERT_LIBRARIES": dylib_path,
                }
                env_fs.pop("SIMS2_DEBUG", None)
                r_fs = subprocess.run([str(probe_exe)], env=env_fs, capture_output=True, text=True)
                self.assertEqual(r_fs.returncode, 0, f"windowDidFailToEnterFullScreen probe failed rc={r_fs.returncode} out={r_fs.stdout} err={r_fs.stderr}")
                self.assertIn("enterFail=1 exitFail=0", r_fs.stdout)
                self.assertNotIn("doesNotRecognizeSelector", r_fs.stderr)
                self.assertFalse((h_fs / "Library" / "Logs" / "Sims2-Crash-Patch").exists(), "Zero crash log should be written")
                diag_txt = (d_fs / "sims2_patch_diag.log").read_text(encoding="utf-8")
                self.assertIn("windowDidFailToEnterFullScreen win=0x", diag_txt)
                self.assertIn("windowDidFailToExitFullScreen win=0x", diag_txt)
                self.assertIn("stillInSpace=0 windowed=1", diag_txt)
                self.assertNotIn("windowDidEnterFullScreen win=0x0", diag_txt)

    def test_exp_rc2_multiscreen_aspect_fit_no_bounce_opengl_and_fail_exit_fs(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")
        restore_sh = (ROOT_DIR / "restore_sims2.command").read_text(encoding="utf-8")
        clean_sh = (ROOT_DIR / "clean_sims2_cache.command").read_text(encoding="utf-8")
        patch_sh = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")

        # 1. Pure aspect-fit formula verification (compute_aspect_fitted_fullscreen_rect):
        #    1800x1131 on 1920x1080@(1800,89) -> 1719x1080@(1900,89) (symmetric pillarboxes, zero stretch)
        #    1800x1131 on 1800x1130@(0,0)     -> 1800x1130@(0,0) (<= 2%, full-bleed)
        #    1920x1080 on 1920x1080@(1800,89) -> 1920x1080@(1800,89) (TV primary, full-bleed 16:9)
        def aspect_fit(sx: float, sy: float, sw: float, sh: float, fb_w: float, fb_h: float) -> tuple[int, int, int, int]:
            screen_aspect = sw / sh
            fb_aspect = fb_w / fb_h
            rel_diff = abs(screen_aspect - fb_aspect) / fb_aspect
            if rel_diff <= 0.02:
                return int(sx), int(sy), int(sw), int(sh)
            if screen_aspect > fb_aspect:
                fit_h = sh
                fit_w = int(fit_h * fb_aspect + 0.5)
                fit_x = sx + int((sw - fit_w) // 2)
                return int(fit_x), int(sy), int(fit_w), int(fit_h)
            fit_w = sw
            fit_h = int(fit_w / fb_aspect + 0.5)
            fit_y = sy + int((sh - fit_h) // 2)
            return int(sx), int(fit_y), int(fit_w), int(fit_h)

        self.assertEqual(aspect_fit(1800, 89, 1920, 1080, 1800, 1131), (1900, 89, 1719, 1080))
        self.assertEqual(aspect_fit(0, 0, 1800, 1130, 1800, 1131), (0, 0, 1800, 1130))
        self.assertEqual(aspect_fit(1800, 89, 1920, 1080, 1920, 1080), (1800, 89, 1920, 1080))
        self.assertEqual(aspect_fit(0, 0, 1800, 1130, 1920, 1080), (0, 58, 1800, 1013))

        # 2. Source safeguards for Bugs 1, 2, 3, and 4 in sims2_trackpad.m
        for sym in (
            "compute_aspect_fitted_fullscreen_rect",
            "resolve_screen_for_rect",
            "compute_anti_tiling_windowed_frame",
            "compute_windowed_game_frame_on_screen",
            "refresh_opengl_surface_for_screen_or_backing_change",
            "NSWindowDidChangeScreenNotification",
            "NSWindowDidChangeBackingPropertiesNotification",
            "CGLUpdateContext(cglCtx)",
            "[nsglCtx update]",
            "setNeedsDisplay:YES",
            "gAllowExplicitSpaceReactivation",
            "NSApplicationPresentationFullScreen",
            "gPrimaryNotchTopInset",
            "gPrimaryRawScreenHeight",
            "failExitFullScreenToWindowed",
            "IGNORED spurious windowDidEnterFullScreen",
            "engine_fb_is_widescreen_16_9",
        ):
            self.assertIn(sym, src_m, f"Missing v1.5.0-rc2 multi-screen fix in sims2_trackpad.m: {sym}")

        # Verify swizzled_sdlConstrainFrameRect delegates to NSWindow superclass instead of Aspyr's Display-0 clamp
        cf_idx = src_m.find("static NSRect swizzled_sdlConstrainFrameRect(")
        self.assertNotEqual(cf_idx, -1)
        cf_end = src_m.find("static void sync_content_view_to_window_bounds(", cf_idx)
        cf_body = src_m[cf_idx : cf_end if cf_end != -1 else cf_idx + 5200]
        self.assertIn("[NSWindow instanceMethodForSelector:@selector(constrainFrameRect:toScreen:)]", cf_body)
        self.assertIn("resolve_screen_for_rect(", cf_body)

        # 3. Version consistency across all scripts & docs (zero stale v1.4.1 banners in restore/clean)
        self.assertIn('PATCH_VERSION="1.5.0"', patch_sh)
        self.assertIn('SCRIPT_VERSION="1.5.0"', restore_sh)
        self.assertIn('SCRIPT_VERSION="1.5.0"', clean_sh)
        self.assertNotIn("v1.4.1", restore_sh)
        self.assertNotIn("v1.4.1", clean_sh)
        for doc_name in ("README.md", "README.txt"):
            doc = (ROOT_DIR / doc_name).read_text(encoding="utf-8")
            self.assertIn("v1.5.0", doc)
            self.assertIn("16:9", doc)
            self.assertIn("16:10", doc)

        # 4. Live x86_64 ObjC runtime test for BUG 1 (no snap from x=2004 -> x=288 on secondary monitor)
        #    and BUG 4 (windowDidFailToExitFullScreen with stillInSpace==NO keeps styleMask=0xf, windowed=1,
        #    and never triggers Aspyr's bogus windowDidEnterFullScreen:nil / styleMask=0x0).
        if sys.platform == "darwin" and vp.find_unix_tool("clang", ()):
            dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()
            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)
                probe_m = tmp_p / "multiscreen_rc2_probe.m"
                probe_exe = tmp_p / "multiscreen_rc2_probe"
                probe_m.write_text(
                    "#import <Cocoa/Cocoa.h>\n"
                    "#import <stdio.h>\n"
                    "static int gAspyrDisplay0BounceCalled = 0;\n"
                    "static int gAspyrBogusFailExitCalled = 0;\n"
                    "@interface SDLWindow : NSWindow\n"
                    "@end\n"
                    "@implementation SDLWindow\n"
                    "- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {\n"
                    "    /* Mimic Aspyr's exact 0x100101050 bug: clamp secondary-screen x onto Display 0 [0,1800] */\n"
                    "    gAspyrDisplay0BounceCalled++;\n"
                    "    NSRect r = [super constrainFrameRect:frameRect toScreen:screen];\n"
                    "    if (r.origin.x + r.size.width > 1800.0) r.origin.x = 1800.0 - r.size.width;\n"
                    "    return r;\n"
                    "}\n"
                    "@end\n"
                    "@interface Cocoa_WindowListener : NSObject <NSWindowDelegate>\n"
                    "@end\n"
                    "@implementation Cocoa_WindowListener\n"
                    "- (void)windowDidEnterFullScreen:(NSNotification *)n { (void)n; }\n"
                    "- (void)windowDidFailToEnterFullScreen:(NSWindow *)w { (void)w; }\n"
                    "- (void)windowDidFailToExitFullScreen:(NSWindow *)w {\n"
                    "    /* Mimic Aspyr's exact 0x1001030e0 bug: tail-call windowDidEnterFullScreen:nil & set styleMask=0 */\n"
                    "    gAspyrBogusFailExitCalled++;\n"
                    "    [self windowDidEnterFullScreen:nil];\n"
                    "    [w setStyleMask:0];\n"
                    "}\n"
                    "@end\n"
                    "int main(void) {\n"
                    "    @autoreleasepool {\n"
                    "        [NSApplication sharedApplication];\n"
                    "        Cocoa_WindowListener *listener = [[Cocoa_WindowListener alloc] init];\n"
                    "        SDLWindow *w = [[SDLWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1512, 982)\n"
                    "                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |\n"
                    "                                                               NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)\n"
                    "                                                      backing:NSBackingStoreBuffered\n"
                    "                                                        defer:NO];\n"
                    "        [w setReleasedWhenClosed:NO];\n"
                    "        [w setDelegate:listener];\n"
                    "        /* Enter Windowed mode cleanly */\n"
                    "        [listener windowDidFailToEnterFullScreen:w];\n"
                    "        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];\n"
                    "        /* BUG 1 probe: constrain a TV window at x=2004 (1512x1010) -> must NOT snap to x=288! */\n"
                    "        NSRect tvRect = NSMakeRect(2004.0, 109.0, 1512.0, 1010.0);\n"
                    "        NSRect constrained = [w constrainFrameRect:tvRect toScreen:nil];\n"
                    "        /* BUG 4 probe: spurious windowDidFailToExitFullScreen while stillInSpace==NO (fs=0) */\n"
                    "        [listener windowDidFailToExitFullScreen:w];\n"
                    "        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];\n"
                    "        NSUInteger finalStyle = (NSUInteger)[w styleMask];\n"
                    "        printf(\"constrainedX=%.0f bounceCalls=%d bogusFailExit=%d finalStyle=0x%lx\\n\",\n"
                    "               constrained.origin.x, gAspyrDisplay0BounceCalled, gAspyrBogusFailExitCalled, (unsigned long)finalStyle);\n"
                    "        [w setDelegate:nil];\n"
                    "        [w close];\n"
                    "        if (constrained.origin.x < 2000.0 || gAspyrDisplay0BounceCalled != 0) return 11;\n"
                    "        if (gAspyrBogusFailExitCalled != 0 || finalStyle != 0xf) return 12;\n"
                    "        return 0;\n"
                    "    }\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_build = subprocess.run(
                    ["clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fobjc-arc", "-framework", "Cocoa", str(probe_m), "-o", str(probe_exe)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_build.returncode, 0, rc_build.stderr)
                h_rc2 = tmp_p / "h_rc2"
                d_rc2 = tmp_p / "d_rc2"
                h_rc2.mkdir()
                d_rc2.mkdir()
                env_rc2 = {
                    **os.environ,
                    "HOME": str(h_rc2),
                    "SIMS2_DIAG_LOG_DIR": str(d_rc2),
                    "SIMS2_DIAG_LOG": "1",
                    "DYLD_INSERT_LIBRARIES": dylib_path,
                }
                env_rc2.pop("SIMS2_DEBUG", None)
                r_rc2 = subprocess.run([str(probe_exe)], env=env_rc2, capture_output=True, text=True)
                self.assertEqual(r_rc2.returncode, 0, f"rc2 multiscreen probe failed rc={r_rc2.returncode} out={r_rc2.stdout} err={r_rc2.stderr}")
                self.assertIn("constrainedX=2004 bounceCalls=0 bogusFailExit=0 finalStyle=0xf", r_rc2.stdout)
                self.assertFalse((h_rc2 / "Library" / "Logs" / "Sims2-Crash-Patch").exists())
                diag_txt = (d_rc2 / "sims2_patch_diag.log").read_text(encoding="utf-8")
                self.assertIn("windowDidFailToExitFullScreen win=0x", diag_txt)
                self.assertNotIn("windowDidEnterFullScreen win=0x0", diag_txt)

    def test_exp_rc2_bug_a_exit_fs_tv_and_bug_b_coalesced_mission_control(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")

        # 1. Bug A static guards: preserve origin monitor (e.g. TV) when exiting Fullscreen Space,
        #    even mid-animation while gInFullscreenTransition==YES, plus 180 ms post-exit settle.
        for sym in (
            "remember_exit_fullscreen_target_screen",
            "clear_exit_fullscreen_target_screen",
            "resolve_active_exit_fullscreen_target_screen",
            "didExitFullScreenSettle",
            "gExitFullscreenTargetScreen",
            "gExitFullscreenTargetFrame",
            "gHasExitFullscreenTarget",
            "if (!gUserRequestedFullscreenExit && !gUserRequestedFullscreenEnter)",
        ):
            self.assertIn(sym, src_m, f"Missing Bug A safeguard in sims2_trackpad.m: {sym}")

        cf_idx = src_m.find("static NSRect swizzled_sdlConstrainFrameRect(")
        self.assertNotEqual(cf_idx, -1)
        cf_end = src_m.find("static void sync_content_view_to_window_bounds(", cf_idx)
        cf_body = src_m[cf_idx : cf_end if cf_end != -1 else cf_idx + 5200]
        self.assertIn("if (gWindowedModeActive || gInFullscreenTransition || gHasExitFullscreenTarget)", cf_body)
        self.assertNotIn("if (gWindowedModeActive && !gInFullscreenTransition)", cf_body)

        wex_idx = src_m.find("static void swizzled_windowWillExitFullScreen(")
        self.assertNotEqual(wex_idx, -1)
        self.assertIn("remember_exit_fullscreen_target_screen(", src_m[wex_idx : wex_idx + 1200])

        dex_idx = src_m.find("static void swizzled_windowDidExitFullScreen(")
        self.assertNotEqual(dex_idx, -1)
        dex_end = src_m.find("static void swizzled_windowDidFailToExitFullScreen(", dex_idx)
        dex_body = src_m[dex_idx : dex_end if dex_end != -1 else dex_idx + 5200]
        self.assertIn("didExitFullScreenSettle", dex_body)
        self.assertIn("clear_exit_fullscreen_target_screen();", dex_body)

        # 2. Bug B static guards: coalesced/debounced OpenGL refresh (zero synchronous setFrame: or CGL storm
        #    while inactive in Mission Control), and 150 ms deferred Space reactivation that yields to macOS activation.
        for sym in (
            "gOpenGLRefreshSeq",
            "gSpaceReactivateSeq",
            "gLastAppliedGlBackingScale",
            "gLastAppliedGlScreen",
            "Coalesced OpenGL refresh",
            "Deferred reactivation of game Fullscreen Space",
            "didResizeSpaceInactive",
        ):
            self.assertIn(sym, src_m, f"Missing Bug B safeguard in sims2_trackpad.m: {sym}")

        gl_ref_idx = src_m.find("static void refresh_opengl_surface_for_screen_or_backing_change(NSWindow *win, const char *reason) {")
        self.assertNotEqual(gl_ref_idx, -1)
        gl_ref_end = src_m.find("static void clear_exit_fullscreen_target_screen(", gl_ref_idx)
        gl_ref_body = src_m[gl_ref_idx : gl_ref_end if gl_ref_end != -1 else gl_ref_idx + 4000]
        da_pos = gl_ref_body.find("dispatch_after(")
        self.assertNotEqual(da_pos, -1, "refresh_opengl_surface_for_screen_or_backing_change must debounce via dispatch_after")
        pre_da = gl_ref_body[:da_pos]
        post_da = gl_ref_body[da_pos:]
        self.assertNotIn("ensure_fullscreen_space_geometry(", pre_da, "Must never call setFrame:/ensure_fullscreen_space_geometry synchronously")
        self.assertNotIn("apply_opengl_surface_backing_size_ex(", pre_da, "Must coalesce CGL updates inside debounced dispatch_after")
        self.assertIn("if (!gWindowedModeActive && wInSpace && appActive)", post_da)

        clamp_idx = src_m.find("static BOOL should_clamp_stale_windowed_frame_during_fullscreen(")
        self.assertNotEqual(clamp_idx, -1)
        self.assertIn("if (!gInFullscreenTransition && NSApp && ![NSApp isActive])", src_m[clamp_idx : clamp_idx + 600])

        sp_idx = src_m.find("static void ensure_workspace_space_observer_registered(void) {")
        self.assertNotEqual(sp_idx, -1)
        sp_end = src_m.find("static void register_window_geometry_observers(", sp_idx)
        sp_body = src_m[sp_idx : sp_end if sp_end != -1 else sp_idx + 6000]
        else_if_pos = sp_body.find("} else if (primaryWin && !gAppIsHiding")
        self.assertNotEqual(else_if_pos, -1)
        sp_inactive = sp_body[else_if_pos:]
        sp_da_pos = sp_inactive.find("dispatch_after(")
        sp_act_pos = sp_inactive.find("[NSApp activateIgnoringOtherApps:YES]")
        sp_active_guard_pos = sp_inactive.find("if (NSApp && [NSApp isActive])")
        self.assertTrue(0 < sp_da_pos < sp_active_guard_pos < sp_act_pos,
                        "NSWorkspaceActiveSpaceDidChangeNotification must defer activateIgnoringOtherApps:YES inside dispatch_after after checking [NSApp isActive]")

        # 3. Live x86_64 ObjC runtime test for Bug A:
        #    Invoke windowWillExitFullScreen: (gInFullscreenTransition == YES) and call constrainFrameRect:toScreen:
        #    with TV coordinates (x=1957, 1512x1010) MID-TRANSITION -> must keep x=1957 and never invoke Aspyr's 0x100101050 clamp!
        if sys.platform == "darwin" and vp.find_unix_tool("clang", ()):
            dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()
            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)
                probe_m = tmp_p / "bug_a_exit_fs_probe.m"
                probe_exe = tmp_p / "bug_a_exit_fs_probe"
                probe_m.write_text(
                    "#import <Cocoa/Cocoa.h>\n"
                    "#import <stdio.h>\n"
                    "static int gAspyrDisplay0BounceCalled = 0;\n"
                    "static int gProbeArmed = 0;\n"
                    "@interface SDLWindow : NSWindow\n"
                    "@end\n"
                    "@implementation SDLWindow\n"
                    "- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {\n"
                    "    if (!gProbeArmed) return frameRect;\n"
                    "    gAspyrDisplay0BounceCalled++;\n"
                    "    NSRect r = [super constrainFrameRect:frameRect toScreen:screen];\n"
                    "    if (r.origin.x + r.size.width > 1800.0) r.origin.x = 1800.0 - r.size.width;\n"
                    "    return r;\n"
                    "}\n"
                    "@end\n"
                    "@interface Cocoa_WindowListener : NSObject <NSWindowDelegate>\n"
                    "@end\n"
                    "@implementation Cocoa_WindowListener\n"
                    "- (void)windowWillExitFullScreen:(NSNotification *)n { (void)n; }\n"
                    "- (void)windowDidExitFullScreen:(NSNotification *)n { (void)n; }\n"
                    "@end\n"
                    "int main(void) {\n"
                    "    @autoreleasepool {\n"
                    "        [NSApplication sharedApplication];\n"
                    "        NSArray<NSScreen *> *screens = [NSScreen screens];\n"
                    "        BOOL hasSec = (screens && [screens count] > 1);\n"
                    "        NSScreen *secScr = hasSec ? [screens objectAtIndex:1] : nil;\n"
                    "        NSRect initRect = hasSec\n"
                    "            ? NSMakeRect(secScr.frame.origin.x + 80.0, secScr.frame.origin.y + 40.0, 1512.0, 982.0)\n"
                    "            : NSMakeRect(100.0, 100.0, 1512.0, 982.0);\n"
                    "        Cocoa_WindowListener *listener = [[Cocoa_WindowListener alloc] init];\n"
                    "        SDLWindow *w = [[SDLWindow alloc] initWithContentRect:initRect\n"
                    "                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |\n"
                    "                                                               NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)\n"
                    "                                                      backing:NSBackingStoreBuffered\n"
                    "                                                        defer:NO];\n"
                    "        [w setReleasedWhenClosed:NO];\n"
                    "        [w setDelegate:listener];\n"
                    "        gProbeArmed = 1;\n"
                    "        /* Enter Space-exit transition: sets gInFullscreenTransition=YES & gHasExitFullscreenTarget=YES */\n"
                    "        NSNotification *willExitNote = [NSNotification notificationWithName:NSWindowWillExitFullScreenNotification object:w];\n"
                    "        [listener windowWillExitFullScreen:willExitNote];\n"
                    "        /* Exact Bug A moment (+00138.209s): AppKit calls constrainFrameRect on TV frame MID-TRANSITION */\n"
                    "        NSRect tvExitRect = hasSec\n"
                    "            ? NSMakeRect(secScr.frame.origin.x + 157.0, secScr.frame.origin.y + 40.0, 1512.0, 1010.0)\n"
                    "            : NSMakeRect(1957.0, 129.0, 1512.0, 1010.0);\n"
                    "        NSRect constrainedMidExit = [w constrainFrameRect:tvExitRect toScreen:nil];\n"
                    "        /* On real multi-screen, also test AppKit attempting a screens[0] @(288,120) bounce mid-exit -> must stay on secScr! */\n"
                    "        NSRect antiBounceRect = hasSec\n"
                    "            ? [w constrainFrameRect:NSMakeRect(288.0, 120.0, 1512.0, 1010.0) toScreen:[screens objectAtIndex:0]]\n"
                    "            : constrainedMidExit;\n"
                    "        /* Complete Space exit + drain 220ms settle timer */\n"
                    "        NSNotification *didExitNote = [NSNotification notificationWithName:NSWindowDidExitFullScreenNotification object:w];\n"
                    "        [listener windowDidExitFullScreen:didExitNote];\n"
                    "        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.22]];\n"
                    "        printf(\"screens=%lu midExitX=%.0f antiBounceX=%.0f bounceCalls=%d\\n\",\n"
                    "               (unsigned long)(screens ? [screens count] : 0),\n"
                    "               constrainedMidExit.origin.x, antiBounceRect.origin.x, gAspyrDisplay0BounceCalled);\n"
                    "        [w setDelegate:nil];\n"
                    "        [w close];\n"
                    "        CGFloat minExpectedX = hasSec ? secScr.frame.origin.x : 1950.0;\n"
                    "        if (constrainedMidExit.origin.x < minExpectedX || gAspyrDisplay0BounceCalled != 0) return 21;\n"
                    "        if (hasSec && antiBounceRect.origin.x < secScr.frame.origin.x) return 22;\n"
                    "        return 0;\n"
                    "    }\n"
                    "}\n",
                    encoding="utf-8",
                )
                rc_build = subprocess.run(
                    ["clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fobjc-arc", "-framework", "Cocoa", str(probe_m), "-o", str(probe_exe)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(rc_build.returncode, 0, rc_build.stderr)
                h_a = tmp_p / "h_a"
                d_a = tmp_p / "d_a"
                h_a.mkdir()
                d_a.mkdir()
                env_a = {
                    **os.environ,
                    "HOME": str(h_a),
                    "SIMS2_DIAG_LOG_DIR": str(d_a),
                    "SIMS2_DIAG_LOG": "1",
                    "DYLD_INSERT_LIBRARIES": dylib_path,
                }
                env_a.pop("SIMS2_DEBUG", None)
                r_a = subprocess.run([str(probe_exe)], env=env_a, capture_output=True, text=True)
                self.assertEqual(r_a.returncode, 0, f"Bug A mid-exit probe failed rc={r_a.returncode} out={r_a.stdout} err={r_a.stderr}")
                self.assertIn("bounceCalls=0", r_a.stdout)
                self.assertFalse((h_a / "Library" / "Logs" / "Sims2-Crash-Patch").exists())
                diag_txt = (d_a / "sims2_patch_diag.log").read_text(encoding="utf-8")
                self.assertIn("Remembered exit-fullscreen target (windowWillExitFullScreen)", diag_txt)

    def test_ci_workflow_links_opengl_framework_for_macos_trackpad_build(self) -> None:
        ci_yml = (ROOT_DIR / ".github" / "workflows" / "ci-and-release.yml").read_text(encoding="utf-8")
        build_sh = (ROOT_DIR / "trackpad_mod" / "build_trackpad.sh").read_text(encoding="utf-8")
        for fw in ("-framework Cocoa", "-framework Carbon", "-framework CoreGraphics", "-framework OpenGL"):
            self.assertIn(fw, build_sh, f"Missing {fw} in trackpad_mod/build_trackpad.sh")
            self.assertIn(fw, ci_yml, f"Missing {fw} in .github/workflows/ci-and-release.yml")

    def test_exp_rc1_single_native_resolution_catalog_no_800x600(self) -> None:
        src_m = (ROOT_DIR / "trackpad_mod" / "sims2_trackpad.m").read_text(encoding="utf-8")
        patch_sh = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")

        # 1. Dylib hook_CGDisplayCopyAllDisplayModes exposes strictly 1 usable native mode (never multiple lower presets)
        #    and hook_sscanf rewrites saved activeDeviceDisplayMode ("%ux%ux%ux%u") to match it (zero 800x600 fallback).
        cg_idx = src_m.find("static CFArrayRef hook_CGDisplayCopyAllDisplayModes(")
        self.assertNotEqual(cg_idx, -1)
        cg_body = src_m[cg_idx : cg_idx + 2800]
        self.assertIn("CFArrayCreateMutable(kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks)", cg_body)
        self.assertEqual(cg_body.count("CFArrayAppendValue(result,"), 1)
        self.assertIn("gLastExposedModeWidth = exposedW;", cg_body)
        self.assertIn("gLastExposedModeHeight = exposedH;", cg_body)

        # Verify usable native height calculation for both MBP 14" scales (1512x982 -> 1512x950, 1800x1169 -> 1800x1131)
        # and non-notched displays (1920x1080 -> 1920x1080)
        for full_w, full_h, notch_top, expected_usable_h in (
            (1512, 982, 32, 950),
            (1800, 1169, 38, 1131),
            (1920, 1080, 0, 1080),
        ):
            usable_h = full_h - notch_top if notch_top > 0 else full_h
            self.assertEqual(usable_h, expected_usable_h)
            self.assertTrue(800 <= full_w <= 2560 and 600 <= usable_h <= 1600)

        # hook_sscanf guard against 800x600 fallback / 0x1006ea404 SIGSEGV
        ss_idx = src_m.find("static int hook_sscanf(")
        self.assertNotEqual(ss_idx, -1)
        ss_body = src_m[ss_idx : ss_idx + 1800]
        self.assertIn("va_copy(", ss_body)
        self.assertIn("vsscanf(", ss_body)
        self.assertIn('"%ux%ux%ux%u"', ss_body)
        self.assertIn("gLastExposedModeWidth > 0 && gLastExposedModeHeight > 0", ss_body)

        # 2. patch_sims2.command removes Aspyr's 3 hardcoded synthetic fallbacks (1280x720, 1024x768, 1344x756)
        for label in (
            "ASL Remove Synthetic 1280x720 (0x5e517)",
            "ASL Remove Synthetic 1024x768 (0x5e54c)",
            "ASL Remove Synthetic 1344x756 (0x5e591)",
            "AslSingleNative=",
        ):
            self.assertIn(label, patch_sh)

        # Verify on synthetic binary that restore_sims2.command rejects any partially patched fallback call
        perl_bin = vp.find_perl()
        if perl_bin:
            with tempfile.TemporaryDirectory() as tmp:
                tmp_dir = Path(tmp)
                restore_blocks = vp.extract_perl_blocks((ROOT_DIR / "restore_sims2.command").read_text(encoding="utf-8"))
                restore_pl = tmp_dir / "check_pristine.pl"
                restore_pl.write_text(restore_blocks[0], encoding="utf-8")
                only_fb_patched = (
                    b"\x00" * 16
                    + ORIG1
                    + b"\x00" * 16
                    + ORIG2
                    + b"\x00" * 16
                    + bytes.fromhex("4c8d4dd09090909090488b9d48ffffff")
                )
                f_bin = tmp_dir / "PartiallyPatched"
                f_bin.write_bytes(only_fb_patched)
                self.assertEqual(subprocess.run([perl_bin, str(restore_pl), str(f_bin)]).returncode, 1)

    def test_v140_silent_logs_crash_capture_dynamic_res_and_github_support(self) -> None:
        patch_text = (ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8")
        self.assertNotIn('grules_w="1800"', patch_text)
        self.assertNotIn('grules_h="1169"', patch_text)
        self.assertNotIn("affichage natif 1800x1169", patch_text)
        self.assertIn("Diagnostic & Support GitHub", patch_text)
        self.assertIn("github_support_report.md", patch_text)

        bug_tpl = ROOT_DIR / ".github" / "ISSUE_TEMPLATE" / "bug_report.md"
        self.assertTrue(bug_tpl.is_file(), "Missing .github/ISSUE_TEMPLATE/bug_report.md")
        bug_tpl_text = bug_tpl.read_text(encoding="utf-8")
        self.assertIn("patch_sims2.command", bug_tpl_text)
        self.assertIn("Diagnostic & Support GitHub", bug_tpl_text)
        self.assertIn("github_support_report.md", bug_tpl_text)

        if sys.platform == "darwin":
            bash_bin = vp.find_bash()
            self.assertIsNotNone(bash_bin)

            # Interactive menu of patch_sims2.command shows [1]..[3] and exits cleanly on 3
            res_quit = subprocess.run(
                [bash_bin, "./patch_sims2.command"],
                cwd=str(ROOT_DIR),
                input="3\n",
                capture_output=True,
                text=True,
            )
            self.assertEqual(res_quit.returncode, 0, res_quit.stderr or res_quit.stdout)
            self.assertIn("[1]", res_quit.stdout)
            self.assertIn("Diagnostic & Support GitHub", res_quit.stdout)
            self.assertIn("[3]", res_quit.stdout)

            # Debug toggle + GitHub support report generation + /Users/<user> anonymization
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                fake_home = base / "Users" / "alice_secret"
                log_dir = fake_home / "Library" / "Logs" / "Sims2-Crash-Patch"
                cfg_dir = fake_home / "Library" / "Application Support" / "Aspyr" / "The Sims 2" / "Config"
                cfg_dir.mkdir(parents=True)
                userprops = cfg_dir / "userProps.xml"
                userprops.write_text(
                    '<?xml version="1.0"?><cGZPersistDBSegment>'
                    '<AnyString key="activeDeviceDisplayMode" type="0x0b8bea18">1440x900x32x60</AnyString>'
                    '</cGZPersistDBSegment>\n',
                    encoding="utf-8",
                )

                r_dbg_on = self._run_bash_lib(
                    "patch_sims2.command",
                    'REAL_HOME="$1"; SIMS2_LOG_DIR="$2"; toggle_debug_mode enable',
                    fake_home.as_posix(),
                    log_dir.as_posix(),
                )
                self.assertEqual(r_dbg_on.returncode, 0, r_dbg_on.stderr or r_dbg_on.stdout)
                self.assertTrue((log_dir / ".debug_enabled").is_file())

                crash_file = log_dir / "crash_report.log"
                crash_file.write_text(
                    f"Patch Version : 1.5.0\nPath: /Users/alice_secret/Library/Application Support/test\n",
                    encoding="utf-8",
                )
                dbg_file = log_dir / "debug_boot.log"
                dbg_file.write_text("BOOT pid=1234 path=/Users/alice_secret/Desktop\n", encoding="utf-8")
                (log_dir / "debug_boot.previous.log").write_text("OLD\n", encoding="utf-8")

                env = dict(os.environ)
                env["SIMS2_LIB_ONLY"] = "1"
                env["SIMS2_SKIP_PBCOPY"] = "1"
                env["SIMS2_SKIP_SYSTEM_PROFILER"] = "1"
                env["SIMS2_LOG_DIR"] = log_dir.as_posix()
                env["SIMS2_USERPROPS_OVERRIDE"] = userprops.as_posix()
                r_rep = subprocess.run(
                    [
                        bash_bin,
                        "-c",
                        'set -u; source "./patch_sims2.command"; REAL_HOME="$1"; REAL_USER="alice_secret"; generate_github_support_report',
                        "_",
                        fake_home.as_posix(),
                    ],
                    cwd=str(ROOT_DIR),
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(r_rep.returncode, 0, r_rep.stderr or r_rep.stdout)
                self.assertNotIn("command not found", r_rep.stderr)
                self.assertNotIn("hw.model", r_rep.stderr)
                report_path = log_dir / "github_support_report.md"
                self.assertTrue(report_path.is_file())
                rep_text = report_path.read_text(encoding="utf-8")
                self.assertIn("v1.5.0", rep_text)
                self.assertIn("1440x900x32x60", rep_text)
                self.assertIn("crash_report.log", rep_text)
                self.assertIn("debug_boot.log", rep_text)
                self.assertNotIn("alice_secret", rep_text)
                self.assertIn("~/Library/Application Support/test", rep_text)

                r_dbg_off = self._run_bash_lib(
                    "patch_sims2.command",
                    'REAL_HOME="$1"; SIMS2_LOG_DIR="$2"; toggle_debug_mode disable',
                    fake_home.as_posix(),
                    log_dir.as_posix(),
                )
                self.assertEqual(r_dbg_off.returncode, 0, r_dbg_off.stderr or r_dbg_off.stdout)
                self.assertFalse((log_dir / ".debug_enabled").exists())
                self.assertFalse(dbg_file.exists())
                self.assertFalse((log_dir / "debug_boot.previous.log").exists())
                self.assertTrue(crash_file.is_file())

            # Runtime test of compiled x86_64 dylib (silent normal mode, debug_boot.log, crash_report.log)
            clangxx = vp.find_unix_tool("clang++", ())
            if clangxx:
                cpp_src = (
                    "#include <csignal>\n"
                    "#include <stdexcept>\n"
                    "#include <string>\n"
                    "int main(int argc, char **argv) {\n"
                    "  if (argc > 1 && std::string(argv[1]) == \"terminate\") throw std::runtime_error(\"boom\");\n"
                    "  if (argc > 1 && std::string(argv[1]) == \"segv\") std::raise(SIGSEGV);\n"
                    "  return 0;\n"
                    "}\n"
                )
                with tempfile.TemporaryDirectory() as tmp:
                    tmp_p = Path(tmp)
                    src = tmp_p / "host.cpp"
                    exe = tmp_p / "host"
                    src.write_text(cpp_src, encoding="utf-8")
                    subprocess.run([clangxx, "-arch", "x86_64", str(src), "-o", str(exe)], check=True)
                    dylib_path = (ROOT_DIR / "trackpad_mod" / "libsims2_trackpad.dylib").as_posix()

                    h_norm = tmp_p / "h_norm"
                    h_norm.mkdir()
                    rn = subprocess.run([str(exe)], env={**os.environ, "HOME": str(h_norm), "SIMS2_DIAG_LOG_DIR": str(tmp_p), "DYLD_INSERT_LIBRARIES": dylib_path})
                    self.assertEqual(rn.returncode, 0)
                    self.assertFalse((h_norm / "Library" / "Logs" / "Sims2-Crash-Patch").exists())

                    h_dbg = tmp_p / "h_dbg"
                    h_dbg.mkdir()
                    rd = subprocess.run([str(exe)], env={**os.environ, "HOME": str(h_dbg), "SIMS2_DEBUG": "1", "SIMS2_DIAG_LOG_DIR": str(tmp_p), "DYLD_INSERT_LIBRARIES": dylib_path})
                    self.assertEqual(rd.returncode, 0)
                    self.assertTrue((h_dbg / "Library" / "Logs" / "Sims2-Crash-Patch" / "debug_boot.log").is_file())

                    h_segv = tmp_p / "h_segv"
                    h_segv.mkdir()
                    rs = subprocess.run([str(exe), "segv"], env={**os.environ, "HOME": str(h_segv), "SIMS2_DIAG_LOG_DIR": str(tmp_p), "DYLD_INSERT_LIBRARIES": dylib_path})
                    self.assertNotEqual(rs.returncode, 0)
                    cr_segv = h_segv / "Library" / "Logs" / "Sims2-Crash-Patch" / "crash_report.log"
                    self.assertTrue(cr_segv.is_file())
                    cr_txt = cr_segv.read_text(encoding="utf-8")
                    self.assertIn("Patch Version : 1.5.0", cr_txt)
                    self.assertIn("SIGSEGV", cr_txt)
                    self.assertIn("Backtrace", cr_txt)

    def test_v14_option_a_userprops_and_graphics_rules_1800x1125(self) -> None:
        if not vp.find_perl():
            self.skipTest("perl not available on PATH")

        sample_tmpl = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<cGZPersistDBSegment>\n"
            '  <AnyString key="activeDeviceDisplayMode" type="0x0b8bea18">{mode}</AnyString>\n'
            '  <AnyBoolean key="usePixelAspectRatio" type="0xcba908e1">true</AnyBoolean>\n'
            "</cGZPersistDBSegment>\n"
        )

        for script in ("patch_sims2.command", "clean_sims2_cache.command"):
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                xml = base / "userProps.xml"
                orig_text = sample_tmpl.format(mode="1800x1169x32x60")
                xml.write_text(orig_text, encoding="utf-8")

                # 1. Native hardware 1800x1169 is preserved so cDeviceEnumDX validates without exception
                r1 = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1512x982,1280x800" 0',
                    xml.as_posix(),
                )
                self.assertEqual(r1.returncode, 0, r1.stderr or r1.stdout)
                updated_text = xml.read_text(encoding="utf-8")
                self.assertIn(">1800x1169x32x60<", updated_text)
                self.assertIn(">true<", updated_text)

                # 2. Unsupported notched 1800x1125 upgrades cleanly to native 1800x1169 when supported
                xml.write_text(sample_tmpl.format(mode="1800x1125x32x60"), encoding="utf-8")
                r2 = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1512x982,1280x800" 0',
                    xml.as_posix(),
                )
                self.assertEqual(r2.returncode, 0, r2.stderr or r2.stdout)
                self.assertIn(">1800x1169x32x60<", xml.read_text(encoding="utf-8"))
                bak = Path(str(xml) + ".backup")
                self.assertEqual(bak.read_text(encoding="utf-8"), sample_tmpl.format(mode="1800x1125x32x60"))

                # 3. Custom supported resolution (1512x982) preserved when force_reset=0, resets to 1800x1169 on force_reset=1
                xml.write_text(sample_tmpl.format(mode="1512x982x32x60"), encoding="utf-8")
                r_keep = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1512x982,2560x1440,1280x800" 0',
                    xml.as_posix(),
                )
                self.assertEqual(r_keep.returncode, 0)
                self.assertIn(">1512x982x32x60<", xml.read_text(encoding="utf-8"))

                # 3K/4K resolution must be rejected back to 1800x1169
                xml.write_text(sample_tmpl.format(mode="3024x1964x32x60"), encoding="utf-8")
                r_cap = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1512x982,2560x1440,1280x800" 0',
                    xml.as_posix(),
                )
                self.assertEqual(r_cap.returncode, 0)
                self.assertIn(">1800x1169x32x60<", xml.read_text(encoding="utf-8"))

                r_reset = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1512x982,2560x1440,1280x800" 1',
                    xml.as_posix(),
                )
                self.assertEqual(r_reset.returncode, 0)
                self.assertIn(">1800x1169x32x60<", xml.read_text(encoding="utf-8"))

        real_like_grules = (
            "seti textureMemory       32\n"
            "option ScreenModeResolution\n"
            "   setting $Low\n"
            "      uintProp maxResWidth      2048\n"
            "      uintProp maxResHeight     2048\n"
            "      uintProp defaultResWidth  800\n"
            "      uintProp defaultResHeight 600\n"
            "   setting $Medium\n"
            "      uintProp maxResWidth      2048\n"
            "      uintProp maxResHeight     2048\n"
            "      uintProp defaultResWidth  1024\n"
            "      uintProp defaultResHeight 768\n"
            "   setting $High\n"
            "      uintProp maxResWidth      2048\n"
            "      uintProp maxResHeight     2048\n"
            "      uintProp defaultResWidth  1024\n"
            "      uintProp defaultResHeight 768\n"
            "end\n"
            "# Override defaults (SIM-281,416)\n"
            "setOption EffectsQuality        $Medium\n"
            "intProp configParserErrorCode 0\n"
        )

        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            grules = base / "Graphics Rules.sgr"
            grules_bak = base / "Graphics Rules.sgr.backup"
            grules.write_text(real_like_grules, encoding="utf-8")

            r_gr1 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2" 1800 1169',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r_gr1.returncode, 0, r_gr1.stderr or r_gr1.stdout)
            patched_gr = grules.read_text(encoding="utf-8")
            self.assertIn("uintProp defaultResWidth  1800", patched_gr)
            self.assertIn("uintProp defaultResHeight 1169", patched_gr)
            self.assertIn("uintProp defaultResWidth  800", patched_gr)
            # $Medium keeps its original 1024x768 default while $High shifts to 1800x1169 and maxRes is capped at 2560x1600
            self.assertIn("setting $Medium\n      uintProp maxResWidth      2560\n      uintProp maxResHeight     1600\n      uintProp defaultResWidth  1024", patched_gr)
            self.assertIn("intProp configParserErrorCode 0", patched_gr)
            self.assertEqual(grules_bak.read_text(encoding="utf-8"), real_like_grules)

            # Second run must be strictly idempotent
            r_gr2 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2" 1800 1169',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r_gr2.returncode, 0, r_gr2.stderr or r_gr2.stdout)
            self.assertEqual(grules.read_text(encoding="utf-8"), patched_gr)
            self.assertIn("OK:already_patched", r_gr2.stdout + r_gr2.stderr)

            # Phase 1/2 5120x3200 file upgrades cleanly to 2560x1600 while preserving default 1800x1169
            grules.write_text(patched_gr.replace("2560", "5120").replace("1600", "3200"), encoding="utf-8")
            r_gr3 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_graphics_rules_sgr "$1" "$2" 1800 1169',
                grules.as_posix(),
                grules_bak.as_posix(),
            )
            self.assertEqual(r_gr3.returncode, 0, r_gr3.stderr or r_gr3.stdout)
            self.assertEqual(grules.read_text(encoding="utf-8"), patched_gr)

    def test_v14_option_a_binary_display_patch_and_restore_guard(self) -> None:
        perl_bin = vp.find_perl()
        if not perl_bin:
            self.skipTest("perl not available on PATH")

        orig_fb_1280 = bytes.fromhex("4989c1e8740c0000c745b000040000")
        repl_fb_1280 = bytes.fromhex("4989c19090909090c745b000040000")
        orig_fb_1024 = bytes.fromhex("4c8d4dd0e83f0c00004c89e8")
        repl_fb_1024 = bytes.fromhex("4c8d4dd090909090904c89e8")
        orig_fb_1344 = bytes.fromhex("4c8d4dd0e8fa0b0000488b9d48ffffff")
        repl_fb_1344 = bytes.fromhex("4c8d4dd09090909090488b9d48ffffff")
        orig_asl = bytes.fromhex("39f17fd04139f87fcb")
        repl_asl = bytes.fromhex("39f190904139f89090")
        orig_val_p0 = bytes.fromhex("0f57c9f3480f2ac9f3480f2ad0f30f5eca0f2ec10f8538ffffff7b40")
        orig_val_p2 = bytes.fromhex("0f57c9f3480f2ac9f3480f2ad0f30f5eca3b45c077063b4dc4764190")
        repl_val_p3 = bytes.fromhex("3d000a0000771581f940060000770deb4b9090909090909090909090")
        orig_stretch = bytes.fromhex("e86277fbff84c074108b43183b45f0")
        repl_stretch = bytes.fromhex("e86277fbff84c0eb108b43183b45f0")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            exe = tmp_dir / "Sims2XP_Exe"
            pristine = (
                b"\x00" * 32
                + ORIG1
                + b"\x90" * 16
                + ORIG2
                + b"\x90" * 16
                + orig_fb_1280
                + b"\x90" * 16
                + orig_fb_1024
                + b"\x90" * 16
                + orig_fb_1344
                + b"\x90" * 16
                + orig_asl
                + b"\x90" * 16
                + orig_stretch
                + b"\x90" * 16
                + orig_val_p0
                + b"\xff" * 32
            )
            exe.write_bytes(pristine)

            r1 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_option_a_display_binary "$1"',
                exe.as_posix(),
            )
            self.assertEqual(r1.returncode, 0, r1.stderr or r1.stdout)
            patched = exe.read_bytes()
            self.assertIn(repl_fb_1280, patched)
            self.assertIn(repl_fb_1024, patched)
            self.assertIn(repl_fb_1344, patched)
            self.assertIn(repl_asl, patched)
            self.assertIn(repl_val_p3, patched)
            self.assertIn(repl_stretch, patched)
            self.assertNotIn(orig_fb_1280, patched)
            self.assertNotIn(orig_fb_1024, patched)
            self.assertNotIn(orig_fb_1344, patched)
            self.assertNotIn(orig_asl, patched)
            self.assertNotIn(orig_val_p0, patched)
            self.assertNotIn(orig_stretch, patched)
            # 60Hz bytes remain completely untouched
            self.assertIn(ORIG1, patched)
            self.assertIn(ORIG2, patched)

            # Second run must be idempotent
            r2 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_option_a_display_binary "$1"',
                exe.as_posix(),
            )
            self.assertEqual(r2.returncode, 0, r2.stderr or r2.stdout)
            self.assertEqual(exe.read_bytes(), patched)

            # Phase 2 -> Phase 3 upgrade path must preserve Option A stretch & 60Hz bytes
            exe_p2 = tmp_dir / "Sims2XP_Exe_p2"
            phase2_bin = (
                b"\x00" * 32
                + ORIG1
                + b"\x90" * 16
                + ORIG2
                + b"\x90" * 16
                + orig_fb_1280
                + b"\x90" * 16
                + orig_fb_1024
                + b"\x90" * 16
                + orig_fb_1344
                + b"\x90" * 16
                + orig_asl
                + b"\x90" * 16
                + repl_stretch
                + b"\x90" * 16
                + orig_val_p2
                + b"\xff" * 32
            )
            exe_p2.write_bytes(phase2_bin)
            r_p2 = self._run_bash_lib(
                "patch_sims2.command",
                'patch_option_a_display_binary "$1"',
                exe_p2.as_posix(),
            )
            self.assertEqual(r_p2.returncode, 0, r_p2.stderr or r_p2.stdout)
            self.assertEqual(exe_p2.read_bytes(), patched)

            # restore_sims2.command is_pristine_binary must reject binaries containing Phase 2 or Phase 3 patches
            restore_blocks = vp.extract_perl_blocks((ROOT_DIR / "restore_sims2.command").read_text(encoding="utf-8"))
            restore_pl = tmp_dir / "check_pristine.pl"
            restore_pl.write_text(restore_blocks[0], encoding="utf-8")
            self.assertEqual(subprocess.run([perl_bin, str(restore_pl), str(exe)]).returncode, 1)
            exe_p2.write_bytes(phase2_bin)
            self.assertEqual(subprocess.run([perl_bin, str(restore_pl), str(exe_p2)]).returncode, 1)

            bad_exe = tmp_dir / "BadExe"
            bad_exe.write_bytes(b"\xcc" * 128)
            r_bad = self._run_bash_lib(
                "patch_sims2.command",
                'patch_option_a_display_binary "$1"',
                bad_exe.as_posix(),
            )
            self.assertNotEqual(r_bad.returncode, 0)
            self.assertEqual(bad_exe.read_bytes(), b"\xcc" * 128)



class TestWindowsToolkit(unittest.TestCase):
    def test_pe32_4gb_patch_and_restore(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "Sims2EP9.exe"
            orig = make_synthetic_pe32(characteristics=0x0102, checksum=0x00010001)
            exe.write_bytes(orig)

            st_before = wt.inspect_pe(exe)
            self.assertTrue(st_before.is_valid_pe32)
            self.assertFalse(st_before.large_address_aware)

            ok, _ = wt.set_large_address_aware(exe, enable=True)
            self.assertTrue(ok)
            self.assertTrue((Path(tmp) / "Sims2EP9.exe.backup").is_file())

            st_after = wt.inspect_pe(exe)
            self.assertTrue(st_after.large_address_aware)
            self.assertNotEqual(st_after.checksum, 0)

            # Idempotent re-run
            ok2, _ = wt.set_large_address_aware(exe, enable=True)
            self.assertTrue(ok2)

            # Restore
            ok3, _ = wt.restore_4gb_backup(exe)
            self.assertTrue(ok3)
            self.assertEqual(exe.read_bytes(), orig)

            # Truncated pre-existing backup must be repaired before patching
            bak = Path(tmp) / "Sims2EP9.exe.backup"
            bak.write_bytes(b"")
            ok4, _ = wt.set_large_address_aware(exe, enable=True)
            self.assertTrue(ok4)
            self.assertEqual(bak.read_bytes(), orig)

            # Size-mismatched backup (valid PE header but truncated trailing data) must be refused on restore
            bak.write_bytes(orig + b"\x00" * 16)
            ok5, msg5 = wt.restore_4gb_backup(exe)
            self.assertFalse(ok5)
            self.assertIn("size mismatch", msg5)

    def test_pe_rejects_invalid_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "NotPE.exe"
            bad.write_bytes(b"NOTAPEFILE" * 20)
            ok, _ = wt.set_large_address_aware(bad, enable=True)
            self.assertFalse(ok)

    def test_fix_userprops_and_cache_cleaner(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp) / "The Sims 2"
            cfg_dir = save_dir / "Config"
            neigh_dir = save_dir / "Neighborhoods"
            cfg_dir.mkdir(parents=True)
            neigh_dir.mkdir(parents=True)

            (save_dir / "Groups.cache").write_bytes(b"123")
            (save_dir / "Accessory.cache").write_bytes(b"456")
            keep_file = neigh_dir / "N001_Neighborhood.package"
            keep_file.write_bytes(b"important")

            userprops = cfg_dir / "userProps.xml"
            userprops.write_text(
                '<UserProps><AnyString key="activeDeviceDisplayMode" type="0x0b8bea18">3840x2160x32x120</AnyString></UserProps>',
                encoding="utf-8",
            )

            ok, _ = wt.fix_userprops_display_mode(userprops, target_mode="1920x1080x32x60")
            self.assertTrue(ok)
            self.assertEqual(wt.read_active_display_mode(userprops), "1920x1080x32x60")
            self.assertTrue((cfg_dir / "userProps.xml.backup").is_file())

            removed = wt.clean_windows_caches(save_dir)
            self.assertEqual(len(removed), 2)
            self.assertTrue(keep_file.is_file())


class TestTrackpadCameraState(unittest.TestCase):
    def test_modifier_left_drag_emulates_mmb_drag(self) -> None:
        sm = tc.TrackpadCameraState(tc.TrackpadConfig(modifier_mode="ralt"))
        sm.on_key_event(tc.VK_RMENU, True, True)

        a1 = sm.on_mouse_event(tc.WM_LBUTTONDOWN, 0, True, 1.0)
        self.assertTrue(a1.swallow)
        self.assertTrue(a1.inject_mmb_down)
        self.assertTrue(sm.mmb_virtually_held)

        a2 = sm.on_mouse_event(tc.WM_LBUTTONUP, 0, True, 1.5)
        self.assertTrue(a2.swallow)
        self.assertTrue(a2.inject_mmb_up)
        self.assertFalse(sm.mmb_virtually_held)

    def test_latch_and_focus_loss_safety(self) -> None:
        sm = tc.TrackpadCameraState(tc.TrackpadConfig(latch_key="f8"))
        k1 = sm.on_key_event(tc.VK_F8, True, True)
        self.assertTrue(k1.swallow)
        self.assertTrue(sm.latch_armed)

        a1 = sm.on_mouse_event(tc.WM_LBUTTONDOWN, 0, True, 2.0)
        self.assertTrue(a1.inject_mmb_down)

        # Losing focus while MMB held MUST force middle button release
        lost = sm.on_tick(2.1, is_target_focused=False)
        self.assertTrue(lost.inject_mmb_up)
        self.assertFalse(sm.latch_armed)
        self.assertFalse(sm.mmb_virtually_held)

    def test_horizontal_swipe_mmb_drag_and_release_timer(self) -> None:
        sm = tc.TrackpadCameraState(tc.TrackpadConfig(hscroll_mode="mmb-drag", swipe_release_sec=0.15))
        a1 = sm.on_mouse_event(tc.WM_MOUSEHWHEEL, 120, True, 10.0)
        self.assertTrue(a1.swallow)
        self.assertTrue(a1.inject_mmb_down)
        self.assertGreater(a1.inject_move_dx, 0)

        a_mid = sm.on_tick(10.05, True)
        self.assertFalse(a_mid.inject_mmb_up)

        a_end = sm.on_tick(10.20, True)
        self.assertTrue(a_end.inject_mmb_up)
        self.assertFalse(sm.mmb_virtually_held)

    def test_horizontal_swipe_keys_mode(self) -> None:
        sm = tc.TrackpadCameraState(tc.TrackpadConfig(hscroll_mode="keys"))
        a1 = sm.on_mouse_event(tc.WM_MOUSEHWHEEL, -120, True, 1.0)
        self.assertTrue(a1.swallow)
        self.assertEqual(a1.inject_key_tap, tc.VK_OEM_COMMA)

        a2 = sm.on_mouse_event(tc.WM_MOUSEHWHEEL, 120, True, 1.1)
        self.assertEqual(a2.inject_key_tap, tc.VK_OEM_PERIOD)

    def test_windows_ctypes_self_test(self) -> None:
        self.assertEqual(tc.run_self_test(), 0)


if __name__ == "__main__":
    unittest.main()
