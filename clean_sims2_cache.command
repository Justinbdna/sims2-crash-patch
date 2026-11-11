#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — Standalone Dual-Location Cache Cleaner
# Version: 1.2.1
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

pause_exit() {
    local code="${1:-0}"
    echo ""
    read -r -p "Appuyez sur Entrée pour fermer / Press Enter to close..."
    exit "$code"
}

echo -e "${CYAN}${BOLD}"
echo "========================================================================"
echo "  The Sims 2 — Utilitaire de Purge des Caches / Cache Cleaner (v1.2.1)  "
echo "========================================================================"
echo -e "${NC}"

# 1. Check if the game is currently running
if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Attention / Warning:${NC} Les Sims 2 est actuellement ouvert."
    echo "    Fermez le jeu avant de nettoyer les caches pour éviter toute corruption."
    echo "    Please quit The Sims 2 before cleaning caches."
    pause_exit 1
fi

echo -e "${BOLD}[*] Nettoyage des caches dans les deux emplacements (Non-Sandbox + Sandbox)...${NC}"
echo "    (Cibles : Groups.cache, Accessory.cache, cAstGroupCache.package)"
echo ""

# 2. Location 1: Non-Sandbox directory (~/Library/Application Support/Aspyr/The Sims 2/)
TARGET_DATA_DIR="$HOME/Library/Application Support/Aspyr/The Sims 2"
CACHE_FILES=("Groups.cache" "Accessory.cache" "cAstGroupCache.package")
POSIX_DELETED=()

if [ -d "$TARGET_DATA_DIR" ]; then
    for cf in "${CACHE_FILES[@]}"; do
        if [ -e "$TARGET_DATA_DIR/$cf" ]; then
            rm -f "$TARGET_DATA_DIR/$cf"
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
SANDBOX_RESULT=$(/usr/bin/osascript <<'OSAEOF'
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

case "$SANDBOX_RESULT" in
    DELETED:*)
        FILES_CLEANED="${SANDBOX_RESULT#DELETED:}"
        echo -e "${GREEN}[+] Conteneur Sandbox (Ancien)  : Placés dans la Corbeille / Moved to Trash ->${NC} $FILES_CLEANED"
        ;;
    ALREADY_CLEAN)
        echo -e "${GREEN}[i] Conteneur Sandbox (Ancien)  : Déjà propre / Already clean.${NC}"
        ;;
    NO_CONTAINER)
        echo -e "${YELLOW}[i] Conteneur Sandbox (Ancien)  : Aucun conteneur détecté.${NC}"
        ;;
    ERROR:*)
        echo -e "${YELLOW}[!] Conteneur Sandbox (Ancien)  : Avertissement (${SANDBOX_RESULT#ERROR:})${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}  NETTOYAGE TERMINÉ / CACHE PURGE COMPLETE (v1.2.1) !                   ${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo "  Vos quartiers, familles et mods (Downloads) sont 100 % intacts."
echo "  Vous pouvez relancer Les Sims 2 et charger votre quartier en sécurité."
echo ""
echo "  Your neighborhoods, families, and mods (Downloads) are 100% untouched."
echo "  You can now relaunch The Sims 2 and load your neighborhood safely."
echo "========================================================================"

pause_exit 0
