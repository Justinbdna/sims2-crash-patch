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

### Points d'Audit Trouvés sur `staging` (à traiter avant `v1.4.0`)
1. **`trackpad_mod/sims2_trackpad.m` vs `libsims2_trackpad.dylib` (Important — sans casser la synchro binaire) :**
   - *Règle d'or depuis Windows / en distanciel :* ne jamais modifier `sims2_trackpad.m` sur `staging` sans recompiler `trackpad_mod/libsims2_trackpad.dylib` sur macOS (`build_trackpad.sh`), sinon le source et la `.dylib` embarquée divergent.
   - **Cas limites repérés dans `sims2_trackpad.m` (pour une future branche `fix/trackpad-edge-cases` à recompiler sur Mac / artefact CI macOS) :**
     - *Conflit clic gauche/droit pendant `Option`+drag (L551–607) :* `handle_option_mouse_down` ne vérifie pas `!gOptionMiddleDragActive` et `handle_option_mouse_up` ne vérifie pas que le `mouseUp:`/`rightMouseUp:` correspond au bouton d'origine (`gOptionDragWasRight`). Un clic secondaire accidentel en cours de glissé peut terminer l'orbite ou envoyer un faux `SDL_BUTTON_MIDDLE`.
     - *Premier pincement avant tout mouvement souris (L283–294) :* si `gWindowListener` est encore `nil`, le fallback `[NSApp postEvent:scrollEv atStart:NO]` n'active pas `gForceScrollNonInverted = YES` (risque d'inversion sur le tout premier pinch avec défilement naturel).
     - *Suppression scroll (L297/508) :* `gSuppressCurrentScroll` est un simple booléen global plutôt que la référence exacte de l'`NSEvent` dépilé.
2. **`Graphics Rules.sgr` (`patch_sims2.command` L17 & L1054) :**
   - À vérifier sur Mac : est-ce que `/Applications/The Sims 2.app` utilise uniquement `Contents/Resources/Config/Graphics Rules.sgr`, ou existe-t-il aussi des copies sous `Contents/Assets/.../TSData/Res/Config/Graphics Rules.sgr` ?
   - Si un bloc `# Override defaults (SIM-281,416)` contient une ligne `# commentaire` au milieu du bloc, la regex actuelle s'arrête à ce `#`.
3. **Collision de numéro de version avant release (`v1.3.1` vs `v1.4.0`) :**
   - `v1.3.1` est déjà publié sur GitHub (`acec191`). `staging` porte encore `Version: 1.3.1` et `[1.3.1]` dans `CHANGELOG.md` / `README.*` alors que les tests Trackpad/Graphics Rules s'appellent `test_v14_*`. Ne jamais re-taguer `v1.3.1` : passer tout en **`v1.4.0`** uniquement lorsque les tests en jeu sur Mac seront validés.
4. **Durcissement CI & Packaging déjà appliqué sur `feat/v1.4-audit-and-macos-ci` :**
   - `.github/workflows/ci-and-release.yml` exécute désormais `verify` sur `ubuntu-latest`, `windows-latest` **et `macos-latest`** (compilation `clang -arch x86_64` de `sims2_trackpad.m` + `codesign --verify --strict` + tests macOS) sur `main`, `staging`, `feat/**`, `fix/**`, `audit/**`, `chore/**` et les PRs.
   - Correction du bug potentiel de nom de branche contenant `/` (`feat/...`) dans `package_releases()` (`scripts/verify_and_package.py`) et validation `LF`/`bash -n` ajoutée sur `trackpad_mod/build_trackpad.sh`.

---

## 3. Checklist de Tests Réels sur MacBook Pro (Quand tu rentreras sur Mac)

- [ ] Vérifier les emplacements réels dans l'app bundle : `find "/Applications/The Sims 2.app/Contents" -name "Graphics Rules.sgr"`
- [ ] Recompiler (si `sims2_trackpad.m` a été modifié sur une branche `fix/*`) : `./trackpad_mod/build_trackpad.sh`
- [ ] Lancer `python3 scripts/verify_and_package.py` sur macOS
- [ ] Lancer `./patch_sims2.command` et vérifier `latest.log`, `LC_LOAD_WEAK_DYLIB` (`otool -L "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"`), `codesign --verify --deep --strict`
- [ ] Tester en jeu *Les Sims 2* (clavier AZERTY puis QWERTY, `SIMS2_TRACKPAD_DEBUG=1` au besoin) :
  - [ ] Pincement 2 doigts = zoom avant/arrière naturel non inversé
  - [ ] Swipe horizontal 2 doigts & rotation 2 doigts = rotation `,`/`.` fluide sans conflit avec le zoom vertical
  - [ ] `Option (⌥)` + clic-glissé = orbite 3D libre + pitch, et relâchement propre si perte de focus (`Cmd+Tab`)
  - [ ] Plein écran Space SDL2 + masquage du Dock + `Cmd+Tab` sans téléportation curseur
  - [ ] Effets graphiques `$High` / résolutions Retina dans les options du jeu
- [ ] Lancer `./restore_sims2.command` et vérifier restauration complète (`Sims2XP_Exe`, `Graphics Rules.sgr`, suppression `libsims2_trackpad.dylib`, `codesign --verify --strict`)
- [ ] Uniquement après tous les `[x]` ci-dessus : passer les versions à `v1.4.0`, merger `staging` -> `main`, puis taguer `v1.4.0`.
