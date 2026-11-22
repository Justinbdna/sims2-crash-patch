# Changelog

All notable changes to **Sims 2 Crash Patch** (*The Sims 2: Super Collection* — Mac App Store Edition) are documented in this file.

---

## [1.5.0-rc2] - 2026-11-22

### Fixed & Improved (FR / EN)
- **Multi-écrans Fenêtré sans rebond & anti ping-pong Window Tiling (`trackpad_mod/sims2_trackpad.m`):**
  - **FR :** Contournement de `-[SDLWindow constrainFrameRect:toScreen:]` (`0x100101050`) qui forçait `SDL_GetDisplayBounds(0)` et renvoyait toute fenêtre déplacée sur un écran secondaire vers le bord droit de l'écran principal (`x = 288`). Délégation propre vers `NSWindow` sur l'écran contenant la fenêtre (`resolve_screen_for_rect`), neutralisation du ping-pong macOS Window Tiling (`compute_anti_tiling_windowed_frame`), et séparation des métriques de l'écran principal (`gPrimary*`) pour stabiliser les coordonnées SDL/souris sur moniteur externe non-Retina (`scale=1.0`, `safeTop=0`).
  - **EN:** Bypassed Aspyr's `-[SDLWindow constrainFrameRect:toScreen:]` (`0x100101050`) hardcoded `SDL_GetDisplayBounds(0)` clamp that bounced windowed sessions on secondary monitors back to Display 0 (`x = 288`). Clean delegation to `NSWindow` on the actual target screen (`resolve_screen_for_rect`), Window Tiling ping-pong neutralization (`compute_anti_tiling_windowed_frame`), and isolated primary display metrics (`gPrimary*`) for rock-solid mouse/SDL coordinates on non-Retina external monitors.
- **Plein écran multi-écrans respectueux des proportions (`compute_aspect_fitted_fullscreen_rect`):**
  - **FR :** Ajustement homothétique centré (`compute_aspect_fitted_fullscreen_rect`) dans les Spaces Plein écran multi-écrans : si l'écran diffère du ratio framebuffer moteur de plus de `2 %` (ex. framebuffer `1800×1131` déplacé sur TV `1920×1080` 16:9), le jeu conserve des bordures noires symétriques propres (`1719×1080@(1900,89)`, zéro étirement) avec projection souris/clics 3D exacte ; un lancement avec l'écran 16:9 en écran principal conserve le plein cadre natif `1920×1080` et propose des presets fenêtrés 16:9 cohérents.
  - **EN:** Added `compute_aspect_fitted_fullscreen_rect` for multi-monitor Fullscreen Spaces: when display aspect differs from the engine framebuffer by `> 2%` (e.g. `1800×1131` moved onto a `1920×1080` 16:9 TV), the game preserves symmetric black pillarboxes (`1719×1080@(1900,89)`, zero stretch) with exact 3D mouse projection; launching with a 16:9 display set as Main Display runs native edge-to-edge `1920×1080` with 16:9 windowed presets.
- **Correctif écran noir `scale=1.0 <-> 2.0`, sortie Plein écran sur l'écran d'origine, rafraîchissement OpenGL/Spaces coalescé & rollback `windowDidFailToExitFullScreen:`:**
  - **FR :** Mémorisation de l'écran source avant sortie du Space Plein écran (`remember_exit_fullscreen_target_screen`, bypass `swizzled_sdlConstrainFrameRect` actif pendant `gInFullscreenTransition` + garde `didExitFullScreenSettle` 180 ms) afin que `⌘ + Entrée` sur un écran externe ne renvoie plus la fenêtre sur l'écran principal. Coalescence des rafraîchissements OpenGL/Metal (`gOpenGLRefreshSeq`, debounce 140 ms sans `setFrame:` synchrone en inactif) sur `NSWindowDidChangeScreenNotification` / `NSWindowDidChangeBackingPropertiesNotification`, réactivation différée 150 ms sur `NSWorkspaceActiveSpaceDidChangeNotification` (`gSpaceReactivateSeq`), protection de `NSApplicationPresentationFullScreen` (`0x400`) et correction de `swizzled_windowDidFailToExitFullScreen` lorsque `stillInSpace == NO`.
  - **EN:** Preserved the origin display when exiting a Fullscreen Space (`remember_exit_fullscreen_target_screen`, `swizzled_sdlConstrainFrameRect` bypass during `gInFullscreenTransition`, plus 180 ms `didExitFullScreenSettle` guard) so `⌘ + Return` on an external display never bounces back to Display 0. Coalesced OpenGL/Metal refreshes (`gOpenGLRefreshSeq`, 140 ms debounce with zero synchronous `setFrame:` while inactive) on `NSWindowDidChangeScreenNotification` / `NSWindowDidChangeBackingPropertiesNotification`, deferred 150 ms `NSWorkspaceActiveSpaceDidChangeNotification` reactivation (`gSpaceReactivateSeq`), `NSApplicationPresentationFullScreen` (`0x400`) preservation, and fixed `swizzled_windowDidFailToExitFullScreen` when `stillInSpace == NO`.
- **Alignement versions `v1.5.0-rc2` (`restore_sims2.command`, `clean_sims2_cache.command`, `patch_sims2.command`, docs & QA):**
  - **FR :** Suppression des anciennes bannières `(v1.4.1)` dans `restore_sims2.command` et `clean_sims2_cache.command`, documentation multi-écrans bilingue et suite de tests dédiée (`36/36`).
  - **EN:** Aligned all banners across `restore_sims2.command`, `clean_sims2_cache.command`, `patch_sims2.command`, docs, and packager to `v1.5.0-rc2`, plus bilingual multi-monitor documentation and dedicated QA tests (`36/36`).

### Known Limitations (FR / EN)
- **FR :** En multi-écrans mixtes (Retina + écran externe 1x) sous macOS 27.0, passez en mode Fenêtré (`⌘ + Entrée`) avant de déplacer le jeu sur un autre écran plutôt que de glisser un Space Plein écran via Mission Control (contournement côté WindowServer/Dock si l'écran externe reste noir : `killall Dock`).
- **EN:** On mixed multi-monitor setups (Retina + 1x external display) on macOS 27.0, switch to Windowed mode (`⌘ + Return`) before moving the game across displays instead of dragging a Fullscreen Space in Mission Control (WindowServer/Dock workaround if the external display stays black: `killall Dock`).

---

## [1.5.0-rc1] - 2026-11-22

### Added & Fixed (FR / EN)
- **Démarrage toujours en Plein écran natif sous l'encoche & correction définitive des crashs au boot (`trackpad_mod/sims2_trackpad.m`):**
  - **FR :** Correctif `hook_sscanf` (wrapper variadique `va_copy`/`vsscanf` sûr) supprimant le crash `SIGSEGV` au démarrage (`0x1006ea404`), résolution O(1) sûre du `SDL_Window*` via `Cocoa_WindowListener._data` (éliminant l'`EXC_BAD_ACCESS` dans `findSDLWindow` pendant `initWithContentRect:`), et démarrage systématique dans un vrai Space Plein écran natif macOS sous l'encoche sans accès disque `userProps.xml` / `Library/Containers` (zéro alerte macOS TCC). Retrait définitif du mode expérimental Upscaling.
  - **EN:** Added `va_copy`/`vsscanf`-safe `hook_sscanf` fixing the startup `SIGSEGV` (`0x1006ea404`), safe O(1) `SDL_Window*` resolution via `Cocoa_WindowListener._data` (eliminating `EXC_BAD_ACCESS` inside `findSDLWindow` during `initWithContentRect:`), and consistent startup directly in a native macOS Fullscreen Space under the notch with zero `userProps.xml` / `Library/Containers` reads (zero TCC prompts). Removed experimental Fullscreen Upscaling completely.
- **Mode Fenêtré multi-résolutions, raccourcis `Command`, menu `Affichage`, résolution interne unique & alignement souris 3D 1:1:**
  - **FR :** Raccourcis séparés et migrés sur `Command` : `⌘ + Entrée` (Plein écran natif ↔ Fenêtré) et `⌘ + R` (cycle des résolutions fenêtrées compatibles avec l'écran actif uniquement) + menu macOS `Affichage` dédié. Nettoyage des 3 résolutions de secours synthétiques codées en dur par Aspyr (`1280×720`, `1024×768`, `1344×756` aux offsets `0x5e517`/`0x5e54c`/`0x5e591`) afin que le panneau interne *Taille de l'écran* n'expose que la résolution native utile active du Mac. Projection souris bidirectionnelle exacte (clics objets 3D, menus circulaires et `CGWarpMouseCursorPosition` / `CGDisplayMoveCursorToPoint` sans décalage Retina), resynchronisation `DidMove` → `sdlWindow->x/y`, et contrôles caméra `Option (⌥)` / `Control (^)` pleinement fonctionnels en mode Fenêtré comme en Plein écran (souris externe USB/Bluetooth incluse).
  - **EN:** Separated `Command` shortcuts: `⌘ + Return` (Native Fullscreen ↔ Windowed) and `⌘ + R` (cycle display-compatible windowed resolutions only), plus a dedicated macOS `Affichage` menu. Removed Aspyr's 3 hardcoded synthetic fallback entries (`1280×720`, `1024×768`, `1344×756` at `0x5e517`/`0x5e54c`/`0x5e591`) so the in-game *Screen Size* dropdown displays only the Mac's active usable native resolution. Exact bidirectional mouse coordinate projection (3D object clicks, pie menus, and inverse `CGWarpMouseCursorPosition` / `CGDisplayMoveCursorToPoint` with zero Retina drift), `DidMove` → `sdlWindow->x/y` sync, and full `Option (⌥)` / `Control (^)` camera controls in both Windowed and Fullscreen modes (including external USB/Bluetooth mice).
- **Fiabilité multi-écrans, changement d'échelle macOS à chaud & correctif `windowDidFailToEnterFullScreen:`:**
  - **FR :** Correction du crash `doesNotRecognizeSelector:` (`-[SDLWindow object]`) dans `swizzled_windowDidFailToEnterFullScreen` avec rollback propre vers l'état Fenêtré et déclenchement différé (`dispatch_async`) des actions du menu `Affichage`. Prise en charge complète des écrans secondaires (`screens[0]` pour le repère CoreGraphics), écrans non-Retina, petits écrans (`1280×800` / `1440×900` / `1512×982`) et changements de résolution/moniteur à chaud (`NSApplicationDidChangeScreenParametersNotification`).
  - **EN:** Fixed `doesNotRecognizeSelector:` (`-[SDLWindow object]`) crash in `swizzled_windowDidFailToEnterFullScreen` with clean Windowed state rollback and deferred (`dispatch_async`) `Affichage` menu dispatch. Full support for secondary displays (`screens[0]` CoreGraphics origin), non-Retina displays, compact displays (`1280×800` / `1440×900` / `1512×982`), and live display/scale changes (`NSApplicationDidChangeScreenParametersNotification`).
- **Crash reporter automatique numéroté, signature propre sans `--deep` & nettoyage des anciennes préférences (`sims2_trackpad.m` & `patch_sims2.command`):**
  - **FR :** Rapports de crash cumulatifs numérotés (`~/Library/Logs/Sims2-Crash-Patch/sims2_crash_001.log`… max 20, lien `crash_report.log` + pile symbolisée `dladdr` + préservation des `.ips` macOS), télémétrie normale 100 % opt-in (`SIMS2_DIAG_LOG=1` → `$TMPDIR/sims2_patch_diag_XXX.log`), signature ad-hoc de la dylib et de l'app **sans `--deep`** suivie de `codesign --verify --deep --strict`, et nettoyage automatique des anciennes clés expérimentales `S2Patch*`.
  - **EN:** Cumulative numbered crash reports (`~/Library/Logs/Sims2-Crash-Patch/sims2_crash_001.log`… max 20, `crash_report.log` symlink, `dladdr`-symbolized stack trace, native macOS `.ips` preserved), strictly opt-in normal telemetry (`SIMS2_DIAG_LOG=1` → `$TMPDIR/sims2_patch_diag_XXX.log`), ad-hoc signing of the dylib and app **without `--deep`** verified with `codesign --verify --deep --strict`, and automatic cleanup of obsolete experimental `S2Patch*` preferences.

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
