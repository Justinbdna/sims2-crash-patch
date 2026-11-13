#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — ProMotion 120Hz Patch, Save Migration & Fixes
# Version: 1.3.1 (Option A — Non-Sandbox Architecture)
# Target:  /Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe
# Zero Xcode / Python dependency: native /usr/bin/perl, codesign & osascript.
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_PATH="/Applications/The Sims 2.app"
EXE_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe"
BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup"
ALT_BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup_original"
GRULES_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr"
GRULES_BACKUP_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr.backup"
TRACKPAD_DYLIB_DEST="$APP_PATH/Contents/MacOS/libsims2_trackpad.dylib"
MANAGED_MAXFILES_PLIST="/Library/LaunchDaemons/limit.maxfiles.plist"

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
APP_REQUIRES_SUDO=1
MIGRATION_STATUS=""
MIGRATION_FAILED=0
MIGRATION_ERROR_KIND=""
PATCH_STATUS=""
GRULES_STATUS=""
TRACKPAD_STATUS=""
CACHE_STATUS=""
USERPROPS_STATUS=""
CC_MAXFILES_STATUS=""
DISPLAY_CUR=""
DISPLAY_MODES=""
MAXFILES_SOFT=""
MAXFILES_HARD=""
LOG_FILE=""
LOG_FINALIZED=0

init_diagnostic_log() {
    local label="${1:-patch_sims2.command v1.3.1}"
    [ -z "${REAL_HOME:-}" ] && return 0
    local log_dir="${SIMS2_LOG_DIR:-$REAL_HOME/Library/Logs/Sims2-Crash-Patch}"
    run_as_real_user mkdir -p "$log_dir" >/dev/null 2>&1 || return 0
    LOG_FILE="$log_dir/latest.log"
    if [ -f "$LOG_FILE" ]; then
        run_as_real_user mv -f "$LOG_FILE" "$log_dir/previous.log" >/dev/null 2>&1 || true
    fi
    local os_ver arch_name
    os_ver="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    arch_name="$(uname -m 2>/dev/null || echo 'unknown')"
    run_as_real_user sh -c 'cat > "$1"' _ "$LOG_FILE" <<LOGEOF 2>/dev/null || LOG_FILE=""
=== Sims 2 Crash Patch — Journal Technique / Diagnostic Log ===
Script : $label
Date   : $(date '+%Y-%m-%d %H:%M:%S %z')
User   : ${REAL_USER:-unknown} (uid=${REAL_UID:-?})
macOS  : $os_ver ($arch_name)
App    : $APP_PATH
LOGEOF
}

log_diag() {
    [ -z "${LOG_FILE:-}" ] && return 0
    local msg="$1"
    run_as_real_user sh -c 'printf "[%s] %s\n" "$(date +%H:%M:%S)" "$2" >> "$1"' _ "$LOG_FILE" "$msg" 2>/dev/null || true
}

finish_diagnostic_log() {
    local code="${1:-0}"
    [ -z "${LOG_FILE:-}" ] && return 0
    [ "${LOG_FINALIZED:-0}" -eq 1 ] && return 0
    LOG_FINALIZED=1
    log_diag "EXIT code=$code"
    [ -n "${PATCH_STATUS:-}" ] && log_diag "SUMMARY patch=$PATCH_STATUS"
    [ -n "${GRULES_STATUS:-}" ] && log_diag "SUMMARY grules=$GRULES_STATUS"
    [ -n "${TRACKPAD_STATUS:-}" ] && log_diag "SUMMARY trackpad=$TRACKPAD_STATUS"
    [ -n "${MIGRATION_STATUS:-}" ] && log_diag "SUMMARY migration=$MIGRATION_STATUS (failed=$MIGRATION_FAILED kind=${MIGRATION_ERROR_KIND:-none})"
    [ -n "${CACHE_STATUS:-}" ] && log_diag "SUMMARY caches=$CACHE_STATUS"
    [ -n "${USERPROPS_STATUS:-}" ] && log_diag "SUMMARY userProps=$USERPROPS_STATUS"
    [ -n "${CC_MAXFILES_STATUS:-}" ] && log_diag "SUMMARY cc_maxfiles=$CC_MAXFILES_STATUS"
    echo -e "  ${CYAN}[i] Journal technique / Log :${NC} $LOG_FILE"
}

pause_exit() {
    local code="${1:-0}"
    finish_diagnostic_log "$code"
    echo ""
    if [ "${SIMS2_NONINTERACTIVE:-0}" = "1" ]; then
        exit "$code"
    fi
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
    if [ "$(id -u)" -eq 0 ] && [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
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
    if [ "${SIMS2_LIB_ONLY:-0}" = "1" ] && [ "$scope_target" != "$MANAGED_MAXFILES_PLIST" ]; then
        case "$scope_target" in
            /tmp/*|/var/folders/*|/private/tmp/*|/private/var/folders/*|[A-Za-z]:/*|/[a-zA-Z]/*|*/[Tt]emp/*|*/_temp/*)
                "$@"
                return $?
                ;;
        esac
    fi
    if [ "$APP_REQUIRES_SUDO" -eq 0 ] && [ "$scope_target" != "$MANAGED_MAXFILES_PLIST" ]; then
        run_as_real_user "$@"
        return $?
    fi
    sudo "$@"
}

# Locate The Sims 2.app in /Applications (preferred) or ~/Applications
locate_app_bundle() {
    local sys_app="${1:-/Applications/The Sims 2.app}"
    local user_app="${2:-$REAL_HOME/Applications/The Sims 2.app}"

    if [ -f "$sys_app/Contents/MacOS/Sims2XP_Exe" ]; then
        APP_PATH="$sys_app"
        APP_REQUIRES_SUDO=1
        if [ "$(id -u)" -ne 0 ] && [ -w "$APP_PATH/Contents/MacOS/Sims2XP_Exe" ] && [ -w "$APP_PATH/Contents/MacOS" ]; then
            APP_REQUIRES_SUDO=0
        fi
    elif [ -f "$user_app/Contents/MacOS/Sims2XP_Exe" ]; then
        APP_PATH="$user_app"
        APP_REQUIRES_SUDO=0
        if [ "$(id -u)" -ne 0 ] && { [ ! -w "$APP_PATH/Contents/MacOS/Sims2XP_Exe" ] || [ ! -w "$APP_PATH/Contents/MacOS" ]; }; then
            APP_REQUIRES_SUDO=1
        fi
        echo -e "${YELLOW}[i] Jeu détecté dans votre dossier personnel :${NC} $APP_PATH"
    else
        APP_PATH="$sys_app"
        APP_REQUIRES_SUDO=1
        EXE_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe"
        BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup"
        ALT_BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup_original"
        GRULES_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr"
        GRULES_BACKUP_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr.backup"
        TRACKPAD_DYLIB_DEST="$APP_PATH/Contents/MacOS/libsims2_trackpad.dylib"
        return 1
    fi

    EXE_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe"
    BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup"
    ALT_BACKUP_PATH="$APP_PATH/Contents/MacOS/Sims2XP_Exe.backup_original"
    GRULES_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr"
    GRULES_BACKUP_PATH="$APP_PATH/Contents/Resources/Config/Graphics Rules.sgr.backup"
    TRACKPAD_DYLIB_DEST="$APP_PATH/Contents/MacOS/libsims2_trackpad.dylib"
    return 0
}

check_admin_rights() {
    local target_user="${1:-$REAL_USER}"
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if /usr/sbin/dseditgroup -o checkmember -m "$target_user" admin >/dev/null 2>&1; then
        return 0
    fi
    if id -Gn "$target_user" 2>/dev/null | grep -qw "admin"; then
        return 0
    fi
    return 1
}

print_non_admin_error() {
    echo -e "${RED}[-] Compte non-Administrateur détecté ($REAL_USER) / Non-Administrator account:${NC}"
    echo "    Votre session macOS est un compte « Standard » sans droits Administrateur."
    echo "    Mac OS refusera votre mot de passe lors de l'étape sudo."
    echo "    -> Solution : Connectez-vous sur une session Administrateur (ou donnez les droits"
    echo "       Admin dans Réglages Système > Utilisateurs et groupes) puis relancez ce script."
    echo ""
    echo "    Your macOS account is Standard (non-Admin), so sudo will reject your password."
    echo "    -> Fix: Log into an Administrator account and run patch_sims2.command again."
}

print_pre_sudo_guidance() {
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}CE QUI VA SE PASSER / WHAT TO EXPECT NEXT :${NC}"
    echo "  1. Tapez votre mot de passe Mac puis appuyez sur Entrée."
    echo -e "     ${YELLOW}NOTE : Aucun caractère (ni '*', ni point) ne s'affiche quand vous tapez,${NC}"
    echo -e "     ${YELLOW}c'est une sécurité normale de macOS (le clavier fonctionne bien).${NC}"
    echo "  2. Ensuite, macOS peut demander « Terminal souhaite contrôler Finder » :"
    echo -e "     cliquez sur ${BOLD}Autoriser / Allow${NC} pour copier vos sauvegardes."
    echo ""
    echo "  1. Enter your Mac Admin password and press Enter."
    echo -e "     ${YELLOW}NOTE: No characters or '*' appear while typing — this is normal on Mac.${NC}"
    echo -e "  2. Next, if macOS asks Terminal to control Finder, click ${BOLD}Allow${NC}."
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    echo ""
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
    printf '%s\n' "$msg" | grep -qiE '(-1743|1743|not authorized to send apple events|apple ?event)'
}

is_container_access_error() {
    local msg="$1"
    printf '%s\n' "$msg" | grep -qiE '(-5000|autorisations requises|vous ne disposez pas des autorisations|operation not permitted|permission denied|privileges|access denied)'
}

print_finder_automation_help() {
    echo "    -> Permission Automatisation Finder requise / Finder Automation permission required."
    echo "    -> Réglages Système -> Confidentialité et sécurité -> Automatisation -> Terminal -> activez Finder."
    echo "    -> System Settings -> Privacy & Security -> Automation -> Terminal -> enable Finder."
}

print_container_access_help() {
    echo "    -> macOS protège l'accès automatisé au conteneur Sandbox (erreur système -5000 / droits conteneur)."
    echo "    -> Solution manuelle sûre (Finder) : Cmd+Maj+G -> ~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/"
    echo "       et copiez vos dossiers (Neighborhoods, Downloads) vers ~/Library/Application Support/Aspyr/The Sims 2/."
    echo "    -> (Ou activez Accès complet au disque pour Terminal dans Réglages Système -> Confidentialité et sécurité.)"
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

run_finder_migration_osascript() {
    local dest_folder_name="$1"
    run_as_real_user /usr/bin/osascript - "$dest_folder_name" 2>&1 <<'OSAEOF'
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

                set copiedCount to 0
                set failedList to {}
                set firstErr to ""
                repeat with anItem in sourceItems
                    set itemName to name of anItem
                    if itemName is not ".DS_Store" and itemName is not ".localized" and itemName does not start with "._" then
                        if not (exists item itemName of destFolder) then
                            try
                                duplicate anItem to destFolder
                                set copiedCount to copiedCount + 1
                            on error errItemMsg number errItemNum
                                if firstErr is "" then
                                    set firstErr to (errItemMsg & " (" & errItemNum & ")")
                                end if
                                set end of failedList to itemName
                            end try
                        end if
                    end if
                end repeat

                if copiedCount is 0 then
                    if (count of failedList) > 0 then
                        return "ERROR:" & firstErr
                    end if
                    return "EMPTY_SOURCE"
                end if

                if (count of failedList) > 0 then
                    set oldDelims to AppleScript's text item delimiters
                    set AppleScript's text item delimiters to ", "
                    set failedStr to failedList as text
                    set AppleScript's text item delimiters to oldDelims
                    return "PARTIAL:" & copiedCount & "|" & failedStr & "|" & firstErr
                end if
                return "OK"
            on error errMsg number errNum
                return "ERROR:" & errMsg & " (" & errNum & ")"
            end try
        end timeout
    end tell
end run
OSAEOF
}

run_finder_cache_purge_osascript() {
    run_as_real_user /usr/bin/osascript 2>&1 <<'OSAEOF'
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
}

handle_migration_result() {
    local result="$1"
    local rc="$2"
    local migrate_mode="$3"
    local target_nonempty="$4"
    local dest_folder="$5"
    MIGRATION_FAILED=0
    MIGRATION_ERROR_KIND=""

    if [ "$rc" -ne 0 ]; then
        case "$result" in
            ERROR:*|PARTIAL:*) ;;
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
        PARTIAL:*)
            local rest="${result#PARTIAL:}"
            local copied_n="${rest%%|*}"
            local tail="${rest#*|}"
            local failed_items="${tail%%|*}"
            local first_err="${tail#*|}"
            log_diag "MIGRATION PARTIAL copied=$copied_n failed=$failed_items err=$first_err"
            echo -e "${YELLOW}[!] Migration Sandbox partielle ($copied_n élément(s) copié(s), ignoré(s) : $failed_items) :${NC} $first_err"
            if [ "$target_nonempty" -eq 1 ]; then
                MIGRATION_FAILED=2
                MIGRATION_ERROR_KIND="CONTAINER_ACCESS"
                echo -e "${GREEN}[i] Vos sauvegardes actives dans Application Support sont déjà intactes et utilisables.${NC}"
                MIGRATION_STATUS="Actives intactes + archive Sandbox partielle ('$dest_folder')"
            else
                MIGRATION_FAILED=1
                MIGRATION_ERROR_KIND="CONTAINER_ACCESS"
                print_container_access_help
                MIGRATION_STATUS="Copie partielle (vérifiez $failed_items)"
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
            log_diag "MIGRATION ERROR rc=$rc msg=$err_msg"
            if is_tcc_automation_error "$err_msg"; then
                MIGRATION_FAILED=1
                MIGRATION_ERROR_KIND="TCC_AUTOMATION"
                echo -e "${YELLOW}[!] Avertissement Automatisation Finder :${NC} $err_msg"
                print_finder_automation_help
                MIGRATION_STATUS="Permission Finder refusée (-1743) / Finder Automation denied"
            elif is_container_access_error "$err_msg"; then
                MIGRATION_ERROR_KIND="CONTAINER_ACCESS"
                if [ "$target_nonempty" -eq 1 ]; then
                    MIGRATION_FAILED=2
                    echo -e "${GREEN}[i] Sauvegardes actives conservées dans Application Support.${NC}"
                    echo -e "${YELLOW}[i] Note Sandbox :${NC} macOS bloque l'archivage automatique de l'ancien conteneur ($err_msg)."
                    echo "    Aucune action nécessaire sauf si vous voulez récupérer d'anciennes parties Sandbox à la main via Finder."
                    MIGRATION_STATUS="Actives intactes (archive Sandbox protégée par macOS)"
                else
                    MIGRATION_FAILED=1
                    echo -e "${YELLOW}[!] Accès conteneur Sandbox bloqué par macOS :${NC} $err_msg"
                    print_container_access_help
                    MIGRATION_STATUS="Conteneur Sandbox protégé par macOS (-5000 / voir instructions)"
                fi
            else
                MIGRATION_FAILED=1
                MIGRATION_ERROR_KIND="OTHER"
                echo -e "${YELLOW}[!] Avertissement lors de la copie Finder :${NC} $err_msg"
                MIGRATION_STATUS="Avertissement Finder (voir message ci-dessus)"
            fi
            ;;
        *)
            MIGRATION_FAILED=1
            log_diag "MIGRATION UNEXPECTED rc=$rc out=$result"
            echo -e "${YELLOW}[!] Réponse Finder inattendue / Unexpected Finder response:${NC} ${result:-<vide / empty>} (code $rc)"
            if is_tcc_automation_error "$result"; then
                MIGRATION_ERROR_KIND="TCC_AUTOMATION"
                print_finder_automation_help
                MIGRATION_STATUS="Permission Finder refusée (-1743) / Finder Automation denied"
            elif is_container_access_error "$result"; then
                MIGRATION_ERROR_KIND="CONTAINER_ACCESS"
                if [ "$target_nonempty" -eq 1 ]; then
                    MIGRATION_FAILED=2
                    MIGRATION_STATUS="Actives intactes (archive Sandbox protégée par macOS)"
                else
                    print_container_access_help
                    MIGRATION_STATUS="Conteneur Sandbox protégé par macOS"
                fi
            else
                MIGRATION_ERROR_KIND="OTHER"
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

# Query current logical display mode & supported CoreGraphics modes without Xcode CLT
query_display_modes() {
    DISPLAY_CUR=""
    DISPLAY_MODES=""
    local jxa_out jxa_rc
    jxa_out="$(run_as_real_user /usr/bin/osascript -l JavaScript 2>/dev/null <<'JXAEOF'
ObjC.import("CoreGraphics");
ObjC.import("AppKit");
ObjC.import("Foundation");
var did = $.CGMainDisplayID();
var cur = $.CGDisplayCopyDisplayMode(did);
var curW = Math.round($.CGDisplayModeGetWidth(cur));
var curH = Math.round($.CGDisplayModeGetHeight(cur));
var seen = {};
if (curW > 0 && curH > 0) seen[curW + "x" + curH] = 1;
var arr = ObjC.castRefToObject($.CGDisplayCopyAllDisplayModes(did, $()));
if (arr && arr.count) {
    for (var i = 0; i < arr.count; i++) {
        var m = arr.objectAtIndex(i);
        var w = Math.round($.CGDisplayModeGetWidth(m));
        var h = Math.round($.CGDisplayModeGetHeight(m));
        if (w > 0 && h > 0) {
            seen[w + "x" + h] = 1;
            if (w >= 1920 && (w % 2 === 0) && (h % 2 === 0)) {
                seen[(w / 2) + "x" + (h / 2)] = 1;
            }
        }
    }
}
var screens = $.NSScreen.screens;
if (screens && screens.count) {
    for (var j = 0; j < screens.count; j++) {
        var f = screens.objectAtIndex(j).frame;
        var sw = Math.round(f.size.width);
        var sh = Math.round(f.size.height);
        if (sw > 0 && sh > 0) {
            seen[sw + "x" + sh] = 1;
            if (curW === 0 || curH === 0) {
                curW = sw;
                curH = sh;
            }
        }
    }
}
if (curW > 0 && curH > 0) {
    "CUR=" + curW + "x" + curH + "\nMODES=" + Object.keys(seen).join(",");
}
JXAEOF
)"
    jxa_rc=$?
    if [ "$jxa_rc" -eq 0 ] && [ -n "$jxa_out" ]; then
        DISPLAY_CUR="$(printf '%s\n' "$jxa_out" | sed -n 's/^CUR=//p' | head -n 1)"
        DISPLAY_MODES="$(printf '%s\n' "$jxa_out" | sed -n 's/^MODES=//p' | head -n 1)"
    fi
}

# Conservative userProps.xml repair (creates userProps.xml.backup once before editing)
repair_userprops_xml() {
    local userprops_path="$1"
    local cur_res="$2"
    local supported_modes="$3"
    local force_reset="${4:-0}"

    if [ ! -f "$userprops_path" ]; then
        USERPROPS_STATUS="Non encore créé (sera généré au 1er lancement)"
        echo -e "${GREEN}[i] userProps.xml :${NC} Non encore créé (configuration générée sainement au 1er lancement)."
        return 0
    fi

    local perl_script runner_out runner_rc
    { IFS= read -r -d '' perl_script || true; } <<'PERLEOF'
use strict;
use warnings;

my ($xml_path, $cur_res, $modes_csv, $force_reset) = @ARGV;

my $active_tmp;
END {
    unlink($active_tmp) if defined $active_tmp && -e $active_tmp;
}

sub read_raw {
    my ($p) = @_;
    open(my $fh, "<:raw", $p) or die "Cannot read $p: $!\n";
    local $/;
    my $buf = <$fh>;
    close($fh);
    return $buf;
}

sub write_atomic {
    my ($p, $buf, $mode) = @_;
    die "Refusing to write through symlink: $p\n" if -l $p;
    my $tmp = "$p.tmp.$$";
    unlink($tmp) if -e $tmp || -l $tmp;
    $active_tmp = $tmp;
    open(my $out, ">:raw", $tmp) or do {
        $active_tmp = undef;
        die "Cannot create $tmp: $!\n";
    };
    if (!print {$out} $buf) {
        my $err = $!;
        close($out);
        unlink($tmp);
        $active_tmp = undef;
        die "Write failed: $err\n";
    }
    if (!close($out)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "Close failed: $err\n";
    }
    if (!chmod($mode, $tmp)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "chmod failed: $err\n";
    }
    if (!rename($tmp, $p)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "rename failed: $err\n";
    }
    $active_tmp = undef;
}

my $raw = read_raw($xml_path);
my $rx = qr{(<AnyString\b[^>]*\bkey="activeDeviceDisplayMode"[^>]*>)([^<]*)(</AnyString>)};
if ($raw !~ $rx) {
    print "NO_KEY\n";
    exit 0;
}

my $old_mode = $2;
$old_mode =~ s/^\s+|\s+$//g;

my %supported;
if (defined $modes_csv && $modes_csv ne "") {
    for my $item (split /,/, $modes_csv) {
        $item =~ s/^\s+|\s+$//g;
        $supported{$item} = 1 if $item =~ /^\d+x\d+$/;
    }
}

my $fallback_res = ($cur_res && $cur_res =~ /^\d+x\d+$/) ? $cur_res : "1280x800";
my $target_mode = "";
my $need_fix = 0;

if ($old_mode =~ /^(\d+)x(\d+)x(\d+)x(\d+)$/) {
    my ($w, $h, $bpp, $hz) = ($1, $2, $3, $4);
    my $res_key = "${w}x${h}";
    my $res_known_ok = 1;

    if ($w < 800 || $h < 600) {
        $res_known_ok = 0;
    } elsif (%supported && !$supported{$res_key} && $res_key ne "800x600") {
        $res_known_ok = 0;
    }

    if ($force_reset) {
        $target_mode = "${fallback_res}x32x60";
        $need_fix = ($old_mode ne $target_mode) ? 1 : 0;
    } elsif (!$res_known_ok) {
        $target_mode = "${fallback_res}x32x60";
        $need_fix = 1;
    } elsif ($bpp != 32 || $hz != 60) {
        $target_mode = "${w}x${h}x32x60";
        $need_fix = 1;
    }
} else {
    $target_mode = "${fallback_res}x32x60";
    $need_fix = 1;
}

if (!$need_fix) {
    print "OK:$old_mode\n";
    exit 0;
}

my $backup_path = "$xml_path.backup";
my $bak_state = "kept";
if (!-e $backup_path) {
    write_atomic($backup_path, $raw, 0644);
    $bak_state = "created";
}

$raw =~ s{$rx}{$1$target_mode$3};
write_atomic($xml_path, $raw, 0644);
print "FIXED:$old_mode->$target_mode|$bak_state\n";
PERLEOF

    if [ "$(id -u)" -eq 0 ] && [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
        runner_out="$(printf '%s\n' "$perl_script" | run_as_real_user /usr/bin/perl - "$userprops_path" "$cur_res" "$supported_modes" "$force_reset" 2>&1)"
    else
        runner_out="$(printf '%s\n' "$perl_script" | /usr/bin/perl - "$userprops_path" "$cur_res" "$supported_modes" "$force_reset" 2>&1)"
    fi
    runner_rc=$?

    if [ "$runner_rc" -ne 0 ]; then
        USERPROPS_STATUS="Avertissement lecture/écriture userProps.xml"
        echo -e "${YELLOW}[!] userProps.xml : Avertissement ($runner_out)${NC}"
        return 1
    fi

    case "$runner_out" in
        OK:*)
            local cur_val="${runner_out#OK:}"
            USERPROPS_STATUS="Valide ($cur_val)"
            echo -e "${GREEN}[+] userProps.xml :${NC} Résolution valide ($cur_val) — aucune modification requise."
            ;;
        NO_KEY)
            USERPROPS_STATUS="Propre (clé activeDeviceDisplayMode absente)"
            echo -e "${GREEN}[i] userProps.xml :${NC} Clé activeDeviceDisplayMode absente (auto-détection au lancement)."
            ;;
        FIXED:*)
            local payload="${runner_out#FIXED:}"
            local change="${payload%|*}"
            local bak="${payload#*|}"
            USERPROPS_STATUS="Réparé ($change, backup .backup $bak)"
            echo -e "${GREEN}[+] userProps.xml : Réparé automatiquement ($change) !${NC}"
            echo "    Sauvegarde de retour : $(dirname "$userprops_path")/userProps.xml.backup"
            ;;
        *)
            USERPROPS_STATUS="Statut inconnu ($runner_out)"
            echo -e "${YELLOW}[!] userProps.xml :${NC} $runner_out"
            ;;
    esac
    return 0
}

read_launchctl_maxfiles() {
    MAXFILES_SOFT=""
    MAXFILES_HARD=""
    local line
    line="$(/bin/launchctl limit maxfiles 2>/dev/null | awk '/maxfiles/ {print $2 " " $3; exit}')"
    MAXFILES_SOFT="${line%% *}"
    MAXFILES_HARD="${line#* }"
}

install_managed_maxfiles_daemon() {
    local target_plist="${1:-$MANAGED_MAXFILES_PLIST}"
    if ! check_admin_rights "$REAL_USER"; then
        print_non_admin_error
        return 1
    fi
    local tmp_plist
    tmp_plist="$(umask 077 && mktemp "${TMPDIR:-/tmp}/sims2_limit_maxfiles.XXXXXX")" || return 1
    if [ -L "$tmp_plist" ] || [ -L "$target_plist" ]; then
        rm -f "$tmp_plist"
        return 1
    fi
    cat > "$tmp_plist" <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Managed by sims2-crash-patch -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>limit.maxfiles</string>
    <key>ProgramArguments</key>
    <array>
        <string>launchctl</string>
        <string>limit</string>
        <string>maxfiles</string>
        <string>64000</string>
        <string>524288</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ServiceIPC</key>
    <false/>
</dict>
</plist>
PLISTEOF
    if ! run_privileged "$target_plist" cp -f "$tmp_plist" "$target_plist"; then
        rm -f "$tmp_plist"
        return 1
    fi
    if [ "$target_plist" = "$MANAGED_MAXFILES_PLIST" ]; then
        if ! run_privileged "$target_plist" chown root:wheel "$target_plist" || \
           ! run_privileged "$target_plist" chmod 644 "$target_plist"; then
            rm -f "$tmp_plist"
            return 1
        fi
        rm -f "$tmp_plist"
        run_privileged "$target_plist" /bin/launchctl load -w "$target_plist" >/dev/null 2>&1 || true
        return 0
    fi
    if ! chmod 644 "$target_plist"; then
        rm -f "$tmp_plist"
        return 1
    fi
    rm -f "$tmp_plist"
    return 0
}

count_cc_and_check_maxfiles() {
    local downloads_dir="$1"
    local allow_prompt="${2:-1}"
    local pkg_count=0
    local archive_count=0

    if [ -d "$downloads_dir" ]; then
        pkg_count="$(find "$downloads_dir" -type f -iname "*.package" ! -name '._*' 2>/dev/null | wc -l | tr -d ' ')"
        archive_count="$(find "$downloads_dir" -type f \( -iname "*.zip" -o -iname "*.rar" -o -iname "*.7z" \) ! -name '._*' 2>/dev/null | wc -l | tr -d ' ')"
    fi

    read_launchctl_maxfiles
    local hard_label="${MAXFILES_HARD:-inconnu}"
    local soft_label="${MAXFILES_SOFT:-inconnu}"

    echo -e "${GREEN}[i] Mods / CC (Downloads) :${NC} ${pkg_count} fichier(s) .package | macOS maxfiles soft=${soft_label}, hard=${hard_label}"

    if [ "$archive_count" -gt 0 ] 2>/dev/null; then
        echo -e "${YELLOW}[!] Attention :${NC} ${archive_count} archive(s) (.zip/.rar/.7z) détectée(s) dans Downloads/ !"
        echo "    Les Sims 2 ne lit PAS les archives compressées : décompressez-les pour y placer uniquement les .package."
        echo "    (The Sims 2 ignores .zip/.rar/.7z files — extract .package files inside Downloads/.)"
    fi

    if [ "$pkg_count" -ge 8000 ] 2>/dev/null; then
        echo -e "${YELLOW}[!] Volume très élevé de CC (${pkg_count} .package) :${NC}"
        echo "    Le binaire Sims2XP_Exe relève la limite à 10 240 descripteurs max au démarrage."
        echo "    Avec le jeu de base + extensions, approcher 8 000–10 000 mods peut saturer cette limite."
        echo "    Conseil : fusionnez/trie vos .package si des objets manquent ou si le jeu plante."
    fi

    if printf '%s' "$MAXFILES_HARD" | grep -Eq '^[0-9]+$' && [ "$MAXFILES_HARD" -lt 10240 ]; then
        echo -e "${YELLOW}[!] Limite macOS hard maxfiles basse (${MAXFILES_HARD} < 10240) !${NC}"
        echo "    Le jeu risque de manquer de descripteurs de fichiers avec des mods/CC."
        if [ "$allow_prompt" -eq 1 ] && [ "${SIMS2_NONINTERACTIVE:-0}" != "1" ]; then
            local ans=""
            read -r -p "    Installer /Library/LaunchDaemons/limit.maxfiles.plist (64000/524288) ? [o/N] : " ans
            case "$ans" in
                o|O|oui|OUI|y|Y|yes|YES)
                    if install_managed_maxfiles_daemon; then
                        echo -e "${GREEN}[+] limit.maxfiles.plist installé (sera retiré proprement via restore_sims2.command).${NC}"
                        CC_MAXFILES_STATUS="${pkg_count} .package (LaunchDaemon maxfiles installé)"
                        return 0
                    else
                        echo -e "${YELLOW}[!] Impossible d'installer limit.maxfiles.plist.${NC}"
                    fi
                    ;;
            esac
        fi
        CC_MAXFILES_STATUS="${pkg_count} .package (hard=${hard_label} < 10240)"
    else
        CC_MAXFILES_STATUS="${pkg_count} .package (hard=${hard_label}, jeu jusqu'à 10240 OK)"
    fi
}

# Step 3A — Optimize Graphics Rules.sgr (Retina 5120x3200, $High profile, 1024 MB VRAM fallback)
patch_graphics_rules_sgr() {
    local grules_path="${1:-$GRULES_PATH}"
    local backup_path="${2:-$GRULES_BACKUP_PATH}"

    if [ -L "$grules_path" ] || [ -L "$backup_path" ]; then
        GRULES_STATUS="ERREUR (lien symbolique refusé)"
        echo -e "${RED}[-] Erreur de sécurité : lien symbolique refusé sur Graphics Rules.sgr.${NC}"
        return 1
    fi

    if [ ! -f "$grules_path" ]; then
        GRULES_STATUS="Absent (Graphics Rules.sgr introuvable)"
        echo -e "${CYAN}[i] Graphics Rules.sgr :${NC} Fichier introuvable ($grules_path) — étape ignorée."
        return 0
    fi

    local perl_script runner_out runner_rc
    { IFS= read -r -d '' perl_script || true; } <<'GRULES_PERL'
use strict;
use warnings;

my ($grules_path, $backup_path) = @ARGV;

my $active_tmp;
END {
    unlink($active_tmp) if defined $active_tmp && -e $active_tmp;
}

sub read_raw {
    my ($p) = @_;
    open(my $fh, "<:raw", $p) or die "Cannot read $p: $!\n";
    local $/;
    my $buf = <$fh>;
    close($fh);
    return $buf;
}

sub write_atomic {
    my ($p, $buf, $mode) = @_;
    die "Refusing to write through symlink: $p\n" if -l $p;
    my $tmp = "$p.tmp.$$";
    unlink($tmp) if -e $tmp || -l $tmp;
    $active_tmp = $tmp;
    open(my $out, ">:raw", $tmp) or do {
        $active_tmp = undef;
        die "Cannot create $tmp: $!\n";
    };
    if (!print {$out} $buf) {
        my $err = $!;
        close($out);
        unlink($tmp);
        $active_tmp = undef;
        die "Write failed: $err\n";
    }
    if (!close($out)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "Close failed: $err\n";
    }
    if (!chmod($mode, $tmp)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "chmod failed: $err\n";
    }
    if (!rename($tmp, $p)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "rename failed: $err\n";
    }
    $active_tmp = undef;
}

die "Refusing symlink: $grules_path\n" if -l $grules_path;
die "Refusing symlink: $backup_path\n" if -l $backup_path;

my $raw = read_raw($grules_path);
my $marker = "# Patched by sims2-crash-patch";
my $is_already_patched = (index($raw, $marker) != -1);

if (!-e $backup_path) {
    if (!$is_already_patched) {
        write_atomic($backup_path, $raw, 0644);
    }
} elsif (!$is_already_patched) {
    my $bak_raw = read_raw($backup_path);
    if (index($bak_raw, $marker) != -1) {
        write_atomic($backup_path, $raw, 0644);
    }
}

if ($is_already_patched) {
    print "OK:already_patched\n";
    exit 0;
}

$raw =~ s/\b(seti[ \t]+textureMemory[ \t]+)32\b/${1}1024/g;
$raw =~ s/\b(uintProp[ \t]+maxResWidth[ \t]+)2048\b/${1}5120/g;
$raw =~ s/\b(uintProp[ \t]+maxResHeight[ \t]+)2048\b/${1}3200/g;

my $override_hdr = "# Override defaults (SIM-281,416)";
my $banner = "# Patched by sims2-crash-patch (Apple Silicon & Retina Rules)\n";
my $found_override = ($raw =~ s{([ \t]*\Q$override_hdr\E\r?\n(?:(?!\r?\n[ \t]*(?:#{5,}|endif\b|end\b)).)*)}{
    my $blk = $1;
    $blk =~ s/\b(setOption[ \t]+(?:EffectsQuality|LightingQuality|Shadows|MaterialDetail)[ \t]+)\$Medium\b/${1}\$High/g;
    my ($indent) = ($blk =~ /^([ \t]*)/);
    $indent . $banner . $blk;
}se);

if (!$found_override) {
    $raw = $banner . $raw;
}

write_atomic($grules_path, $raw, 0644);
print "PATCHED\n";
GRULES_PERL

    runner_out="$(printf '%s\n' "$perl_script" | run_privileged "$grules_path" /usr/bin/perl - "$grules_path" "$backup_path" 2>&1)"
    runner_rc=$?

    if [ "$runner_rc" -ne 0 ]; then
        GRULES_STATUS="AVERTISSEMENT ($runner_out)"
        echo -e "${YELLOW}[!] Graphics Rules.sgr : Erreur ($runner_out)${NC}"
        return 1
    fi

    case "$runner_out" in
        OK:already_patched)
            GRULES_STATUS="OK (déjà patché / already patched)"
            echo -e "${GREEN}[i] Graphics Rules.sgr :${NC} Déjà patché (OK:already_patched)."
            ;;
        PATCHED)
            GRULES_STATUS="OK (Retina 5120x3200, \$High, VRAM 1024 Mo)"
            echo -e "${GREEN}[+] Graphics Rules.sgr :${NC} Optimisé (5120x3200, profil \$High, VRAM 1024 Mo) [PATCHED]."
            ;;
        *)
            GRULES_STATUS="Statut ($runner_out)"
            echo -e "${YELLOW}[!] Graphics Rules.sgr :${NC} $runner_out"
            ;;
    esac
    return 0
}

# Step 3B — Idempotent LC_LOAD_WEAK_DYLIB Mach-O 64-bit injector
inject_weak_dylib_macho() {
    local exe_path="$1"
    local dylib_install_name="${2:-@executable_path/libsims2_trackpad.dylib}"

    if [ -L "$exe_path" ]; then
        echo -e "${RED}[-] Erreur de sécurité : lien symbolique refusé sur $exe_path.${NC}"
        return 1
    fi
    if [ ! -f "$exe_path" ]; then
        echo -e "${RED}[-] Binaire introuvable pour injection Mach-O : $exe_path.${NC}"
        return 1
    fi

    local perl_script runner_out runner_rc
    { IFS= read -r -d '' perl_script || true; } <<'MACHO_PERL'
use strict;
use warnings;

my ($exe_path, $dylib_install_name) = @ARGV;

my $active_tmp;
END {
    unlink($active_tmp) if defined $active_tmp && -e $active_tmp;
}

sub read_raw {
    my ($p) = @_;
    open(my $fh, "<:raw", $p) or die "Cannot read $p: $!\n";
    local $/;
    my $buf = <$fh>;
    close($fh);
    return $buf;
}

sub write_atomic {
    my ($p, $buf, $mode) = @_;
    die "Refusing to write through symlink: $p\n" if -l $p;
    my $tmp = "$p.tmp.$$";
    unlink($tmp) if -e $tmp || -l $tmp;
    $active_tmp = $tmp;
    open(my $out, ">:raw", $tmp) or do {
        $active_tmp = undef;
        die "Cannot create $tmp: $!\n";
    };
    if (!print {$out} $buf) {
        my $err = $!;
        close($out);
        unlink($tmp);
        $active_tmp = undef;
        die "Write failed: $err\n";
    }
    if (!close($out)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "Close failed: $err\n";
    }
    if (!chmod($mode, $tmp)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "chmod failed: $err\n";
    }
    if (!rename($tmp, $p)) {
        my $err = $!;
        unlink($tmp);
        $active_tmp = undef;
        die "rename failed: $err\n";
    }
    $active_tmp = undef;
}

die "Refusing symlink: $exe_path\n" if -l $exe_path;
my $data = read_raw($exe_path);
die "File too small for Mach-O 64-bit header\n" if length($data) < 32;

my ($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved) =
    unpack("V8", substr($data, 0, 32));
die sprintf("Invalid Mach-O 64-bit magic: 0x%08x\n", $magic) if $magic != 0xfeedfacf;
die "Invalid sizeofcmds in Mach-O header\n" if 32 + $sizeofcmds > length($data);

my $off = 32;
my $end_cmds = 32 + $sizeofcmds;
my $min_sect_off;

for (my $i = 0; $i < $ncmds; $i++) {
    die "Truncated load command at offset $off\n" if $off + 8 > $end_cmds;
    my ($cmd, $cmdsize) = unpack("VV", substr($data, $off, 8));
    die "Invalid load command size ($cmdsize) at offset $off\n"
        if $cmdsize < 8 || $off + $cmdsize > $end_cmds;

    if ($cmd == 0x0c || $cmd == 0x80000018) {
        if ($cmdsize >= 24) {
            my $str_off = unpack("V", substr($data, $off + 8, 4));
            my $read_off = ($str_off >= 24 && $str_off < $cmdsize) ? $str_off : 24;
            my $name = substr($data, $off + $read_off, $cmdsize - $read_off);
            $name =~ s/\0.*$//s;
            if ($name eq $dylib_install_name || index($name, "libsims2_trackpad.dylib") != -1) {
                print "ALREADY_INJECTED\n";
                exit 0;
            }
        }
    } elsif ($cmd == 0x19) {
        die "Truncated LC_SEGMENT_64 at offset $off\n" if $cmdsize < 72;
        my $nsects = unpack("V", substr($data, $off + 64, 4));
        die "Truncated section_64 list in LC_SEGMENT_64 at offset $off\n"
            if 72 + $nsects * 80 > $cmdsize;
        for (my $s = 0; $s < $nsects; $s++) {
            my $sect_off = $off + 72 + ($s * 80);
            my $sec_file_off = unpack("V", substr($data, $sect_off + 48, 4));
            if ($sec_file_off > 0 && (!defined($min_sect_off) || $sec_file_off < $min_sect_off)) {
                $min_sect_off = $sec_file_off;
            }
        }
    }

    $off += $cmdsize;
}

my $str = $dylib_install_name . "\0";
my $raw_len = 24 + length($str);
my $new_cmdsize = ($raw_len + 7) & ~7;
my $pad = "\0" x ($new_cmdsize - $raw_len);
my $new_cmd = pack("VVVVVV", 0x80000018, $new_cmdsize, 24, 2, 0x00010000, 0x00010000) . $str . $pad;

my $target_off = 32 + $sizeofcmds;
die "Insufficient Mach-O header padding for LC_LOAD_WEAK_DYLIB\n"
    unless defined($min_sect_off) && ($target_off + $new_cmdsize <= $min_sect_off);

my $target_space = substr($data, $target_off, $new_cmdsize);
die "Non-zero bytes in Mach-O header padding\n"
    unless $target_space eq ("\0" x $new_cmdsize);

substr($data, $target_off, $new_cmdsize, $new_cmd);
substr($data, 16, 4, pack("V", $ncmds + 1));
substr($data, 20, 4, pack("V", $sizeofcmds + $new_cmdsize));

write_atomic($exe_path, $data, 0755);
print "INJECTED\n";
MACHO_PERL

    runner_out="$(printf '%s\n' "$perl_script" | run_privileged "$exe_path" /usr/bin/perl - "$exe_path" "$dylib_install_name" 2>&1)"
    runner_rc=$?

    if [ "$runner_rc" -ne 0 ]; then
        echo -e "${YELLOW}[!] Injection LC_LOAD_WEAK_DYLIB échouée :${NC} $runner_out"
        return 1
    fi

    case "$runner_out" in
        ALREADY_INJECTED)
            echo -e "${GREEN}[i] Mach-O Weak Dylib :${NC} Déjà injecté (ALREADY_INJECTED)."
            ;;
        INJECTED)
            echo -e "${GREEN}[+] Mach-O Weak Dylib :${NC} LC_LOAD_WEAK_DYLIB injecté (INJECTED)."
            ;;
        *)
            echo -e "${YELLOW}[!] Mach-O Weak Dylib :${NC} $runner_out"
            ;;
    esac
    return 0
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2: Super Collection — ProMotion 120Hz & Stability Patch v1.3.1"
    echo "========================================================================"
    echo -e "${NC}"

    if ! resolve_real_user; then
        pause_exit 1
    fi

    # 1. Verify application presence (supports /Applications or ~/Applications)
    if ! locate_app_bundle; then
        init_diagnostic_log "patch_sims2.command v1.3.1"
        log_diag "ERROR game not found (/Applications or ~/Applications)"
        echo -e "${RED}[-] Erreur / Error:${NC} Jeu introuvable / Game not found at:"
        echo "    /Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
        echo "    (ni dans ~/Applications/The Sims 2.app)"
        echo "    Vérifiez que The Sims 2: Super Collection est bien installé."
        pause_exit 1
    fi

    init_diagnostic_log "patch_sims2.command v1.3.1"
    local ASPYR_BASE_DIR="$REAL_HOME/Library/Application Support/Aspyr"
    local TARGET_DATA_DIR="$ASPYR_BASE_DIR/The Sims 2"
    log_diag "START active_dir=$TARGET_DATA_DIR sudo_required=$APP_REQUIRES_SUDO"

    echo -e "[i] Session utilisateur détectée / Active user: ${BOLD}$REAL_USER${NC} ($REAL_HOME)"
    echo ""

    # 2. Verify the game is not currently running
    if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Attention / Warning:${NC} Les Sims 2 est actuellement ouvert !"
        echo "    Fermez complètement le jeu (Cmd+Q / vérifiez le Dock) puis relancez ce script."
        echo "    Please quit The Sims 2 completely before running this patch."
        pause_exit 1
    fi

    # 3. Pre-check Administrator privileges & explain invisible password before sudo
    if [ "$APP_REQUIRES_SUDO" -eq 1 ]; then
        if ! check_admin_rights "$REAL_USER"; then
            print_non_admin_error
            pause_exit 1
        fi

        echo -e "${BOLD}[1/6] Autorisation administrateur / Administrator authorization${NC}"
        echo "      Requise uniquement pour modifier l'application dans /Applications."
        echo "      Required solely to patch the application bundle in /Applications."
        echo ""
        print_pre_sudo_guidance

        if ! sudo -v; then
            echo ""
            echo -e "${RED}[-] Échec d'authentification / Authentication failed.${NC}"
            echo "    Vérifiez : 1) Touche Verr Maj (Caps Lock) éteinte, 2) Mot de passe exact du Mac,"
            echo "    puis relancez simplement patch_sims2.command."
            pause_exit 1
        fi
    else
        echo -e "${BOLD}[1/6] Préparation / Preparation (écriture directe autorisée)${NC}"
    fi

    # 4. Verified Pristine Backup & Atomic Dual Idempotent Binary Patch (/usr/bin/perl)
    echo ""
    echo -e "${BOLD}[2/6] Sauvegarde vérifiée & Double Patch Binaire 60 Hz / 60 Hz Patch...${NC}"

    if ! run_privileged "$EXE_PATH" /usr/bin/perl - "$EXE_PATH" "$BACKUP_PATH" "$ALT_BACKUP_PATH" <<'PERLEOF'
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
    die "Refusing to write through symlink: $p\n" if -l $p;
    my $tmp = "$p.tmp.$$";
    unlink($tmp) if -e $tmp || -l $tmp;
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
        count_occurrences($buf, $repl2) == 0 &&
        index($buf, "libsims2_trackpad.dylib") == -1
    );
}

my $data = read_raw($exe_path);

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
        PATCH_STATUS="FAILED (binary patch error)"
        log_diag "BINARY_PATCH FAILED"
        echo -e "${RED}[-] Le patch binaire a échoué / Binary patch failed.${NC}"
        pause_exit 1
    fi
    if ! run_privileged "$EXE_PATH" chmod 755 "$EXE_PATH"; then
        PATCH_STATUS="FAILED (chmod 755 error)"
        log_diag "BINARY_PATCH CHMOD FAILED"
        echo -e "${RED}[-] Impossible d'appliquer les permissions 0755 sur $EXE_PATH.${NC}"
        pause_exit 1
    fi
    PATCH_STATUS="OK (60 Hz verrouillé / locked)"
    log_diag "BINARY_PATCH OK"

    # 4B. Graphics Rules.sgr optimization & native Trackpad weak dylib injection
    echo ""
    echo -e "${BOLD}[+] Optimisation Graphics Rules.sgr & Module Trackpad natif...${NC}"
    if patch_graphics_rules_sgr "$GRULES_PATH" "$GRULES_BACKUP_PATH"; then
        log_diag "GRULES_PATCH OK"
    else
        log_diag "GRULES_PATCH WARNING"
    fi

    local trackpad_src=""
    if [ -f "$SCRIPT_DIR/trackpad_mod/libsims2_trackpad.dylib" ]; then
        trackpad_src="$SCRIPT_DIR/trackpad_mod/libsims2_trackpad.dylib"
    elif [ -f "$SCRIPT_DIR/libsims2_trackpad.dylib" ]; then
        trackpad_src="$SCRIPT_DIR/libsims2_trackpad.dylib"
    fi

    if [ -n "$trackpad_src" ]; then
        if [ -L "$trackpad_src" ] || [ -L "$TRACKPAD_DYLIB_DEST" ]; then
            TRACKPAD_STATUS="AVERTISSEMENT (lien symbolique refusé)"
            log_diag "TRACKPAD_DYLIB SYMLINK_REFUSED"
            echo -e "${YELLOW}[!] Sécurité : lien symbolique refusé pour libsims2_trackpad.dylib.${NC}"
        else
            local tmp_dylib="${TRACKPAD_DYLIB_DEST}.tmp.$$"
            run_privileged "$TRACKPAD_DYLIB_DEST" rm -f "$tmp_dylib" 2>/dev/null || true
            if run_privileged "$TRACKPAD_DYLIB_DEST" cp -f "$trackpad_src" "$tmp_dylib" && \
               run_privileged "$TRACKPAD_DYLIB_DEST" chmod 755 "$tmp_dylib" && \
               run_privileged "$TRACKPAD_DYLIB_DEST" mv -f "$tmp_dylib" "$TRACKPAD_DYLIB_DEST" && \
               run_privileged "$TRACKPAD_DYLIB_DEST" chmod 755 "$TRACKPAD_DYLIB_DEST"; then
                run_privileged "$TRACKPAD_DYLIB_DEST" /usr/bin/xattr -d com.apple.quarantine "$TRACKPAD_DYLIB_DEST" >/dev/null 2>&1 || true
                echo -e "${GREEN}[+] Module Trackpad installé :${NC} $TRACKPAD_DYLIB_DEST"
                if inject_weak_dylib_macho "$EXE_PATH" "@executable_path/libsims2_trackpad.dylib"; then
                    TRACKPAD_STATUS="OK (libsims2_trackpad.dylib installé & injecté)"
                    log_diag "TRACKPAD_DYLIB OK"
                else
                    TRACKPAD_STATUS="AVERTISSEMENT (injection LC_LOAD_WEAK_DYLIB échouée)"
                    log_diag "TRACKPAD_DYLIB INJECT_FAILED"
                fi
            else
                run_privileged "$TRACKPAD_DYLIB_DEST" rm -f "$tmp_dylib" 2>/dev/null || true
                TRACKPAD_STATUS="AVERTISSEMENT (copie dylib échouée)"
                log_diag "TRACKPAD_DYLIB COPY_FAILED"
                echo -e "${YELLOW}[!] Impossible d'installer libsims2_trackpad.dylib dans $TRACKPAD_DYLIB_DEST.${NC}"
            fi
        fi
    else
        TRACKPAD_STATUS="Ignoré (libsims2_trackpad.dylib absent)"
        log_diag "TRACKPAD_DYLIB SKIPPED missing_source"
        echo -e "${CYAN}[i] Module Trackpad :${NC} libsims2_trackpad.dylib absent du dossier — étape ignorée."
    fi

    # 5. Ad-hoc Local Code Signing + Strict Verification
    echo ""
    echo -e "${BOLD}[3/6] Re-signature locale ad-hoc & vérification (codesign)...${NC}"
    if sign_and_verify_app "$APP_PATH"; then
        echo -e "${GREEN}[+] Signature locale appliquée et vérifiée (--strict) / Ad-hoc signature applied & verified.${NC}"
        log_diag "CODESIGN OK --strict"
    else
        log_diag "CODESIGN FAILED"
        pause_exit 1
    fi

    # 6. Safe, Non-Overwriting Save Migration (Sandbox -> Application Support)
    echo ""
    echo -e "${BOLD}[4/6] Vérification & Migration sécurisée des sauvegardes / Safe Save Migration...${NC}"
    echo "      Dossier actif : ~/Library/Application Support/Aspyr/The Sims 2/"

    MIGRATION_STATUS=""

    local TARGET_EXISTS_NONEMPTY=0
    if dir_has_real_entries "$TARGET_DATA_DIR"; then
        TARGET_EXISTS_NONEMPTY=1
    fi

    local EXISTING_SANDBOX_BACKUP=""
    local cand_bak
    while IFS= read -r cand_bak; do
        [ -n "$cand_bak" ] || continue
        if [ -n "$(find "$cand_bak" -type f ! -name '.DS_Store' ! -name '.localized' ! -name '._*' 2>/dev/null | head -n 1)" ]; then
            EXISTING_SANDBOX_BACKUP="$cand_bak"
            break
        fi
    done <<FINDBAK
$(find "$ASPYR_BASE_DIR" -maxdepth 1 -type d -name "The Sims 2 (Sandbox Backup*)" 2>/dev/null)
FINDBAK

    if [ "$TARGET_EXISTS_NONEMPTY" -eq 1 ] && [ -n "$EXISTING_SANDBOX_BACKUP" ]; then
        echo -e "${GREEN}[i] Dossier Application Support actif et sauvegarde Sandbox déjà archivée :${NC}"
        echo "    -> $(basename "$EXISTING_SANDBOX_BACKUP")"
        echo "    Aucune donnée écrasée / No data overwritten."
        MIGRATION_STATUS="Intactes + Archive Sandbox conservée / Active + Sandbox backup kept"
        log_diag "MIGRATION SKIPPED already_archived=$(basename "$EXISTING_SANDBOX_BACKUP")"
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

        local DEST_PREEXISTED=0
        [ -e "$ASPYR_BASE_DIR/$DEST_FOLDER_NAME" ] && DEST_PREEXISTED=1

        run_as_real_user mkdir -p "$ASPYR_BASE_DIR"

        local SANDBOX_DATA_DIR="$REAL_HOME/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2"
        local MIGRATE_RESULT="" MIGRATE_RC=0

        if run_as_real_user ls "$SANDBOX_DATA_DIR" >/dev/null 2>&1; then
            log_diag "MIGRATION strategy=posix mode=$MIGRATE_MODE dest=$DEST_FOLDER_NAME"
            if ! dir_has_real_entries "$SANDBOX_DATA_DIR"; then
                MIGRATE_RESULT="EMPTY_SOURCE"
            else
                local DEST_FULL="$ASPYR_BASE_DIR/$DEST_FOLDER_NAME"
                run_as_real_user mkdir -p "$DEST_FULL"
                local copied_posix=0 failed_posix=0 src_item base_name
                for src_item in "$SANDBOX_DATA_DIR"/*; do
                    [ -e "$src_item" ] || continue
                    base_name="$(basename "$src_item")"
                    case "$base_name" in
                        .DS_Store|.localized|._*) continue ;;
                    esac
                    if [ ! -e "$DEST_FULL/$base_name" ]; then
                        if run_as_real_user cp -Rp "$src_item" "$DEST_FULL/$base_name" 2>/dev/null; then
                            copied_posix=$((copied_posix + 1))
                        else
                            failed_posix=$((failed_posix + 1))
                        fi
                    fi
                done
                if [ "$copied_posix" -eq 0 ] && [ "$failed_posix" -eq 0 ]; then
                    MIGRATE_RESULT="EMPTY_SOURCE"
                elif [ "$failed_posix" -gt 0 ] && [ "$copied_posix" -eq 0 ]; then
                    MIGRATE_RESULT="ERROR:Operation not permitted (-5000)"
                elif [ "$failed_posix" -gt 0 ]; then
                    MIGRATE_RESULT="PARTIAL:$copied_posix|$failed_posix item(s)|POSIX copy error"
                else
                    MIGRATE_RESULT="OK"
                fi
            fi
        else
            log_diag "MIGRATION strategy=finder mode=$MIGRATE_MODE dest=$DEST_FOLDER_NAME"
            MIGRATE_RESULT="$(run_finder_migration_osascript "$DEST_FOLDER_NAME")"
            MIGRATE_RC=$?
        fi

        if [ "$MIGRATE_MODE" = "BACKUP" ] && [ "$DEST_PREEXISTED" -eq 0 ] && [ -d "$ASPYR_BASE_DIR/$DEST_FOLDER_NAME" ]; then
            if [ -z "$(find "$ASPYR_BASE_DIR/$DEST_FOLDER_NAME" -type f ! -name '.DS_Store' ! -name '.localized' ! -name '._*' 2>/dev/null | head -n 1)" ]; then
                run_as_real_user rm -rf "$ASPYR_BASE_DIR/$DEST_FOLDER_NAME" >/dev/null 2>&1 || true
            fi
        fi

        handle_migration_result "$MIGRATE_RESULT" "$MIGRATE_RC" "$MIGRATE_MODE" "$TARGET_EXISTS_NONEMPTY" "$DEST_FOLDER_NAME"
    fi

    # 7. Dual-Location Cache Purge (Application Support POSIX + Sandbox Finder Automation)
    echo ""
    echo -e "${BOLD}[5/6] Double purge des caches corrompus / Dual-location cache purge...${NC}"

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
    SANDBOX_CACHE_RESULT="$(run_finder_cache_purge_osascript)"
    SANDBOX_CACHE_RC=$?

    handle_sandbox_cache_result "$SANDBOX_CACHE_RESULT" "$SANDBOX_CACHE_RC"

    # 8. Display resolution safety check (userProps.xml) & CC / maxfiles diagnostics
    echo ""
    echo -e "${BOLD}[6/6] Stabilité affichage (userProps.xml) & Diagnostic CC / maxfiles...${NC}"
    query_display_modes
    repair_userprops_xml "$TARGET_DATA_DIR/Config/userProps.xml" "$DISPLAY_CUR" "$DISPLAY_MODES" 0
    count_cc_and_check_maxfiles "$TARGET_DATA_DIR/Downloads" 1

    echo ""
    if [ "$MIGRATION_FAILED" -eq 1 ]; then
        echo -e "${YELLOW}${BOLD}"
        echo "========================================================================"
        echo "  PATCH 120 HZ OK — ACTION REQUISE POUR VOS SAUVEGARDES / ACTION NEEDED"
        echo "========================================================================"
        echo -e "${NC}"
        echo -e "  • ${BOLD}Patch Binaire 120 Hz :${NC} $PATCH_STATUS"
        echo -e "  • ${BOLD}Graphics Rules.sgr   :${NC} $GRULES_STATUS"
        echo -e "  • ${BOLD}Module Trackpad      :${NC} $TRACKPAD_STATUS"
        echo -e "  • ${BOLD}Sauvegardes / Saves  :${NC} $MIGRATION_STATUS"
        echo -e "  • ${BOLD}Dossier Données/Mods :${NC} ~/Library/Application Support/Aspyr/The Sims 2/"
        echo -e "  • ${BOLD}Purge des Caches     :${NC} $CACHE_STATUS"
        echo -e "  • ${BOLD}Affichage userProps  :${NC} $USERPROPS_STATUS"
        echo -e "  • ${BOLD}CC / Limite macOS    :${NC} $CC_MAXFILES_STATUS"
        echo ""
        echo -e "  ${YELLOW}[!] NE LANCEZ PAS ENCORE LES SIMS 2 !${NC}"
        if [ "$MIGRATION_ERROR_KIND" = "TCC_AUTOMATION" ]; then
            echo "      Vos sauvegardes Sandbox n'ont pas encore pu être copiées (Automatisation refusée)."
            echo "      Activez Terminal → Finder dans Réglages Système > Confidentialité et sécurité > Automatisation,"
            echo "      puis relancez simplement patch_sims2.command pour terminer la copie."
            echo ""
            echo -e "  ${YELLOW}[!] DO NOT LAUNCH THE SIMS 2 YET!${NC}"
            echo "      Enable Terminal → Finder in System Settings > Privacy & Security > Automation,"
            echo "      then re-run patch_sims2.command to complete the migration."
        elif [ "$MIGRATION_ERROR_KIND" = "CONTAINER_ACCESS" ]; then
            echo "      macOS a bloqué la copie automatique depuis le conteneur App Store (erreur droits conteneur)."
            echo "      1) Ouvrez dans Finder (Cmd+Maj+G) : ~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/"
            echo "      2) Copiez Neighborhoods et Downloads vers ~/Library/Application Support/Aspyr/The Sims 2/"
            echo "      (Ou activez Réglages Système > Confidentialité et sécurité > Accès complet au disque > Terminal puis relancez.)"
            echo ""
            echo -e "  ${YELLOW}[!] DO NOT LAUNCH THE SIMS 2 YET!${NC}"
            echo "      macOS blocked scripted read inside the Sandbox container (-5000)."
            echo "      Copy Neighborhoods/Downloads manually in Finder into ~/Library/Application Support/Aspyr/The Sims 2/"
            echo "      (or grant Full Disk Access to Terminal and re-run patch_sims2.command)."
        else
            echo "      Vos sauvegardes Sandbox n'ont pas encore pu être copiées (voir message Finder ci-dessus)."
            echo "      Consultez le journal ~/Library/Logs/Sims2-Crash-Patch/latest.log avant de relancer."
        fi
        echo "========================================================================"

        pause_exit 1
    fi

    echo -e "${GREEN}${BOLD}"
    echo "========================================================================"
    echo "  INSTALLATION TERMINÉE AVEC SUCCÈS / PATCH COMPLETE (v1.3.1) !         "
    echo "========================================================================"
    echo -e "${NC}"
    echo -e "  • ${BOLD}Patch Binaire 120 Hz :${NC} $PATCH_STATUS"
    echo -e "  • ${BOLD}Graphics Rules.sgr   :${NC} $GRULES_STATUS"
    echo -e "  • ${BOLD}Module Trackpad      :${NC} $TRACKPAD_STATUS"
    echo -e "  • ${BOLD}Sauvegardes / Saves  :${NC} $MIGRATION_STATUS"
    echo -e "  • ${BOLD}Dossier Données/Mods :${NC} ~/Library/Application Support/Aspyr/The Sims 2/"
    echo -e "  • ${BOLD}Purge des Caches     :${NC} $CACHE_STATUS"
    echo -e "  • ${BOLD}Affichage userProps  :${NC} $USERPROPS_STATUS"
    echo -e "  • ${BOLD}CC / Limite macOS    :${NC} $CC_MAXFILES_STATUS"
    if [ "$MIGRATION_FAILED" -eq 2 ]; then
        echo ""
        echo -e "  ${YELLOW}[i] Note Sandbox :${NC} Vos parties actives dans Application Support sont prêtes et intactes."
        echo "      Si d'anciennes parties manquent encore, copiez-les à la main depuis le Finder :"
        echo "      Cmd+Maj+G -> ~/Library/Containers/com.aspyr.sims2.appstore/Data/Library/Application Support/Aspyr/The Sims 2/"
    fi
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
