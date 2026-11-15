# État du Projet, Workflow Git & Checklist Mac — `sims2-crash-patch`

> **Usage :** Ce document reflète l'état réel après la release `v1.3.1` (`main` `acec191`) et les évolutions sur `staging` jusqu'au commit **`93b7141`** (en attente de validation complète en jeu sur Mac).

---

## 1. Convention de Branches Git (Obligatoire pour chaque ajout)

| Branche | Rôle | Règle stricte |
| :--- | :--- | :--- |
| **`main`** | Production stable & releases (`v1.3.1`) | Ne recevoir des merges que depuis `staging` **après** tests réels en jeu sur Mac et bump de version cohérent (`v1.4.0`). Ne jamais coder directement dessus. |
| **`staging`** | Pré-production / intégration `v1.4` | Reçoit les branches `feat/*`, `fix/*`, `audit/*` validées par GitHub Actions (sans créer de GitHub Release). |
| **`feat/*`**, **`fix/*`**, **`audit/*`**, **`chore/*`** | **1 branche dédiée par ajout, correctif ou audit** | Toujours partir de `staging`, faire passer la CI (`ubuntu-latest`, `windows-latest`, `macos-latest`), puis ouvrir une Pull Request vers `staging`. |

---

## 2. Où on en est (Audit Réel de `main` & `staging`)

### Ce qui est déjà livré et validé en production (`main` `acec191`, tag `v1.3.1`)
- Correctifs d'audit `A1`–`A7` (ignore `.DS_Store`/`.localized`/`._*`, capture `osascript` + gestion TCC `-1743` et conteneur `-5000`, `launchctl asuser` pour Aqua, nettoyage tmp Perl, auto-réparation `Sims2XP_Exe.backup`, `codesign --verify --strict` + nettoyage `xattr`, `resolve_real_user` dans `clean_sims2_cache.command`).
- Protection `Config/userProps.xml` (JXA `CoreGraphics`/`NSScreen` + `userProps.xml.backup`), diagnostic Mods/CC & `maxfiles` (`LaunchDaemon` marqué `Managed by sims2-crash-patch`), menu interactif `[1/2/3/4]` dans `clean_sims2_cache.command`, journaux `~/Library/Logs/Sims2-Crash-Patch/latest.log`.
- Cohabitation Windows/macOS isolée dans `windows/` + `.gitattributes` + packaging ZIP séparé (`scripts/verify_and_package.py`).

### Ce qui a été ajouté sur `staging` (`68e897` ➔ `93b7141`) — En attente de test réel Mac
1. **Étape 3A — `Graphics Rules.sgr` & Patchs d'affichage (`patch_sims2.command` & `restore_sims2.command`) :**
   - Cible `$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr` (avec `.backup`), passe `textureMemory` `32 -> 1024`, plafonne `maxResWidth`/`maxResHeight` à `2560x1600` (défaut natif `1800x1169`), et passe `# Override defaults (SIM-281,416)` (`EffectsQuality`, `LightingQuality`, `Shadows`, `MaterialDetail`) sur `$High`.
   - Ajoute les patchs binaires d'affichage (`0x5e610` ASL mode filter, `0x1303243` cap `<= 2560x1600`, `0xa7619` Option A Fullscreen Fill sous encoche).
2. **Étape 3B — Module Trackpad, Fenêtre & Affichage (`trackpad_mod/sims2_trackpad.m` + `libsims2_trackpad.dylib`) :**
   - Injecté par `/usr/bin/perl` via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`) sans Xcode CLT.
   - Hints SDL2 fullscreen Space/Dock (`SDL_VIDEO_MAC_FULLSCREEN_SPACES=1`, `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`), neutralisation des fenêtres SDL secondaires orphelines (`focusSomeWindow:`, préservation `Cmd+H`/`Cmd+M`), garde `swizzled_mouseMoved:` hors focus.
   - Gestes trackpad : `Control (^)` + clic-glissé (`SDL_BUTTON_MIDDLE` + masquage `NSEventModifierFlagControl` -> inclinaison/orbite 3D `cTSUserToolCameraMiddleClick`), `Option (⌥)` laissé natif au jeu (`e447157`), pincement 2 doigts (`NSEventTypeMagnify` -> zoom `scrollWheel`), swipe horizontal 2 doigts & rotation (`NSEventTypeRotate`) -> touches `,`/`.`.
   - Affichage & diagnostics (`4af0c5b` ➔ `93b7141`) : filtrage des vrais modes CoreGraphics 32-bit (zéro mode synthétique), virtualisation `CGDisplayFade`/`CGDisplaySetDisplayMode`, calage `NSScreen.visibleFrame` sous encoche, synchronisation `CGL`/`glViewport`/`glScissor` sécurisée contre l'abort Metal (`cgl_context_has_attached_drawable`, `tInCGLHook`, pas de `CGLEnable` dans `hook_CGLSetParameter`), et journaux `launch_boot.log` (`___cxa_throw`) + `trackpad_events.log`.

---

## 3. Checklist de Tests Réels sur MacBook Pro (Prochaine étape en jeu)

- [x] Compiler `libsims2_trackpad.dylib` & vérifier la CI (`macos-latest`, `ubuntu-latest`, `windows-latest` verts sur `93b7141`)
- [ ] Lancer `./patch_sims2.command` sur Mac et démarrer *Les Sims 2* avec `93b7141`
- [ ] Vérifier `~/Library/Logs/Sims2-Crash-Patch/launch_boot.log` (absence de `SIGABRT` Metal, modes CoreGraphics filtrés, `WIN` `visibleFrame`, `CGL`/`GL` et `MOUSE`)
- [ ] Tester en jeu *Les Sims 2* (clavier AZERTY/QWERTY) :
  - [ ] Démarrage & menu principal sans crash ni décalage de clics souris (tester aussi changement de résolution en jeu + FBO/reflets)
  - [ ] Pincement 2 doigts = zoom naturel, swipe/rotation 2 doigts = `,`/`.`, `Control (^)` + clic-glissé = orbite 3D, `Option (⌥)` natif = déplacement caméra
  - [ ] Plein écran Space sous encoche + `Cmd+Tab` / `Cmd+H` / `Cmd+M` sans écran bleu ni rebond vers le Bureau
- [ ] Lancer `./restore_sims2.command` et vérifier restauration complète (`Sims2XP_Exe`, `Graphics Rules.sgr`, suppression `libsims2_trackpad.dylib`, `codesign --verify --strict`)
- [ ] Uniquement après tous les `[x]` ci-dessus : mettre la date finale dans `CHANGELOG.md`, merger `staging` -> `main`, taguer `v1.4.0`, puis passer le dépôt en Public.
