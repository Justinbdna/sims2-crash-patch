# Changelog

All notable changes to **Sims 2 Crash Patch** (*The Sims 2: Super Collection* — Mac App Store Edition) are documented in this file.

---

## [1.4.1] - 2026-11-18

### Added & Changed (FR / EN)
- **Garde-fou plein écran sans bordure & alignement souris 1:1 (`trackpad_mod/sims2_trackpad.m`):**
  - **FR :** Isolation des hooks Cocoa sur `SDLWindow` (`swizzle_target_class_method`) verrouillant strictement la fenêtre principale en mode sans bordure (`NSWindowStyleMaskBorderless`) avec synchronisation 1:1 du `contentView` (`compute_primary_game_frame`, `sync_content_view_to_window_bounds`, `enforce_primary_window_borderless_fullscreen`) — supprimant définitivement la barre de titre grise macOS, les débordements du Bureau/Terminal et tout décalage des clics souris, tout en préservant `Command+Tab` et les gestes trackpad natifs.
  - **EN:** Isolated `SDLWindow` Cocoa swizzling (`swizzle_target_class_method`) strictly enforcing a borderless game window (`NSWindowStyleMaskBorderless`) with 1:1 `contentView` geometry alignment (`compute_primary_game_frame`, `sync_content_view_to_window_bounds`, `enforce_primary_window_borderless_fullscreen`) — permanently eliminating the macOS grey title bar, Desktop/Terminal bleed, and mouse click coordinate offsets while preserving `Command+Tab` and native trackpad gestures.
- **Filtrage autonome des résolutions & lancement natif (`hook_CGDisplayCopyAllDisplayModes`, `patch_sims2.command` & `clean_sims2_cache.command`):**
  - **FR :** Remplacement de l'ancienne liste statique par une sélection matérielle autonome (`find_optimal_mode_in_array`, `is_better_display_mode`) ne conservant que la résolution optimale du moniteur actif à 60 Hz, épurant le menu *Taille de l'écran*, et initialisant/réparant automatiquement `activeDeviceDisplayMode` dans `userProps.xml` dès le premier lancement sur la résolution native.
  - **EN:** Replaced the static whitelist with autonomous hardware display selection (`find_optimal_mode_in_array`, `is_better_display_mode`) exposing only the optimal 60 Hz native mode, decluttering the *Screen Size* menu, and automatically initializing/upgrading `activeDeviceDisplayMode` in `userProps.xml` to the detected native resolution on first launch.
- **Licence MIT & Mentions Légales Internationales (`LICENSE`, `README.md`, `README.txt`, en-têtes des scripts & `trackpad_mod/sims2_trackpad.m`):**
  - **FR :** Ajout du fichier `LICENSE` (licence MIT) à la racine du dépôt (également inclus dans l'archive macOS) et intégration d'une section légale bilingue complète précisant le caractère **100 % gratuit, communautaire et à but non lucratif** du projet, son objet strictement limité au **débogage, à la correction d'erreurs et à la préservation** d'un jeu ancien non maintenu pour Apple Silicon (*The Sims 2: Super Collection*), l'absence totale de fichiers propriétaires et de contournement de DRM, la non-affiliation (EA, Maxis, Aspyr, Apple) et les cadres législatifs informatifs (UE Directive `2009/24/CE` art. `5(1)` & `6`, USA `17 U.S.C. § 117(a)`, `§ 1201(f)`, `§ 107`, Royaume-Uni `CDPA 1988 s. 50B/50C`, Canada, Australie, Suisse et principes OMPI).
  - **EN:** Added root `LICENSE` (MIT License, also packaged inside the macOS release ZIP) and comprehensive bilingual legal & software preservation notices across `README.md`, `README.txt`, script headers, and `sims2_trackpad.m`, clarifying that the project is **100% free, community-driven, and strictly non-profit**, exists solely to **debug, fix compatibility bugs, and preserve** a legitimately owned, unsupported legacy game, distributes zero copyrighted game binaries, bypasses zero DRM, is unaffiliated with EA/Maxis/Aspyr/Apple, and references informational international frameworks (EU Directive `2009/24/EC` Art. `5(1)` & `6`, USA `17 U.S.C. § 117(a)`, `§ 1201(f)`, `§ 107`, UK `CDPA 1988 s. 50B/50C`, and comparable international interoperability/preservation exceptions).

---

## [1.4.0] - 2026-11-16

### Added & Changed (FR / EN)
- **Plein écran sous l'encoche & Résolution native (`patch_sims2.command` & `trackpad_mod/sims2_trackpad.m`):**
  - **FR :** Double verrou 60 Hz (`0xfe6dc` / `0xfe741`), filtrage CoreGraphics des vrais modes matériels macOS à 60 Hz (`hook_CGDisplayCopyAllDisplayModes`, zéro mode synthétique), déblocage plein écran bord à bord (`0x5e610`, `0x1303243`, `0xa7619` jusqu'à `2560×1600`) et calage dynamique sous l'encoche via `NSScreen.visibleFrame` pour tout MacBook Air/Pro 13"/14"/16" ou écran externe. La résolution est initialisée dynamiquement au lancement (`userProps.xml` + `Graphics Rules.sgr` `$High`, `textureMemory` à `1024` Mo, sans changement de résolution à chaud en pleine partie dans la `v1.4.0`).
  - **EN:** Dual 60 Hz binary lock (`0xfe6dc` / `0xfe741`), CoreGraphics hardware-only 60 Hz mode filtering (`hook_CGDisplayCopyAllDisplayModes`, zero synthetic modes), edge-to-edge fullscreen support up to `2560×1600` (`0x5e610`, `0x1303243`, `0xa7619`), and runtime under-notch clamping via `NSScreen.visibleFrame` across 13"/14"/16" MacBooks and external displays. Resolution is configured at game launch (`userProps.xml` + `Graphics Rules.sgr` `$High` preset, `1024` MB `textureMemory` fallback; no in-game hot-swap resolution switching in `v1.4.0`).
- **Trackpad natif MacBook & Correctif `Command+Tab` (`trackpad_mod/libsims2_trackpad.dylib`):**
  - **FR :** Injecté via `LC_LOAD_WEAK_DYLIB` sans Xcode : pincement à 2 doigts (zoom non inversé), balayage horizontal / rotation 2 doigts (`,`/`.`, AZERTY & QWERTY via Carbon `UCKeyTranslate`), `Control (^)` + clic-glissé (orbite 3D & inclinaison), `Option (⌥)` + glisser natif préservé, et retour `Command+Tab` propre sans rebond vers le Bureau (`SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`, neutralisation des fenêtres `SDLWindow` orphelines). Retrait complet des hooks expérimentaux de changement de résolution à chaud.
  - **EN:** Weak-linked via `LC_LOAD_WEAK_DYLIB` with zero Xcode dependency: non-inverted 2-finger pinch zoom, 2-finger horizontal swipe / twist camera rotation (`,`/`.`, AZERTY & QWERTY via Carbon `UCKeyTranslate`), `Control (^)` + click-drag 3D orbit/pitch, native `Option (⌥)` pan preserved, and clean `Command+Tab` focus recovery (`SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`, orphan `SDLWindow` suppression). Experimental hot-swap resolution hooks removed for full stability.
- **Logs silencieux, `crash_report.log` & `[2] Diagnostic & Support GitHub` (`sims2_trackpad.m` & `patch_sims2.command`):**
  - **FR :** Zéro écriture disque en session normale ; capture async-signal-safe dans `crash_report.log` uniquement en cas de crash ; mode debug à la demande (`debug_boot.log`) et option `[2] Diagnostic & Support GitHub` générant `github_support_report.md` anonymisé (`~`) copié automatiquement dans le presse-papier.
  - **EN:** Zero disk writes during normal play; async-signal-safe `crash_report.log` created only on crash; on-demand `debug_boot.log` and `patch_sims2.command` option `[2] Diagnostic & Support GitHub` generating an anonymized (`~`) `github_support_report.md` copied straight to the clipboard.

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
