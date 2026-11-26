# 💎 Sims 2 Crash Patch — *The Sims 2: Super Collection* (Aspyr) for macOS Apple Silicon (M1–M5) & Intel

[![CI (macOS / Linux / Windows)](https://github.com/Justinbdna/sims2-crash-patch/actions/workflows/ci-and-release.yml/badge.svg)](https://github.com/Justinbdna/sims2-crash-patch/actions/workflows/ci-and-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/Justinbdna/sims2-crash-patch?label=Release&color=blue)](https://github.com/Justinbdna/sims2-crash-patch/releases/latest)
[![Total Downloads](https://img.shields.io/github/downloads/Justinbdna/sims2-crash-patch/total?label=Downloads&color=brightgreen)](https://github.com/Justinbdna/sims2-crash-patch/releases/latest)
[![License: MIT](https://img.shields.io/github/license/Justinbdna/sims2-crash-patch?color=yellow)](LICENSE)
[![Automated Tests](https://img.shields.io/badge/Tests-38%2F38%20passing-success.svg)](tests/test_repo_and_patcher.py)
[![macOS Apple Silicon M1-M5 & Intel](https://img.shields.io/badge/macOS-Apple%20Silicon%20%28M1%E2%80%93M5%29%20%26%20Intel-black.svg?logo=apple)](https://github.com/Justinbdna/sims2-crash-patch/releases/latest)
[![Zero External Dependencies](https://img.shields.io/badge/Dependencies-Zero%20%28No%20Xcode%29-success.svg)](patch_sims2.command)

> **🇬🇧 EN:** Fix ***The Sims 2: Super Collection* (Aspyr, Mac App Store)** **crash on launch** on **macOS Apple Silicon (M1 / M2 / M3 / M4 / M5 via Rosetta 2) & Intel**. Keeps your Mac at **120Hz ProMotion** while locking the game cleanly to 60 Hz, with crisp **under-notch fullscreen**, hot-swap **windowed mode**, **multi-monitor** support, working `Command+Tab`, and **native Trackpad** camera controls — zero Xcode required.  
> **🇫🇷 FR :** Corrige le **crash au démarrage** de ***The Sims 2: Super Collection* (Aspyr, Mac App Store)** sur **macOS Apple Silicon (M1 / M2 / M3 / M4 / M5 via Rosetta 2) et Intel**. Votre Mac reste en **ProMotion 120 Hz** tandis que le jeu tourne à 60 Hz stables, en **plein écran natif sous l'encoche**, avec **mode Fenêtré**, support **multi-écrans**, `Command+Tab` fonctionnel et **gestes Trackpad natifs** — sans Xcode.

**⬇️ [Download Latest Release (`v1.5.0`) / Télécharger la dernière version](https://github.com/Justinbdna/sims2-crash-patch/releases/latest)** · **🪟 [Windows 10/11 Special Edition (`windows/`)](windows/README.md)** · **💬 [Discussions & Compatibility Reports](https://github.com/Justinbdna/sims2-crash-patch/discussions)**

<!-- 📸 Screenshot placeholder (à décommenter quand la capture plein écran sous l'encoche est ajoutée dans docs/) :
![The Sims 2: Super Collection — Plein écran sous l'encoche macOS](docs/screenshots/fullscreen-notch.png)
-->

---

## ✨ What This Patch Fixes / Ce que le patch corrige

| Issue / Problème | 🇬🇧 In English | 🇫🇷 En français |
| :--- | :--- | :--- |
| **1. 120Hz ProMotion Crash on Launch** | Fixes the instant startup crash on 120 Hz displays: your Mac stays at **120 Hz** while the game engine runs cleanly at **60 Hz**. | Supprime le plantage immédiat au lancement : votre Mac reste en **120 Hz**, le moteur du jeu est verrouillé à **60 Hz** stables. |
| **2. Notch, Windowed Mode & Multi-Monitor** | Always boots in a native **under-notch macOS Fullscreen Space**, with hot-swap **multi-resolution Windowed mode** (`⌘ + Return`, `⌘ + R`, `Affichage` menu) and pixel-exact 3D clicks (multi-monitor & external mouse supported). | Démarre toujours en vrai **Space Plein écran natif sous l'encoche**, avec bascule à chaud vers le **mode Fenêtré multi-résolutions** (`⌘ + Entrée`, `⌘ + R`, menu `Affichage`) et clics 3D alignés au pixel près (multi-écrans & souris externe inclus). |
| **3. Broken `Command+Tab`** | Stops Desktop bounce-backs and cursor-lock issues when switching to another macOS app and back. | Corrige le rebond vers le Bureau et les blocages de curseur quand vous basculez vers une autre app macOS. |
| **4. Native Trackpad Camera** | Adds native MacBook gestures (pinch zoom, 2-finger rotate, 3D orbit, and pan) so you can play comfortably without an external mouse. | Ajoute les gestes MacBook natifs (zoom, rotation, orbite 3D et panoramique) pour jouer confortablement sans souris externe. |

---

## 🚀 3-Click Setup / Installation en 3 clics

> [!NOTE]
> **Zero external dependencies:** uses only built-in macOS system tools (no Xcode or Command Line Tools required).  
> **Zéro dépendance externe :** tout fonctionne avec les outils déjà intégrés à macOS (aucun besoin d'installer Xcode ni les Command Line Tools).

### 🇬🇧 English
1. **Download and unzip** [`sims2-crash-patch-v1.5.0.zip`](https://github.com/Justinbdna/sims2-crash-patch/releases/latest) *(quit The Sims 2 first with `Cmd + Q`)*.
2. **Bypass Gatekeeper:** double-click `patch_sims2.command` → if macOS shows *"blocked to protect your Mac"*, click **Done**, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. **Press `Enter` (`[1]`)** in Terminal:
   - Type your Mac login password blindly at `Password:` (**nothing prints on screen**, that is standard macOS security) and press `Enter`.
   - When macOS asks *"Terminal wants access to control Finder"*, click **Allow** (*Autoriser*) so your App Store saves are safely copied without overwriting anything.
   - Wait for `PATCH COMPLETE (v1.5.0)` and launch the game as usual.

### 🇫🇷 Français
1. **Téléchargez et décompressez** [`sims2-crash-patch-v1.5.0.zip`](https://github.com/Justinbdna/sims2-crash-patch/releases/latest) *(fermez d'abord Les Sims 2 avec `Cmd + Q`)*.
2. **Débloquez Gatekeeper :** double-cliquez sur `patch_sims2.command` → si macOS affiche *« bloqué pour protéger votre Mac »*, cliquez sur **Terminé**, ouvrez **Réglages Système → Confidentialité et sécurité**, descendez tout en bas et cliquez sur **Ouvrir quand même**.
3. **Appuyez sur `Entrée` (`[1]`)** dans le Terminal :
   - Tapez votre mot de passe session Mac à l'aveugle (`Password:`, **aucun caractère `*` ne s'affiche**, c'est la sécurité normale de macOS) puis faites `Entrée`.
   - Quand macOS affiche *« Terminal souhaite contrôler Finder »*, cliquez sur **Autoriser** pour copier vos sauvegardes sans rien écraser.
   - Attendez le message `PATCH COMPLETE (v1.5.0)` puis lancez le jeu normalement.

> **🪟 Windows 10/11 users:** A dedicated, strictly separated Windows toolkit (`sims2-crash-patch-windows-v1.5.0.zip` — 4GB `LARGEADDRESSAWARE` patch, cache/OneDrive diagnostics, and native Trackpad camera assistant) is available in [`windows/`](windows/README.md) and attached to every [GitHub Release](https://github.com/Justinbdna/sims2-crash-patch/releases/latest).

---

## 🖱️ MacBook Trackpad & Display Controls / Contrôles Trackpad & Affichage

| Gesture / Geste | 🇬🇧 In-Game Action | 🇫🇷 Action en jeu |
| :--- | :--- | :--- |
| **2-finger pinch** / *Pincement à 2 doigts* | Zoom in / out (`+` / `-`) | Zoom avant / arrière (`+` / `-`) |
| **2-finger horizontal swipe (or twist)** / *Balayage horizontal (ou rotation 2 doigts)* | Smooth camera rotation (`,` / `.`, **AZERTY & QWERTY** layouts supported) | Rotation fluide de la caméra (`,` / `.`, compatible claviers **AZERTY & QWERTY**) |
| **`Control (^)` + click & drag** / *`Control (^)` + clic-glissé* | Free 3D camera orbit & pitch (middle-mouse drag emulation — Fullscreen & Windowed) | Orbite 3D libre & inclinaison verticale (émulation clic molette — Plein écran & Fenêtré) |
| **`Option (⌥)` + drag** / *`Option (⌥)` + glisser* | Native camera pan (hand-drag across the map — Fullscreen & Windowed) | Panoramique natif (déplacement sur la carte, curseur 4 flèches — Plein écran & Fenêtré) |
| **`⌘ + Return`** / *`⌘ + Entrée`* | Hot-swap **Native Fullscreen ↔ Windowed** (also in the macOS **`Affichage`** menu) | Basculer à chaud **Plein écran natif ↔ Fenêtré** (également dans le menu **`Affichage`**) |
| **`⌘ + R`** | In **Windowed mode only**, cycle display-compatible windowed resolutions | En **mode Fenêtré uniquement**, faire défiler les résolutions compatibles avec votre écran |

> [!NOTE]
> **Display, Resolution & Multi-Monitor (`v1.5.0`):** The game always launches into a **native under-notch Fullscreen Space**. Press **`⌘ + Return`** (or use the macOS **`Affichage`** menu) to toggle Fullscreen ↔ Windowed, and **`⌘ + R`** in Windowed mode to cycle display-compatible resolutions. On **multi-monitor** setups, moving a 16:10 MacBook session onto a 16:9 external display automatically preserves **symmetric black pillarboxes** so proportions never stretch — **tip:** to play in **native edge-to-edge 16:9** on an external display, set it as your **Main Display** in *System Settings → Displays* before launching the game. *(Known limitation on macOS 27.0 with mixed Retina + 1x external displays: switch to Windowed mode with `⌘ + Return` before dragging across displays instead of dragging a Fullscreen Space in Mission Control; workaround if black screen: `killall Dock`.)*  
> **Affichage, Résolution & Multi-écrans (`v1.5.0`) :** Le jeu démarre toujours en **Space Plein écran natif sous l'encoche** (`⌘ + Entrée` pour basculer Plein écran ↔ Fenêtré, `⌘ + R` en Fenêtré). En **multi-écrans**, déplacer une session 16:10 vers un écran externe 16:9 conserve automatiquement des **bordures noires symétriques** sans étirement — **astuce :** définissez l'écran externe comme **Écran principal** dans *Réglages Système → Moniteurs* avant de lancer le jeu pour du **16:9 plein cadre**. *(Limitation connue macOS 27.0 Retina + externe 1x : passez en Fenêtré avant de changer d'écran ; si écran noir : `killall Dock`.)*

---

## 💻 Compatibility / Compatibilité

| Platform / Puce | Runtime | Status (`v1.5.0`) | Report / Retour |
| :--- | :--- | :--- | :--- |
| **Apple Silicon M1 / M1 Pro / Max / Ultra** | Rosetta 2 (`x86_64`) | ✅ Supported (120Hz ProMotion & 60Hz) | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |
| **Apple Silicon M2 / M2 Pro / Max / Ultra** | Rosetta 2 (`x86_64`) | ✅ Supported (120Hz ProMotion & 60Hz) | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |
| **Apple Silicon M3 / M3 Pro / Max** | Rosetta 2 (`x86_64`) | ✅ Supported (120Hz ProMotion & 60Hz) | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |
| **Apple Silicon M4 / M4 Pro / Max** | Rosetta 2 (`x86_64`) | ✅ Verified on MacBook Pro 120Hz ProMotion | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |
| **Apple Silicon M5** | Rosetta 2 (`x86_64`) | ✅ Compatible (`x86_64` binary + dylib) | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |
| **Intel Macs (`x86_64`)** | Native `x86_64` | ✅ Compatible (macOS 10.13+) | [Submit Test Report](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) |

---

## 🧰 Included Utilities / Outils inclus

| Script | 🇬🇧 What It Does | 🇫🇷 Utilité pour le joueur |
| :--- | :--- | :--- |
| **`clean_sims2_cache.command`** | Interactive maintenance menu (no password for `[1]` & `[2]`):<br>• **`[1]`** Purges corrupted caches without touching your saves.<br>• **`[2]`** Resets launch resolution in `userProps.xml` to a safe 60 Hz mode (preserves `userProps.xml.backup`).<br>• **`[3]`** Checks Mods/CC (`.package`, leftover `.zip`/`.rar`/`.7z` archives) and the `10,240` open-file limit. | Menu interactif sans mot de passe pour `[1]` & `[2]` :<br>• **`[1]`** Nettoie les caches corrompus (`Groups.cache`, `Accessory.cache`, `cAstGroupCache.package`) sans toucher à vos parties.<br>• **`[2]`** Réinitialise la résolution au lancement dans `userProps.xml` en mode 60 Hz sûr (`userProps.xml.backup` conservée).<br>• **`[3]`** Vérifie vos Mods/CC (`.package`, `.zip`/`.rar`/`.7z` oubliés) et la limite système `10 240` fichiers ouverts. |
| **`restore_sims2.command`** | Clean full uninstall: restores the verified original binary (`Sims2XP_Exe.backup`) and `Graphics Rules.sgr.backup`, removes the trackpad module, re-signs the app, and removes the managed `LaunchDaemon` if installed by this patch. *(To also restore the Apple App Store signature/Sandbox, delete and re-download the app from the Mac App Store; saves are kept.)* | Désinstallation complète et propre : restaure l'exécutable original vérifié (`Sims2XP_Exe.backup`) et `Graphics Rules.sgr.backup`, retire le module trackpad, re-signe l'app et nettoie le `LaunchDaemon` géré. *(Pour retrouver aussi la signature Mac App Store officielle, supprimez puis retéléchargez l'app depuis l'App Store ; sauvegardes conservées.)* |

---

## 🛟 Support & Quick Troubleshooting / Support & Dépannage rapide

### Built-in Tool: `[2] Diagnostic & Support GitHub`
By default, `v1.5.0` is **100% silent** and writes zero normal log files during gameplay *(diagnostic telemetry is strictly opt-in via `SIMS2_DIAG_LOG=1` → `$TMPDIR/sims2_patch_diag_XXX.log`)*.
* If a crash occurs, a numbered report **`sims2_crash_001.log`**… *(up to 20 kept, symlinked as `crash_report.log`, native macOS `.ips` reports preserved)* is written to `~/Library/Logs/Sims2-Crash-Patch/`.
* Run **`patch_sims2.command` → `[2] Diagnostic & Support GitHub`** to toggle optional `debug_boot.log` or generate an anonymized (`~`) `github_support_report.md` **copied straight to your clipboard**, ready to paste into a [GitHub Issue](https://github.com/Justinbdna/sims2-crash-patch/issues/new/choose).

*Par défaut, la `v1.5.0` n'écrit aucun log en partie normale. En cas de plantage, un rapport numéroté `sims2_crash_XXX.log` (lien `crash_report.log` + `.ips` natif préservé) est créé dans `~/Library/Logs/Sims2-Crash-Patch/`. Lancez `patch_sims2.command` → `[2] Diagnostic & Support GitHub` pour générer un rapport `github_support_report.md` anonymisé (`~`) copié automatiquement dans votre presse-papier.*

### Common Cases / Cas fréquents
* **Gatekeeper bloque le script :** double-cliquez sur `patch_sims2.command` → cliquez sur **Terminé**, ouvrez **Réglages Système → Confidentialité et sécurité**, descendez tout en bas et cliquez sur **Ouvrir quand même**.
* **Mot de passe Terminal invisible :** Normal sous macOS (aucun `*` affiché). Vérifiez *Verrouillage Majuscule* et utilisez un compte Administrateur.
* **Sauvegardes / Finder (`-1743` ou `-5000`) :** Vos données actives sont dans `~/Library/Application Support/Aspyr/The Sims 2/`. Si vos anciens quartiers n'apparaissent pas, vérifiez `~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup ...)` et fusionnez `Neighborhoods/` + `Downloads/` (jeu fermé). En cas d'erreur `-1743`, autorisez **Terminal → Finder** dans **Réglages Système → Confidentialité et sécurité → Automatisation**.
* **Crash après débranchement d'écran externe :** Lancez `clean_sims2_cache.command` → **`[2]`** pour réinitialiser `userProps.xml` sur votre écran actuel en 60 Hz.
* **Mods/CC manquants :** Décompressez bien vos `.zip`/`.rar`/`.7z` en `.package` dans `~/Library/Application Support/Aspyr/The Sims 2/Downloads/` et lancez `clean_sims2_cache.command` → **`[1]`** puis **`[3]`**.

---

## 🏗️ Architecture & Engineering

* **Mach-O `x86_64` Binary Patching (Rosetta 2):** Fingerprint-verified, idempotent binary patching of `Sims2XP_Exe` using macOS built-in `/usr/bin/perl` (zero Xcode CLT dependency), atomic temp-file writes, and pristine backup verification (`Sims2XP_Exe.backup`).
* **Objective-C / Cocoa Runtime Injection (`LC_LOAD_WEAK_DYLIB`):** Precompiled `x86_64` module ([`trackpad_mod/sims2_trackpad.m`](trackpad_mod/sims2_trackpad.m)) injected cleanly via Mach-O load command to add native Trackpad gestures, AZERTY/QWERTY Carbon `UCKeyTranslate` rotation, and SDL2 Fullscreen Space / Windowed mode hot-swapping.
* **CoreGraphics & Multi-Monitor Hooking:** Intercepts `_CGDisplayCopyAllDisplayModes` via `__DATA,__la_symbol_ptr` to expose only real 60 Hz hardware modes, clamps fullscreen geometry dynamically to `NSScreen.visibleFrame` under the notch, and keeps 16:10 / 16:9 OpenGL viewports pixel-accurate across mixed displays.
* **Async-Signal-Safe Crash Reporter:** Runs on a dedicated `sigaltstack` (`SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`, `SIGFPE`, `std::set_terminate`, `NSException`) with `dladdr` symbolication, numbered reports, and zero disk writes during normal play.
* **Strict Code Integrity & QA Automation:** Inside-out ad-hoc signing (`codesign --force --sign -` **without `--deep`**) validated with `codesign --verify --deep --strict`, backed by a **38-test automated cross-platform suite** ([`tests/test_repo_and_patcher.py`](tests/test_repo_and_patcher.py)) running in **3-OS GitHub Actions CI** (`macos-latest`, `ubuntu-latest`, `windows-latest`, including `clang -arch x86_64 -Wall -Wextra` compile checks).
* **Repository Layout Note:** [`windows/`](windows/README.md) hosts the standalone Windows 10/11 edition; [`legacy/`](legacy/) preserves early historical Python/shell prototypes archived for reference and regression checks.

<details>
<summary>🔧 <strong>Deep-Dive Technical Details (Offsets, CoreGraphics, Notch, Sandbox &amp; Codesign)</strong></summary>

### 1. Binary Patch `Sims2XP_Exe` (`x86_64` via Rosetta 2)
All binary edits verify unique byte fingerprints first and atomically create `Sims2XP_Exe.backup` before writing:
* **`0xfe6dc` (`FUN_1000fe510`):** Neutralizes `_CGDisplayModeGetRefreshRate` by forcing `60` (`0x3c`) in `R15D` (`f20f1045d0f2440f2cf84889df` → `41bf3c000000909090904889df`).
* **`0xfe741` (`FUN_1000fe510`):** Locks the secondary `_CVDisplayLink` branch via `NOP` over `cmovnel %eax, %r15d` (`41bf3c000000440f45f8c70300000000` → `41bf3c00000090909090c70300000000`).
* **`0x5e517` / `0x5e54c` / `0x5e591`:** Neutralizes Aspyr's 3 hardcoded fallback modes (`1280×720`, `1024×768`, `1344×756`) in the ASL constructor so the in-game *Screen Size* selector only lists the Mac's real native usable resolution.
* **`0x5e610`:** Lifts the ASL mode filter (`39f17fd04139f87fcb` → `39f190904139f89090`) so calibrated resolutions `≤ 2560×1600` stay selectable.
* **`0x1303243`:** Replaces the fullscreen validator with a clean `width ≤ 2560 && height ≤ 1600` ceiling.
* **`0xa7619`:** Enables edge-to-edge fullscreen fill under Spaces without side letterboxing or FBO offset (`e86277fbff84c074108b43183b45f0` → `e86277fbff84c0eb108b43183b45f0`).

### 2. Cocoa / CoreGraphics Hooks (`trackpad_mod/libsims2_trackpad.dylib`)
Compiled as `x86_64` and injected into `Sims2XP_Exe` via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`):
* **`hook_CGDisplayCopyAllDisplayModes`:** Intercepts `_CGDisplayCopyAllDisplayModes` via `__DATA,__la_symbol_ptr` to expose only real 60 Hz macOS hardware modes (no synthetic modes).
* **`NSScreen.visibleFrame`:** Dynamically detects the usable under-notch frame at runtime (`clamp_fullscreen_window_to_visible_frame`) on 13"/14"/16" MacBooks and external displays.
* **Trackpad & `Command+Tab`:** `SDL_VIDEO_MAC_FULLSCREEN_SPACES=1`, `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`, orphan `SDLWindow` suppression, non-inverted pinch zoom, Carbon `UCKeyTranslate` rotation (AZERTY/QWERTY), and `SDL_BUTTON_MIDDLE` emulation on `Control (^)` + drag while keeping native `Option (⌥)` pan intact.
* **Logs & Crash Reporter:** Zero normal disk writes (opt-in via `SIMS2_DIAG_LOG=1`); async-signal-safe handler on `sigaltstack` with `dladdr` symbolication, cumulative `sims2_crash_001.log`… (max 20, `crash_report.log` symlink), preserving native macOS `.ips` reports.

### 3. Sandbox Migration, `Graphics Rules.sgr` & `codesign --strict`
* **Non-Destructive Sandbox Migration:** Local re-signing drops App Store Sandbox entitlements; `patch_sims2.command` uses Finder Automation to copy saves from `~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/` to `~/Library/Application Support/Aspyr/The Sims 2/` (or `The Sims 2 (Sandbox Backup YYYY-MM-DD)` if an active folder already exists).
* **`Graphics Rules.sgr`:** Backs up `Graphics Rules.sgr.backup`, sets `maxResWidth 2560` / `maxResHeight 1600`, configures `$High` for the detected native resolution, and raises `textureMemory` to `1024` MB.
* **macOS Integrity:** Clears `xattr -cr` detritus and AppleDouble/ResourceFork metadata, signs inside-out **without `--deep`** (`libsims2_trackpad.dylib`, `Sims2XP_Exe`, then `The Sims 2.app` via `codesign --force --sign -`), and validates with `codesign --verify --deep --strict`.

</details>

---

## ⚖️ License & Software Preservation / Licence & Préservation

**100% free, non-profit, and open-source under the [MIT License](LICENSE)** (see also [`NOTICE`](NOTICE)). This independent community tool exists solely for debugging, interoperability, and software preservation for lawful owners of *The Sims 2: Super Collection* — **zero copyrighted game binaries are distributed and zero DRM is bypassed**. Not affiliated with, endorsed by, or sponsored by Electronic Arts Inc., Maxis, Aspyr Media Inc., or Apple Inc.

<details>
<summary>📜 <strong>International Legal Frameworks &amp; Full Notice (FR / EN)</strong></summary>

* **European Union (EU / EEA):** *Directive 2009/24/EC* on the legal protection of computer programs — **Article 5(1)** *(acts necessary for use by the lawful acquirer, including error correction)* and **Article 6** *(interoperability)*, and national implementations (e.g., French *Code de la propriété intellectuelle*, Art. `L122-6-1`).
* **United States (USA):** `17 U.S.C. § 117(a)` *(essential step / adaptation required to utilize a lawfully owned program)*, `17 U.S.C. § 1201(f)` *(interoperability)*, and `17 U.S.C. § 107` *(non-commercial compatibility, research, and preservation fair use)*.
* **United Kingdom (UK):** *Copyright, Designs and Patents Act 1988*, Sections `50B` & `50C` *(interoperability and error correction by a lawful user)*.
* **Other Jurisdictions (Canada, Australia, Switzerland, WIPO / Berne principles):** comparable statutory exceptions allowing error correction, interoperability, and non-commercial preservation by lawful owners (Canadian *Copyright Act* s. `30.6` / `30.61`, Australian *Copyright Act 1968* s. `47D` / `47E`, Swiss *CopA/LDA* Art. `21`).
* **Disclaimer / Clause de non-responsabilité :** Provided *"AS IS"* without warranty under the MIT License. Informational notice only; does not constitute formal legal advice.

</details>
