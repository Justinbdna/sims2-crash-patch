# 💎 Sims 2 Crash Patch — macOS Edition (`v1.4.0`)

[![Release v1.4.0](https://img.shields.io/badge/Release-v1.4.0-blue.svg)](https://github.com/Justinbdna/sims2-crash-patch/releases)
[![macOS Apple Silicon & Intel](https://img.shields.io/badge/macOS-Apple%20Silicon%20%26%20Intel-black.svg?logo=apple)](https://apple.com)
[![ProMotion 120Hz Fix](https://img.shields.io/badge/ProMotion-120Hz%20Fix-brightgreen.svg)](https://github.com/Justinbdna/sims2-crash-patch)
[![Zero External Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(No%20Xcode)-success.svg)](https://github.com/Justinbdna/sims2-crash-patch)

> **🇫🇷 FR :** Jouez à *The Sims 2: Super Collection* (Mac App Store) sans crash sur MacBook ProMotion 120 Hz, en vrai plein écran sous l'encoche, avec `Command+Tab` fonctionnel et un vrai support natif du Trackpad.  
> **🇬🇧 EN:** Play *The Sims 2: Super Collection* (Mac App Store) crash-free on 120 Hz ProMotion MacBooks, with crisp under-notch fullscreen, working `Command+Tab`, and native Trackpad camera controls.

<!-- 📸 Screenshot placeholder (à décommenter quand la capture plein écran sous l'encoche est ajoutée dans docs/) :
![The Sims 2: Super Collection — Plein écran sous l'encoche macOS](docs/screenshots/fullscreen-notch.png)
-->

---

## ✨ Ce que le patch corrige / What This Patch Fixes

| Problème / Issue | 🇫🇷 En français | 🇬🇧 In English |
| :--- | :--- | :--- |
| **1. Crash 120 Hz ProMotion** | Supprime le plantage immédiat au lancement : votre Mac reste en **120 Hz**, le moteur du jeu est verrouillé à **60 Hz** stables. | Fixes the instant startup crash on 120 Hz displays: your Mac stays at **120 Hz** while the game engine runs cleanly at **60 Hz**. |
| **2. Bandes noires & Encoche** | Détecte la résolution native de votre MacBook ou écran externe et cale le plein écran proprement sous l'encoche (jusqu'à `2560×1600`, profil `$High`). | Automatically detects your MacBook or external display resolution and fits fullscreen neatly below the notch (up to `2560×1600`, `$High` preset). |
| **3. `Command+Tab` cassé** | Corrige le rebond vers le Bureau et les blocages de curseur quand vous basculez vers une autre app macOS. | Stops Desktop bounce-backs and cursor-lock issues when switching to another macOS app and back. |
| **4. Caméra Trackpad** | Ajoute les gestes MacBook natifs (zoom, rotation, orbite 3D et panoramique) pour jouer confortablement sans souris externe. | Adds native MacBook gestures (pinch zoom, 2-finger rotate, 3D orbit, and pan) so you can play comfortably without an external mouse. |

---

## 🚀 Installation en 3 clics / 3-Click Setup

> [!NOTE]
> **Zéro dépendance externe :** tout fonctionne avec les outils déjà intégrés à macOS (aucun besoin d'installer Xcode ni les Command Line Tools).  
> **Zero external dependencies:** uses only built-in macOS system tools (no Xcode or Command Line Tools required).

### 🇫🇷 Français
1. **Téléchargez et décompressez** [`sims2-crash-patch-v1.4.0.zip`](https://github.com/Justinbdna/sims2-crash-patch/releases) *(fermez d'abord Les Sims 2 avec `Cmd + Q`)*.
2. **Débloquez Gatekeeper :** double-cliquez sur `patch_sims2.command` → si macOS affiche *« bloqué pour protéger votre Mac »*, cliquez sur **Terminé**, ouvrez **Réglages Système → Confidentialité et sécurité**, descendez tout en bas et cliquez sur **Ouvrir quand même**.
3. **Appuyez sur `Entrée` (`[1]`)** dans le Terminal :
   - Tapez votre mot de passe session Mac à l'aveugle (`Password:`, **aucun caractère `*` ne s'affiche**, c'est la sécurité normale de macOS) puis faites `Entrée`.
   - Quand macOS affiche *« Terminal souhaite contrôler Finder »*, cliquez sur **Autoriser** pour copier vos sauvegardes sans rien écraser.
   - Attendez le message `PATCH COMPLETE (v1.4.0)` puis lancez le jeu normalement.

### 🇬🇧 English
1. **Download and unzip** [`sims2-crash-patch-v1.4.0.zip`](https://github.com/Justinbdna/sims2-crash-patch/releases) *(quit The Sims 2 first with `Cmd + Q`)*.
2. **Bypass Gatekeeper:** double-click `patch_sims2.command` → if macOS shows *"blocked to protect your Mac"*, click **Done**, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. **Press `Enter` (`[1]`)** in Terminal:
   - Type your Mac login password blindly at `Password:` (**nothing prints on screen**, that is standard macOS security) and press `Enter`.
   - When macOS asks *"Terminal wants access to control Finder"*, click **Allow** so your App Store saves are safely copied without overwriting anything.
   - Wait for `PATCH COMPLETE (v1.4.0)` and launch the game as usual.

---

## 🖱️ Contrôles Trackpad MacBook / MacBook Trackpad Controls

| Geste / Gesture | 🇫🇷 Action en jeu | 🇬🇧 In-Game Action |
| :--- | :--- | :--- |
| **Pincement à 2 doigts** / *2-finger pinch* | Zoom avant / arrière (`+` / `-`) | Zoom in / out (`+` / `-`) |
| **Balayage horizontal à 2 doigts** *(ou rotation 2 doigts)* / *2-finger horizontal swipe (or twist)* | Rotation fluide de la caméra (`,` / `.`, compatible claviers **AZERTY & QWERTY**) | Smooth camera rotation (`,` / `.`, **AZERTY & QWERTY** layouts supported) |
| **`Control (^)` + clic-glissé** / *`Control (^)` + click & drag* | Orbite 3D libre & inclinaison verticale (émulation clic molette) | Free 3D camera orbit & pitch (middle-mouse drag emulation) |
| **`Option (⌥)` + glisser** / *`Option (⌥)` + drag* | Panoramique natif (déplacement sur la carte, curseur 4 flèches) | Native camera pan (hand-drag across the map) |

---

## 🧰 Outils inclus / Included Utilities

En plus de `patch_sims2.command`, deux scripts compagnons sont inclus dans l'archive :

| Script | 🇫🇷 Utilité pour le joueur | 🇬🇧 What It Does |
| :--- | :--- | :--- |
| **`clean_sims2_cache.command`** | Menu interactif sans mot de passe pour les options 1 & 2 :<br>• **`[1]`** Nettoie les caches corrompus (`Groups.cache`, `Accessory.cache`, `cAstGroupCache.package`) sans toucher à vos parties.<br>• **`[2]`** Réinitialise la résolution au lancement dans `userProps.xml` (mode 60 Hz sûr, sauvegarde `userProps.xml.backup` conservée).<br>• **`[3]`** Vérifie vos Mods/CC (`.package`, `.zip`/`.rar`/`.7z` oubliés) et la limite système `10 240` fichiers ouverts. | Interactive maintenance menu (no password for `[1]` & `[2]`):<br>• **`[1]`** Purges corrupted caches without touching your saves.<br>• **`[2]`** Resets launch resolution in `userProps.xml` to a safe 60 Hz mode (preserves `userProps.xml.backup`).<br>• **`[3]`** Checks Mods/CC (`.package`, leftover `.zip`/`.rar`/`.7z` archives) and the `10,240` open-file limit. |
| **`restore_sims2.command`** | Désinstallation complète et propre : restaure l'exécutable original vérifié (`Sims2XP_Exe.backup`) et `Graphics Rules.sgr.backup`, retire le module trackpad, re-signe l'app et nettoie le `LaunchDaemon` si le patch l'avait ajouté. *(Pour retrouver aussi la signature Mac App Store officielle, supprimez puis retéléchargez l'app depuis l'App Store ; vos sauvegardes restent intactes.)* | Clean full uninstall: restores the verified original binary (`Sims2XP_Exe.backup`) and `Graphics Rules.sgr.backup`, removes the trackpad module, re-signs the app, and removes the managed `LaunchDaemon` if installed by this patch. *(To also restore the Apple App Store signature/Sandbox, delete and re-download the app from the Mac App Store; saves are kept.)* |

> [!NOTE]
> **Résolution en jeu (`v1.4.0`) :** La résolution et le plein écran sous l'encoche sont configurés **au lancement du jeu** (via `userProps.xml` / `Graphics Rules.sgr` et l'option `[2]` de `clean_sims2_cache.command`). **Il n'y a pas de changement de résolution à chaud en pleine partie dans la `v1.4.0`.**  
> **In-game resolution (`v1.4.0`):** Resolution and under-notch fullscreen are applied **at game launch** (via `userProps.xml` / `Graphics Rules.sgr` and `clean_sims2_cache.command` option `[2]`). **There is no in-game hot-swap resolution switching in `v1.4.0`.**

---

## 🛟 Support & Dépannage rapide / Support & Quick Troubleshooting

### Outil intégré : `[2] Diagnostic & Support GitHub`
Par défaut, la `v1.4.0` est **100 % silencieuse** : aucun fichier de log n'est écrit lors d'une partie normale.
* Si un plantage survient, un fichier `crash_report.log` est automatiquement créé dans `~/Library/Logs/Sims2-Crash-Patch/`.
* En cas de souci, lancez **`patch_sims2.command` → `[2] Diagnostic & Support GitHub`** :
  * Activez/désactivez le mode debug à la demande (`debug_boot.log`).
  * Générez `github_support_report.md` : **votre nom d'utilisateur macOS est anonymisé avec `~`**, les infos utiles (`crash_report.log`, écran, `userProps.xml`) sont rassemblées, et le rapport est **copié automatiquement dans votre presse-papier** prêt à coller dans une [issue GitHub](https://github.com/Justinbdna/sims2-crash-patch/issues/new/choose).

*By default, `v1.4.0` writes zero log files during normal gameplay. Only a crash triggers `crash_report.log`. Run `patch_sims2.command` → `[2] Diagnostic & Support GitHub` to toggle optional `debug_boot.log` or generate an anonymized (`~`) `github_support_report.md` copied straight to your clipboard for GitHub Issues.*

### Cas fréquents / Common Cases
* **Gatekeeper bloque le script :** double-cliquez sur `patch_sims2.command` → si macOS affiche *« bloqué pour protéger votre Mac »*, cliquez sur **Terminé**, ouvrez **Réglages Système → Confidentialité et sécurité**, descendez tout en bas et cliquez sur **Ouvrir quand même**.
* **Mot de passe Terminal invisible :** C'est normal sous macOS (aucun `*` affiché). Vérifiez *Verrouillage Majuscule* et utilisez le mot de passe d'ouverture de session du Mac (avec un compte Administrateur).
* **Sauvegardes / Finder (`-1743` ou `-5000`) :** Vos données actives sont dans `~/Library/Application Support/Aspyr/The Sims 2/`. Si vos anciens quartiers n'apparaissent pas, vérifiez `~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup ...)` et fusionnez `Neighborhoods/` + `Downloads/` (jeu fermé). En cas d'erreur `-1743`, autorisez **Terminal → Finder** dans **Réglages Système → Confidentialité et sécurité → Automatisation**.
* **Crash après débranchement d'écran externe :** Lancez `clean_sims2_cache.command` → **`[2]`** pour réinitialiser `userProps.xml` sur votre écran actuel en 60 Hz.
* **Mods/CC manquants :** Décompressez bien vos `.zip`/`.rar`/`.7z` en `.package` dans `~/Library/Application Support/Aspyr/The Sims 2/Downloads/` et lancez `clean_sims2_cache.command` → **`[1]`** puis **`[3]`**.

---

<details>
<summary>🔧 <strong>Détails techniques (binaire, CoreGraphics, encoche, Sandbox &amp; signature) / Technical Details</strong></summary>

### 1. Patch binaire `Sims2XP_Exe` (`x86_64` via Rosetta 2)
Toutes les modifications vérifient d'abord les empreintes d'origine et créent atomiquement `Sims2XP_Exe.backup` avant toute écriture :
* **`0xfe6dc` (`FUN_1000fe510`) :** Neutralise `_CGDisplayModeGetRefreshRate` en forçant `60` (`0x3c`) dans `R15D` (`f20f1045d0f2440f2cf84889df` → `41bf3c000000909090904889df`).
* **`0xfe741` (`FUN_1000fe510`) :** Verrouille la branche secondaire `_CVDisplayLink` via `NOP` sur `cmovnel %eax, %r15d` (`41bf3c000000440f45f8c70300000000` → `41bf3c00000090909090c70300000000`).
* **`0x5e610` :** Lève le filtre de modes ASL (`39f17fd04139f87fcb` → `39f190904139f89090`) afin que toutes les résolutions calibrées `≤ 2560×1600` restent sélectionnables.
* **`0x1303243` :** Remplace le validateur plein écran par un plafond propre `width ≤ 2560 && height ≤ 1600`.
* **`0xa7619` :** Active le remplissage plein écran bord à bord sous Space sans bandes noires latérales ni décalage FBO (`e86277fbff84c074108b43183b45f0` → `e86277fbff84c0eb108b43183b45f0`).

### 2. Hooks Cocoa / CoreGraphics (`trackpad_mod/libsims2_trackpad.dylib`)
Compilé en `x86_64` et injecté dans `Sims2XP_Exe` via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`) :
* **`hook_CGDisplayCopyAllDisplayModes` :** Intercepte `_CGDisplayCopyAllDisplayModes` via `__DATA,__la_symbol_ptr` pour filtrer et exposer uniquement de vrais modes matériels macOS à 60 Hz (aucun mode synthétique).
* **`NSScreen.visibleFrame` :** Détecte dynamiquement la zone utilisable sous l'encoche au runtime (`clamp_fullscreen_window_to_visible_frame`) pour les MacBook 13"/14"/16" et écrans externes.
* **Trackpad & `Command+Tab` :** `SDL_VIDEO_MAC_FULLSCREEN_SPACES=1`, `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`, neutralisation des fenêtres `SDLWindow` orphelines, pincement non inversé, rotation Carbon `UCKeyTranslate` (AZERTY/QWERTY), et émulation `SDL_BUTTON_MIDDLE` sur `Control (^)` + clic-glissé tout en laissant `Option (⌥)` natif intact.
* **Logs & Crash handler :** Zéro écriture disque en session normale ; gestionnaire async-signal-safe (`SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`, `SIGFPE`, `std::set_terminate`) écrivant `crash_report.log` uniquement en cas d'incident.

### 3. Migration Sandbox, `Graphics Rules.sgr` & Signature `codesign --strict`
* **Migration Sandbox sans écrasement :** La re-signature locale retire les entitlements App Store Sandbox ; `patch_sims2.command` copie via Automation Finder les sauvegardes de `~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/` vers `~/Library/Application Support/Aspyr/The Sims 2/` (ou vers `The Sims 2 (Sandbox Backup YYYY-MM-DD)` si un dossier actif existe déjà).
* **`Graphics Rules.sgr` :** Sauvegarde `Graphics Rules.sgr.backup`, fixe `maxResWidth 2560` / `maxResHeight 1600`, configure `$High` sur la résolution native détectée et passe `textureMemory` à `1024` Mo.
* **Intégrité macOS :** Nettoyage des attributs AppleDouble/ResourceFork superflus, signature ad-hoc `codesign --force --deep --sign -` et validation stricte `codesign --verify --deep --strict`.

> *Initiative communautaire de préservation logicielle (Directive européenne 2009/24/CE, article 5(1)). Aucun binaire propriétaire distribué ni DRM contourné.*

</details>
