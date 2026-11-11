================================================================================
  THE SIMS 2: SUPER COLLECTION — PROMOTION 120Hz PATCH & CACHE FIX (v1.2.1)
  Tested and validated on MacBook Pro (Apple Silicon M1 Pro, 120 Hz ProMotion
  display, macOS 27.0) — Mac App Store Edition (com.aspyr.sims2.appstore)
================================================================================

[ENGLISH] ----------------------------------------------------------------------

1. OVERVIEW & INCLUDED TOOLS
   - patch_sims2.command       : Main installer (verified pristine backup +
                                 atomic 60 Hz binary patch + zero-overwrite save
                                 migration + dual-location cache purge).
   - clean_sims2_cache.command : Standalone cache cleaner (NO admin password!).
   - restore_sims2.command     : Verifies and atomically restores the original
                                 unpatched binary from Sims2XP_Exe.backup.

2. STEP-BY-STEP INSTALLATION & GATEKEEPER (macOS 15+ / Sequoia / macOS 27)
   Step 1: Make sure The Sims 2 is closed and installed in:
           /Applications/The Sims 2.app
   Step 2: Double-click "patch_sims2.command".
   Step 3: IF BLOCKED BY GATEKEEPER (Security Alert on first double-click):
           - Click "Done" (or "OK") on the alert dialog.
           - Immediately open System Settings -> Privacy & Security.
           - Scroll down to the "Security" section and click "Open Anyway"
             next to patch_sims2.command (this button appears for about 1 hour
             after a blocked launch attempt).
           - Click "Open" in the confirmation dialog and authenticate with your
             Mac login password or Touch ID.
   Step 4: In Terminal, type your Mac administrator password when prompted and
           press Enter (no characters appear while typing; this is normal).
           Admin privileges are used solely to patch /Applications/The Sims 2.app.
   Step 5: When macOS asks to allow Terminal to control Finder (standard Finder
           Automation permission), click "Allow".
   Step 6: Once "PATCH COMPLETE (v1.2.1)" appears, launch The Sims 2 normally
           from Launchpad or Applications!

3. IMPORTANT: NON-SANDBOX DATA FOLDER, SAVES & MODS (Downloads)
   - Why the game runs outside the App Sandbox:
     Re-signing the app locally (codesign --force --deep --sign -) removes
     Aspyr's proprietary App Store entitlements on AppBundleExe, as re-signing
     commercial App Store entitlements ad-hoc without a paid Apple Developer
     certificate is unsupported and risks macOS launch policy rejection.
   - Where your saves and mods are now located:
     ~/Library/Application Support/Aspyr/The Sims 2/
   - Major Benefit for Mods & Custom Content (CC):
     You can now access your "Downloads" folder directly inside
     ~/Library/Application Support/Aspyr/The Sims 2/Downloads/ without digging
     into hidden macOS Sandbox containers!
   - Safe, Zero-Overwrite Save Migration (Finder Automation Permission):
     * If ~/Library/Application Support/Aspyr/The Sims 2/ does not exist yet,
       patch_sims2.command duplicates your Sandbox container contents directly
       into it.
     * If ~/Library/Application Support/Aspyr/The Sims 2/ already exists, the
       script NEVER overwrites any file ("with replacing" is prohibited).
       Instead, it duplicates your legacy Sandbox saves into a timestamped
       backup folder:
       ~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/
       and notifies you in Terminal. Original Sandbox files are never deleted.

4. TECHNICAL SUMMARY
   - Tested and validated on MacBook Pro (Apple Silicon M1 Pro, 120 Hz ProMotion
     display, macOS 27.0).
   - Patch 1 (0xfe6dc): Directly neutralizes the 120 Hz display reading by
     locking R15D to 60 Hz (0x3c).
   - Patch 2 (0xfe741): Secondary fallback safety lock in the _CVDisplayLink
     branch (replaces CMOVNE with NOPs).

5. TROUBLESHOOTING & RESTORATION
   - If a neighborhood ever fails to load after a crash or bad mod, double-click
     "clean_sims2_cache.command". It deletes corrupted cache files
     (Groups.cache, Accessory.cache, cAstGroupCache.package) in Application
     Support (rm -f) and moves any residual Sandbox cache files to the macOS
     Trash via Finder (without requiring sudo).
   - To restore the original binary from Sims2XP_Exe.backup, double-click
     "restore_sims2.command" (verifies pristine byte fingerprints before
     performing an atomic restore).
     Note on App Store Reinstallation & Saves:
     To restore Aspyr's official commercial signature and re-enable Apple's
     initial App Sandbox isolation, delete the app and re-download it for free
     from the Mac App Store. Your files in ~/Library/Application Support/Aspyr/
     are never deleted, but a reinstalled Mac App Store version (running inside
     the Sandbox) will read from ~/Library/Containers/com.aspyr.sims2.appstore/
     again (and will crash on startup if your screen is set to 120 Hz).

6. LEGAL NOTICE
   This project is a community-driven software preservation initiative,
   conducted in the spirit of Article 5(1) of European Directive 2009/24/EC,
   which permits the lawful acquirer of a computer program to correct errors so
   that it may be used in accordance with its intended purpose.


[FRANÇAIS] ---------------------------------------------------------------------

1. PRÉSENTATION & OUTILS INCLUS
   - patch_sims2.command       : Installateur principal (sauvegarde binaire
                                 vérifiée + patch atomique 60 Hz + migration des
                                 sauvegardes sans écrasement + double purge).
   - clean_sims2_cache.command : Outil de purge des caches (SANS mot de passe !).
   - restore_sims2.command     : Vérifie l'intégrité de Sims2XP_Exe.backup et
                                 restaure le binaire d'origine de façon atomique.

2. INSTALLATION PAS À PAS & PROCÉDURE GATEKEEPER (macOS 15+ / Sequoia / macOS 27)
   Étape 1 : Vérifiez que Les Sims 2 est fermé et installé dans :
             /Applications/The Sims 2.app
   Étape 2 : Double-cliquez sur "patch_sims2.command".
   Étape 3 : EN CAS D'ALERTE DE SÉCURITÉ GATEKEEPER AU PREMIER DOUBLE-CLIC :
             - Fermez l'alerte ("Terminé" ou "OK").
             - Ouvrez immédiatement Réglages Système -> Confidentialité et
               sécurité.
             - Faites défiler jusqu'à la section "Sécurité" et cliquez sur le
               bouton "Ouvrir quand même" à côté de patch_sims2.command (ce
               bouton s'affiche pendant environ 1 heure après une tentative
               d'ouverture bloquée).
             - Cliquez sur "Ouvrir" dans la fenêtre de confirmation puis validez
               avec votre mot de passe de session Mac ou Touch ID.
   Étape 4 : Dans le Terminal, entrez votre mot de passe administrateur Mac puis
             appuyez sur Entrée (aucun caractère ne s'affiche, c'est normal).
             Ce droit sert uniquement à modifier l'app dans /Applications.
   Étape 5 : Lorsque macOS demande d'autoriser Terminal à contrôler le Finder
             (permission Automatisation Finder), cliquez sur "Autoriser".
   Étape 6 : Une fois le message "INSTALLATION TERMINÉE AVEC SUCCÈS (v1.2.1)"
             affiché, lancez Les Sims 2 depuis le Launchpad ou Applications !

3. SORTIE DU SANDBOX, EMPLACEMENT DES SAUVEGARDES & MODS (Downloads)
   - Pourquoi l'application s'exécute hors du Sandbox :
     La re-signature locale (codesign --force --deep --sign -) retire les
     entitlements commerciaux d'Aspyr sur AppBundleExe, car réinjecter des
     entitlements propres au Mac App Store sous une signature ad-hoc sans
     certificat développeur Apple payant n'est pas supporté et expose à un refus
     d'exécution par la politique de sécurité de macOS.
   - Nouvel emplacement des sauvegardes et mods :
     ~/Library/Application Support/Aspyr/The Sims 2/
   - Avantage majeur pour les joueurs (Mods / CC) :
     Vous accédez directement et facilement au dossier "Downloads" dans
     ~/Library/Application Support/Aspyr/The Sims 2/Downloads/ pour installer
     vos mods et contenus personnalisés sans passer par les conteneurs cachés
     de macOS.
   - Migration sécurisée sans écrasement (Permission Automatisation Finder) :
     * Si ~/Library/Application Support/Aspyr/The Sims 2/ n'existe pas encore,
       le script y duplique directement vos données depuis le conteneur Sandbox.
     * Si ce dossier existe déjà, le script N'ÉCRASE RIEN ("with replacing" est
       proscrit) : il duplique le contenu de votre ancien conteneur Sandbox dans
       un sous-dossier de sécurité horodaté :
       ~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/
       et vous prévient dans le Terminal. Vos originaux dans le Sandbox restent
       intacts.

4. PRÉCISIONS TECHNIQUES & ENVIRONNEMENT TESTÉ
   - Testé et validé sur MacBook Pro (Apple Silicon M1 Pro, écran ProMotion
     120 Hz, macOS 27.0).
   - Patch 1 (0xfe6dc) : Neutralise directement la lecture du 120 Hz en forçant
     60 Hz (0x3c) dans le registre R15D.
   - Patch 2 (0xfe741) : Sert de verrouillage de sécurité de repli dans la
     branche secondaire _CVDisplayLink.

5. DÉPANNAGE & RESTAURATION DE L'ORIGINAL
   - Si un quartier plante ultérieurement (suite à un arrêt forcé ou un mod
     défectueux), double-cliquez sur "clean_sims2_cache.command" : il supprime
     les caches corrompus (Groups.cache, Accessory.cache, cAstGroupCache.package)
     dans Application Support (rm -f) et déplace ceux du conteneur Sandbox vers
     la Corbeille macOS via le Finder (sans demander de mot de passe).
   - Pour restaurer le binaire d'origine depuis Sims2XP_Exe.backup,
     double-cliquez sur "restore_sims2.command" (vérifie la présence des octets
     d'origine avant la restauration atomique).
     Note sur la réinstallation depuis le Mac App Store et vos sauvegardes :
     Pour rétablir la signature commerciale officielle d'Aspyr et réactiver
     l'isolation Sandbox initiale d'Apple, supprimez l'application et
     retéléchargez-la gratuitement depuis le Mac App Store. Vos données dans
     ~/Library/Application Support/Aspyr/The Sims 2/ ne sont jamais supprimées,
     mais une version Mac App Store réinstallée (en Sandbox) relira uniquement
     le conteneur ~/Library/Containers/com.aspyr.sims2.appstore/... (et plantera
     de nouveau au démarrage si votre écran est à 120 Hz).

6. MENTION LÉGALE
   Ce projet est une initiative communautaire de préservation logicielle,
   s'inscrivant dans l'esprit de l'article 5(1) de la directive européenne
   2009/24/CE autorisant la correction d'erreurs par l'acquéreur légitime d'un
   logiciel pour en permettre une utilisation conforme à sa destination.
================================================================================
