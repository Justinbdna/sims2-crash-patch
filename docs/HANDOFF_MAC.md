# État du Projet, Workflow Git & Checklist Mac — `sims2-crash-patch`

> **Usage :** Ce document reflète l'état réel après la release `v1.3.1` (`main` `acec191`), l'intégration prototype sur `staging` (`68e897`) et la mise en place du workflow multi-branches + CI macOS sur `feat/v1.4-audit-and-macos-ci`.

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

### Ce qui a été ajouté sur `staging` (`68e897`) — En attente de test réel Mac
1. **Étape 3A — `Graphics Rules.sgr` (`patch_sims2.command` & `restore_sims2.command`) :**
   - Cible `$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr` (avec `.backup`), passe `textureMemory` `32 -> 1024`, `maxResWidth`/`maxResHeight` `2048 -> 5120`/`3200`, et `# Override defaults (SIM-281,416)` (`EffectsQuality`, `LightingQuality`, `Shadows`, `MaterialDetail`) de `$Medium` vers `$High`.
2. **Étape 3B — Module Trackpad & SDL2 natif (`trackpad_mod/sims2_trackpad.m` + `libsims2_trackpad.dylib`) :**
   - Injecté par `/usr/bin/perl` via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`) sans Xcode CLT.
   - Hints SDL2 fullscreen Space/Dock (`SDL_VIDEO_MAC_FULLSCREEN_SPACES`, `SDL_ALLOW_TOPMOST`, etc.) + garde `swizzled_mouseMoved:` hors focus.
   - Gestes trackpad : `Option (⌥)` + clic-glissé (`SDL_BUTTON_MIDDLE` + masquage `NSEventModifierFlagOption`), pincement 2 doigts (`NSEventTypeMagnify` -> zoom `scrollWheel`), swipe horizontal 2 doigts & rotation (`NSEventTypeRotate`) -> touches `,`/`.` résolues via Carbon `UCKeyTranslate` (AZERTY/QWERTY) maintenues `75 ms`.

### Points d'Audit Résolus & Points Restants sur `staging` (avant `v1.4.0`)
1. **`trackpad_mod/sims2_trackpad.m` + `libsims2_trackpad.dylib` — Corrigés & recompilés sur Mac :**
   - *Conflit clic gauche/droit pendant `Option`+drag :* `handle_option_mouse_down` vérifie `!gOptionMiddleDragActive`, et `handle_option_mouse_drag` / `handle_option_mouse_up` vérifient `isRight == gOptionDragWasRight`.
   - *Premier pincement avant tout mouvement souris :* `resolve_window_listener()` résout `[[NSApp keyWindow] delegate]` si possible, et le fallback `[NSApp postEvent:]` protège l'`NSEvent` ciblé via `gForcedNonInvertedEvent`.
   - *Suppression scroll par événement exact :* `gSuppressCurrentScroll` remplacé par la référence `NSEvent *` exacte (`gSuppressedScrollEvent`).
   - `.dylib` recompilée sur Mac via `./trackpad_mod/build_trackpad.sh` et signée (`codesign --verify --strict`).
2. **`Graphics Rules.sgr` (`patch_sims2.command` L17 & L1054) — Vérifié & renforcé :**
   - Vérifié dans `/Applications/The Sims 2.app/Contents/` : 19 copies existent dans les packs `Assets`, mais `config-log.txt` confirme que le binaire macOS Aspyr lit `Contents/Resources/Config/Graphics Rules.sgr`.
   - La regex `# Override defaults (SIM-281,416)` tolère désormais les commentaires `#` intermédiaires et ne s'arrête qu'aux séparateurs `#####`, `endif` ou `end`.
3. **Préparation `v1.4.0` (sur `chore/prepare-v1.4-pre-test` ➔ `staging`, sans release publiée tant que non testé) :**
   - `v1.3.1` reste la dernière release publiée sur `main` (`acec191`). Sur `staging`, les scripts `.command`, `README.*`, `CHANGELOG.md` (`[1.4.0] - Unreleased`), `verify_and_package.py` (`build_trackpad.sh` inclus), le template `.github/ISSUE_TEMPLATE/test-report.md` et les tests unitaires ont été alignés sur `1.4.0`, et le parsing `runner_out` de `patch_sims2.command` a été durci contre d'éventuels warnings `stderr`.
   - **Ne pas merger dans `main` ni pousser de tag `v1.4.0` avant d'avoir validé la checklist en jeu sur Mac ci-dessous.**
4. **Durcissement CI & Packaging — Intégré sur `staging` :**
   - `.github/workflows/ci-and-release.yml` exécute `verify` sur `ubuntu-latest`, `windows-latest` **et `macos-latest`** (compilation `clang -arch x86_64 -Wall -Wextra` de `sims2_trackpad.m` + `codesign --verify --strict` + tests macOS).
   - Sanitisation du nom de branche (`/`) dans `package_releases()` (`scripts/verify_and_package.py`) et validation `LF`/`bash -n` ajoutée sur `trackpad_mod/build_trackpad.sh`.

---

## 3. Checklist de Tests Réels sur MacBook Pro (Prochaine étape en jeu)

- [x] Vérifier les emplacements réels dans l'app bundle (`Contents/Resources/Config/Graphics Rules.sgr` confirmé via `config-log.txt`)
- [x] Recompiler `libsims2_trackpad.dylib` sur Mac : `./trackpad_mod/build_trackpad.sh` + `codesign --verify --strict`
- [x] Lancer `python3 scripts/verify_and_package.py` sur macOS (`25/25 OK`)
- [ ] Lancer `./patch_sims2.command` et vérifier `latest.log`, `LC_LOAD_WEAK_DYLIB` (`otool -L "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"`), `codesign --verify --deep --strict`
- [ ] Tester en jeu *Les Sims 2* (clavier AZERTY puis QWERTY, `SIMS2_TRACKPAD_DEBUG=1` au besoin) :
  - [ ] Pincement 2 doigts = zoom avant/arrière naturel non inversé (dès le 1er geste)
  - [ ] Swipe horizontal 2 doigts & rotation 2 doigts = rotation `,`/`.` fluide sans conflit avec le zoom vertical
  - [ ] `Option (⌥)` + clic-glissé = orbite 3D libre + pitch, sans conflit clic gauche/droit et relâchement propre sur `Cmd+Tab`
  - [ ] Plein écran Space SDL2 + masquage du Dock + `Cmd+Tab` sans téléportation curseur
  - [ ] Effets graphiques `$High` / résolutions Retina dans les options du jeu (`MacBook-Pro-*-config-log.txt`)
- [ ] Lancer `./restore_sims2.command` et vérifier restauration complète (`Sims2XP_Exe`, `Graphics Rules.sgr`, suppression `libsims2_trackpad.dylib`, `codesign --verify --strict`)
- [x] Aligner les scripts, docs, `CHANGELOG.md`, `test-report.md` et le packager sur `v1.4.0` en pré-release sur `staging` (sans taguer ni publier tant que non testé en jeu)
- [ ] Uniquement après tous les `[x]` ci-dessus : mettre la date finale dans `CHANGELOG.md` si besoin, merger `staging` -> `main`, taguer `v1.4.0`, puis passer le dépôt en Public.
