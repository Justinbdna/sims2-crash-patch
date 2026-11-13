# Handoff PC Windows ➔ MacBook Pro — `sims2-crash-patch`

> **Usage sur Mac :** Dans Antigravity sur ton MacBook Pro (avec le workspace `sims2-crash-patch` ouvert), tape simplement :  
> `Lis @docs/HANDOFF_MAC.md et @docs/AUDIT_MEGA.md puis continuons l'implémentation et les tests sur Mac.`  
> *(Tu peux aussi glisser-déposer ce fichier directement dans une nouvelle conversation Antigravity sur Mac si tu n'as pas encore fait `git pull`.)*

---

## 1. Résumé de ce qui a été fait sur le PC Gamer Windows (`2026-11-13`)

1. **Dépôt cloné & authentifié :** `Justinbdna/sims2-crash-patch` cloné proprement depuis `origin/main` (commit de départ `da8242d`, release `v1.2.1`).
2. **Code macOS `v1.2.1` préservé à 100 % :**
   - `patch_sims2.command`, `clean_sims2_cache.command`, `restore_sims2.command`, `README.md`, `README.txt` et `CHANGELOG.md` n'ont subi **aucune modification logique** (`git diff` vide).
3. **Cohabitation Windows ↔ Mac & Build de Release mis en place :**
   - [`.gitattributes`](../.gitattributes) : force `eol=lf` sur `*.command`, `*.sh`, `*.py`, `*.md`, `*.txt`, `*.yml`, `*.m`, `*.c`, `*.h` et `eol=crlf` sur `*.bat`, `*.cmd`, `*.ps1` (fin du risque `^M: bad interpreter` lors d'éditions depuis Windows).
   - [`scripts/verify_and_package.py`](../scripts/verify_and_package.py) : vérifie `LF`, `bash -n`, `perl -c`, compile Python, lance les tests unitaires, et génère deux ZIP séparés dans `dist/` (`sims2-crash-patch-<ver>.zip` avec droits POSIX **`0755`** et `LF` sur les `.command`, et `sims2-crash-patch-windows-<ver>.zip`).
   - [`tests/test_repo_and_patcher.py`](../tests/test_repo_and_patcher.py) : 11 tests automatisés couvrant le moteur Perl exact de `patch_sims2.command` & `restore_sims2.command` (sur binaires synthétiques) + la suite Windows.
   - [`.github/workflows/ci-and-release.yml`](../.github/workflows/ci-and-release.yml) : CI sur `ubuntu-latest` + `windows-latest` et packaging automatique des releases sur tag `v*`.
4. **Édition Spéciale Windows isolée dans [`windows/`](../windows/README.md) :**
   - `windows/sims2_trackpad_camera.py` + `Sims2_Trackpad_Camera.bat` (hook Win32 `WH_MOUSE_LL`/`WH_KEYBOARD_LL` pour swipe 2 doigts horizontal, `AltGr` + drag, bascule `F8`).
   - `windows/sims2_windows_toolkit.py` + `Sims2_Toolkit.bat` (diagnostic PE32 4GB `LARGEADDRESSAWARE`, OneDrive, écran > 60 Hz, `userProps.xml`, caches).
   - *Note : Le jeu n'étant pas installé sur le PC Windows (seule l'ISO PC est dans `Downloads`), `windows/` reste isolé et facultatif pour le Mac.*

---

## 2. Priorités validées par l'utilisateur pour la suite sur Mac

### Phase Immédiate (AVANT toute nouvelle release `v1.2.2` / `v1.3.0`)
> **Rappel important :** Aucun binaire `Sims2XP_Exe` ni projet Ghidra n'est requis pour cette Phase Immédiate (tout se passe en Bash/Perl/AppleScript/XML/launchctl). En revanche, **aucune release GitHub / tag ne doit être publiée avant test réel sur le MacBook Pro**.
1. **Corriger les 7 failles/cas limites d'audit (`A1`–`A7`) dans les scripts `.command`** (détails complets dans [`docs/AUDIT_MEGA.md`](AUDIT_MEGA.md)) :
   - **A1** (`patch_sims2.command` L252–255) : `ls -A "$TARGET_DATA_DIR"` compte `.DS_Store` comme un dossier actif non vide -> bascule à tort en mode `BACKUP` au lieu de `DIRECT`. Ignorer `.DS_Store`.
   - **A2** (`patch_sims2.command` L322–350, L415–428 & `clean_sims2_cache.command` L105–119) : ajouter `2>&1` / gestion d'erreur + branche `*)` dans les `case` `osascript` (si l'utilisateur refuse la permission Automatisation Finder `-1743`, le script ne doit pas laisser `MIGRATION_STATUS` vide ni prétendre que tout est OK silencieusement).
   - **A3** (`patch_sims2.command` L59–65) : `run_as_real_user` doit utiliser `launchctl asuser "$REAL_UID" sudo -u "$REAL_USER"` quand `id -u == 0` afin de conserver le contexte Aqua/WindowServer pour `osascript`.
   - **A4** (`patch_sims2.command` L138–149) : `write_atomic` Perl doit supprimer `$tmp` (`Sims2XP_Exe.tmp.$$`) aussi en cas d'échec de `print`/`close`/`chmod`, pas seulement sur échec de `rename`.
   - **A5** (`patch_sims2.command` L172–181) : si `Sims2XP_Exe.backup` existe mais contient déjà des octets patchés alors que `Sims2XP_Exe` courant est vierge (`is_pristine($data)`), auto-réparer `.backup` depuis `$data`.
   - **A6** (`patch_sims2.command` L237 & `restore_sims2.command` L131) : ajouter `codesign --verify --deep --strict "$APP_PATH"` après re-signature, et diagnostiquer/nettoyer les attributs Finder (*detritus* / `xattr`) si `codesign` échoue à cause d'eux.
   - **A7** (`clean_sims2_cache.command` L44) : utiliser `resolve_real_user` (ou refuser/adapter en cas d'exécution via `sudo`) au lieu de `$HOME` brut, et supprimer l'import inutilisé `use File::Copy qw(copy);` (L115 de `patch_sims2.command`).

2. **Résoudre les 2 crashs / limites macOS majeurs identifiés par la veille :**
   - **Crash `userProps.xml` (`activeDeviceDisplayMode`) :**
     Même avec le patch 60 Hz, brancher puis débrancher un écran externe (ou changer la mise à l'échelle Retina) laisse un `activeDeviceDisplayMode` invalide dans `~/Library/Application Support/Aspyr/The Sims 2/Config/userProps.xml`, provoquant un `SIGSEGV` (`__cxa_throw`) au lancement.
     ➔ Ajouter une réparation sécurisée (avec sauvegarde `userProps.xml.backup`) corrigeant ou réinitialisant `activeDeviceDisplayMode` vers un mode valide à `60 Hz`.
   - **Limite macOS des descripteurs de fichiers (`maxfiles` / `ulimit -n`) pour les CC/Mods :**
     Le passage hors Sandbox donne un accès direct à `Downloads/`, mais ouvrir des centaines/milliers de `.package` simultanément fait dépasser la limite macOS par processus et provoque des crashs ou objets/quartiers manquants.
     ➔ Ajouter la détection du nombre de `.package` dans `Downloads/` + `ulimit -n`, avec avertissement clair et proposition propre pour relever `maxfiles` (ex. script/option dédiée `/Library/LaunchDaemons/limit.maxfiles.plist` réversible dans `restore_sims2.command`, ou diagnostic + commande guidée selon le choix utilisateur).

### Phase Ultérieure (Reportée après la validation des crashs/limites ci-dessus)
1. **`Graphics Rules.sgr` Apple Silicon :** Optimisation `textureMemory` (*pink soup*) et déblocage des résolutions Retina/16:10 (dans `/Applications/The Sims 2.app/Contents/Assets/Expansion Packs/TSData/Res/Config/`).
2. **Caméra Trackpad Native sur macOS :**
   - *Action requise au démarrage sur Mac :* inspecter `Sims2XP_Exe` et `AppBundleExe` avec :
     ```bash
     otool -L "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
     nm -u "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe" | grep -iE "NSEvent|CGEvent|Carbon|HID|Mouse|Trackpad|AppKit"
     ```
   - Trancher entre **Option A** (`.dylib` `x86_64` injectée swizzlant `NSEvent` `sendEvent:` pour `Option + drag`, swipe horizontal 2 doigts, pinch/rotate) et **Option B** (compagnon `CGEventTap` si Carbon/IOKit).

---

## 3. Décisions rapides à trancher au début de la prochaine session Mac

1. **Branche :** travailler sur `main` en local (sans tag/release GitHub tant que non testé en jeu) ou sur une branche `feat/v1.3.0-stability` ?
2. **Politique `maxfiles` (`ulimit -n`) :** installation interactive `O/N` du `LaunchDaemon` `/Library/LaunchDaemons/limit.maxfiles.plist` (avec suppression propre dans `restore_sims2.command`), script séparé `fix_cc_limit.command`, ou simple diagnostic ?
3. **Politique `userProps.xml` :** réparation automatique avec backup à chaque exécution de `clean_sims2_cache.command` / `patch_sims2.command`, ou uniquement sur option / détection de résolution suspecte ?
4. **Conservation de `windows/` :** garder `windows/` isolé pour plus tard ou le supprimer si le jeu ne sera jamais installé sur PC ?

---

## 4. Checklist de test réel sur le MacBook Pro (une fois les modifs codées)

- [ ] `python3 scripts/verify_and_package.py` (tous tests unitaires + `bash -n` + `perl -c` + `LF` OK)
- [ ] Double-clic `patch_sims2.command` sur MacBook Pro Apple Silicon (écran 120 Hz ProMotion) : vérifier backup intègre, `codesign --verify --deep --strict`, migration sans écrasement, `userProps.xml`, diagnostic `maxfiles`.
- [ ] Test scénario écran externe branché -> débranché (`userProps.xml`) puis lancement du jeu.
- [ ] Double-clic `clean_sims2_cache.command` et `restore_sims2.command` pour confirmer restauration & ré-application idempotente.
- [ ] Génération de la release finale via `python3 scripts/verify_and_package.py --package --version v1.3.0` (ou tag GitHub `v1.3.0`).
