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

            with zipfile.ZipFile(mac_zip, "r") as zf:
                names = set(zf.namelist())
                self.assertEqual(
                    names,
                    {
                        "patch_sims2.command",
                        "clean_sims2_cache.command",
                        "restore_sims2.command",
                        "README.txt",
                        "trackpad_mod/libsims2_trackpad.dylib",
                        "trackpad_mod/sims2_trackpad.m",
                        "trackpad_mod/build_trackpad.sh",
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

                # 1. Missing userProps.xml must succeed without error
                missing_xml = base / "missing.xml"
                r_missing = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169,1280x800" 0',
                    missing_xml.as_posix(),
                )
                self.assertEqual(r_missing.returncode, 0, r_missing.stderr or r_missing.stdout)
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

                nokey_xml = base / "nokey.xml"
                nokey_text = '<?xml version="1.0"?><cGZPersistDBSegment></cGZPersistDBSegment>\n'
                nokey_xml.write_text(nokey_text, encoding="utf-8")
                r_nokey = self._run_bash_lib(
                    script,
                    'repair_userprops_xml "$1" "1800x1169" "1800x1169" 0',
                    nokey_xml.as_posix(),
                )
                self.assertEqual(r_nokey.returncode, 0)
                self.assertEqual(nokey_xml.read_text(encoding="utf-8"), nokey_text)
                self.assertFalse(Path(str(nokey_xml) + ".backup").exists())

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
            self.assertIn("Version: 1.4.0", text)
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
            self.assertIn("v1.4.0", doc_text)
            self.assertIn("Gatekeeper", doc_text)
            self.assertIn("userProps.xml.backup", doc_text)
            self.assertIn("Autoriser", doc_text)
        self.assertIn("[1.4.0]", changelog)
        self.assertIn("[1.3.1]", changelog)
        self.assertIn("[1.3.0]", changelog)

        if sys.platform == "darwin":
            bash_bin = vp.find_bash()
            self.assertIsNotNone(bash_bin)
            with tempfile.TemporaryDirectory() as tmp:
                env = dict(os.environ)
                env["SIMS2_NONINTERACTIVE"] = "1"
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
            self.assertIn("5120", patched_text)
            self.assertIn("3200", patched_text)
            self.assertIn("$High", patched_text)
            self.assertNotIn("seti textureMemory       32", patched_text)
            self.assertNotIn("2048", patched_text)
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
                info = zf.getinfo("trackpad_mod/libsims2_trackpad.dylib")
                mode = (info.external_attr >> 16) & 0o777
                self.assertEqual(mode, 0o755)
                self.assertEqual(zf.read("trackpad_mod/libsims2_trackpad.dylib"), expected_dylib)

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

        # Brique 3 layout-independent pinch zoom, Carbon AZERTY/QWERTY rotation, Control-orbit & Option-pan
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
        self.assertIn("!gCtrlMiddleDragActive", src_m)
        self.assertIn("isRight == gCtrlDragWasRight", src_m)
        self.assertIn("gOptionHandPanActive", src_m)
        self.assertIn("raw_event_modifier_flags", src_m)
        self.assertIn("gSuppressedScrollEvent", src_m)
        self.assertIn("gForcedNonInvertedEvent", src_m)
        self.assertIn("resolve_window_listener", src_m)

        # Compiled dylib header check (Mach-O 64-bit x86_64 MH_DYLIB)
        raw = dylib.read_bytes()
        magic, cputype, _, filetype = struct.unpack_from("<IIII", raw, 0)
        self.assertEqual(magic, 0xFEEDFACF)
        self.assertEqual(cputype, 0x01000007)
        self.assertEqual(filetype, 6)
        if sys.platform == "darwin":
            cs = subprocess.run(["codesign", "--verify", "--strict", dylib.as_posix()], capture_output=True, text=True)
            self.assertEqual(cs.returncode, 0, cs.stderr)



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
