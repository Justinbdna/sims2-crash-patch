#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — Standalone Dual-Location Cache Cleaner
# Version: 1.2.2
# No administrator password required! Purges both Non-Sandbox & Sandbox caches.
# ==============================================================================

set -u

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
SANDBOX_FAILED=0

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

is_tcc_automation_error() {
    local msg="$1"
    printf '%s\n' "$msg" | grep -qiE '(-1743|1743|not authorized to send apple events|apple ?event|non autoris)'
}

print_finder_automation_help() {
    echo "    -> Permission Automatisation Finder requise / Finder Automation permission required."
    echo "    -> Réglages Système -> Confidentialité et sécurité -> Automatisation -> Terminal -> activez Finder."
    echo "    -> System Settings -> Privacy & Security -> Automation -> Terminal -> enable Finder."
}

handle_clean_sandbox_result() {
    local result="$1"
    local rc="$2"

    SANDBOX_FAILED=0

    if [ "$rc" -ne 0 ]; then
        case "$result" in
            ERROR:*) ;;
            *) result="ERROR:${result:-osascript exit code $rc}" ;;
        esac
    fi

    case "$result" in
        DELETED:*)
            local files_cleaned="${result#DELETED:}"
            echo -e "${GREEN}[+] Conteneur Sandbox (Ancien)  : Placés dans la Corbeille / Moved to Trash ->${NC} $files_cleaned"
            ;;
        ALREADY_CLEAN)
            echo -e "${GREEN}[i] Conteneur Sandbox (Ancien)  : Déjà propre / Already clean.${NC}"
            ;;
        NO_CONTAINER)
            echo -e "${YELLOW}[i] Conteneur Sandbox (Ancien)  : Aucun conteneur détecté.${NC}"
            ;;
        ERROR:*)
            local err_msg="${result#ERROR:}"
            echo -e "${YELLOW}[!] Conteneur Sandbox (Ancien)  : Erreur Finder ($err_msg)${NC}"
            if is_tcc_automation_error "$err_msg"; then
                print_finder_automation_help
            fi
            SANDBOX_FAILED=1
            ;;
        *)
            echo -e "${YELLOW}[!] Conteneur Sandbox (Ancien)  : Réponse inattendue (${result:-<vide / empty>}, code $rc)${NC}"
            if is_tcc_automation_error "$result"; then
                print_finder_automation_help
            fi
            SANDBOX_FAILED=1
            ;;
    esac
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2 — Utilitaire de Purge des Caches / Cache Cleaner (v1.2.2)  "
    echo "========================================================================"
    echo -e "${NC}"

    if ! resolve_real_user; then
        pause_exit 1
    fi

    if [ "$(id -u)" -eq 0 ]; then
        echo -e "${YELLOW}[i] Note : sudo n'est pas nécessaire pour cet outil (contexte utilisateur $REAL_USER conservé).${NC}"
        echo ""
    fi

    # 1. Check if the game is currently running
    if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Attention / Warning:${NC} Les Sims 2 est actuellement ouvert."
        echo "    Fermez le jeu avant de nettoyer les caches pour éviter toute corruption."
        echo "    Please quit The Sims 2 before cleaning caches."
        pause_exit 1
    fi

    echo -e "${BOLD}[*] Nettoyage des caches dans les deux emplacements (Non-Sandbox + Sandbox)...${NC}"
    echo "    (Utilisateur : $REAL_USER | Cibles : Groups.cache, Accessory.cache, cAstGroupCache.package)"
    echo ""

    # 2. Location 1: Non-Sandbox directory (~/Library/Application Support/Aspyr/The Sims 2/)
    local TARGET_DATA_DIR="$REAL_HOME/Library/Application Support/Aspyr/The Sims 2"
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
        if [ ${#POSIX_DELETED[@]} -gt 0 ]; then
            echo -e "${GREEN}[+] Application Support (Actif) : Supprimés (rm -f) ->${NC} ${POSIX_DELETED[*]}"
        else
            echo -e "${GREEN}[i] Application Support (Actif) : Déjà propre / Already clean.${NC}"
        fi
    else
        echo -e "${YELLOW}[i] Application Support (Actif) : Dossier non créé pour le moment.${NC}"
    fi

    # 3. Location 2: Sandbox container via Finder Automation permission (moves to Trash)
    local SANDBOX_RESULT SANDBOX_RC
    SANDBOX_RESULT="$(run_as_real_user /usr/bin/osascript 2>&1 <<'OSAEOF'
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
    SANDBOX_RC=$?

    handle_clean_sandbox_result "$SANDBOX_RESULT" "$SANDBOX_RC"

    echo ""
    if [ "$SANDBOX_FAILED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}========================================================================${NC}"
        echo -e "${GREEN}${BOLD}  NETTOYAGE TERMINÉ / CACHE PURGE COMPLETE (v1.2.2) !                   ${NC}"
        echo -e "${GREEN}${BOLD}========================================================================${NC}"
        echo "  Vos quartiers, familles et mods (Downloads) sont 100 % intacts."
        echo "  Vous pouvez relancer Les Sims 2 et charger votre quartier en sécurité."
        echo ""
        echo "  Your neighborhoods, families, and mods (Downloads) are 100% untouched."
        echo "  You can now relaunch The Sims 2 and load your neighborhood safely."
        echo "========================================================================"
        pause_exit 0
    else
        echo -e "${YELLOW}${BOLD}========================================================================${NC}"
        echo -e "${YELLOW}${BOLD}  NETTOYAGE PARTIEL / PARTIAL CLEANUP (v1.2.2)                          ${NC}"
        echo -e "${YELLOW}${BOLD}========================================================================${NC}"
        echo "  Le dossier actif Application Support a été vérifié/nettoyé, mais le"
        echo "  conteneur Sandbox n'a pas pu être inspecté via Finder (voir message"
        echo "  ci-dessus). Si vous utilisez une version non patchée en Sandbox,"
        echo "  autorisez Automatisation -> Terminal -> Finder puis relancez ce script."
        echo ""
        echo "  The active Application Support folder was processed, but the legacy"
        echo "  Sandbox container could not be accessed via Finder (see warning above)."
        echo "========================================================================"
        pause_exit 1
    fi
}

if [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
    main "$@"
fi
