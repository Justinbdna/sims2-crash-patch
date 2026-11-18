================================================================================
  THE SIMS 2: SUPER COLLECTION (macOS) — QUICK START & SUPPORT MEMO (v1.4.1)
  Apple Silicon & Intel | Zero Xcode | MIT License (Free & Non-Profit)
================================================================================

[FRANÇAIS] (English version below / Version anglaise plus bas) -----------------

1. INSTALLATION EN 3 CLICS
   1) Décompressez tout le fichier .zip (Téléchargements ou Bureau) et fermez
      Les Sims 2 (Cmd + Q).
   2) Débloquez Gatekeeper : double-cliquez sur « patch_sims2.command » -> si
      macOS affiche « bloqué pour protéger votre Mac », cliquez sur « Terminé »,
      ouvrez Réglages Système -> Confidentialité et sécurité, descendez tout
      en bas et cliquez sur « Ouvrir quand même ».
   3) Appuyez sur Entrée ([1]) dans le Terminal :
      - Tapez votre mot de passe Mac à l'aveugle (rien ne s'affiche à l'écran,
        aucun '*', c'est normal !) puis Entrée.
      - Cliquez impérativement sur « Autoriser » si Terminal demande à contrôler
        Finder (pour copier vos sauvegardes sans rien écraser).
      - Attendez « PATCH COMPLETE (v1.4.1) » puis lancez le jeu !

2. CONTRÔLES TRACKPAD MACBOOK
   - Pincement 2 doigts                 : Zoom (+ / -)
   - Balayage horizontal / rotation 2 d.: Rotation caméra (, / ., AZERTY & QWERTY)
   - Control (^) + clic-glissé          : Orbite 3D libre & inclinaison
   - Option (⌥) + glisser               : Panoramique natif (déplacement carte)

3. OUTILS INCLUS & NOTE RÉSOLUTION
   - clean_sims2_cache.command :
     [1] Nettoyer les caches corrompus (Entrée, sans mot de passe).
     [2] Réinitialiser la résolution au lancement dans userProps.xml (crée
         userProps.xml.backup). Note : pas de changement de résolution à chaud
         en pleine partie dans la v1.4.1.
     [3] Vérifier vos Mods (.package / .zip oubliés) & limite maxfiles (10 240).
   - restore_sims2.command :
     Restaure le jeu d'origine (Sims2XP_Exe.backup + Graphics Rules.sgr.backup)
     et retire le module trackpad. (Pour retrouver la signature Mac App Store,
     supprimez et retéléchargez l'app depuis l'App Store ; sauvegardes gardées.)

4. SUPPORT & DÉPANNAGE RAPIDE
   - Option [2] de patch_sims2.command (Diagnostic & Support GitHub) :
     En partie normale, zéro log n'est écrit. Un fichier crash_report.log est
     créé uniquement en cas de crash. L'option [2] active le mode debug au
     besoin et génère github_support_report.md anonymisé (chemins /Users/...
     remplacés par ~), copié automatiquement dans votre presse-papier.
   - Anciennes sauvegardes absentes ? Vérifiez le dossier :
     ~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup ...)
     et fusionnez Neighborhoods/ et Downloads/ vers The Sims 2/ (jeu fermé).
   - Erreur Finder (-1743) ? Activez Réglages Système -> Confidentialité et
     sécurité -> Automatisation -> Terminal -> Finder.

-> Détails techniques (offsets, CoreGraphics, encoche) dans README.md sur
   GitHub : https://github.com/Justinbdna/sims2-crash-patch


[ENGLISH] ----------------------------------------------------------------------

1. 3-CLICK SETUP
   1) Unzip the full archive (Downloads or Desktop) and quit The Sims 2 (Cmd+Q).
   2) Bypass Gatekeeper: double-click "patch_sims2.command" -> if macOS
      shows "blocked to protect your Mac", click "Done", open System Settings
      -> Privacy & Security, scroll down and click "Open Anyway".
   3) Press Enter ([1]) in Terminal:
      - Type your Mac login password blindly at "Password:" (zero characters
        or '*' appear on screen — normal macOS security) then press Enter.
      - Click "Allow" ("Autoriser") if Terminal asks to control Finder so your
        saves are copied without overwriting anything.
      - Wait for "PATCH COMPLETE (v1.4.1)" and launch the game!

2. MACBOOK TRACKPAD CONTROLS
   - 2-finger pinch                     : Zoom in / out (+ / -)
   - 2-finger horizontal swipe / twist  : Camera rotation (, / ., AZERTY & QWERTY)
   - Control (^) + click & drag         : Free 3D orbit & pitch
   - Option (⌥) + drag                  : Native camera pan (hand-drag)

3. INCLUDED TOOLS & RESOLUTION NOTE
   - clean_sims2_cache.command :
     [1] Purge corrupted caches (Enter, no password).
     [2] Reset launch resolution in userProps.xml (keeps userProps.xml.backup).
         Note: there is no in-game hot-swap resolution switching in v1.4.1.
     [3] Check Mods/CC (.package / leftover .zip) & 10,240 open-file limit.
   - restore_sims2.command :
     Cleanly restores original binaries/configs and removes the trackpad dylib.
     (Delete & re-download from the Mac App Store to restore App Store Sandbox;
     your saves in ~/Library/Application Support/Aspyr/ remain intact.)

4. SUPPORT & QUICK TROUBLESHOOTING
   - Run patch_sims2.command -> [2] Diagnostic & Support GitHub:
     Normal sessions write zero logs; crash_report.log is only created if a
     crash happens. Option [2] toggles optional debug mode and copies an
     anonymized (~) github_support_report.md straight to your clipboard.
   - Missing saves? Check ~/Library/Application Support/Aspyr/ for a
     "The Sims 2 (Sandbox Backup ...)" folder and merge Neighborhoods/Downloads
     while the game is closed.
   - Finder Automation error (-1743)? Enable System Settings -> Privacy &
     Security -> Automation -> Terminal -> Finder.

-> Full technical details (binary offsets, CoreGraphics, notch) in README.md on
   GitHub: https://github.com/Justinbdna/sims2-crash-patch

--------------------------------------------------------------------------------
5. MENTIONS LÉGALES & PRÉSERVATION / LEGAL NOTICE & SOFTWARE PRESERVATION
   - FR : Projet communautaire 100 % gratuit, open-source (licence MIT) et à
     but non lucratif. Destiné uniquement au débogage et à la correction
     d'erreurs d'une copie légitime d'un jeu ancien non maintenu (macOS).
     Aucun binaire propriétaire distribué, aucun DRM contourné, aucune
     affiliation avec EA, Maxis, Aspyr ou Apple. Cadres informatifs :
     UE Directive 2009/24/CE (art. 5(1), 6), USA (17 U.S.C. § 117, § 1201(f),
     § 107), UK (CDPA 1988 s. 50B/50C) et principes internationaux analogues.
   - EN : 100% free, non-profit, open-source (MIT License, see LICENSE)
     community tool solely for debugging, bug-fixing, and preserving a
     legitimately owned, unsupported legacy game. Zero copyrighted binaries
     distributed, zero DRM bypassed, no affiliation with EA, Maxis, Aspyr, or
     Apple. Informational frameworks: EU Directive 2009/24/EC (Art. 5(1), 6),
     USA (17 U.S.C. § 117, § 1201(f), § 107), UK (CDPA 1988 s. 50B/50C), and
     comparable international interoperability/preservation exceptions.
================================================================================
