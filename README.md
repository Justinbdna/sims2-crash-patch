# 💎 Sims 2 Crash Patch — ProMotion 120 Hz & Cache Fix (v1.2.1)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black.svg?style=flat&logo=apple)](https://apple.com)
[![Tested on](https://img.shields.io/badge/Tested%20on-M1%20Pro%20%7C%20120Hz%20%7C%20macOS%2027.0-success)](https://apple.com)
[![Version](https://img.shields.io/badge/Release-v1.2.1-blue.svg)](https://github.com/Justinbdna/sims2-crash-patch/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **EN:** Permanent 60 FPS startup fix, zero-overwrite save migration, and dual-location cache cleaner for *The Sims 2: Super Collection* (Mac App Store edition by Aspyr) on Apple Silicon Macs with 120 Hz ProMotion displays.  
> **FR :** Correctif permanent à 60 FPS au démarrage, migration sécurisée des sauvegardes (sans écrasement) et nettoyeur de caches pour *The Sims 2: Super Collection* (version Mac App Store par Aspyr) sur les Mac Apple Silicon équipés d'écrans ProMotion 120 Hz.

* 🌍 **[English Documentation](#-english-documentation)**
* 🇫🇷 **[Documentation Française](#-documentation-française)**

---

# 🌍 English Documentation

## 1. Why Does the Game Crash?

1. **Startup Crash (~2 seconds after launch on 120 Hz ProMotion displays):**
   The legacy `Sims2XP_Exe` engine (x86_64 running under Rosetta 2) queries macOS for the active display refresh rate (`_CGDisplayModeGetRefreshRate`). On ProMotion screens, macOS reports `120.0 Hz`. The engine's internal display mode validator (`0x101769030`) rejects all 120 Hz modes, finds zero valid resolutions, and throws an unhandled C++ exception (`__cxa_throw` at `0x10081cfca`), terminating the process immediately (`SIGSEGV`).
2. **Neighborhood Loading Crash (corrupted cache files):**
   Repeated startup crashes or abrupt exits corrupt the game's index files (`Groups.cache`, `Accessory.cache`, `cAstGroupCache.package`), causing a crash when loading 3D neighborhoods (Pleasantview, Strangetown, etc.).

### What This Toolkit Does (`v1.2.1`)
* ✅ **Keeps your Mac at 120 Hz ProMotion** while locking the game's internal refresh rate enumeration to **60 Hz** via an atomic binary update.
* ✅ **Zero external dependencies:** Uses macOS native `/usr/bin/perl`, `/usr/bin/codesign`, and `Finder` — does not trigger the 1 GB Xcode Command Line Developer Tools prompt (`libxcselect`).
* ✅ **Verified pristine backup (`Sims2XP_Exe.backup`):** Only creates or restores a backup after verifying that both original unpatched byte fingerprints are intact.
* ✅ **Safe, zero-overwrite save migration:** Uses macOS's standard **Finder Automation permission** (`Terminal ➔ Finder`) to copy your existing saves from the App Sandbox container into `~/Library/Application Support/Aspyr/The Sims 2/` (or into a timestamped `The Sims 2 (Sandbox Backup YYYY-MM-DD)` folder if an active folder already exists, never overwriting a single file).
* ✅ **Dual-location cache healing:** Purges corrupted cache files in both `Application Support` (`rm -f`) and the legacy Sandbox container (moved to the macOS Trash via Finder).

---

## 2. Included Utilities (`.command` Scripts)

| Script | Role | Requires Admin (`sudo`)? |
| :--- | :--- | :--- |
| **`patch_sims2.command`** | Main installer: verifies & backs up pristine binary, applies atomic dual 60 Hz patch, re-signs bundle, safely migrates saves, and purges corrupted caches. | **Yes** (only for `/Applications`) |
| **`clean_sims2_cache.command`** | Standalone rescue tool: purges `Groups.cache`, `Accessory.cache`, and `cAstGroupCache.package` in both data folders. | **No** |
| **`restore_sims2.command`** | Official uninstaller: verifies that `Sims2XP_Exe.backup` contains the untouched original bytes before atomically restoring it and re-signing locally. | **Yes** |

---

## 3. Step-by-Step Installation & Gatekeeper Guide (macOS 15+ / Sequoia / macOS 27)

1. Download **`sims2-crash-patch-v1.2.1.zip`** from the [Releases](https://github.com/Justinbdna/sims2-crash-patch/releases) page and extract it.
2. Ensure *The Sims 2* is closed and installed at `/Applications/The Sims 2.app`.
3. Double-click **`patch_sims2.command`**.
4. **If macOS blocks the script (Gatekeeper on macOS 15+ / Sequoia / macOS 27):**
   - Click **Done** (or **OK**) on the alert popup.
   - Immediately open **System Settings ➔ Privacy & Security**.
   - Scroll down to the **Security** section and click **"Open Anyway"** next to `patch_sims2.command` (this button appears for about 1 hour after a blocked launch attempt).
   - Click **"Open"** in the confirmation dialog and authenticate with your Mac password or Touch ID.
5. In the Terminal window that opens, enter your Mac administrator password when prompted and press **Enter** (characters are hidden for security).
6. When macOS asks to allow Terminal to control **Finder** (standard **Finder Automation permission**), click **Allow**.
7. Once `INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.2.1) !` appears, launch *The Sims 2* normally from Launchpad or `/Applications`!

---

## 4. Non-Sandbox Transition, Saves & Mods (`Downloads`)

### Why the Game Runs Outside the App Sandbox
When `codesign --force --deep --sign -` re-signs `/Applications/The Sims 2.app` after patching `Sims2XP_Exe`, it strips Aspyr's proprietary App Store entitlements (including `com.apple.security.app-sandbox`) from the launcher (`AppBundleExe`). Re-signing commercial Mac App Store entitlements ad-hoc without a paid Apple Developer certificate is unsupported and risks launch rejection by macOS security policy (`amfid` / Gatekeeper).

Consequently, macOS runs the patched game as a standard non-sandboxed macOS application:
* **Active Data & Mods Folder:**
  ```text
  ~/Library/Application Support/Aspyr/The Sims 2/
  ```
* **Major Benefit for Players & Modders:** You now have direct, easy access to `~/Library/Application Support/Aspyr/The Sims 2/Downloads/` to install Mods and Custom Content (CC) without navigating hidden `~/Library/Containers/` folders.
* **Zero-Overwrite Save Migration (`v1.2.1`):**
  - If `~/Library/Application Support/Aspyr/The Sims 2/` does **not** exist yet, `patch_sims2.command` duplicates your Sandbox container contents directly into `~/Library/Application Support/Aspyr/The Sims 2/`.
  - If `~/Library/Application Support/Aspyr/The Sims 2/` **already exists** (for example if you already launched the patched game), the script **never overwrites** your active folder (`with replacing` is strictly prohibited). Instead, it duplicates your legacy Sandbox saves into a dedicated safety folder:
    `~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/`
    and notifies you in Terminal so you can merge any older neighborhoods or mods at your leisure.

---

## 5. Technical Root Cause & Dual Binary Patch

* **Tested Environment:** *Tested and validated on MacBook Pro (Apple Silicon M1 Pro, 120 Hz ProMotion display, macOS 27.0).*
* **Target Binary:** `/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe` (`x86_64` Mach-O, 36,119,728 bytes).
* **Analysis Tools:** Ghidra 12.2 & Antigravity binary inspection.

### Dual Anchored Patch in `FUN_1000fe510`
1. **Patch 1 (`0xfe6dc` — Primary 60 Hz Lock):**
   Directly neutralizes the 120 Hz reading returned by `_CGDisplayModeGetRefreshRate` by assigning `60` (`0x3c`) to `R15D` instead of converting the `120.0` float in `XMM0`:
   - **Original (13 bytes):** `f2 0f 10 45 d0 f2 44 0f 2c f8 48 89 df` (`movsd -0x30(%rbp), %xmm0; cvttsd2si %xmm0, %r15d; movq %rbx, %rdi`)
   - **Patched (13 bytes):** `41 bf 3c 00 00 00 90 90 90 90 48 89 df` (`movl $0x3c, %r15d; nop; nop; nop; nop; movq %rbx, %rdi`)
2. **Patch 2 (`0xfe73b` / `0xfe741` — Fallback Safety Lock):**
   Secondary safety lock inside the `_CVDisplayLink` fallback path (`0x1000fe700`–`0x1000fe744`), replacing `cmovnel %eax, %r15d` (`44 0f 45 f8`) with 4 `NOP` bytes (`90 90 90 90`) so `R15D` remains locked at `60`:
   - **Original (16 bytes):** `41 bf 3c 00 00 00 44 0f 45 f8 c7 03 00 00 00 00`
   - **Patched (16 bytes):** `41 bf 3c 00 00 00 90 90 90 90 c7 03 00 00 00 00`

---

## 6. Restoring the Original Binary (`restore_sims2.command`)

Double-click **`restore_sims2.command`** at any time to verify the integrity of `Sims2XP_Exe.backup`, atomically restore the unpatched binary, and re-sign the bundle locally.

> **Important Note on App Store Reinstallation & Saves:**  
> To restore Aspyr's official commercial signature and re-enable Apple's initial App Sandbox isolation, delete the application and re-download it for free from the Mac App Store.  
> Your files in `~/Library/Application Support/Aspyr/The Sims 2/` are **never deleted**, but a reinstalled Mac App Store version (running inside the Sandbox) will read its data from the Sandbox container (`~/Library/Containers/com.aspyr.sims2.appstore/...`) again — so any progress saved outside the Sandbox would need to be copied back manually into the container (and on a 120 Hz display, the unpatched game will crash at launch unless the screen is lowered to 60 Hz).

---

## 7. Legal Notice

> *This project is a community-driven software preservation initiative, conducted in the spirit of Article 5(1) of European Directive 2009/24/EC, which permits the lawful acquirer of a computer program to correct errors so that it may be used in accordance with its intended purpose.*  
> This patch distributes zero copyrighted game binaries, does not bypass Apple FairPlay DRM or Mac App Store receipts, and requires a legitimately purchased copy of *The Sims 2: Super Collection*.

---
---

# 🇫🇷 Documentation Française

## 1. Pourquoi le jeu plante-t-il ?

1. **Crash au démarrage (~2 secondes après le lancement sur écran ProMotion 120 Hz) :**
   Le moteur `Sims2XP_Exe` (binaire `x86_64` exécuté via Rosetta 2) interroge macOS pour connaître le taux de rafraîchissement de l'écran (`_CGDisplayModeGetRefreshRate`). Sur une dalle ProMotion, macOS renvoie `120.0 Hz`. Le validateur interne du moteur (`0x101769030`) rejette toutes les résolutions à 120 Hz, ne trouve aucun mode d'affichage valide et lève une exception C++ non interceptée (`__cxa_throw` à `0x10081cfca`), provoquant la fermeture brutale du jeu (`SIGSEGV`).
2. **Crash au chargement d'un quartier (caches corrompus) :**
   Les fermetures brutales corrompent les fichiers d'indexation (`Groups.cache`, `Accessory.cache`, `cAstGroupCache.package`), bloquant l'ouverture des quartiers en 3D (Montsimpa, Zarbville, Florimont-la-Rivière, etc.).

### Ce que fait cette suite d'outils (`v1.2.1`)
* ✅ **Votre écran Mac reste à 120 Hz ProMotion** tout en verrouillant l'énumération interne du jeu sur **60 Hz** via une mise à jour binaire atomique.
* ✅ **Zéro dépendance externe :** Utilise exclusivement `/usr/bin/perl`, `/usr/bin/codesign` et le `Finder` natifs de macOS — ne dépend pas de `libxcselect` et ne déclenche pas le téléchargement de 1 Go des outils Xcode.
* ✅ **Sauvegarde binaire à intégrité vérifiée (`Sims2XP_Exe.backup`) :** Ne crée ou ne restaure la sauvegarde que si les deux empreintes d'octets d'origine non modifiées sont formellement reconnues.
* ✅ **Migration sécurisée sans aucun écrasement :** Utilise la **permission Automatisation Finder** standard de macOS (`Terminal ➔ Finder`) pour copier vos sauvegardes du conteneur Sandbox vers `~/Library/Application Support/Aspyr/The Sims 2/` (ou vers un sous-dossier horodaté `The Sims 2 (Sandbox Backup YYYY-MM-DD)` si un dossier actif existe déjà, sans jamais écraser le moindre fichier).
* ✅ **Double purge des caches :** Supprime les caches corrompus dans `Application Support` (`rm -f`) et déplace ceux de l'ancien conteneur Sandbox vers la **Corbeille** macOS via le Finder.

---

## 2. Les 3 Utilitaires Inclus (Scripts `.command`)

| Script | Rôle | Mot de passe Admin (`sudo`) ? |
| :--- | :--- | :--- |
| **`patch_sims2.command`** | Installateur principal : vérifie et sauvegarde le binaire intègre, applique le double patch 60 Hz de façon atomique, re-signe l'app, migre les sauvegardes sans écrasement et purge les caches. | **Oui** (uniquement pour `/Applications`) |
| **`clean_sims2_cache.command`** | Outil de secours autonome : purge `Groups.cache`, `Accessory.cache` et `cAstGroupCache.package` dans les deux dossiers. | **Non** |
| **`restore_sims2.command`** | Désinstallateur officiel : vérifie que `Sims2XP_Exe.backup` contient bien les octets d'origine avant de le restaurer de façon atomique et de re-signer l'application. | **Oui** |

---

## 3. Guide d'Installation & Procédure Gatekeeper (macOS 15+ / Sequoia / macOS 27)

1. Téléchargez l'archive **`sims2-crash-patch-v1.2.1.zip`** depuis la page [Releases](https://github.com/Justinbdna/sims2-crash-patch/releases) et décompressez-la.
2. Vérifiez que *Les Sims 2* est fermé et bien installé dans `/Applications/The Sims 2.app`.
3. Double-cliquez sur **`patch_sims2.command`**.
4. **En cas d'alerte de sécurité Gatekeeper au premier double-clic (macOS 15+ / Sequoia / macOS 27) :**
   - Cliquez sur **Terminé** (ou **OK**) sur la fenêtre d'alerte.
   - Ouvrez immédiatement **Réglages Système ➔ Confidentialité et sécurité**.
   - Faites défiler jusqu'à la section **Sécurité** et cliquez sur le bouton **« Ouvrir quand même »** à côté de `patch_sims2.command` (ce bouton s'affiche pendant environ 1 heure après une tentative d'ouverture bloquée).
   - Cliquez sur **« Ouvrir »** dans la boîte de dialogue de confirmation puis validez avec votre mot de passe Mac ou Touch ID.
5. Dans la fenêtre du Terminal qui s'ouvre, tapez votre mot de passe administrateur Mac lorsqu'il est demandé puis appuyez sur **Entrée** (aucun caractère ne s'affiche à l'écran, c'est normal).
6. Lorsque macOS demande d'autoriser le Terminal à contrôler le **Finder** (**permission Automatisation Finder**), cliquez sur **Autoriser**.
7. Dès que le message `INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.2.1) !` s'affiche, lancez *Les Sims 2* normalement depuis le Launchpad ou `/Applications` !

---

## 4. Sortie du Sandbox, Sauvegardes & Mods (`Downloads`)

### Pourquoi l'application s'exécute désormais hors du Sandbox
Lors de la signature locale ad-hoc (`codesign --force --deep --sign -`), la commande retire les entitlements commerciaux d'Aspyr (notamment `com.apple.security.app-sandbox`) sur le lanceur `AppBundleExe`. Réinjecter des entitlements propres au Mac App Store sous une signature ad-hoc locale sans certificat développeur Apple payant n'est pas supporté et expose l'application à un refus d'exécution par la politique de sécurité de macOS (`amfid` / Gatekeeper).

En conséquence, le jeu patché s'exécute hors du bac à sable Apple :
* **Nouvel emplacement actif des sauvegardes et des mods :**
  ```text
  ~/Library/Application Support/Aspyr/The Sims 2/
  ```
* **Avantage majeur pour les joueurs :** Vous bénéficiez d'un accès direct et simple au dossier `~/Library/Application Support/Aspyr/The Sims 2/Downloads/` pour installer vos mods et contenus personnalisés (CC), sans avoir à chercher dans les conteneurs cachés de macOS.
* **Migration garantie sans écrasement (`v1.2.1`) :**
  - Si `~/Library/Application Support/Aspyr/The Sims 2/` n'existe pas encore, `patch_sims2.command` y duplique directement vos données depuis le conteneur Sandbox.
  - Si un dossier `~/Library/Application Support/Aspyr/The Sims 2/` **existe déjà** (par exemple si vous avez déjà lancé le jeu en v1.1.0), le script **n'écrase absolument rien** (`with replacing` est proscrit) : il duplique le contenu de votre ancien conteneur Sandbox dans un sous-dossier de sécurité horodaté :
    `~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/`
    et vous en informe clairement dans le Terminal. Vos fichiers d'origine dans le conteneur Sandbox ne sont jamais supprimés.

---

## 5. Précisions Techniques & Environnement Testé

* **Environnement validé :** *Testé et validé sur MacBook Pro (Apple Silicon M1 Pro, écran ProMotion 120 Hz, macOS 27.0).*
* **Binaire cible :** `/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe` (Mach-O `x86_64`, 36 119 728 octets).
* **Double patch binaire (`FUN_1000fe510`) :**
  - **Patch 1 (`0xfe6dc`) :** Neutralise directement la lecture du 120 Hz issue de `_CGDisplayModeGetRefreshRate` en forçant la valeur `60` (`0x3c`) dans le registre `R15D` (`f20f1045d0f2440f2cf84889df` ➔ `41bf3c000000909090904889df`).
  - **Patch 2 (`0xfe741`) :** Sert de verrouillage de sécurité de repli dans la branche secondaire `_CVDisplayLink` en remplaçant `cmovnel %eax, %r15d` par 4 instructions `NOP` (`41bf3c000000440f45f8c70300000000` ➔ `41bf3c00000090909090c70300000000`).

---

## 6. Restauration du Binaire d'Origine (`restore_sims2.command`)

Double-cliquez sur **`restore_sims2.command`** à tout moment : le script vérifie d'abord que `Sims2XP_Exe.backup` contient bien les empreintes d'origine non modifiées, le restaure de façon atomique et re-signe localement l'application.

> **Note importante sur la réinstallation depuis le Mac App Store et vos sauvegardes :**  
> Pour rétablir la signature commerciale officielle d'Aspyr et réactiver l'isolation Sandbox initiale d'Apple, supprimez l'application et retéléchargez-la gratuitement depuis le Mac App Store.  
> Vos données dans `~/Library/Application Support/Aspyr/The Sims 2/` ne sont jamais supprimées, mais une version Mac App Store réinstallée (exécutée en Sandbox) relira ses données dans le conteneur `~/Library/Containers/com.aspyr.sims2.appstore/...` : toute progression effectuée hors Sandbox devra donc y être recopiée manuellement (et sur un écran à 120 Hz, le jeu non patché plantera de nouveau au lancement tant que l'écran n'est pas abaissé à 60 Hz).

---

## 7. Mention Légale

> *Ce projet est une initiative communautaire de préservation logicielle, s'inscrivant dans l'esprit de l'article 5(1) de la directive européenne 2009/24/CE autorisant la correction d'erreurs par l'acquéreur légitime d'un logiciel pour en permettre une utilisation conforme à sa destination.*  
> Aucun fichier propriétaire du jeu n'est distribué dans ce dépôt. Ce correctif ne contourne aucun DRM Apple FairPlay et requiert une copie légitime de *The Sims 2: Super Collection* acquise sur le Mac App Store.
