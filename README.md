# Sims 2: Super Collection — ProMotion (120 Hz) Compatibility Fix for macOS

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20%7C%20Intel-black.svg?style=flat&logo=apple)](https://apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tested on](https://img.shields.io/badge/Tested%20on-macOS%20Sequoia%20%2F%20Sonoma%20%2F%20Ventura-success)](https://apple.com)

A permanent surgical binary patch and automated toolkit fixing the instant startup crash (`SIGSEGV` / `std::__terminate` at `0x10081cfca`) in **The Sims 2: Super Collection** (Mac App Store version by Aspyr) on Macs equipped with **ProMotion (120 Hz)** displays.

---

## 🎮 The Problem / Le Problème

On Apple Silicon MacBooks (M1/M2/M3/M4 Pro & Max) with 120 Hz ProMotion displays, *The Sims 2: Super Collection* crashes ~2 seconds after launch.
Previously, the only workaround was manually throttling the entire macOS display refresh rate to 60 Hz in *System Settings > Displays*.

This project permanently fixes the game binary so it runs at a smooth, stable 60 FPS without ever changing your Mac's 120 Hz ProMotion display settings.

---

## 🚀 Quick Install (1-Click) / Installation Rapide

### Option A: Double-Click (Recommended)
1. Download or clone this repository.
2. Double-click **`patch_sims2.command`**.
3. Enter your Mac administrator password when prompted.
4. Launch the game normally!

### Option B: Terminal (One-Liner)
Run the following command in your macOS Terminal:
```bash
sudo python3 -c '
path = "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
with open(path, "rb") as f: data = bytearray(f.read())
target = bytes.fromhex("f20f1045d0f2440f2cf8")
patched = bytes.fromhex("41bf3c00000090909090")
if target in data:
    data = data.replace(target, patched, 1)
    with open(path, "wb") as f: f.write(data)
    print("SUCCÈS : Patch appliqué !")
else:
    print("Déjà patché ou motif introuvable.")
' && sudo codesign --force --deep --sign - "/Applications/The Sims 2.app"
```

---

## 🔬 Technical Root Cause Analysis / Analyse Technique

### Target Environment
* **Application:** *The Sims 2: Super Collection* (Mac App Store, `com.aspyr.sims2.appstore`).
* **Binary:** `/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe` (Mach-O x86_64 translated via Rosetta 2).
* **Tooling Used:** Ghidra 12.2 (NSA SRE Framework, `Sims2Debug` project) and REA (*Reverse Engineer Anything* MCP framework).
* **Crash Stack:**
  ```text
  0  libc++abi.dylib    std::__terminate(void (*)()) + 6
  1  libc++abi.dylib    __cxxabiv1::failed_throw(__cxxabiv1::__cxa_exception*) + 27
  2  libc++abi.dylib    __cxa_throw + 69
  3  Sims2XP_Exe        0x10081cfc6 (FUN_10081a5c0 + offset 8507334)
  ```

### Why the Crash Occurred
1. In `FUN_1000fe510` (at `0x1000fe665`), the engine queries display refresh rates via `_CGDisplayModeGetRefreshRate`.
2. On 120 Hz ProMotion displays, Quartz returns `120.0`.
3. At `0x1000fe6e1`, `cvttsd2si %xmm0, %r15d` loads integer `120` (`0x78`) into `R15D`.
4. At `0x1000fe6f7`, `testl %r15d, %r15d` followed by `jne 0x1000fe745` (`1000fe6fc(j)`) branches immediately to `0x1000fe745`, bypassing the fallback routine (`_CVDisplayLinkGetNominalOutputVideoRefreshPeriod`).
5. At `0x1000fe790`, `movl %r15d, 0xc(%rbx)` writes `120` to the display mode structure.
6. In `FUN_10081a5c0`, the engine calls `0x101769030` to validate supported display modes. The legacy engine rejects 120 Hz, returning `0` (no valid modes).
7. At `0x10081a8ca`, `je 0x10081cf8f` branches to `___cxa_throw` at `0x10081cfca`. Without an active catch handler, `std::__terminate` is triggered -> instant SIGSEGV.

### The Surgical Patch
The patch overrides the Quartz result immediately before CoreFoundation release, guaranteeing `R15D = 60` (`0x3C`) unconditionally:

* **File Offset:** `0x000fe6dc` (Virtual Address: `0x1000fe6dc`)
* **Original Bytes (10 bytes):**
  ```text
  F2 0F 10 45 D0 F2 44 0F 2C F8
  (movsd -0x30(%rbp), %xmm0 ; cvttsd2si %xmm0, %r15d)
  ```
* **Patched Bytes (10 bytes):**
  ```text
  41 BF 3C 00 00 00 90 90 90 90
  (movl $0x3c, %r15d ; nop ; nop ; nop ; nop)
  ```

**Result:** `R15D` holds 60, `_CFRelease` cleans up memory without leaks, all enumerated modes are registered as standard 60 Hz, mode selection succeeds, and startup completes flawlessly.

---

## ⚖️ Legal Disclaimer & Fan Preservation Notice

* **Non-Profit Fan Project:** This project is strictly non-commercial, developed by passionate fans for the preservation of *The Sims 2* on modern Apple hardware.
* **No DRM Circumvention / No Crack:** This patch does **NOT** bypass Apple FairPlay, App Store receipt validation, or any digital rights management. You **must** own a legally purchased copy of *The Sims 2: Super Collection* on the Mac App Store.
* **Context:** Official support requests sent to Aspyr regarding this crash on ProMotion screens went unanswered for years. This fix is released under software interoperability exemptions (Directive 2009/24/EC Art. 6, and 17 U.S. Code § 1201(f)).

---

## 🔄 Uninstallation / Restauration

To revert to the untouched original binary at any time:
```bash
sudo python3 restore_sims2.py
```

---

## 📄 License
MIT License. Created for software preservation and community interoperability.
