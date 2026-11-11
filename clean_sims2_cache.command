#!/bin/bash
# ==============================================================================
# Sims 2: Super Collection — Standalone Sandbox Cache Rescue Utility
# Version: 1.1.0
# No admin password required! Uses native Finder session context.
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
echo "=================================================================="
echo "  The Sims 2 — Utilitaire de Purge des Caches / Cache Cleaner     "
echo "=================================================================="
echo -e "${NC}"

# 1. Check if the game is currently running
if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Attention / Warning:${NC} Les Sims 2 est actuellement ouvert."
    echo "    Fermez le jeu avant de nettoyer les caches pour éviter toute corruption."
    echo "    Please quit The Sims 2 before cleaning caches."
    pause_exit 1
fi

echo -e "${BOLD}[*] Inspection du conteneur Sandbox via Finder...${NC}"
echo "    (Cibles : Groups.cache, Accessory.cache, cAstGroupCache.package)"
echo ""

CACHE_RESULT=$(/usr/bin/osascript <<'OSAEOF'
tell application "Finder"
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
end tell
OSAEOF
)

case "$CACHE_RESULT" in
    DELETED:*)
        FILES_CLEANED="${CACHE_RESULT#DELETED:}"
        echo -e "${GREEN}[+] Caches supprimés avec succès / Caches purged successfully:${NC}"
        echo "    -> $FILES_CLEANED"
        echo ""
        echo -e "${GREEN}${BOLD}Tout est propre !${NC} Vos quartiers et sauvegardes sont intacts."
        echo "Vous pouvez relancer votre quartier immédiatement en toute sécurité."
        echo ""
        echo -e "${GREEN}${BOLD}All clean!${NC} Your neighborhoods and saves are completely safe."
        echo "You can now launch the game and load your neighborhood immediately."
        ;;
    ALREADY_CLEAN)
        echo -e "${GREEN}[i] Vos caches sont déjà propres / Your caches are already clean.${NC}"
        echo "    Aucun fichier corrompu trouvé. Vous pouvez lancer votre jeu normalement !"
        echo "    No corrupted cache files found. You can launch the game normally!"
        ;;
    NO_CONTAINER)
        echo -e "${YELLOW}[i] Dossier Sandbox introuvable / Sandbox folder not found yet.${NC}"
        echo "    Lancez Les Sims 2 une première fois afin que macOS crée le dossier du jeu."
        echo "    Launch The Sims 2 once so macOS creates the user data container."
        ;;
    ERROR:*)
        echo -e "${RED}[-] Erreur / Error:${NC} ${CACHE_RESULT#ERROR:}"
        pause_exit 1
        ;;
esac

pause_exit 0
