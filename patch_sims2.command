#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — ProMotion 120Hz Patch, Save Migration & Cache Fix
# Version: 1.2.1 (Option A — Non-Sandbox Architecture)
# Target:  /Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe
# Zero Xcode / Python dependency: uses native /usr/bin/perl, codesign & Finder.
# ==============================================================================

set -u

APP_PATH="/Applications/The Sims 2.app"
EXE_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe"
BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup"
ALT_BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup_original"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pause_exit() {
    local code="${1:-0}"
    echo ""
    read -r -p "Appuyez sur Entrée pour fermer / Press Enter to close..."
    exit "$code"
}

# Resolve the real logged-in macOS user and their real $HOME (never /var/root)
resolve_real_user() {
    if [ "$(id -u)" -eq 0 ]; then
        REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || stat -f '%Su' /dev/console 2>/dev/null || echo '')}"
    else
        REAL_USER="$(id -un)"
    fi

    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        REAL_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo '')"
    fi

    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        echo -e "${RED}[-] Erreur / Error:${NC} Impossible de déterminer l'utilisateur courant (non-root)."
        pause_exit 1
    fi

    REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    if [ -z "$REAL_HOME" ] || [ ! -d "$REAL_HOME" ]; then
        REAL_HOME="$(eval echo "~$REAL_USER")"
    fi

    if [ -z "$REAL_HOME" ] || [ "$REAL_HOME" = "/var/root" ] || [ ! -d "$REAL_HOME" ]; then
        echo -e "${RED}[-] Erreur / Error:${NC} Répertoire personnel invalide ($REAL_HOME)."
        pause_exit 1
    fi
}

run_as_real_user() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

echo -e "${CYAN}${BOLD}"
echo "========================================================================"
echo "  The Sims 2: Super Collection — ProMotion 120Hz Patch (v1.2.1)         "
echo "========================================================================"
echo -e "${NC}"

resolve_real_user

ASPYR_BASE_DIR="$REAL_HOME/Library/Application Support/Aspyr"
TARGET_DATA_DIR="$ASPYR_BASE_DIR/The Sims 2"

echo -e "[i] Session utilisateur détectée / Active user: ${BOLD}$REAL_USER${NC} ($REAL_HOME)"
echo ""

# 1. Verify application presence
if [ ! -f "$EXE_PATH" ]; then
    echo -e "${RED}[-] Erreur / Error:${NC} Jeu introuvable / Game not found at:"
    echo "    $EXE_PATH"
    echo "    Vérifiez que The Sims 2 est installé dans /Applications."
    pause_exit 1
fi

# 2. Verify the game is not currently running
if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Attention / Warning:${NC} Le jeu est actuellement en cours d'exécution."
    echo "    Veuillez fermer Les Sims 2 avant d'appliquer le patch."
    echo "    Please quit The Sims 2 before running this patch."
    pause_exit 1
fi

# 3. Selective privilege elevation ONLY for /Applications bundle modifications
echo -e "${BOLD}[1/5] Autorisation administrateur / Administrator authorization${NC}"
echo "      Requise uniquement pour modifier l'application dans /Applications."
echo "      Required solely to patch the application bundle in /Applications."
echo ""

if ! sudo -v; then
    echo -e "${RED}[-] Échec d'authentification / Authentication failed.${NC}"
    pause_exit 1
fi

# 4. Verified Pristine Backup & Atomic Dual Idempotent Binary Patch (/usr/bin/perl)
echo ""
echo -e "${BOLD}[2/5] Sauvegarde vérifiée & Double Patch Binaire 60 Hz / 60 Hz Patch...${NC}"

if ! sudo /usr/bin/perl - "$EXE_PATH" "$BACKUP_PATH" "$ALT_BACKUP_PATH" <<'PERLEOF'
use strict;
use warnings;
use File::Copy qw(copy);

my ($exe_path, $backup_path, $alt_backup_path) = @ARGV;

sub count_occurrences {
    my ($haystack, $needle) = @_;
    my $count = 0;
    my $pos = -1;
    while (($pos = index($haystack, $needle, $pos + 1)) != -1) {
        $count++;
    }
    return $count;
}

sub read_raw {
    my ($p) = @_;
    open(my $fh, "<:raw", $p) or die "Impossible de lire $p / Cannot read $p: $!\n";
    local $/;
    my $buf = <$fh>;
    close($fh);
    return $buf;
}

sub write_atomic {
    my ($p, $buf, $mode) = @_;
    my $tmp = "$p.tmp.$$";
    open(my $out, ">:raw", $tmp) or die "Impossible de créer $tmp / Cannot create temp file: $!\n";
    print {$out} $buf or die "Erreur d'écriture dans $tmp / Write failed: $!\n";
    close($out) or die "Erreur de fermeture $tmp / Close failed: $!\n";
    chmod($mode, $tmp) or die "chmod failed on $tmp: $!\n";
    if (!rename($tmp, $p)) {
        unlink($tmp);
        die "Échec du remplacement atomique vers $p / Atomic rename failed: $!\n";
    }
}

# Dual anchored binary patch definitions:
# - Patch 1 (0xfe6dc): Locks Quartz _CGDisplayModeGetRefreshRate conversion to 60 Hz (0x3c) in R15D.
# - Patch 2 (0xfe73b / 0xfe741): Secondary safety lock in _CVDisplayLink fallback (NOPs CMOVNE R15D, EAX).
my $orig1 = pack("H*", "f20f1045d0f2440f2cf84889df");
my $repl1 = pack("H*", "41bf3c000000909090904889df");
my $orig2 = pack("H*", "41bf3c000000440f45f8c70300000000");
my $repl2 = pack("H*", "41bf3c00000090909090c70300000000");

sub is_pristine {
    my ($buf) = @_;
    return (
        count_occurrences($buf, $orig1) == 1 &&
        count_occurrences($buf, $orig2) == 1 &&
        count_occurrences($buf, $repl1) == 0 &&
        count_occurrences($buf, $repl2) == 0
    );
}

my $data = read_raw($exe_path);

# Verify or create Sims2XP_Exe.backup ONLY from a verified pristine unpatched binary
if (-e $backup_path) {
    my $bak_data = read_raw($backup_path);
    if (is_pristine($bak_data)) {
        print "[i] Sauvegarde Sims2XP_Exe.backup existante vérifiée (intègre) / Pristine backup verified.\n";
    } elsif (-e $alt_backup_path && is_pristine(read_raw($alt_backup_path))) {
        print "[+] Réparation de Sims2XP_Exe.backup depuis backup_original intègre...\n";
        write_atomic($backup_path, read_raw($alt_backup_path), 0755);
    } else {
        print "[!] Avertissement : Sims2XP_Exe.backup existe mais contient déjà des octets modifiés.\n";
    }
} else {
    if (is_pristine($data)) {
        print "[+] Empreintes d'origine vérifiées : création de Sims2XP_Exe.backup...\n";
        write_atomic($backup_path, $data, 0755);
    } elsif (-e $alt_backup_path && is_pristine(read_raw($alt_backup_path))) {
        print "[+] Création de Sims2XP_Exe.backup depuis backup_original vérifié...\n";
        write_atomic($backup_path, read_raw($alt_backup_path), 0755);
    } else {
        print "[!] Attention : Le binaire actuel est déjà modifié et aucune sauvegarde vierge n'a été trouvée.\n";
        print "    Sims2XP_Exe.backup n'a pas été créé pour ne pas archiver un binaire déjà patché.\n";
    }
}

my @patches = (
    [ "Patch 1 (0xfe6dc - Primary 60Hz Lock)",  $orig1, $repl1 ],
    [ "Patch 2 (0xfe741 - Fallback Safety Lock)", $orig2, $repl2 ]
);

my $changed = 0;

for my $entry (@patches) {
    my ($label, $orig, $repl) = @$entry;
    my $orig_count = count_occurrences($data, $orig);
    my $repl_count = count_occurrences($data, $repl);

    if ($repl_count == 1 && $orig_count == 0) {
        print "[i] $label : Déjà appliqué (idempotent) / Already applied.\n";
    } elsif ($orig_count == 1 && $repl_count == 0) {
        my $offset = index($data, $orig);
        substr($data, $offset, length($orig), $repl);
        printf("[+] %s : Patch appliqué à l'offset 0x%x !\n", $label, $offset);
        $changed = 1;
    } else {
        print STDERR "[-] ERREUR : Empreinte introuvable ou ambiguë pour $label (orig=$orig_count, patched=$repl_count).\n";
        print STDERR "[-] Binaire non modifié pour protéger votre installation.\n";
        exit 1;
    }
}

if ($changed) {
    write_atomic($exe_path, $data, 0755);
    print "[+] Binaire mis à jour de façon atomique sur le disque / Binary atomically updated.\n";
} else {
    print "[i] Binaire déjà patché — aucune écriture disque requise / Binary already patched.\n";
}
PERLEOF
then
    echo -e "${RED}[-] Le patch binaire a échoué / Binary patch failed.${NC}"
    pause_exit 1
fi
PATCH_STATUS="OK (60 Hz verrouillé / locked)"

# 5. Ad-hoc Local Code Signing
echo ""
echo -e "${BOLD}[3/5] Re-signature locale ad-hoc (codesign)...${NC}"
if sudo /usr/bin/codesign --force --deep --sign - "$APP_PATH"; then
    echo -e "${GREEN}[+] Signature locale appliquée / Ad-hoc signature applied.${NC}"
else
    echo -e "${RED}[-] Erreur lors du codesign / codesign failed.${NC}"
    pause_exit 1
fi

# 6. Safe, Non-Overwriting Save Migration (Sandbox -> Application Support)
echo ""
echo -e "${BOLD}[4/5] Vérification & Migration sécurisée des sauvegardes / Safe Save Migration...${NC}"
echo "      Dossier actif : ~/Library/Application Support/Aspyr/The Sims 2/"

MIGRATION_STATUS=""

# Check if Target already exists and is non-empty
TARGET_EXISTS_NONEMPTY=0
if [ -d "$TARGET_DATA_DIR" ] && [ -n "$(ls -A "$TARGET_DATA_DIR" 2>/dev/null)" ]; then
    TARGET_EXISTS_NONEMPTY=1
fi

# Check if a timestamped Sandbox Backup folder already exists from a previous run
EXISTING_SANDBOX_BACKUP="$(find "$ASPYR_BASE_DIR" -maxdepth 1 -type d -name "The Sims 2 (Sandbox Backup*)" 2>/dev/null | head -n 1)"

if [ "$TARGET_EXISTS_NONEMPTY" -eq 1 ] && [ -n "$EXISTING_SANDBOX_BACKUP" ]; then
    echo -e "${GREEN}[i] Dossier Application Support actif et sauvegarde Sandbox déjà archivée :${NC}"
    echo "    -> $(basename "$EXISTING_SANDBOX_BACKUP")"
    echo "    Aucune donnée écrasée / No data overwritten."
    MIGRATION_STATUS="Intactes + Archive Sandbox conservée / Active + Sandbox backup kept"
else
    # Determine destination folder:
    # - Mode DIRECT: Target does not exist (or is empty) -> copy directly into "The Sims 2"
    # - Mode BACKUP: Target already exists -> copy into "The Sims 2 (Sandbox Backup YYYY-MM-DD)" without touching active folder
    TODAY_STAMP="$(date +%Y-%m-%d)"
    BACKUP_FOLDER_NAME="The Sims 2 (Sandbox Backup $TODAY_STAMP)"
    if [ -e "$ASPYR_BASE_DIR/$BACKUP_FOLDER_NAME" ]; then
        BACKUP_FOLDER_NAME="The Sims 2 (Sandbox Backup $(date +%Y-%m-%d_%H%M%S))"
    fi

    if [ "$TARGET_EXISTS_NONEMPTY" -eq 0 ]; then
        MIGRATE_MODE="DIRECT"
        DEST_FOLDER_NAME="The Sims 2"
    else
        MIGRATE_MODE="BACKUP"
        DEST_FOLDER_NAME="$BACKUP_FOLDER_NAME"
    fi

    run_as_real_user mkdir -p "$ASPYR_BASE_DIR"

    MIGRATE_RESULT=$(run_as_real_user /usr/bin/osascript - "$DEST_FOLDER_NAME" <<'OSAEOF'
on run argv
    set destFolderName to item 1 of argv
    tell application "Finder"
        with timeout of 3600 seconds
            try
                set homePath to (path to home folder as text)
                set sourcePath to homePath & "Library:Containers:com.aspyr.sims2.appstore:Data:Library:Application Support:Aspyr:The Sims 2:"
                set aspyrBasePath to homePath & "Library:Application Support:Aspyr:"

                if not (exists folder sourcePath) then
                    return "NO_SOURCE"
                end if

                set sourceFolder to folder sourcePath
                if (count of items of sourceFolder) is 0 then
                    return "EMPTY_SOURCE"
                end if

                set aspyrFolder to folder aspyrBasePath
                if not (exists folder destFolderName of aspyrFolder) then
                    make new folder at aspyrFolder with properties {name:destFolderName}
                end if
                set destFolder to folder destFolderName of aspyrFolder

                -- Strictly no overwrite clause so no existing user file is ever overwritten
                duplicate every item of sourceFolder to destFolder
                return "OK"
            on error errMsg
                return "ERROR:" & errMsg
            end try
        end timeout
    end tell
end run
OSAEOF
    )

    case "$MIGRATE_RESULT" in
        OK)
            if [ "$MIGRATE_MODE" = "DIRECT" ]; then
                echo -e "${GREEN}[+] Sauvegardes, quartiers et mods copiés depuis le Sandbox vers Application Support !${NC}"
                echo "    (Les fichiers d'origine dans le conteneur Sandbox restent intacts.)"
                MIGRATION_STATUS="Migrées vers Application Support / Migrated to Application Support"
            else
                echo -e "${YELLOW}[!] Un dossier 'The Sims 2' existait déjà dans Application Support.${NC}"
                echo -e "${GREEN}[+] Pour ne rien écraser, vos anciennes données Sandbox ont été sauvegardées dans :${NC}"
                echo -e "    ${BOLD}~/Library/Application Support/Aspyr/$DEST_FOLDER_NAME/${NC}"
                echo "    (An existing 'The Sims 2' folder was found; your Sandbox data was safely"
                echo "     duplicated into '$DEST_FOLDER_NAME' without overwriting any active files.)"
                MIGRATION_STATUS="Archivées dans '$DEST_FOLDER_NAME' (zéro écrasement)"
            fi
            ;;
        NO_SOURCE|EMPTY_SOURCE)
            if [ "$TARGET_EXISTS_NONEMPTY" -eq 1 ]; then
                echo -e "${GREEN}[i] Sauvegardes Application Support conservées (aucun conteneur Sandbox à migrer).${NC}"
                MIGRATION_STATUS="Sauvegardes existantes conservées / Existing saves kept"
            else
                echo -e "${YELLOW}[i] Aucune sauvegarde antérieure détectée (nouvelle installation).${NC}"
                MIGRATION_STATUS="Nouvelle installation (vierge) / Fresh install"
            fi
            ;;
        ERROR:*)
            echo -e "${YELLOW}[!] Avertissement lors de la copie Finder:${NC} ${MIGRATE_RESULT#ERROR:}"
            MIGRATION_STATUS="Avertissement Finder (voir message ci-dessus)"
            ;;
    esac
fi

# 7. Dual-Location Cache Purge (Application Support POSIX + Sandbox Finder Automation)
echo ""
echo -e "${BOLD}[5/5] Double purge des caches corrompus / Dual-location cache purge...${NC}"

CACHE_FILES=("Groups.cache" "Accessory.cache" "cAstGroupCache.package")
POSIX_DELETED=()

if [ -d "$TARGET_DATA_DIR" ]; then
    for cf in "${CACHE_FILES[@]}"; do
        if [ -e "$TARGET_DATA_DIR/$cf" ]; then
            run_as_real_user rm -f "$TARGET_DATA_DIR/$cf"
            POSIX_DELETED+=("$cf")
        fi
    done
fi

if [ ${#POSIX_DELETED[@]} -gt 0 ]; then
    echo -e "${GREEN}[+] Application Support : Caches supprimés (rm -f) ->${NC} ${POSIX_DELETED[*]}"
else
    echo -e "${GREEN}[+] Application Support : Aucun cache corrompu (propre / clean).${NC}"
fi

SANDBOX_CACHE_RESULT=$(run_as_real_user /usr/bin/osascript <<'OSAEOF'
tell application "Finder"
    with timeout of 300 seconds
        set oldDelims to AppleScript's text item delimiters
        try
            set containerPath to (path to home folder as text) & "Library:Containers:com.aspyr.sims2.appstore:Data:Library:Application Support:Aspyr:The Sims 2:"
            if not (exists folder containerPath) then
                set AppleScript's text item delimiters to oldDelims
                return "NO_CONTAINER"
            end if

            set targetFolder to folder containerPath
            set cacheFiles to {"Groups.cache", "Accessory.cache", "cAstGroupCache.package"}
            set deletedList to {}

            repeat with fName in cacheFiles
                if exists file fName of targetFolder then
                    delete file fName of targetFolder
                    set end of deletedList to (fName as text)
                end if
            end repeat

            if (count of deletedList) is 0 then
                set AppleScript's text item delimiters to oldDelims
                return "ALREADY_CLEAN"
            else
                set AppleScript's text item delimiters to ", "
                set resStr to deletedList as text
                set AppleScript's text item delimiters to oldDelims
                return "DELETED:" & resStr
            end if
        on error errMsg
            set AppleScript's text item delimiters to oldDelims
            return "ERROR:" & errMsg
        end try
    end timeout
end tell
OSAEOF
)

case "$SANDBOX_CACHE_RESULT" in
    DELETED:*)
        echo -e "${GREEN}[+] Conteneur Sandbox   : Caches résiduels placés dans la Corbeille ->${NC} ${SANDBOX_CACHE_RESULT#DELETED:}"
        ;;
    ALREADY_CLEAN)
        echo -e "${GREEN}[+] Conteneur Sandbox   : Déjà propre / Already clean.${NC}"
        ;;
    NO_CONTAINER)
        echo -e "${GREEN}[+] Conteneur Sandbox   : Aucun conteneur existant / None.${NC}"
        ;;
    ERROR:*)
        echo -e "${YELLOW}[!] Conteneur Sandbox   : Avertissement (${SANDBOX_CACHE_RESULT#ERROR:})${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}${BOLD}"
echo "========================================================================"
echo "  INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.2.1) !         "
echo "========================================================================"
echo -e "${NC}"
echo -e "  • ${BOLD}Patch Binaire 120 Hz :${NC} $PATCH_STATUS"
echo -e "  • ${BOLD}Sauvegardes / Saves  :${NC} $MIGRATION_STATUS"
echo -e "  • ${BOLD}Dossier Données/Mods :${NC} ~/Library/Application Support/Aspyr/The Sims 2/"
echo -e "  • ${BOLD}Purge des Caches     :${NC} Double assainissement effectué (Actif + Sandbox)"
echo ""
echo "  👉 Vous pouvez maintenant démarrer Les Sims 2 depuis le Launchpad"
echo "     ou votre dossier Applications (en gardant votre écran Mac à 120 Hz) !"
echo ""
echo "  👉 You can now launch The Sims 2 from Launchpad or Applications"
echo "     while keeping your Mac display at smooth 120 Hz ProMotion!"
echo "========================================================================"

pause_exit 0
