#!/usr/bin/env python3
"""
Cross-platform unit & integration test suite for sims2-crash-patch.

Tests both:
  1. macOS v1.2.1 patch/restore integrity (EOLs, syntax, Perl binary engine on synthetic Mach-O buffers)
  2. Windows Special Edition toolkit & trackpad state machine (PE32 4GB patch, userProps, caches, camera)
"""

from __future__ import annotations

from pathlib import Path
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
                    },
                )
                for info in zf.infolist():
                    raw = zf.read(info.filename)
                    self.assertNotIn(b"\r", raw, f"CR found inside {info.filename} in release zip")
                    mode = (info.external_attr >> 16) & 0o777
                    if info.filename.endswith(".command"):
                        self.assertEqual(mode, 0o755, f"{info.filename} must be 0755 in zip")
                    else:
                        self.assertEqual(mode, 0o644)

    def test_perl_patch_and_restore_engines_on_synthetic_binary(self) -> None:
        perl_bin = vp.find_perl()
        if not perl_bin:
            self.skipTest("perl not available on PATH")

        patch_blocks = vp.extract_perl_blocks((ROOT_DIR / "patch_sims2.command").read_text(encoding="utf-8"))
        self.assertEqual(len(patch_blocks), 1)
        patch_pl = patch_blocks[0]

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
