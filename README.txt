================================================================================
  THE SIMS 2: SUPER COLLECTION — PROMOTION 120Hz PATCH & CACHE FIX (v1.1.0)
  For macOS (Apple Silicon M1/M2/M3/M4 Pro & Max — Mac App Store Edition)
================================================================================

[ENGLISH] ----------------------------------------------------------------------

1. WHY DOES THE GAME CRASH?
   - Startup Crash (2 seconds after launch):
     The legacy game engine only accepts 60 Hz display modes. On Apple Silicon
     MacBook Pros with 120 Hz ProMotion screens, macOS reports 120 Hz, causing
     an unhandled C++ exception and instant crash.
   - Neighborhood Loading Crash (after entering a world):
     Because the game previously crashed, macOS/Sims 2 left corrupted cache
     files (Groups.cache, Accessory.cache, cAstGroupCache.package) inside your
     Sandbox folder, crashing the game when loading 3D neighborhoods.

   This patch permanently locks the game's display enumeration to 60 Hz (while
   keeping your Mac screen at 120 Hz!) AND safely cleans the corrupted caches.

2. INSTALLATION (STEP BY STEP)
   Step 1: Make sure The Sims 2 is completely closed and installed in:
           /Applications/The Sims 2.app
   Step 2: Double-click "patch_sims2.command".
           * NOTE (Gatekeeper): If macOS says the file is from an unidentified
             developer, RIGHT-CLICK (or Ctrl+Click) "patch_sims2.command",
             select "Open", then click "Open" in the dialog.
   Step 3: Type your Mac administrator password when asked and press Enter
           (nothing appears while typing — this is normal on macOS).
           Admin access is needed solely to patch the app in /Applications.
   Step 4: Wait for "SUCCÈS TOTAL / PATCH & CACHE HEALING COMPLETE !", then press
           Enter to close Terminal.
   Step 5: Launch The Sims 2 normally from Launchpad or Applications!

3. TROUBLESHOOTING / FUTURE CRASHES ("clean_sims2_cache.command")
   If your neighborhood ever crashes later (for example after adding bad custom
   content / mods or force-quitting the game):
   - Simply double-click "clean_sims2_cache.command" (NO password required!).
   - It safely deletes corrupted index caches via Finder without touching your
     saves, neighborhoods, or mods.

4. UNINSTALL / RESTORE ORIGINAL GAME
   A full backup ("Sims2XP_Exe.backup") is automatically created before patching.
   To revert to the untouched Mac App Store binary, open Terminal and run:

     sudo cp "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe.backup" \
             "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
     sudo codesign --force --deep --sign - "/Applications/The Sims 2.app"

   Or simply delete the app and re-download it from the Mac App Store.

5. LEGAL NOTICE
   Non-profit community interoperability fix. Does NOT bypass DRM or receipts.
   Requires a legitimate copy of The Sims 2: Super Collection (Mac App Store).


[FRANÇAIS] ---------------------------------------------------------------------

1. POURQUOI LE JEU PLANTE-T-IL ?
   - Crash au démarrage (2 secondes après le lancement) :
     Le moteur d'origine du jeu n'accepte que les fréquences d'affichage à 60 Hz.
     Sur les MacBook Pro dotés d'écrans ProMotion (120 Hz), le jeu reçoit 120 Hz,
     ne trouve aucun mode compatible et plante immédiatement.
   - Crash au chargement d'un quartier (Montsimpa, Zarbville, etc.) :
     Les crashs précédents ont corrompu les fichiers d'indexation temporaires
     (Groups.cache, Accessory.cache, cAstGroupCache.package) dans votre dossier
     Sandbox, provoquant un crash dès l'entrée dans un monde 3D.

   Ce patch verrouille définitivement le moteur du jeu sur 60 Hz (tout en
   laissant votre écran Mac à 120 Hz !) ET assainit vos caches automatiquement.

2. GUIDE D'INSTALLATION PAS À PAS
   Étape 1 : Vérifiez que Les Sims 2 est fermé et installé dans /Applications.
   Étape 2 : Double-cliquez sur "patch_sims2.command".
             * ASTUCE (Gatekeeper) : Si macOS bloque l'ouverture (développeur
               non vérifié), faites un CLIC DROIT sur "patch_sims2.command",
               cliquez sur "Ouvrir", puis confirmez "Ouvrir".
   Étape 3 : Entrez votre mot de passe de session Mac quand il est demandé puis
             appuyez sur Entrée (aucun caractère ne s'affiche, c'est normal).
             Le mot de passe sert uniquement à modifier l'app dans /Applications.
   Étape 4 : Une fois le message "SUCCÈS TOTAL" affiché, appuyez sur Entrée.
   Étape 5 : Lancez Les Sims 2 normalement depuis le Launchpad ou Applications !

3. DÉPANNAGE / SECOURS ("clean_sims2_cache.command")
   Si un quartier plante à l'avenir (par exemple après l'ajout d'un mod / CC
   défectueux ou suite à un arrêt brutal du jeu) :
   - Double-cliquez simplement sur "clean_sims2_cache.command"
     (AUCUN mot de passe requis !).
   - Vos quartiers, familles et téléchargements restent 100 % intacts.

4. DÉSINSTALLATION / RESTAURER L'ORIGINAL
   Une sauvegarde ("Sims2XP_Exe.backup") est créée automatiquement.
   Pour restaurer le binaire officiel d'origine, exécutez dans le Terminal :

     sudo cp "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe.backup" \
             "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
     sudo codesign --force --deep --sign - "/Applications/The Sims 2.app"

   Vous pouvez également simplement supprimer et retélécharger le jeu depuis
   le Mac App Store.

5. MENTION LÉGALE
   Correctif communautaire à but non lucratif (interopérabilité logicielle).
   Ne contourne aucun DRM. Nécessite de posséder le jeu original du Mac App Store.
================================================================================
