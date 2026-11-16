# Changelog

All notable changes to **Sims 2 Crash Patch** (*The Sims 2: Super Collection* — Mac App Store Edition) are documented in this file.

---

## [1.4.0] - 2026-11-16

### Changed & Cleaned
- **Socle Trackpad & Affichage Stabilisé (`trackpad_mod/sims2_trackpad.m`):** Retrait complet des hooks expérimentaux de changement de résolution à chaud (`CGLSetParameter`, `CGLEnable`, `CGLDisable`, `glViewport`, `glScissor`, `CGDisplaySetDisplayMode`, `CGDisplayFade`, `CGAcquireDisplayFadeReservation`, `CGReleaseDisplayFadeReservation`, `CGConfigureDisplayFadeEffect`), du watcher `userProps.xml` et du remapping souris. Conservation du socle validé : double verrou 60 Hz (`0xfe6dc` / `0xfe741`), filtrage CoreGraphics des vrais modes matériels macOS à 60 Hz (`CGDisplayCopyAllDisplayModes`, zéro mode synthétique), plein écran dynamique calé sous l'encoche (`NSScreen.visibleFrame` détecté au runtime pour tout MacBook Air/Pro 13"/14"/16" ou écran externe), correctif `Command+Tab` (`focusSomeWindow:` + neutralisation fenêtre `SDLWindow` orpheline) et gestes trackpad (`Control`+clic-glissé, `Option` natif, pincement non inversé, rotation AZERTY/QWERTY via Carbon `UCKeyTranslate`).
- **Détection dynamique de la résolution native (`patch_sims2.command` & `clean_sims2_cache.command`):** Suppression de toute résolution `1800x1169` codée en dur : détection dynamique de l'écran actif pour initialiser `activeDeviceDisplayMode` (`<Largeur>x<Hauteur>x32x60`) dans `userProps.xml` et `$High` dans `Graphics Rules.sgr` (avec plafond `maxResWidth 2560`, `maxResHeight 1600`, `configParserErrorCode 0`).

### Added
- **Logs silencieux par défaut, rapport de crash automatique & mode debug à la demande (`sims2_trackpad.m`):** Zéro fichier écrit dans `~/Library/Logs/Sims2-Crash-Patch/` en session normale ; gestionnaire async-signal-safe (`SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`, `SIGFPE` et `std::set_terminate`) écrivant `crash_report.log` uniquement en cas de crash (`1.4.0`, `hw.model`, version macOS, `frame`, `visibleFrame`, signal/exception, `backtrace_symbols_fd`) ; journal `debug_boot.log` activé uniquement via `SIMS2_DEBUG=1` ou `.debug_enabled`.
- **Menu & outil Diagnostic & Support GitHub (`patch_sims2.command` + `.github/ISSUE_TEMPLATE/bug_report.md`):** Option `[2]` ajoutée en fin de menu de `patch_sims2.command` (conservant `[1]` Installation par défaut) pour activer/désactiver `.debug_enabled` (avec purge des anciens logs debug) et générer `github_support_report.md` (copié via `pbcopy`, chemins `/Users/<utilisateur>` anonymisés en `~`).

---

## [1.4.0-staging] - Archive R&D (`staging` `93b7141`)

### Added
- **Étape 3A — Retina & High Graphics Rules (`Graphics Rules.sgr`):** `patch_sims2.command` now creates an atomic `Graphics Rules.sgr.backup`, unlocks resolutions up to `5120x3200`, raises the `textureMemory` fallback from `32` to `1024` MB, and upgrades `# Override defaults (SIM-281,416)` (`EffectsQuality`, `LightingQuality`, `Shadows`, `MaterialDetail`) to `$High` (tolérant les commentaires `#` intermédiaires jusqu'à `#####`/`endif`/`end`); `restore_sims2.command` restores `Graphics Rules.sgr.backup` atomically.
- **Étape 3B — Native MacBook Trackpad & SDL2 Module (`trackpad_mod/libsims2_trackpad.dylib`):** Bundled and auto-injected into `Sims2XP_Exe` via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`) with zero Xcode CLT dependency: `Control (^)` + click-drag for 360° free 3D orbit + vertical pitch/tilt, `Option (⌥)` + slide (or click-drag) for 4-way camera pan (`cTSUserToolCameraHandDrag`), 2-finger pinch (`NSEventTypeMagnify`) for zoom `+/-`, 2-finger horizontal swipe / rotation for smooth `,`/`.` camera rotation (AZERTY/QWERTY Carbon `UCKeyTranslate`), SDL2 fullscreen Spaces hints (`SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0` avoiding `Cmd+Tab` bounce), and out-of-focus `mouseMoved:` cursor-warp guard; removed cleanly by `restore_sims2.command`.
- **Multi-Branch GitHub Actions & macOS Compiler CI:** Added `macos-latest` (`clang -arch x86_64` + `codesign --verify --strict`) and multi-branch triggers (`staging`, `feat/**`, `fix/**`, `audit/**`, `chore/**`) to `.github/workflows/ci-and-release.yml`, plus `trackpad_mod/build_trackpad.sh` inclusion/verification and branch-name sanitization in `scripts/verify_and_package.py`.

### Fixed
- **Trackpad Camera & Focus Fixes (`sims2_trackpad.m`):** Switched middle-click camera orbit/tilt to `Control (^)` + click-drag (natively matching `cTSUserToolCameraMiddleClick` in `Sims2XP_Exe`), preserved `Option (⌥)` + slide or click-drag as smooth 4-way camera panning by swallowing mouse clicks when `Option` is held without `Control`, set `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0` to stop `Cmd+Tab` bounce-back on focus recovery, ensured non-inverted zoom on the very first pinch gesture via `resolve_window_listener()` / `gForcedNonInvertedEvent`, tracked scroll suppression by exact `NSEvent` reference (`gSuppressedScrollEvent`), and hardened `runner_out` status parsing in `patch_sims2.command`.

---

## [1.3.1] - 2026-11-13

### Changed & Fixed
- **Clean Release Packaging (`v1.3.1`):** Removed `SHA256SUMS.txt` generation and attachment from `scripts/verify_and_package.py` and `.github/workflows/ci-and-release.yml` so GitHub Releases ship only the macOS ZIP, Windows ZIP, and automatic source archives; bumped packager default `--version` and script headers to `v1.3.1`.
- **Hardened Temp Files, Permissions & Windows Backup Validation (Audit Brique 1):** Enforced `umask 077` + `${TMPDIR:-/tmp}` + symlink checks around `limit.maxfiles.plist` creation, enforced `chmod 755` + symlink refusal on atomic `Sims2XP_Exe` updates/restores, and added `.backup` file size validation in `windows/sims2_windows_toolkit.py`.

---

## [1.3.0] - 2026-11-13

### Added
- **Conservative `userProps.xml` Display Safety & Backup (`patch_sims2.command` & `clean_sims2_cache.command`):** Queries live CoreGraphics/NSScreen display modes via zero-CLT JXA (`osascript -l JavaScript`), creates an atomic one-time `Config/userProps.xml.backup` before any modification, and repairs only invalid, external/absent, malformed, or non-`60 Hz` / non-`32 bpp` `activeDeviceDisplayMode` entries.
- **CC / Mods & `maxfiles` Diagnostics (`patch_sims2.command` & `clean_sims2_cache.command`):** Counts `.package` files inside `Downloads/`, warns on unextracted `.zip`/`.rar`/`.7z` archives ignored by the game and high CC counts approaching `Sims2XP_Exe`'s `10 240` `RLIMIT_NOFILE` ceiling, checks `launchctl limit maxfiles`, and offers `[o/N]` installation of a tagged `/Library/LaunchDaemons/limit.maxfiles.plist` (`<!-- Managed by sims2-crash-patch -->`) only when numeric `hard < 10240`.
- **Interactive Maintenance Menu (`clean_sims2_cache.command`):** Added `[1]` Clean caches *(Default on Enter)*, `[2]` Reset `userProps.xml` screen resolution, `[3]` CC & `maxfiles` diagnostic, and `[4]` Quit.
- **Container `-5000` Fallback & Diagnostic Logs (`latest.log`):** `patch_sims2.command` now classifies macOS App Container `-5000` access restrictions separately from TCC `-1743` Automation denials, copies via POSIX directly if Terminal already has read access, falls back to per-item non-overwriting Finder duplication (cleaning empty leftover backup folders on 0-file errors without falsely blocking launch when active `Application Support` saves already exist), and writes lightweight diagnostic logs (`~/Library/Logs/Sims2-Crash-Patch/latest.log`) across all 3 `.command` tools.
- **`~/Applications/The Sims 2.app` Support, Admin Check & Honest Beginner UX:** Added `locate_app_bundle` (`/Applications` fallback to `~/Applications`), `dseditgroup` Admin check before `sudo`, pre-`sudo` invisible-password explanation banner, managed daemon cleanup in `restore_sims2.command` (only removes plists carrying the `Managed by sims2-crash-patch` marker), and complete EN/FR troubleshooting cases in `README.txt` and `README.md`.

### Changed
- **Release Packager (`scripts/verify_and_package.py`):** Bumped default `--version` to `v1.3.0`.

---

## [1.2.2] - 2026-11-12

### Fixed
- **macOS Hardening (`A1`–`A7`):**
  - Ignored Finder metadata files (`.DS_Store`, `.localized`, `._*`) when deciding direct vs. `Sandbox Backup` migration (`dir_has_real_entries` + AppleScript item filter).
  - Captured AppleScript stdout/stderr (`2>&1`) and flagged `MIGRATION_FAILED=1` with TCC `-1743` Automatisation Finder recovery steps when migration cannot complete.
  - Resolved the real desktop user/UID/home (`resolve_real_user` + `launchctl asuser`) even under `sudo` so saves and Aqua Finder AppleEvents never target `/var/root`.
  - Guaranteed temporary file cleanup on `write_atomic` failures (`chmod`/`rename`), repaired corrupted `Sims2XP_Exe.backup` from pristine executables, cleaned AppleDouble/detritus xattrs before strict `codesign --verify --deep --strict`, and removed unused `File::Copy`.

---

## [1.2.1] - 2026-11-11

### Added
- **Pristine Backup Fingerprint Verification (`patch_sims2.command` & `restore_sims2.command`):** `Sims2XP_Exe.backup` is now created only when both original unpatched byte fingerprints (`0xfe6dc` and `0xfe73b`/`0xfe741`) are verified intact, preventing an already-patched binary from ever being archived as a backup. `restore_sims2.command` likewise verifies pristine fingerprints before restoring.
- **Zero-Overwrite Save Migration (`patch_sims2.command`):** Completely removed `with replacing` from the Finder AppleScript migration. If `~/Library/Application Support/Aspyr/The Sims 2/` does not exist yet, Sandbox saves are duplicated directly into it; if it already exists, Sandbox contents are safely duplicated into a timestamped backup folder (`The Sims 2 (Sandbox Backup YYYY-MM-DD)`) with zero file overwrites.
- **Atomic Binary Updates:** Both `patch_sims2.command` and `restore_sims2.command` now write to a temporary file (`Sims2XP_Exe.tmp.$$`) and perform an atomic POSIX `rename`/`mv` into `/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe`.
- **Official Uninstaller (`restore_sims2.command`), `CHANGELOG.md`, and `.github/ISSUE_TEMPLATE/test-report.md`.**

### Changed
- **Dual-Location Cache Purge (`patch_sims2.command` & `clean_sims2_cache.command`):** Purges `Groups.cache`, `Accessory.cache`, and `cAstGroupCache.package` across both `~/Library/Application Support/Aspyr/The Sims 2/` (`rm -f`) and the legacy Sandbox container (moved to the macOS Trash via Finder Automation permission).
- **Documentation (`README.md` & `README.txt`):** Updated bilingual (EN/FR) documentation covering the Non-Sandbox transition, Finder Automation permission, complete Gatekeeper steps on macOS 15+ / Sequoia / macOS 27 (including the 1-hour window and confirmation dialog), App Store reinstallation save behavior, and protective EU Directive 2009/24/EC Article 5(1) notice.
- **Repository Hygiene:** Moved early Python/shell prototypes (`patch_sims2.py`, `patch_sims2.sh`, `restore_sims2.py`) into `legacy/`.

---

## [1.1.0] - 2026-11-04

### Added
- **Zero-Dependency Native Perl Patcher (`patch_sims2.command`):** Replaced `/usr/bin/python3` with preinstalled `/usr/bin/perl` to avoid triggering the 1 GB Xcode Command Line Developer Tools prompt (`libxcselect`).
- **Dual Fingerprint-Anchored Binary Patch:** Combined Patch 1 (`0xfe6dc` primary 60 Hz lock) and Patch 2 (`0xfe741` fallback safety lock) into a single idempotent pass.
- **Standalone Cache Cleaner (`clean_sims2_cache.command`):** Added Finder AppleScript delegation (`osascript`) to purge corrupted cache files via macOS Finder Automation permission.

---

## [1.0.0] - 2026-11-04

### Added
- Initial binary analysis (`FUN_1000fe510` & `FUN_10081a5c0`) and proof-of-concept 60 Hz refresh rate patch for 120 Hz ProMotion displays on Apple Silicon.
