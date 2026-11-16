# Méga Audit Technique & Feuille de Route — `sims2-crash-patch` (v1.2.1 ➔ v1.3.0+)

> [!NOTE]
> **Archive historique (`v1.2.1`) :** Tous les correctifs `A1`–`A7`, `userProps.xml`, `maxfiles`, `Graphics Rules.sgr` et Trackpad natif SDL2 listés ci-dessous ont depuis été implémentés entre `v1.3.0` (`main`) et `v1.4.1` (`release/v1.4.1`). Pour l'état actuel et la checklist des tests en cours, consultez [`docs/HANDOFF_MAC.md`](HANDOFF_MAC.md).

**Date de l'audit :** `2026-11-13`  
**Base auditée :** Commit `da8242d` (`v1.2.1`, branche `main`)  
**Scope :** Scripts macOS (`*.command`), packaging & CI/CD, cohabitation Windows ↔ macOS, veille communautaire et nouvelles fonctionnalités (Trackpad / Caméra, stabilité post-patch).

---

## 1. Verdict Global sur `v1.2.1` (macOS)

Le socle `v1.2.1` est **sain et bien pensé** pour son objectif initial :
- Le patch binaire dans `FUN_1000fe510` (`0xfe6dc` + `0xfe73b`/`0xfe741`) utilise une recherche par empreinte unique (`count_occurrences == 1`), est **idempotent**, ne dépend pas d'offsets fragiles et fonctionne avec `/usr/bin/perl` natif (zéro déclenchement Xcode CLT / `libxcselect`).
- L'écriture atomique (`Sims2XP_Exe.tmp.$$` + `rename`) et la vérification des octets vierges avant de créer/restaurer `Sims2XP_Exe.backup` protègent efficacement contre la corruption du binaire de secours.
- La sortie du Sandbox via `codesign --force --deep --sign -` débloque l'accès direct à `~/Library/Application Support/Aspyr/The Sims 2/Downloads/` pour les mods/CC, avec migration Finder sans `with replacing`.

Cependant, un audit approfondi ligne par ligne et une veille technique sur macOS (Apple Silicon / Sequoia / macOS 26–27) et Windows 11 mettent en évidence **7 failles/cas limites dans les scripts macOS**, **4 causes majeures de crash encore non couvertes sur Mac**, et **une opportunité majeure pour la caméra Trackpad**.

---

## 2. Bugs & Cas Limites Trouvés dans `v1.2.1` (à corriger en `v1.2.2` sur Mac)

> **Principe strict :** Ces correctifs ne touchent pas encore aux `.command` tant qu'ils ne sont pas testés sur Mac ; les fichiers macOS `v1.2.1` à la racine restent donc **100 % intacts** aujourd'hui.

| # | Fichier & Lignes | Problème identifié | Impact réel | Correctif recommandé |
| :--- | :--- | :--- | :--- | :--- |
| **A1** | `patch_sims2.command` L252–255 | `ls -A "$TARGET_DATA_DIR"` compte `.DS_Store` comme dossier non vide. | Si le Finder a créé `.DS_Store` dans `Application Support/Aspyr/The Sims 2/`, le script bascule en mode `BACKUP` et place les vraies sauvegardes dans `The Sims 2 (Sandbox Backup ...)` : le jeu démarre sans quartiers ! | Ignorer `.DS_Store` (vérifier la présence d'autres éléments ou de `Neighborhoods/` / `Downloads/` / `Config/`). |
| **A2** | `patch_sims2.command` L285–350 & L375–428, `clean_sims2_cache.command` L105–119 | Les blocs `case "$MIGRATE_RESULT"` et `case "$SANDBOX_CACHE_RESULT"` n'ont **aucune branche par défaut `*)`**. | Si l'utilisateur clique sur « Ne pas autoriser » lors du prompt Automatisation Finder (`-1743`) ou si `osascript` échoue sur `stderr`, `$MIGRATE_RESULT` est vide, la variable `MIGRATION_STATUS` reste vide, et le script affiche tout de même `PATCH COMPLETE` avec une ligne vide. | Ajouter `2>&1` (ou capturer le code retour `$?`) + une branche `*)` affichant clairement l'erreur TCC Finder et comment la réactiver dans *Réglages Système ➔ Confidentialité et sécurité ➔ Automatisation*. |
| **A3** | `patch_sims2.command` L59–65 | `run_as_real_user` utilise `sudo -u "$REAL_USER"` si le script est lancé avec `sudo`. | Sur macOS récent, `sudo -u` perd le contexte Aqua/WindowServer (`bootstrap` mach), faisant échouer `osascript` / Finder AppleEvents. | Si `id -u == 0`, utiliser `launchctl asuser "$REAL_UID" sudo -u "$REAL_USER" "$@"`. |
| **A4** | `patch_sims2.command` L138–149 | `write_atomic` en Perl ne supprime `$tmp` qu'en cas d'échec de `rename`, pas si `print`/`close`/`chmod` échoue (ex. disque plein). | Un fichier résiduel `Sims2XP_Exe.tmp.<pid>` dans `Contents/MacOS/` peut faire échouer `codesign --force --deep`. | Utiliser un bloc `END` ou `unlink($tmp)` systématique sur toute erreur avant `rename`. |
| **A5** | `patch_sims2.command` L172–181 | Si `Sims2XP_Exe.backup` existe mais contient un binaire déjà patché (issu d'une ancienne v1.0) alors que `Sims2XP_Exe` actuel est vierge (ex. réinstallation App Store par-dessus), le script avertit mais **ne répare pas** `.backup`. | L'utilisateur reste bloqué avec un `.backup` invalide pour `restore_sims2.command`. | Ajouter `elsif (is_pristine($data))` pour auto-réparer `Sims2XP_Exe.backup` depuis le binaire vierge courant. |
| **A6** | `patch_sims2.command` L237, `restore_sims2.command` L131 | Absence de `codesign --verify --deep --strict "$APP_PATH"` après re-signature, et aucun traitement des attributs étendus Finder (`resource fork, Finder information, or similar detritus not allowed`). | Une re-signature partielle ou bloquée par un attribut Finder peut passer inaperçue ou planter sans explication claire. | Ajouter une vérification post-signature (`codesign --verify --deep --strict`) et diagnostiquer/nettoyer les `xattr` parasites si `codesign` échoue pour *detritus*. |
| **A7** | `clean_sims2_cache.command` L44 | Utilise `$HOME` directement au lieu de `resolve_real_user`. | Si quelqu'un lance `sudo ./clean_sims2_cache.command`, `$HOME` pointe sur `/var/root` au lieu de `/Users/<nom>`. | Réutiliser `resolve_real_user` (ou refuser poliment `sudo` puisqu'il n'en a pas besoin). |

*(Détail mineur : ligne 115 de `patch_sims2.command` importe `use File::Copy qw(copy);` sans jamais l'utiliser.)*

---

## 3. Veille Communautaire — 4 Opportunités Majeures sur macOS (Apple Silicon)

### Opportunité 1 — Crash `userProps.xml` (`activeDeviceDisplayMode`)
- **Constat :** Même après le patch ProMotion 120 Hz, si le joueur branche un écran externe (4K, TV, moniteur 16:9) puis relance le jeu sur l'écran interne du MacBook (ou change la mise à l'échelle Retina), `Sims2XP_Exe` lit une résolution obsolète dans `~/Library/Application Support/Aspyr/The Sims 2/Config/userProps.xml` (`<AnyString key="activeDeviceDisplayMode" ...>`) et lève une exception fatale (`SIGSEGV` / `__cxa_throw`).
- **Action recommandée (`v1.3.0`) :** Ajouter dans `clean_sims2_cache.command` (ou un module de réparation dédié) la détection et la réinitialisation sécurisée (avec `.backup`) de `activeDeviceDisplayMode` vers un mode valide à `60 Hz`.

### Opportunité 2 — Crash / Objets manquants par limite de descripteurs (`maxfiles` / `ulimit -n`)
- **Constat :** Le mode Non-Sandbox facilite l'ajout de centaines/milliers de fichiers `.package` dans `Downloads/`. Or le moteur *Sims 2* ouvre tous les `.package` simultanément au démarrage ; macOS plafonne les descripteurs de fichiers ouverts par application GUI, provoquant des crashs aléatoires ou des sauvegardes corrompues dès que la collection de CC grossit.
- **Action recommandée (`v1.3.0`) :** Compter le nombre de `.package` dans `Downloads/` lors de l'exécution du patch/nettoyeur, avertir au-delà d'un seuil critique (~200–250 fichiers), et proposer un assistant optionnel pour `/Library/LaunchDaemons/limit.maxfiles.plist` (ou un lanceur avec `ulimit -n`).

### Opportunité 3 — `Graphics Rules.sgr` sur Apple Silicon (Pink Soup / VRAM / Résolutions Retina)
- **Constat :** Comme le bundle `.app` est déjà re-signé en local (`codesign --force --deep --sign -`), on n'est plus bloqué par le sceau App Store pour ajuster `/Applications/The Sims 2.app/Contents/Assets/Expansion Packs/TSData/Res/Config/Graphics Rules.sgr` (toujours avec backup `.backup`).
- **Action recommandée (`v1.3.0`) :** Ajuster `textureMemory` (pour éviter la « soupe rose » / textures violettes sur GPU unifiés M1/M2/M3/M4) et débloquer proprement les résolutions 16:10 / Retina supportées.

### Opportunité 4 — Caméra Trackpad Native sur macOS (Architecture Technique)
- **Le problème :** *The Sims 2* exige un **clic-glissé du bouton central (molette)** pour pivoter et incliner la caméra. Les MacBook trackpads n'ont pas de bouton central maintenu (et les outils tiers comme BetterTouchTool sont payants ou délicats à configurer).
- **Deux architectures possibles pour macOS :**
  1. **Option A (Recommandée si `Sims2XP_Exe` passe par AppKit `NSEvent`) — Dylib injectée (`x86_64`, `LC_LOAD_DYLIB` via `insert_dylib` ou wrapper) :**
     Puisque l'app est re-signée ad-hoc sans *Hardened Runtime / Library Validation*, une minuscule `.dylib` Objective-C peut swizzler `sendEvent:` sur `NSApplication`/`NSWindow` pour convertir :
     - **Scroll horizontal à 2 doigts (`deltaX`)** ➔ rotation caméra fluide (`NSOtherMouseDown/Dragged/Up` ou `,`/`.`)
     - **`Option (⌥)` + clic-glissé trackpad** ➔ orbite + inclinaison 3D (`NSOtherMouseDown/Dragged/Up`, bouton `2`)
     - **Pinch (`NSEventTypeMagnify`) / Rotation (`NSEventTypeRotate`)** ➔ zoom et rotation directs !
  2. **Option B (Si `Sims2XP_Exe` lit les événements via Carbon `WaitNextEvent` / IOKit HID) — Compagnon `CGEventTap` :**
     Un utilitaire léger natif macOS (menu bar / CLI) utilisant `CGEventTapCreate` filtré sur le PID de `Sims2XP_Exe` (nécessite la permission *Accessibilité* macOS, sans modifier le binaire d'entrée du jeu).
- **Prérequis exact pour trancher entre Option A et Option B :** Inspecter les symboles importés de `Sims2XP_Exe` et `AppBundleExe` sur Mac (ou depuis un dump `otool -L` / `nm -u` / projet Ghidra).

---

## 4. Cohabitation PC Windows ↔ Mac & Optimisations Déjà Mises en Place

Afin de coder confortablement depuis ce PC Windows **sans jamais casser le code macOS** :

1. **`.gitattributes` :**
   - Force `eol=lf` sur tous les scripts macOS (`*.command`, `*.sh`), Python, Markdown, YAML, XML, Objective-C/C.
   - Force `eol=crlf` uniquement sur les scripts Windows (`*.bat`, `*.cmd`, `*.ps1`).
   - Protège les binaires/archives (`*.zip`, `*.exe`, `*.dll`, `*.dylib`).
2. **Validation & Build de Release Cross-Plateforme (`scripts/verify_and_package.py` + `tests/test_repo_and_patcher.py`) :**
   - Vérifie automatiquement l'absence de `CRLF` dans tous les scripts Mac, la syntaxe `bash -n` et `perl -c`, et exécute des tests unitaires réels sur les moteurs Perl d'origine avec des binaires synthétiques.
   - Génère deux archives séparées dans `dist/` :
     - `sims2-crash-patch-<version>.zip` (Mac : garantit `LF` + permissions POSIX **`0755`** sur tous les `.command` même si généré depuis Windows !).
     - `sims2-crash-patch-windows-<version>.zip` (Windows uniquement, dossier `windows/`).
3. **GitHub Actions (`.github/workflows/ci-and-release.yml`) :**
   - Lance la suite QA sur `ubuntu-latest` et `windows-latest` à chaque push/PR, et publie automatiquement les deux ZIPs propres lors d'un tag `v*`.
4. **Édition Spéciale Windows isolée dans `windows/` :**
   - `windows/sims2_trackpad_camera.py` + `Sims2_Trackpad_Camera.bat` : Hook Win32 bas niveau (`WH_MOUSE_LL` + `WH_KEYBOARD_LL`) actif uniquement quand *The Sims 2* est au premier plan :
     - **Swipe horizontal 2 doigts (`WM_MOUSEHWHEEL`)** ➔ rotation fluide de la caméra
     - **`AltGr` (`Right Alt`) + clic gauche glissé** ➔ orbite & inclinaison 3D (`MMB`)
     - **Touche `F8`** ➔ bascule « Orbite 1 doigt » (désarmement auto sur `Esc` / `Alt-Tab`)
   - `windows/sims2_windows_toolkit.py` + `Sims2_Toolkit.bat` : Diagnostic PE32 **4GB (`LARGEADDRESSAWARE`)** + patch/backup atomique avec recalcul checksum PE, détecteur **OneDrive Documents**, vérification **> 60 Hz**, réparation `userProps.xml` et nettoyeur de caches Windows.

---

## 5. Ce dont j'ai besoin (si tu veux aller encore plus loin sur la partie Mac depuis ce PC)

Pour développer et tester sur ce PC Windows la **suite Mac (`v1.2.2` / `v1.3.0`)** et la **caméra trackpad native macOS** :
1. **Le binaire `Sims2XP_Exe` (et idéalement `AppBundleExe` / ton projet Ghidra `.gzf`)** — à copier en local dans un dossier ignoré par Git (ex. `scratch/` ou `tmp/` qui sont déjà dans `.gitignore` !) pour ne jamais le publier sur GitHub : cela me permettra d'inspecter les imports (`NSEvent` vs Carbon/SDL/IOKit) et de cibler précisément le trackpad, `userProps.xml`, et `Graphics Rules.sgr`.
2. **Outils optionnels (seulement si tu veux analyser du Mach-O / recompiler sur ce PC) :**
   - **Ghidra** (ou **LLVM / `llvm-objdump`**) en local sur Windows si tu veux faire du reverse engineering avancé ici.
   - Pour compiler/tester une vraie `.dylib` macOS et exécuter `codesign` en conditions réelles depuis ce PC, un runner **`macos-latest` sur GitHub Actions** est déjà utilisable via `gh` (sans rien installer localement), et la validation finale en jeu se fera sur ton MacBook Pro.
   - **Côté Windows :** Tu as `The Sims 2 Ultimate Collection.iso` dans `Downloads` — si tu l'installes (ou nous donnes le chemin si tu comptes y jouer sur ce PC), tu pourras tester directement `windows/Sims2_Trackpad_Camera.bat` et `windows/Sims2_Toolkit.bat` en jeu !
