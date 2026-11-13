# Sims 2 Crash Patch — Windows Special Edition (`windows/`)

> **FR :** Édition dédiée à **Windows 10 / Windows 11**, volontairement séparée des scripts macOS (`*.command`) à la racine du dépôt afin que PC et Mac cohabitent sans jamais interférer.  
> **EN:** Dedicated **Windows 10 / Windows 11** edition, strictly isolated from the macOS scripts (`*.command`) at the repository root so PC and Mac never interfere with each other.

---

## Pourquoi une édition Windows séparée ? / Why a Separate Windows Edition?

Sur macOS, le jeu concerné est *The Sims 2: Super Collection* (`Sims2XP_Exe`, Mach-O `x86_64`).  
Sur Windows (*Ultimate Collection* / *Legacy Collection* / versions CD-DVD, `Sims2EP9.exe` PE32 x86), la communauté dispose déjà d'outils dédiés comme **TS2-Extender** / **Sims2RPC** et **Graphics Rules Maker**. Plutôt que de réinventer ces outils ou de mélanger du code Windows dans les scripts macOS, ce dossier `windows/` fournit des utilitaires légers, sans dépendance externe (`Python 3` standard library + API Win32 native), focalisés sur les problèmes réels restants :

1. **Assistant Caméra Trackpad (`sims2_trackpad_camera.py` / `Sims2_Trackpad_Camera.bat`)**
   - **Swipe horizontal à 2 doigts (`WM_MOUSEHWHEEL`) :** Fait pivoter la caméra en douceur (par défaut via un glisser simulé du bouton central, ou via `,` / `.` avec `--hscroll keys`).
   - **`AltGr` (`Right Alt`) + Clic gauche glissé :** Orbite et inclinaison 3D complète à 360° (simule le bouton central maintenu).
   - **Touche bascule `F8` :** Active/désactive le mode « Orbite à 1 doigt » sans avoir à maintenir aucune touche (`Esc` ou Alt-Tab le désactive automatiquement).
   - **Sécurité :** Ne s'active **que** lorsque la fenêtre *The Sims 2* est au premier plan et relâche automatiquement le bouton central en cas de changement de fenêtre (`Alt-Tab`) ou de fermeture.

2. **Boîte à outils Diagnostic & Réparation (`sims2_windows_toolkit.py` / `Sims2_Toolkit.bat`)**
   - **`scan` :** Détecte les installations Sims 2 et dossiers `Documents\EA Games\The Sims 2*`, vérifie la présence du flag **4GB / `LARGEADDRESSAWARE`** dans le header PE32, signale les conflits de synchronisation **OneDrive**, vérifie si l'écran dépasse **60 Hz**, inspecte `userProps.xml` (`activeDeviceDisplayMode`) et liste les caches corrompus.
   - **`clean-cache` :** Nettoie `Groups.cache`, `Accessory.cache`, `cigen.package`, `ContentRegistry` sans toucher à `Neighborhoods` ni `Downloads`.
   - **`patch-4gb` / `restore-4gb` :** Active le flag `LARGEADDRESSAWARE` avec sauvegarde `.backup` et recalcul atomique du checksum PE32.
   - **`fix-userprops` :** Sauvegarde et corrige `activeDeviceDisplayMode` dans `userProps.xml` vers un mode valide à 60 Hz.

---

## Utilisation rapide / Quick Start

- Double-cliquez sur **`Sims2_Toolkit.bat`** pour le menu interactif, ou **`Sims2_Trackpad_Camera.bat`** avant de lancer Les Sims 2.
- En ligne de commande :
  ```powershell
  python windows/sims2_windows_toolkit.py scan
  python windows/sims2_trackpad_camera.py --modifier alt --sensitivity 22
  ```
