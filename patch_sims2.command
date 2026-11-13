#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — ProMotion 120Hz Patch, Save Migration & Cache Fix
# Version: 1.2.2 (Option A — Non-Sandbox Architecture)
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

REAL_USER=""
REAL_UID=""
REAL_HOME=""
MIGRATION_STATUS=""
MIGRATION_FAILED=0
CACHE_STATUS=""

pause_exit() {
    local code="${1:-0}"
    echo ""
    read -r -p "Appuyez sur Entrée pour fermer / Press Enter to close..."
    exit "$code"
}

# Resolve the real logged-in macOS user, UID, and $HOME (never /var/root)
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
        return 1
    fi

    REAL_UID="$(id -u "$REAL_USER" 2>/dev/null || echo '')"
    if [ -z "$REAL_UID" ] || ! [ "$REAL_UID" -gt 0 ] 2>/dev/null; then
        echo -e "${RED}[-] Erreur / Error:${NC} UID utilisateur invalide pour $REAL_USER ($REAL_UID)."
        return 1
    fi

    REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
    if [ -z "$REAL_HOME" ] || [ ! -d "$REAL_HOME" ]; then
        REAL_HOME="$(eval echo "~$REAL_USER")"
    fi

    if [ -z "$REAL_HOME" ] || [ "$REAL_HOME" = "/var/root" ] || [ ! -d "$REAL_HOME" ]; then
        echo -e "${RED}[-] Erreur / Error:${NC} Répertoire personnel invalide ($REAL_HOME)."
        return 1
    fi

    return 0
}

# Run a command in the real user's Aqua/WindowServer session when invoked via sudo
run_as_real_user() {
    if [ "$(id -u)" -eq 0 ]; then
        if [ -n "${REAL_UID:-}" ] && /bin/launchctl print "user/$REAL_UID" >/dev/null 2>&1; then
            /bin/launchctl asuser "$REAL_UID" /usr/bin/sudo -H -u "$REAL_USER" "$@"
        else
            /usr/bin/sudo -H -u "$REAL_USER" "$@"
        fi
    else
        "$@"
    fi
}

run_privileged() {
    local scope_target="$1"
    shift
    if [ "${SIMS2_LIB_ONLY:-0}" = "1" ]; then
        case "$scope_target" in
            /tmp/*|/var/folders/*|/private/tmp/*|/private/var/folders/*)
                "$@"
                return $?
                ;;
        esac
    fi
    sudo "$@"
}

# Check if directory contains real game data (ignoring Finder metadata files)
dir_has_real_entries() {
    local dir="$1"
    [ -d "$dir" ] || return 1
    local first_entry
    first_entry="$(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' ! -name '.localized' ! -name '._*' 2>/dev/null | head -n 1)"
    [ -n "$first_entry" ]
}

is_tcc_automation_error() {
    local msg="$1"
    printf '%s\n' "$msg" | grep -qiE '(-1743|1743|not authorized to send apple events|apple ?event|non autoris)'
}

print_finder_automation_help() {
    echo "    -> Permission Automatisation Finder requise / Finder Automation permission required."
    echo "    -> Réglages Système -> Confidentialité et sécurité -> Automatisation -> Terminal -> activez Finder."
    echo "    -> System Settings -> Privacy & Security -> Automation -> Terminal -> enable Finder."
}

sign_and_verify_app() {
    local target_app="${1:-$APP_PATH}"
    local cs_out cs_rc verify_out verify_rc

    cs_out="$(run_privileged "$target_app" /usr/bin/codesign --force --deep --sign - "$target_app" 2>&1)"
    cs_rc=$?

    if [ "$cs_rc" -ne 0 ] && printf '%s\n' "$cs_out" | grep -qiE '(detritus|Finder information|resource fork|AppleDouble)'; then
        echo -e "${YELLOW}[!] Détection d'attributs Finder parasites (detritus) — nettoyage sécurisé en cours...${NC}"
        run_privileged "$target_app" /usr/bin/xattr -dr com.apple.FinderInfo "$target_app" >/dev/null 2>&1 || true
        run_privileged "$target_app" /usr/bin/xattr -dr com.apple.ResourceFork "$target_app" >/dev/null 2>&1 || true
        run_privileged "$target_app" /usr/bin/xattr -dr com.apple.quarantine "$target_app" >/dev/null 2>&1 || true
        run_privileged "$target_app" /usr/sbin/dot_clean -m "$target_app" >/dev/null 2>&1 || true
        cs_out="$(run_privileged "$target_app" /usr/bin/codesign --force --deep --sign - "$target_app" 2>&1)"
        cs_rc=$?
    fi

    if [ "$cs_rc" -ne 0 ]; then
        echo -e "${RED}[-] Erreur lors du codesign / codesign failed:${NC}"
        [ -n "$cs_out" ] && echo "$cs_out"
        local leftover_tmp
        leftover_tmp="$(find "$target_app/Contents/MacOS" -maxdepth 1 -name 'Sims2XP_Exe.tmp.*' 2>/dev/null | head -n 1)"
        if [ -n "$leftover_tmp" ]; then
            echo -e "${YELLOW}[!] Fichier temporaire résiduel détecté :${NC} $leftover_tmp"
        fi
        return 1
    fi

    verify_out="$(run_privileged "$target_app" /usr/bin/codesign --verify --deep --strict "$target_app" 2>&1)"
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ]; then
        echo -e "${RED}[-] Échec de vérification stricte de la signature (codesign --verify --strict) :${NC}"
        [ -n "$verify_out" ] && echo "$verify_out"
        return 1
    fi

    return 0
}

handle_migration_result() {
    local result="$1"
    local rc="$2"
    local migrate_mode="$3"
    local target_nonempty="$4"
    local dest_folder="$5"
    MIGRATION_FAILED=0

    if [ "$rc" -ne 0 ]; then
        case "$result" in
            ERROR:*) ;;
            *) result="ERROR:${result:-osascript exit code $rc}" ;;
        esac
    fi

    case "$result" in
        OK)
            if [ "$migrate_mode" = "DIRECT" ]; then
                echo -e "${GREEN}[+] Sauvegardes, quartiers et mods copiés depuis le Sandbox vers Application Support !${NC}"
                echo "    (Les fichiers d'origine dans le conteneur Sandbox restent intacts.)"
                MIGRATION_STATUS="Migrées vers Application Support / Migrated to Application Support"
            else
                echo -e "${YELLOW}[!] Un dossier 'The Sims 2' existait déjà dans Application Support.${NC}"
                echo -e "${GREEN}[+] Pour ne rien écraser, vos anciennes données Sandbox ont été sauvegardées dans :${NC}"
                echo -e "    ${BOLD}~/Library/Application Support/Aspyr/$dest_folder/${NC}"
                echo "    (An existing 'The Sims 2' folder was found; your Sandbox data was safely"
                echo "     duplicated into '$dest_folder' without overwriting any active files.)"
                MIGRATION_STATUS="Archivées dans '$dest_folder' (zéro écrasement)"
            fi
            ;;
        NO_SOURCE|EMPTY_SOURCE)
            if [ "$target_nonempty" -eq 1 ]; then
                echo -e "${GREEN}[i] Sauvegardes Application Support conservées (aucun conteneur Sandbox à migrer).${NC}"
                MIGRATION_STATUS="Sauvegardes existantes conservées / Existing saves kept"
            else
                echo -e "${YELLOW}[i] Aucune sauvegarde antérieure détectée (nouvelle installation).${NC}"
                MIGRATION_STATUS="Nouvelle installation (vierge) / Fresh install"
            fi
            ;;
        ERROR:*)
            local err_msg="${result#ERROR:}"
            MIGRATION_FAILED=1
            echo -e "${YELLOW}[!] Avertissement lors de la copie Finder:${NC} $err_msg"
            if is_tcc_automation_error "$err_msg"; then
                print_finder_automation_help
                MIGRATION_STATUS="Permission Finder refusée (-1743) / Finder Automation denied"
            else
                MIGRATION_STATUS="Avertissement Finder (voir message ci-dessus)"
            fi
            ;;
        *)
            MIGRATION_FAILED=1
            echo -e "${YELLOW}[!] Réponse Finder inattendue / Unexpected Finder response:${NC} ${result:-<vide / empty>} (code $rc)"
            if is_tcc_automation_error "$result"; then
                print_finder_automation_help
                MIGRATION_STATUS="Permission Finder refusée (-1743) / Finder Automation denied"
            else
                MIGRATION_STATUS="Erreur Finder inattendue (code $rc)"
            fi
            ;;
    esac
}

handle_sandbox_cache_result() {
    local result="$1"
    local rc="$2"

    if [ "$rc" -ne 0 ]; then
        case "$result" in
            ERROR:*) ;;
            *) result="ERROR:${result:-osascript exit code $rc}" ;;
        esac
    fi

    case "$result" in
        DELETED:*)
            echo -e "${GREEN}[+] Conteneur Sandbox   : Caches résiduels placés dans la Corbeille ->${NC} ${result#DELETED:}"
            CACHE_STATUS="Double assainissement effectué (Actif + Sandbox)"
            ;;
        ALREADY_CLEAN)
            echo -e "${GREEN}[+] Conteneur Sandbox   : Déjà propre / Already clean.${NC}"
            CACHE_STATUS="Double assainissement effectué (Actif + Sandbox)"
            ;;
        NO_CONTAINER)
            echo -e "${GREEN}[+] Conteneur Sandbox   : Aucun conteneur existant / None.${NC}"
            CACHE_STATUS="Actif assaini (aucun conteneur Sandbox)"
            ;;
        ERROR:*)
            local err_msg="${result#ERROR:}"
            echo -e "${YELLOW}[!] Conteneur Sandbox   : Avertissement ($err_msg)${NC}"
            if is_tcc_automation_error "$err_msg"; then
                print_finder_automation_help
                CACHE_STATUS="Actif traité ; Sandbox bloqué (-1743 Automatisation Finder)"
            else
                CACHE_STATUS="Actif traité ; Sandbox non vérifié (avertissement Finder)"
            fi
            ;;
        *)
            echo -e "${YELLOW}[!] Conteneur Sandbox   : Réponse inattendue (${result:-<vide / empty>}, code $rc)${NC}"
            if is_tcc_automation_error "$result"; then
                print_finder_automation_help
                CACHE_STATUS="Actif traité ; Sandbox bloqué (-1743 Automatisation Finder)"
            else
                CACHE_STATUS="Actif traité ; Sandbox non vérifié (code $rc)"
            fi
            ;;
    esac
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2: Super Collection — ProMotion 120Hz Patch (v1.2.2)         "
    echo "========================================================================"
    echo -e "${NC}"

    if ! resolve_real_user; then
        pause_exit 1
    fi

    local ASPYR_BASE_DIR="$REAL_HOME/Library/Application Support/Aspyr"
    local TARGET_DATA_DIR="$ASPYR_BASE_DIR/The Sims 2"

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

my ($exe_path, $backup_path, $alt_backup_path) = @ARGV;

my $active_tmp;
END {
    unlink($active_tmp) if defined $active_tmp && -e $active_tmp;
}

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
    $active_tmp = $tmp;
    open(my $out, ">:raw", $tmp) or do {
        $active_tmp = undef;
        die "Impossible de créer $tmp / Cannot create temp file: $!\n";
    };
    if (!print {$out} $buf) {
        my $err = $!;
        close($out);
        unlink($tmp);
        $active_tmp = undef;
        die "Erreur d'écriture dans $tmp / Write failed: $err\n";
    }
    if (!close($out)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "Erreur de fermeture $tmp / Close failed: $err\n";
    }
    if (!chmod($mode, $tmp)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "chmod failed on $tmp: $err\n";
    }
    if (!rename($tmp, $p)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "Échec du remplacement atomique vers $p / Atomic rename failed: $err\n";
    }
    $active_tmp = undef;
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
    } elsif (is_pristine($data)) {
        print "[+] Réparation de Sims2XP_Exe.backup depuis le binaire vierge actuel / Repairing backup from pristine binary...\n";
        write_atomic($backup_path, $data, 0755);
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
    local PATCH_STATUS="OK (60 Hz verrouillé / locked)"

    # 5. Ad-hoc Local Code Signing + Strict Verification
    echo ""
    echo -e "${BOLD}[3/5] Re-signature locale ad-hoc & vérification (codesign)...${NC}"
    if sign_and_verify_app "$APP_PATH"; then
        echo -e "${GREEN}[+] Signature locale appliquée et vérifiée (--strict) / Ad-hoc signature applied & verified.${NC}"
    else
        pause_exit 1
    fi

    # 6. Safe, Non-Overwriting Save Migration (Sandbox -> Application Support)
    echo ""
    echo -e "${BOLD}[4/5] Vérification & Migration sécurisée des sauvegardes / Safe Save Migration...${NC}"
    echo "      Dossier actif : ~/Library/Application Support/Aspyr/The Sims 2/"

    MIGRATION_STATUS=""

    # Check if Target already exists and has real content (ignoring .DS_Store / Finder metadata)
    local TARGET_EXISTS_NONEMPTY=0
    if dir_has_real_entries "$TARGET_DATA_DIR"; then
        TARGET_EXISTS_NONEMPTY=1
    fi

    # Check if a timestamped Sandbox Backup folder already exists from a previous run
    local EXISTING_SANDBOX_BACKUP
    EXISTING_SANDBOX_BACKUP="$(find "$ASPYR_BASE_DIR" -maxdepth 1 -type d -name "The Sims 2 (Sandbox Backup*)" 2>/dev/null | head -n 1)"

    if [ "$TARGET_EXISTS_NONEMPTY" -eq 1 ] && [ -n "$EXISTING_SANDBOX_BACKUP" ]; then
        echo -e "${GREEN}[i] Dossier Application Support actif et sauvegarde Sandbox déjà archivée :${NC}"
        echo "    -> $(basename "$EXISTING_SANDBOX_BACKUP")"
        echo "    Aucune donnée écrasée / No data overwritten."
        MIGRATION_STATUS="Intactes + Archive Sandbox conservée / Active + Sandbox backup kept"
    else
        local TODAY_STAMP BACKUP_FOLDER_NAME MIGRATE_MODE DEST_FOLDER_NAME
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

        local MIGRATE_RESULT MIGRATE_RC
        MIGRATE_RESULT="$(run_as_real_user /usr/bin/osascript - "$DEST_FOLDER_NAME" 2>&1 <<'OSAEOF'
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
                set sourceItems to every item of sourceFolder
                if (count of sourceItems) is 0 then
                    return "EMPTY_SOURCE"
                end if

                set aspyrFolder to folder aspyrBasePath
                if not (exists folder destFolderName of aspyrFolder) then
                    make new folder at aspyrFolder with properties {name:destFolderName}
                end if
                set destFolder to folder destFolderName of aspyrFolder

                -- Strictly no overwrite clause; skip Finder metadata files to avoid .DS_Store collisions
                set copiedCount to 0
                repeat with anItem in sourceItems
                    set itemName to name of anItem
                    if itemName is not ".DS_Store" and itemName is not ".localized" and itemName does not start with "._" then
                        duplicate anItem to destFolder
                        set copiedCount to copiedCount + 1
                    end if
                end repeat

                if copiedCount is 0 then
                    return "EMPTY_SOURCE"
                end if
                return "OK"
            on error errMsg
                return "ERROR:" & errMsg
            end try
        end timeout
    end tell
end run
OSAEOF
)"
        MIGRATE_RC=$?

        handle_migration_result "$MIGRATE_RESULT" "$MIGRATE_RC" "$MIGRATE_MODE" "$TARGET_EXISTS_NONEMPTY" "$DEST_FOLDER_NAME"
    fi

    # 7. Dual-Location Cache Purge (Application Support POSIX + Sandbox Finder Automation)
    echo ""
    echo -e "${BOLD}[5/5] Double purge des caches corrompus / Dual-location cache purge...${NC}"

    local CACHE_FILES=("Groups.cache" "Accessory.cache" "cAstGroupCache.package")
    local POSIX_DELETED=()
    local cf

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

    local SANDBOX_CACHE_RESULT SANDBOX_CACHE_RC
    SANDBOX_CACHE_RESULT="$(run_as_real_user /usr/bin/osascript 2>&1 <<'OSAEOF'
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
)"
    SANDBOX_CACHE_RC=$?

    handle_sandbox_cache_result "$SANDBOX_CACHE_RESULT" "$SANDBOX_CACHE_RC"

    echo ""
    if [ "$MIGRATION_FAILED" -eq 1 ]; then
        echo -e "${YELLOW}${BOLD}"
        echo "========================================================================"
        echo "  PATCH 120 HZ OK — ACTION REQUISE POUR VOS SAUVEGARDES / ACTION NEEDED"
        echo "========================================================================"
        echo -e "${NC}"
        echo -e "  • ${BOLD}Patch Binaire 120 Hz :${NC} $PATCH_STATUS"
        echo -e "  • ${BOLD}Sauvegardes / Saves  :${NC} $MIGRATION_STATUS"
        echo -e "  • ${BOLD}Dossier Données/Mods :${NC} ~/Library/Application Support/Aspyr/The Sims 2/"
        echo -e "  • ${BOLD}Purge des Caches     :${NC} $CACHE_STATUS"
        echo ""
        echo -e "  ${YELLOW}[!] NE LANCEZ PAS ENCORE LES SIMS 2 !${NC}"
        echo "      Vos sauvegardes Sandbox n'ont pas encore pu être copiées."
        echo "      Si vous lancez le jeu maintenant, un nouveau profil vierge sera créé."
        echo "      Activez Terminal → Finder dans Réglages Système > Confidentialité et sécurité > Automatisation,"
        echo "      puis relancez simplement patch_sims2.command pour terminer la copie."
        echo ""
        echo -e "  ${YELLOW}[!] DO NOT LAUNCH THE SIMS 2 YET!${NC}"
        echo "      Your Sandbox saves could not be copied yet (a fresh launch now would create an empty profile)."
        echo "      Enable Terminal → Finder in System Settings > Privacy & Security > Automation,"
        echo "      then re-run patch_sims2.command to complete the migration."
        echo "========================================================================"

        pause_exit 1
    fi

    echo -e "${GREEN}${BOLD}"
    echo "========================================================================"
    echo "  INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.2.2) !         "
    echo "========================================================================"
    echo -e "${NC}"
    echo -e "  • ${BOLD}Patch Binaire 120 Hz :${NC} $PATCH_STATUS"
    echo -e "  • ${BOLD}Sauvegardes / Saves  :${NC} $MIGRATION_STATUS"
    echo -e "  • ${BOLD}Dossier Données/Mods :${NC} ~/Library/Application Support/Aspyr/The Sims 2/"
    echo -e "  • ${BOLD}Purge des Caches     :${NC} $CACHE_STATUS"
    echo ""
    echo "  👉 Vous pouvez maintenant démarrer Les Sims 2 depuis le Launchpad"
    echo "     ou votre dossier Applications (en gardant votre écran Mac à 120 Hz) !"
    echo ""
    echo "  👉 You can now launch The Sims 2 from Launchpad or Applications"
    echo "     while keeping your Mac display at smooth 120 Hz ProMotion!"
    echo "========================================================================"

    pause_exit 0
}

if [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
    main "$@"
fi
