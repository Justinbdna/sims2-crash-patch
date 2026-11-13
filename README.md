# 💎 Sims 2 Crash Patch — ProMotion 120 Hz & Stability Fix (`v1.3.1`)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black.svg?style=flat&logo=apple)](https://apple.com)
[![Tested on](https://img.shields.io/badge/Tested%20on-M1%20Pro%20%7C%20120Hz%20%7C%20macOS%2027.0-success)](https://apple.com)
[![Version](https://img.shields.io/badge/Release-v1.3.1-blue.svg)](https://github.com/Justinbdna/sims2-crash-patch/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **FR :** Correctif 60 FPS au démarrage, migration de sauvegardes sans écrasement, protection d'affichage (`userProps.xml`), diagnostic Mods/CC (`maxfiles`) et menu de maintenance pour *The Sims 2: Super Collection* (Mac App Store, Aspyr) sur Mac Apple Silicon ProMotion 120 Hz.  
> **EN:** Startup 60 FPS fix, zero-overwrite save migration, `userProps.xml` display protection, Mods/CC & `maxfiles` diagnostics, and interactive maintenance menu for *The Sims 2: Super Collection* (Mac App Store edition) on Apple Silicon Macs with 120 Hz ProMotion displays.

* 🇫🇷 **[Documentation Française & Guide Utilisateur](#-documentation-française--guide-utilisateur)**
* 🌍 **[English Documentation & User Guide](#-english-documentation--user-guide)**

---

# 🇫🇷 Documentation Française & Guide Utilisateur

## 1. Pourquoi le jeu plante-t-il ?

1. **Crash au démarrage (~2 secondes après le lancement sur écran ProMotion 120 Hz) :**
   Le moteur `Sims2XP_Exe` (binaire `x86_64` exécuté via Rosetta 2) interroge macOS pour connaître le taux de rafraîchissement de l'écran (`_CGDisplayModeGetRefreshRate`). Sur une dalle ProMotion, macOS renvoie `120.0 Hz`. Le validateur interne (`0x101769030`) rejette toutes les résolutions à 120 Hz, ne trouve aucun mode d'affichage valide et lève une exception C++ non interceptée (`__cxa_throw` à `0x10081cfca`), provoquant la fermeture immédiate (`SIGSEGV`).
2. **Crash après débranchement d'écran externe ou mauvais `userProps.xml` (`v1.3.0`) :**
   Si `Config/userProps.xml` mémorise une résolution externe absente, un rafraîchissement != 60 Hz ou une valeur corrompue, le jeu peut également refuser de démarrer.
3. **Crash au chargement d'un quartier (caches corrompus) ou saturation Mods/CC :**
   Les fermetures brutales corrompent `Groups.cache`, `Accessory.cache` et `cAstGroupCache.package`. De plus, `Sims2XP_Exe` relève au lancement sa limite de fichiers ouverts à `10 240` (`setrlimit(RLIMIT_NOFILE, min(rlim_max, 10240))`) : une archive `.zip`/`.rar` oubliée ou une limite système basse peut perturber le jeu.

### Ce que fait cette suite d'outils (`v1.3.1`)
* ✅ **Votre écran Mac reste à 120 Hz ProMotion** tout en verrouillant le jeu sur **60 Hz** via un patch binaire atomique (`Sims2XP_Exe.backup` vérifié intègre avant modification).
* ✅ **Zéro dépendance externe :** Utilise exclusivement `/usr/bin/perl`, `/usr/bin/codesign`, `/usr/sbin/dseditgroup` et `/usr/bin/osascript` (AppleScript + JXA) natifs — ne déclenche jamais l'installation Xcode de 1 Go (`libxcselect`).
* ✅ **Migration des sauvegardes garantie sans écrasement :** Copie vos sauvegardes Sandbox via la **permission Automatisation Finder** vers `~/Library/Application Support/Aspyr/The Sims 2/` (ou vers `The Sims 2 (Sandbox Backup YYYY-MM-DD)` si des données actives existent déjà).
* ✅ **Protection automatique `userProps.xml` (`v1.3.0`) :** Inspecte `activeDeviceDisplayMode`, crée une sauvegarde de retour (`Config/userProps.xml.backup`) avant toute retouche, et ne corrige que les modes invalides, absents de CoreGraphics/NSScreen ou ≠ 60 Hz / 32 bpp.
* ✅ **Règles graphiques Retina / Apple Silicon (`Graphics Rules.sgr`) :** Sauvegarde l'original (`Graphics Rules.sgr.backup`), débloque les résolutions jusqu'à `5120x3200`, passe le profil par défaut en `$High` (effets, éclairage, ombres, matériaux) et relève le fallback VRAM (`textureMemory`) à `1024 Mo`.
* ✅ **Module Trackpad natif MacBook (`libsims2_trackpad.dylib`) :** Auto-chargé dans `Sims2XP_Exe` via `LC_LOAD_WEAK_DYLIB` sans Xcode : **`Option (⌥)` + clic-glissé** = orbite 3D libre + inclinaison verticale (pitch), **pincement à 2 doigts** = zoom `+/-`, **swipe horizontal ou rotation à 2 doigts** = rotation caméra `,`/`.`.
* ✅ **Diagnostic Mods/CC & `maxfiles` (`v1.3.0`) :** Compte vos `.package` dans `Downloads/`, alerte si des `.zip`/`.rar`/`.7z` s'y trouvent ou si vous approchez du plafond de `10 240`, et propose `[o/N]` l'installation d'un `LaunchDaemon` géré uniquement si `launchctl limit maxfiles` hard < `10 240`.
* ✅ **Utilitaire de maintenance à menu interactif (`clean_sims2_cache.command` `v1.3.0`) :** `[1]` Purger les caches *(Entrée par défaut)*, `[2]` Réinitialiser l'affichage `userProps.xml`, `[3]` Diagnostiquer les Mods & `maxfiles`, `[4]` Quitter.

---

## 2. Les 3 Utilitaires Inclus (Scripts `.command`)

| Script | Rôle | Mot de passe Admin (`sudo`) ? |
| :--- | :--- | :--- |
| **`patch_sims2.command`** | Installateur principal : vérifie les droits Admin, localise le jeu (`/Applications` ou `~/Applications`), vérifie et sauvegarde le binaire intègre, applique le double patch 60 Hz, patch `Graphics Rules.sgr` (`5120x3200`, `$High`, `1024 Mo`, `.backup`), installe et injecte `libsims2_trackpad.dylib` (`LC_LOAD_WEAK_DYLIB`), re-signe `--strict`, migre les sauvegardes sans écrasement, purge les caches, protège `userProps.xml` et diagnostique CC/`maxfiles`. | **Oui** (si l'app est dans `/Applications`, ou pour installer le `LaunchDaemon` optionnel) |
| **`clean_sims2_cache.command`** | Outil de maintenance interactif `[1/2/3/4]` : `[1]` Purge des caches (Actif + Sandbox), `[2]` Reset résolution `userProps.xml` + `.backup`, `[3]` Diagnostic Mods/CC & `maxfiles`, `[4]` Quitter. | **Non** (sauf option `[3]` si vous acceptez d'installer `limit.maxfiles.plist`) |
| **`restore_sims2.command`** | Désinstallateur officiel : vérifie l'intégrité de `Sims2XP_Exe.backup`, restaure atomiquement le binaire d'origine et `Graphics Rules.sgr.backup`, retire `libsims2_trackpad.dylib`, re-signe `--strict` et supprime `/Library/LaunchDaemons/limit.maxfiles.plist` **uniquement** s'il porte le marqueur géré par ce patch. | **Oui** (si app dans `/Applications` ou `LaunchDaemon` géré présent) |

---

## 3. Guide d'Installation Pas à Pas (Débutant) & Pop-ups macOS

> [!IMPORTANT]
> **À savoir AVANT de cliquer (transparence complète) :**
> 1. **Blocage Gatekeeper au 1er clic :** Comme ce correctif communautaire n'est pas notarié par un certificat Apple payant, macOS bloquera le script au premier double-clic (voir l'étape 4 ci-dessous).
> 2. **Le mot de passe dans le Terminal est 100 % INVISIBLE :** Quand le Terminal demande `Password:`, tapez votre mot de passe session Mac puis appuyez sur **Entrée**. **Aucun caractère (`*`, point ou espace) ne s'affichera pendant la frappe** : ce n'est pas un bug et votre clavier n'est pas bloqué, c'est la sécurité normale de macOS.
> 3. **Pop-up « Terminal souhaite contrôler Finder » :** Cliquez impérativement sur **Autoriser** pour copier vos sauvegardes hors du conteneur protégé du Mac App Store.

1. Téléchargez **`sims2-crash-patch-v1.3.1.zip`** depuis la page [Releases](https://github.com/Justinbdna/sims2-crash-patch/releases) et **décompressez-le** complètement (par exemple dans *Téléchargements* ou sur le *Bureau*).
2. **Fermez complètement *Les Sims 2*** (`Cmd + Q`, vérifiez que le point sous l'icône du Dock a disparu) et vérifiez que `The Sims 2.app` est dans `/Applications` (ou `~/Applications`).
3. Double-cliquez sur **`patch_sims2.command`**.
4. **Si macOS bloque le script (Gatekeeper sur macOS 15+ / Sequoia / macOS 27) :**
   - Cliquez sur **Terminé** (ou **OK**) sur la fenêtre d'alerte.
   - Ouvrez immédiatement **Réglages Système ➔ Confidentialité et sécurité**.
   - Faites défiler jusqu'à la section **Sécurité** et cliquez sur **« Ouvrir quand même »** à côté de `patch_sims2.command` (ce bouton reste visible environ 1 heure après l'essai).
   - Cliquez sur **« Ouvrir »** dans la fenêtre de confirmation, puis validez avec votre mot de passe Mac ou Touch ID.
5. Dans la fenêtre du Terminal :
   - Lisez l'encadré `CE QUI VA SE PASSER` qui vous rappelle que la frappe du mot de passe est invisible.
   - Tapez votre mot de passe administrateur Mac à l'aveugle puis appuyez sur **Entrée**.
6. Lorsque macOS affiche **« Terminal souhaite contrôler Finder »**, cliquez sur **Autoriser**.
7. Si le script détecte une limite `hard maxfiles < 10240`, il propose `[o/N]` d'installer `/Library/LaunchDaemons/limit.maxfiles.plist` (`o` pour installer, ou `Entrée` pour ignorer).
8. Dès que `INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.3.1) !` apparaît (sauf si un message jaune vous demande de finir l'autorisation Finder d'abord !), lancez *Les Sims 2* normalement depuis le Launchpad ou `/Applications` !

---

## 4. Sortie du Sandbox, Sauvegardes & Mods (`Downloads`)

* **Nouvel emplacement actif des sauvegardes et des mods :**
  ```text
  ~/Library/Application Support/Aspyr/The Sims 2/
  ```
* **Vos Mods / CC :** Placez vos fichiers `.package` décompressés directement dans `~/Library/Application Support/Aspyr/The Sims 2/Downloads/`.
* **Sauvegarde de retour (`userProps.xml.backup`) :** Avant toute correction automatique ou via l'option `[2]` de `clean_sims2_cache.command`, votre fichier original est sauvegardé dans `~/Library/Application Support/Aspyr/The Sims 2/Config/userProps.xml.backup`.
* **Migration sans écrasement :**
  - Si `~/Library/Application Support/Aspyr/The Sims 2/` n'existe pas encore, vos données Sandbox y sont dupliquées directement.
  - S'il existe déjà, rien n'est écrasé : vos anciennes données Sandbox sont dupliquées dans `~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/`.

---

## 5. En cas d'erreur : Cas Pratiques & Dépannage

| Cas pratique / Symptôme | Cause & Solution exacte |
| :--- | :--- |
| **Cas 1 : « Apple ne peut pas vérifier / Logiciel malveillant » au double-clic** | Comportement normal Gatekeeper sur macOS 15+. Cliquez sur **Terminé** ➔ **Réglages Système** ➔ **Confidentialité et sécurité** ➔ **Ouvrir quand même** ➔ **Ouvrir**. Répétez une seule fois si vous lancez ensuite `clean_sims2_cache.command` ou `restore_sims2.command`. |
| **Cas 2 : Rien ne s'écrit quand je tape le mot de passe dans Terminal / `Sorry, try again`** | La frappe invisible (sans `*`) est voulue par macOS. Vérifiez que **Verrouillage Majuscule** est désactivé et que votre clavier est sur la bonne disposition (FR/EN). Saisissez le mot de passe d'ouverture de session du Mac + `Entrée` (Touch ID ne remplace pas `sudo` ici). |
| **Cas 3 : « Compte non-Administrateur détecté » / `not in the sudoers file`** | Votre session est un compte **Standard**. Connectez-vous à une session Administrateur du Mac (ou cochez *Autoriser à administrer cet ordinateur* dans *Réglages Système ➔ Utilisateurs et groupes*), puis relancez `patch_sims2.command`. |
| **Cas 4 : Erreur `-1743` (Automatisation) ou `-5000` (`autorisations requises` sur conteneur Sandbox)** | Pour `-1743` : activez **Réglages Système ➔ Confidentialité et sécurité ➔ Automatisation ➔ Terminal ➔ Finder** et relancez. Pour `-5000` après avoir cliqué *Autoriser* : macOS protège le conteneur App Store contre la copie scriptée ; ouvrez Finder (`Cmd+Maj+G`) dans `~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/` et copiez `Neighborhoods`/`Downloads` vers `~/Library/Application Support/Aspyr/The Sims 2/` (ou accordez *Accès complet au disque* à Terminal). |
| **Cas 4B : Partager un journal de diagnostic (`latest.log`)** | Chaque exécution enregistre un journal léger (0 % CPU en arrière-plan, aucun mot de passe) dans `~/Library/Logs/Sims2-Crash-Patch/latest.log` (`previous.log` pour le précédent). |
| **Cas 5 : Mes anciens quartiers n'apparaissent pas en jeu** | Ouvrez `~/Library/Application Support/Aspyr/` dans le Finder (`Cmd+Maj+G`). Si un dossier `The Sims 2 (Sandbox Backup ...)` s'y trouve, c'est que vous aviez déjà lancé le jeu hors Sandbox. Jeu fermé, fusionnez `Neighborhoods/` et `Downloads/` depuis ce backup vers `The Sims 2/`. |
| **Cas 6 : Crash au lancement après débranchement d'écran externe ou changement vidéo** | Double-cliquez sur `clean_sims2_cache.command` et choisissez **`[2]`** : réinitialise la résolution vers le mode actuel à 60 Hz tout en conservant `Config/userProps.xml.backup`. |
| **Cas 7 : Crash chargement quartier ou Mods absents** | Lancez `clean_sims2_cache.command` : choisissez **`[1]`** (purge les caches sans toucher aux parties) puis **`[3]`** (détecte les archives `.zip`/`.rar`/`.7z` ignorées par le jeu dans `Downloads/` et contrôle la proximité de la limite `10 240` fichiers ouverts). |
| **Cas 8 : `Permission denied` ou ouverture du script dans TextEdit** | Assurez-vous d'avoir extrait le `.zip` avec l'*Utilitaire d'archive* macOS (clic droit ➔ Ouvrir). Si un décompresseur tiers a retiré les droits exécutables, tapez dans Terminal `chmod +x ` (espace à la fin), glissez le `.command` dedans et faites `Entrée`. |
| **Cas 9 : Tout annuler / Revenir à la version Mac App Store** | Double-cliquez sur `restore_sims2.command` (restaure `Sims2XP_Exe.backup`, re-signe l'app et nettoie `limit.maxfiles.plist` s'il a été créé par le patch). Pour retrouver la signature Apple/Aspyr officielle et le Sandbox App Store : supprimez `The Sims 2.app` et retéléchargez-le gratuitement depuis le Mac App Store (vos sauvegardes dans `Application Support` restent intactes, mais le jeu re-sandboxé relit `~/Library/Containers/com.aspyr.sims2.appstore/`). |

---

## 6. Précisions Techniques & Mention Légale

* **Environnement validé pour le patch binaire :** *MacBook Pro Apple Silicon M1 Pro, écran ProMotion 120 Hz, macOS 27.0 (`Sims2XP_Exe` `x86_64`, 36 119 728 octets).*
* **Double patch binaire (`FUN_1000fe510`) :**
  - **Patch 1 (`0xfe6dc`) :** Neutralise `_CGDisplayModeGetRefreshRate` en forçant `60` (`0x3c`) dans `R15D` (`f20f1045d0f2440f2cf84889df` ➔ `41bf3c000000909090904889df`).
  - **Patch 2 (`0xfe741`) :** Verrouille la branche secondaire `_CVDisplayLink` en remplaçant `cmovnel %eax, %r15d` par 4 `NOP` (`41bf3c000000440f45f8c70300000000` ➔ `41bf3c00000090909090c70300000000`).
* **Diagnostic système `maxfiles` (`Sims2XP_Exe`):** `0x1000b2920`–`0x1000b2970` appelle `getrlimit(RLIMIT_NOFILE)` puis `setrlimit(RLIMIT_NOFILE, min(rlim_max, 0x2800 = 10240))`.
* **Optimisation `Graphics Rules.sgr` :** Sauvegarde `Graphics Rules.sgr.backup`, relève `textureMemory` de `32` à `1024` Mo, débloque `maxResWidth`/`maxResHeight` jusqu'à `5120x3200`, et bascule `EffectsQuality`, `LightingQuality`, `Shadows` et `MaterialDetail` sur `$High`.
* **Module Trackpad Cocoa natif (`trackpad_mod/libsims2_trackpad.dylib`) :** Injecté via `LC_LOAD_WEAK_DYLIB` (`@executable_path/libsims2_trackpad.dylib`) sans Xcode ni CLT :
  - `Option (⌥)` + clic-glissé : émulation `SDL_BUTTON_MIDDLE` pour orbite 3D libre et inclinaison verticale (pitch).
  - Pincement à 2 doigts (`NSEventTypeMagnify`) : zoom `+/-`.
  - Swipe horizontal ou rotation à 2 doigts : rotation caméra `,`/`.`.

> *Ce projet est une initiative communautaire de préservation logicielle (article 5(1) de la directive européenne 2009/24/CE). Aucun binaire propriétaire n'est distribué ni aucun DRM contourné.*

---
---

# 🌍 English Documentation & User Guide

## 1. Why Does the Game Crash?

1. **Startup Crash (~2 seconds after launch on 120 Hz ProMotion displays):**
   The legacy `Sims2XP_Exe` engine (`x86_64` under Rosetta 2) queries `_CGDisplayModeGetRefreshRate`. On ProMotion displays, macOS returns `120.0 Hz`. The engine's validator (`0x101769030`) rejects 120 Hz modes, finds zero valid modes, throws an unhandled C++ exception (`__cxa_throw` at `0x10081cfca`), and crashes (`SIGSEGV`).
2. **External Monitor / Invalid `userProps.xml` Crash (`v1.3.0`):**
   An unplugged external screen resolution, non-60 Hz refresh rate, or malformed `activeDeviceDisplayMode` string in `Config/userProps.xml` can prevent launch.
3. **Neighborhood Crash & CC Open-File Limit:**
   Sudden crashes corrupt `Groups.cache`, `Accessory.cache`, and `cAstGroupCache.package`. Meanwhile, `Sims2XP_Exe` sets `RLIMIT_NOFILE` to `min(rlim_max, 10240)` at startup: excessive `.package` counts, unextracted `.zip`/`.rar` files in `Downloads/`, or a restrictive system hard `maxfiles` limit (< 10240) can affect stability.

## 2. Included Utilities (`.command` Scripts)

| Script | Role | Requires Admin (`sudo`)? |
| :--- | :--- | :--- |
| **`patch_sims2.command`** | Main installer: Admin check, `/Applications` + `~/Applications` support, verified backup + atomic 60 Hz patch, `Graphics Rules.sgr` upgrade (`5120x3200`, `$High`, `1024 MB` VRAM fallback, `.backup`), `libsims2_trackpad.dylib` injection (`LC_LOAD_WEAK_DYLIB` without Xcode), strict ad-hoc signing, zero-overwrite save migration, dual cache purge, `userProps.xml` protection (`.backup`), and CC/`maxfiles` check. | **Yes** (for `/Applications` or optional LaunchDaemon) |
| **`clean_sims2_cache.command`** | Interactive menu `[1/2/3/4]`: `[1]` Clean caches *(Default on Enter)*, `[2]` Reset `userProps.xml` resolution (60 Hz + `.backup`), `[3]` Check Mods/CC (`.package`/`.zip`) & `maxfiles`, `[4]` Quit. | **No** (unless opting `[y]` to install `limit.maxfiles.plist` in `[3]`) |
| **`restore_sims2.command`** | Official uninstaller: verifies `Sims2XP_Exe.backup`, atomically restores original binary and `Graphics Rules.sgr.backup`, removes `libsims2_trackpad.dylib`, re-signs strictly, and cleans `/Library/LaunchDaemons/limit.maxfiles.plist` **only** if tagged as managed by this patch. | **Yes** (when `/Applications` or managed plist exists) |

### Native MacBook Trackpad Controls (`libsims2_trackpad.dylib`)
* **Option (`⌥`) + Click & Drag:** Free 3D camera orbit & vertical pitch (emulates middle mouse drag).
* **Two-Finger Pinch:** Zoom in/out (`+`/`-`).
* **Two-Finger Horizontal Swipe or Rotate:** Smooth camera rotation (`,`/`.`).
* **Retina & High Graphics (`Graphics Rules.sgr`):** Unlocks resolutions up to `5120x3200`, sets `$High` shadows/lighting/effects/material defaults, raises `textureMemory` fallback to `1024` MB, and preserves `Graphics Rules.sgr.backup`.

## 3. Step-by-Step Installation & Beginner Tips (`v1.3.1`)

> [!IMPORTANT]
> **Upfront expectations on macOS:**
> * **Gatekeeper on first double-click:** macOS blocks unsigned `.command` scripts on first launch — follow Step 4 below once.
> * **Terminal password typing is INVISIBLE:** When Terminal prompts `Password:`, type your Mac login password blindly and press **Enter**. **Zero characters (no `*`, no dots)** appear on screen — this is standard macOS security, not a bug.
> * **"Terminal wants access to control Finder":** Click **Allow** so your App Store Sandbox saves can be safely copied.

1. Download **`sims2-crash-patch-v1.3.1.zip`** from [Releases](https://github.com/Justinbdna/sims2-crash-patch/releases) and fully extract it (e.g. into Downloads or Desktop).
2. Quit *The Sims 2* completely (`Cmd+Q`) and ensure `The Sims 2.app` is in `/Applications` (or `~/Applications`).
3. Double-click **`patch_sims2.command`**.
4. **If blocked by Gatekeeper (macOS 15+ / Sequoia / macOS 27):**
   - Click **Done** (or **OK**), open **System Settings ➔ Privacy & Security**, scroll to **Security**, click **"Open Anyway"** next to `patch_sims2.command` (~1h window), then click **Open** and authenticate.
5. Read the on-screen pre-`sudo` box, type your Mac Admin password blindly (nothing prints while typing!), and press **Enter**.
6. Click **Allow** when macOS asks Terminal to control **Finder**.
7. If `hard maxfiles < 10240` is detected, optionally enter `y` to install the managed `/Library/LaunchDaemons/limit.maxfiles.plist` (or press Enter for No).
8. Once `INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.3.1) !` appears (if a yellow Finder warning appears instead, follow it *before* launching!), launch *The Sims 2* from Launchpad or `/Applications`!

## 4. Practical Troubleshooting Cases

| Case | Cause & Fix |
| :--- | :--- |
| **1. Gatekeeper blocks first launch** | Click **Done** ➔ **System Settings ➔ Privacy & Security ➔ Open Anyway ➔ Open**. Repeat once for other first-run `.command` tools if needed. |
| **2. Nothing prints while typing password / `Sorry, try again`** | Hidden input (no `*`) is normal macOS security. Check Caps Lock and keyboard layout; enter your Mac session password (not Apple ID unless identical) + **Enter**. |
| **3. Non-Administrator account detected** | Log into an Administrator account on the Mac (or enable *Allow user to administer this computer* in *System Settings ➔ Users & Groups*) and re-run. |
| **4. Finder Automation (`-1743`) or Container permissions (`-5000`)** | For `-1743`: enable **System Settings ➔ Privacy & Security ➔ Automation ➔ Terminal ➔ Finder** and re-run. For `-5000` after clicking *Allow*: macOS blocks scripted container copies; open Finder (`Cmd+Shift+G`) at `~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/` and copy `Neighborhoods`/`Downloads` to `~/Library/Application Support/Aspyr/The Sims 2/` (or grant *Full Disk Access* to Terminal). |
| **4B. Diagnostic Log (`latest.log`)** | Every script run writes a zero-overhead plain-text diagnostic log (never storing passwords) to `~/Library/Logs/Sims2-Crash-Patch/latest.log`. |
| **5. Old saves appear missing (`Sandbox Backup`)** | Check `~/Library/Application Support/Aspyr/` for `The Sims 2 (Sandbox Backup ...)`. With the game closed, merge `Neighborhoods/` and `Downloads/` into `~/Library/Application Support/Aspyr/The Sims 2/`. |
| **6. Crash after unplugging external monitor / bad video mode** | Run `clean_sims2_cache.command` ➔ option **`[2]`** to reset `userProps.xml` to your current logical display at `60 Hz` (keeps `userProps.xml.backup`). |
| **7. CC missing or heavy-CC neighborhood crashes** | Run `clean_sims2_cache.command`: **`[1]`** cleans corrupted caches without touching saves/mods; **`[3]`** flags unextracted `.zip`/`.rar`/`.7z` files inside `Downloads/` and checks the `10,240` open-file limit. |
| **8. `Permission denied` or opens in TextEdit** | Extract via macOS Archive Utility first. If a third-party unarchiver stripped `+x`, run `chmod +x ` (trailing space) in Terminal, drop the `.command` file in, and press **Enter**. |
| **9. Restore original state** | Double-click `restore_sims2.command` (atomically restores verified `Sims2XP_Exe.backup`, re-signs `--strict`, and deletes `limit.maxfiles.plist` only if tagged `Managed by sims2-crash-patch`). Delete and re-download free from the Mac App Store to restore Apple Sandbox + official Aspyr signature. |

---

## 5. Legal Notice

> *This project is a community-driven software preservation initiative, conducted in the spirit of Article 5(1) of European Directive 2009/24/EC, permitting error correction by the lawful acquirer. Zero copyrighted game binaries are distributed and no DRM is bypassed.*
