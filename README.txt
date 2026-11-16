================================================================================
  THE SIMS 2: SUPER COLLECTION — PROMOTION 120Hz PATCH & STABILITY FIX (v1.4.0)
  Tested on MacBook Pro (Apple Silicon M1 Pro, 120 Hz ProMotion, macOS 27.0)
  Mac App Store Edition (com.aspyr.sims2.appstore)
================================================================================

[FRANÇAIS] (English guide follows below / Version anglaise plus bas) ----------

1. PRÉSENTATION & OUTILS INCLUS
   - patch_sims2.command       : Installateur principal & Diagnostic [1/2/3] :
                                 • [1] Installer / Mettre à jour (Entrée) :
                                   - Vérifie la session Admin et trouve le jeu
                                     (/Applications ou ~/Applications)
                                   - Sauvegarde le binaire d'origine vérifié
                                     (Sims2XP_Exe.backup)
                                   - Applique le double patch atomique 60 Hz &
                                     plein écran calé sous encoche (visibleFrame)
                                   - Optimise Graphics Rules.sgr (résolutions
                                     jusqu'à 2560x1600, défaut natif dynamique,
                                     profil $High, fallback VRAM 1024 Mo, .backup)
                                   - Installe & injecte le module Trackpad natif
                                     libsims2_trackpad.dylib via LC_LOAD_WEAK_DYLIB
                                     sans Xcode (Control + clic-glissé = orbite 3D,
                                     Option + glisser = panoramique, pincement 2 doigts
                                     = zoom +/-, swipe/rotation 2 doigts = ,/.)
                                   - Re-signe l'application proprement
                                   - Copie vos sauvegardes Sandbox sans écraser
                                   - Purge les caches corrompus (Actif + Sandbox)
                                   - Vérifie userProps.xml (écran externe/120 Hz)
                                     et diagnostique vos Mods (.package / maxfiles)
                                 • [2] Diagnostic & Support GitHub :
                                   - Active/désactive le mode debug (debug_boot.log)
                                   - Génère github_support_report.md anonymisé
                                     (+ copie automatique dans le presse-papier)
   - clean_sims2_cache.command : Utilitaire interactif avec menu [1 / 2 / 3 / 4]
                                 (SANS mot de passe pour les caches / affichage) :
                                 [1] Nettoyer les caches (appui sur Entrée)
                                 [2] Réinitialiser la résolution (userProps.xml)
                                 [3] Vérifier vos Mods (.package/.zip) & maxfiles
                                 [4] Quitter
   - restore_sims2.command     : Désinstallateur officiel :
                                 • Vérifie l'intégrité de Sims2XP_Exe.backup
                                 • Restaure le binaire d'origine atomiquement
                                   et restaure Graphics Rules.sgr.backup
                                 • Retire libsims2_trackpad.dylib
                                 • Retire le LaunchDaemon maxfiles s'il a été
                                   installé par ce patch
                                 • Préserve vos sauvegardes et backups config

2. AVANT DE COMMENCER : CE QUE MACOS VA VOUS DEMANDER (HONNÊTETÉ & SÉCURITÉ)
   Sur Mac, il est tout à fait normal que le système vous pose plusieurs questions
   de sécurité lors de la première utilisation. Ne paniquez pas, voici pourquoi :

   a) Blocage « Apple ne peut pas vérifier... » (Gatekeeper) :
      Le script n'est pas payé/notarié via un compte Apple Developer à 99 $/an,
      donc macOS le bloque par défaut au tout premier double-clic (voir Étape 3).
   b) Mot de passe dans le Terminal INVISIBLE (100 % NORMAL !) :
      Quand le Terminal affiche "Password:" (avec une petite clé), TAPEZ VOTRE
      MOT DE PASSE MAC HABITUEL À L'AVEUGLE PUIS APPUYEZ SUR ENTRÉE.
      IMPORTANT : AUCUN CARACTÈRE (ni '*', ni point, rien du tout !) ne
      s'affiche quand vous tapez. Le curseur ne bouge même pas. Ce n'est PAS un
      bug et votre clavier n'est PAS bloqué : c'est une règle de sécurité
      normale de macOS pour que personne ne voie la longueur de votre mot de passe.
   c) Pop-up « Terminal souhaite contrôler Finder » :
      Indispensable pour copier vos anciennes sauvegardes et mods depuis le
      dossier protégé du Mac App Store (Sandbox) vers votre dossier actif sans
      rien perdre. Cliquez impérativement sur « Autoriser ».

3. INSTALLATION PAS À PAS (UTILISATEUR DÉBUTANT)
   Étape 1 : Décompressez complètement l'archive .zip dans Téléchargements ou sur
             le Bureau (ne lancez pas le script depuis l'aperçu du fichier .zip).
   Étape 2 : Fermez complètement Les Sims 2 (Cmd+Q, vérifiez dans le Dock) et
             vérifiez qu'il est installé dans /Applications/The Sims 2.app
             (ou ~/Applications/The Sims 2.app).
   Étape 3 : Double-cliquez sur « patch_sims2.command ».
   Étape 4 : SI MACOS BLOQUE LE SCRIPT (ALERTE GATEKEEPER AU 1ER LANCEMENT) :
             1) Cliquez sur « Terminé » (ou « OK ») sur la fenêtre d'alerte.
             2) Ouvrez Réglages Système -> Confidentialité et sécurité.
             3) Faites défiler tout en bas jusqu'à la section « Sécurité ».
             4) Vous verrez : « "patch_sims2.command" a été bloqué... » avec
                un bouton « Ouvrir quand même » (valable ~1 heure après essai).
             5) Cliquez sur « Ouvrir quand même », puis sur « Ouvrir » dans la
                nouvelle fenêtre, et validez avec votre mot de passe ou Touch ID.
   Étape 5 : Dans la fenêtre noire du Terminal :
             - Vérifiez l'encadré d'explication affiché à l'écran.
             - À la ligne « Password: », tapez votre mot de passe session Mac
               (rien ne s'affichera à l'écran, c'est normal !) + Entrée.
   Étape 6 : Si une fenêtre demande d'autoriser Terminal à contrôler le Finder :
             Cliquez sur « Autoriser ».
   Étape 7 : Si le script détecte une limite système maxfiles trop basse (< 10240)
             pour vos mods, il vous propose [o/N] d'installer une configuration
             système gérée (/Library/LaunchDaemons/limit.maxfiles.plist).
             Répondez « o » puis Entrée si vous jouez avec beaucoup de CC, sinon
             appuyez juste sur Entrée (= Non).
   Étape 8 : Attendez « INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE »
             (ou si une action Finder est requise, suivez le message jaune AVANT
             de lancer le jeu !), puis lancez Les Sims 2 depuis Launchpad !

4. EMPLACEMENT DES SAUVEGARDES, MODS & GARDE-FOUS AUTOMATIQUES
   - Pourquoi le jeu sort du Sandbox Apple :
     La re-signature locale ad-hoc (codesign --force --deep --sign -) retire les
     entitlements Mac App Store d'Aspyr sur AppBundleExe (car réinjecter des
     entitlements App Store sans certificat payant Apple est refusé par macOS).
   - Nouvel emplacement actif (très simple d'accès !) :
     ~/Library/Application Support/Aspyr/The Sims 2/
     Vos Mods/CC (.package décompressés) vont dans :
     ~/Library/Application Support/Aspyr/The Sims 2/Downloads/
   - Migration garantie sans écrasement :
     • Si ce dossier est vide/absent, vos sauvegardes Sandbox y sont copiées.
     • Si un dossier actif existe déjà, rien n'est écrasé : l'ancien contenu
       Sandbox est dupliqué à côté dans :
       ~/Library/Application Support/Aspyr/The Sims 2 (Sandbox Backup YYYY-MM-DD)/
   - Protection écran externe / 120 Hz (userProps.xml) :
     Si votre écran externe a été débranché ou si une vieille résolution/Hz
     fait planter le jeu au démarrage, v1.3.0 crée d'abord une sauvegarde de
     retour (Config/userProps.xml.backup) puis règle l'affichage en 60 Hz sûr.

5. EN CAS D'ERREUR / CAS PRATIQUES (GUIDE DE DÉPANNAGE COMPLET)

   CAS 1 : Double-clic bloqué (« Développeur non identifié / Logiciel malveillant »)
   -> Voir Étape 4 ci-dessus (Réglages Système -> Confidentialité et sécurité ->
      Ouvrir quand même). Répétez une seule fois si macOS bloque aussi
      clean_sims2_cache.command ou restore_sims2.command au 1er lancement.

   CAS 2 : « Je tape mon mot de passe dans Terminal mais rien ne s'écrit ! »
           ou erreur « Sorry, try again »
   -> C'est 100 % normal que rien ne s'affiche (aucune '*', sécurité macOS).
   -> Vérifiez que la touche Verrouillage Majuscule (Caps Lock) n'est pas active
      et que vous êtes bien en clavier français (AZERTY) / habituel.
   -> Utilisez le mot de passe de votre session Mac (Touch ID ne fonctionne pas
      directement dans sudo par défaut).

   CAS 3 : « Compte non-Administrateur détecté » / « is not in the sudoers file »
   -> Votre session macOS actuelle est un compte « Standard » (sans pouvoir
      modifier /Applications). Connectez-vous sur la session Administrateur du
      Mac (ou activez « Autoriser à administrer cet ordinateur » dans Réglages
      Système -> Utilisateurs et groupes), puis relancez patch_sims2.command.

   CAS 4 : Erreur « Not authorized to send Apple events to Finder (-1743) »
           ou « vous ne disposez pas des autorisations requises » (-5000)
   -> Si erreur -1743 (Automatisation refusée) :
      Activez Réglages Système -> Confidentialité et sécurité -> Automatisation
      -> Terminal -> Finder, puis relancez patch_sims2.command.
   -> Si erreur « autorisations requises / -5000 » alors que vous avez cliqué
      Autoriser : macOS protège le conteneur App Store contre les copies auto.
      • Si vous aviez déjà des sauvegardes dans Application Support, vous
        pouvez lancer le jeu normalement.
      • Sinon, copiez à la main dans le Finder (Cmd+Maj+G) :
        ~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/
        vers ~/Library/Application Support/Aspyr/The Sims 2/ (ou accordez
        Accès complet au disque à Terminal dans Réglages Système).

   CAS 4B : Partager un rapport clair si quelque chose ne marche pas
   -> En session normale, zéro journal de jeu n'est écrit sur le disque
      (un crash_report.log est généré uniquement si un crash survient).
   -> Lancez patch_sims2.command -> [2] Diagnostic & Support GitHub pour
      activer/désactiver le mode debug (debug_boot.log) et générer le rapport
      prêt à coller ~/Library/Logs/Sims2-Crash-Patch/github_support_report.md
      (copié automatiquement dans le presse-papier, /Users/... anonymisé en ~).

   CAS 5 : Le jeu démarre mais mes anciens quartiers / familles semblent absents
   -> Regardez dans ~/Library/Application Support/Aspyr/ (Finder : menu Aller ->
      Aller au dossier... et collez ce chemin).
   -> S'il existe un dossier « The Sims 2 (Sandbox Backup ...) », c'est que vous
      aviez déjà lancé le jeu une fois hors Sandbox avant de migrer vos saves.
      Vous pouvez copier manuellement vos quartiers (Neighborhoods) et
      Downloads depuis ce backup vers « The Sims 2 » (jeu fermé).

   CAS 6 : Le jeu plante au lancement après avoir débranché un écran externe ou
           changé une résolution en jeu
   -> Double-cliquez sur « clean_sims2_cache.command », tapez « 2 » puis Entrée :
      il réinitialise la résolution dans userProps.xml en mode natif sûr à 60 Hz
      tout en conservant une copie de secours userProps.xml.backup.

   CAS 7 : Vos Mods / CC n'apparaissent pas ou le quartier plante au chargement
   -> Double-cliquez sur « clean_sims2_cache.command » :
      • Choix [1] (Entrée) : supprime les caches corrompus sans toucher à vos
        familles ni vos mods.
      • Choix [3] : compte vos .package et signale si des fichiers .zip/.rar/.7z
        ont été oubliés dans Downloads/ (Les Sims 2 ne lit PAS les archives !).
        Rappel technique : le moteur Sims2XP_Exe plafonne à 10 240 fichiers
        ouverts en même temps ; au-delà de ~8 000–9 000 mods, pensez à fusionner
        ou trier vos .package.

   CAS 8 : « Permission denied » ou le script s'ouvre dans TextEdit au lieu du Terminal
   -> Assurez-vous d'avoir bien DÉCOMPRESSÉ l'archive .zip (clic droit -> Ouvrir
      avec Utilitaire d'archive). Si vous utilisez un outil tiers qui a retiré
      les droits d'exécution, ouvrez Terminal, tapez « chmod +x  » (avec un
      espace à la fin), glissez le fichier .command dans Terminal et Entrée.

   CAS 9 : Revenir à l'état d'origine (avant le patch)
   -> Double-cliquez sur « restore_sims2.command » (remet Sims2XP_Exe.backup,
      re-signe l'app et supprime limit.maxfiles.plist si installé par le patch).
   -> Pour retrouver la signature commerciale officielle Apple / Aspyr et le
      Sandbox App Store : supprimez The Sims 2.app puis retéléchargez-le
      gratuitement depuis le Mac App Store (vos données dans Application Support
      ne sont jamais supprimées).

6. PRÉCISIONS TECHNIQUES & MENTION LÉGALE
   - Patch binaire dual ancré dans FUN_1000fe510 (0xfe6dc -> 60 Hz / 0x3c dans R15D,
     0xfe741 -> NOPs sur branche _CVDisplayLink). Zéro dépendance Xcode CLT
     (/usr/bin/perl, /usr/bin/osascript, /usr/bin/codesign natifs uniquement).
   - Graphics Rules.sgr : sauvegarde Graphics Rules.sgr.backup, déblocage jusqu'à
     2560x1600, défaut $High sur résolution native dynamique, textureMemory 1024 Mo.
   - Trackpad natif (libsims2_trackpad.dylib) : chargé via LC_LOAD_WEAK_DYLIB
     sans Xcode : Control (^) + clic-glissé = inclinaison / orbite 3D libre,
     Option (⌥) + glisser ou clic-glissé = se déplacer (curseur 4 flèches),
     pincement 2 doigts = zoom +/-, swipe horizontal / rotation 2 doigts = ,/.,
     SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0 (Cmd+Tab sans rebond vers le Bureau).
   - Ce projet est une initiative communautaire de préservation logicielle
     (article 5(1) de la directive européenne 2009/24/CE), sans distribution de
     fichiers du jeu ni contournement de DRM.


[ENGLISH] ----------------------------------------------------------------------

1. OVERVIEW & INCLUDED TOOLS
   - patch_sims2.command       : Automatic main installer & Support menu [1/2/3]:
                                 • [1] Install/Update (Enter):
                                   - Verifies Admin rights & locates app bundle
                                   - Backs up verified original Sims2XP_Exe.backup
                                   - Applies atomic dual 60 Hz & notch-fit patch
                                   - Upgrades Graphics Rules.sgr (up to 2560x1600,
                                     dynamic native $High default, 1024 MB VRAM)
                                   - Installs & injects libsims2_trackpad.dylib
                                   - Re-signs locally (--strict), migrates saves
                                     with zero overwrite, purges caches, validates
                                     userProps.xml & checks CC/maxfiles
                                 • [2] Diagnostics & GitHub Support:
                                   - Toggles Debug Mode (debug_boot.log)
                                   - Generates anonymized github_support_report.md
                                     (copied to clipboard automatically)
   - clean_sims2_cache.command : Interactive maintenance menu [1 / 2 / 3 / 4]:
                                 [1] Clean caches (Default on Enter — no sudo)
                                 [2] Reset display mode in userProps.xml (60 Hz)
                                 [3] Check Mods/CC (.package/.zip) & maxfiles
                                 [4] Quit
   - restore_sims2.command     : Verifies Sims2XP_Exe.backup integrity, restores
                                 original binary & Graphics Rules.sgr.backup
                                 atomically, removes libsims2_trackpad.dylib, and
                                 removes managed limit.maxfiles.plist if installed
                                 by patch.

2. BEFORE YOU START: WHAT MACOS WILL ASK (HONESTY & BEGINNER NOTES)
   macOS protects users with several security prompts on first run:
   a) Gatekeeper block ("Apple could not verify..."): Normal for unsigned
      community .command tools (see Step 4 below).
   b) INVISIBLE Password in Terminal (100% NORMAL!):
      When Terminal says "Password:", type your normal Mac login password blind
      and press Enter. ZERO characters (not even '*') or cursor movement appear
      on screen. Your keyboard is NOT frozen — macOS hides all keystrokes here.
   c) "Terminal wants access to control Finder": Click "Allow" so your existing
      Mac App Store Sandbox saves can be duplicated safely without overwriting.

3. STEP-BY-STEP INSTALLATION
   Step 1: Extract the downloaded .zip archive completely (e.g. in Downloads).
   Step 2: Quit The Sims 2 completely (Cmd+Q) and make sure The Sims 2.app is in
           /Applications or ~/Applications.
   Step 3: Double-click "patch_sims2.command".
   Step 4: IF BLOCKED BY GATEKEEPER:
           Click "Done"/"OK" -> open System Settings -> Privacy & Security ->
           scroll down to Security -> click "Open Anyway" next to
           patch_sims2.command (visible ~1h) -> click "Open" -> authenticate.
   Step 5: In Terminal, read the pre-sudo notice, type your Mac Admin password
           blindly (nothing appears while typing!), and press Enter.
   Step 6: Click "Allow" if macOS asks Terminal to control Finder.
   Step 7: If maxfiles hard limit < 10240, optionally answer "y" to install the
           managed /Library/LaunchDaemons/limit.maxfiles.plist (press Enter = No).
   Step 8: When "PATCH COMPLETE (v1.4.0)" appears, launch The Sims 2 normally!

4. PRACTICAL TROUBLESHOOTING CASES
   - Case 1 (Gatekeeper block): Follow Step 4 above for any first-run .command.
   - Case 2 (Password typing appears blank / "Sorry, try again"): Blank screen
     typing is normal. Check Caps Lock & keyboard layout; use your Mac login
     password (not Apple ID unless identical).
   - Case 3 (Standard non-Admin account): Switch to an Admin account on the Mac
     or grant Admin rights in System Settings -> Users & Groups.
   - Case 4 (Finder Automation denied -1743 OR Container permissions -5000):
     For -1743: enable System Settings -> Privacy & Security -> Automation ->
     Terminal -> Finder, then re-run patch_sims2.command.
     For -5000 ("do not have permission" after clicking Allow): macOS blocks
     scripted reads from App Store Sandbox containers. Open Finder (Cmd+Shift+G)
     at ~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/
     and drag Neighborhoods/Downloads into ~/Library/Application Support/Aspyr/The Sims 2/
     (or grant Full Disk Access to Terminal). Note: if you already have active
     saves in Application Support, you can still launch normally.
   - Case 4B (Diagnostics & GitHub Support): Normal game sessions write zero log
     files (crash_report.log is written only if a crash occurs). Run
     patch_sims2.command -> [2] Diagnostic & Support GitHub to toggle Debug Mode
     or generate ~/Library/Logs/Sims2-Crash-Patch/github_support_report.md
     (copied to clipboard with /Users/... anonymized to ~).
   - Case 5 (Old saves appear missing -> Sandbox Backup folder): Check
     ~/Library/Application Support/Aspyr/ for "The Sims 2 (Sandbox Backup ...)"
     and merge Neighborhoods/Downloads while the game is closed.
   - Case 6 (Crash after unplugging external monitor / bad resolution): Run
     clean_sims2_cache.command -> option [2] (creates userProps.xml.backup
     before resetting to your current display mode at 60 Hz).
   - Case 7 (CC not showing or heavy-CC crashes): Run clean_sims2_cache.command
     -> option [1] (clean caches) and option [3] (warns on leftover .zip/.rar/.7z
     and checks the game's 10,240 open-file cap).
   - Case 8 ("Permission denied" / opens in TextEdit): Extract via Archive
     Utility first; if needed run `chmod +x /path/to/patch_sims2.command`.
   - Case 9 (Full restore / App Store Sandbox): Run restore_sims2.command, or
     delete The Sims 2.app and re-download free from the Mac App Store (files in
     ~/Library/Application Support/Aspyr/ are never deleted, though the Sandbox
     App Store version reads ~/Library/Containers/com.aspyr.sims2.appstore/).

5. TECHNICAL & LEGAL NOTICE
   - Dual binary patch in FUN_1000fe510 (0xfe6dc + 0xfe741), zero Xcode CLT.
   - Community software preservation under EU Directive 2009/24/EC Art. 5(1).
================================================================================
