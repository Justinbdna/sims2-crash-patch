#!/bin/bash
# ==============================================================================
# Sims 2: Super Collection — ProMotion 120Hz Fix & Sandbox Cache Auto-Healer
# Version: 1.1.0
# Target:  /Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe
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

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "  The Sims 2: Super Collection — ProMotion 120Hz Patch (v1.1.0)   "
echo "=================================================================="
echo -e "${NC}"

# 1. Verify application presence
if [ ! -f "$EXE_PATH" ]; then
    echo -e "${RED}[-] Erreur / Error:${NC} Jeu introuvable / Game not found at:"
    echo "    $EXE_PATH"
    echo "    Vérifiez que The Sims 2 est installé dans /Applications."
    pause_exit 1
fi

# 2. Check if the game is currently running
if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Attention / Warning:${NC} Le jeu semble être en cours d'exécution."
    echo "    Veuillez fermer Les Sims 2 avant d'appliquer le patch."
    echo "    Please quit The Sims 2 before running this patch."
    pause_exit 1
fi

# 3. Elevate privileges ONLY for /Applications bundle modifications
echo -e "${BOLD}[1/4] Demande d'autorisation administrateur / Admin authorization${NC}"
echo "      Requis uniquement pour modifier l'application dans /Applications."
echo "      Required only to modify the app bundle in /Applications."
echo ""

if ! sudo -v; then
    echo -e "${RED}[-] Échec d'authentification / Authentication failed.${NC}"
    pause_exit 1
fi

# 4. Surgical Binary Patch (Idempotent & Fingerprint-Anchored)
echo ""
echo -e "${BOLD}[2/4] Application du patch binaire 60Hz / Applying 60Hz binary patch...${NC}"

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

open(my $fh, "<:raw", $exe_path) or die "Impossible de lire le binaire / Cannot read binary: $!\n";
local $/;
my $data = <$fh>;
close($fh);

# Create backup before mutating if no backup exists yet
if (!-e $backup_path) {
    if (-e $alt_backup_path) {
        print "[+] Sauvegarde créée depuis backup_original / Backup created from backup_original.\n";
        copy($alt_backup_path, $backup_path) or die "Backup copy failed: $!\n";
    } else {
        print "[+] Création de la sauvegarde / Creating backup: Sims2XP_Exe.backup\n";
        copy($exe_path, $backup_path) or die "Backup copy failed: $!\n";
    }
    chmod(0755, $backup_path);
} else {
    print "[i] Sauvegarde existante conservée / Existing backup preserved.\n";
}

# Dual anchored patch:
# - Patch 1 (0xFE6DC): Overrides Quartz _CGDisplayModeGetRefreshRate result -> forces R15D = 60Hz (0x3c) before JNE jump.
# - Patch 2 (0xFE741): NOPs CMOVNZ R15D, EAX inside _CVDisplayLink fallback (anchored by MOV R15D, 0x3c + MOV [RBX], 0).
my @patches = (
    [
        "Patch 1 (0xfe6dc - Quartz 60Hz Lock)",
        pack("H*", "f20f1045d0f2440f2cf84889df"),
        pack("H*", "41bf3c000000909090904889df")
    ],
    [
        "Patch 2 (0xfe741 - Fallback CMOVNZ NOP)",
        pack("H*", "41bf3c000000440f45f8c70300000000"),
        pack("H*", "41bf3c00000090909090c70300000000")
    ]
);

my $changed = 0;

for my $entry (@patches) {
    my ($label, $orig, $repl) = @$entry;
    my $orig_count = count_occurrences($data, $orig);
    my $repl_count = count_occurrences($data, $repl);

    if ($repl_count == 1 && $orig_count == 0) {
        print "[i] $label : Déjà appliqué / Already applied.\n";
    } elsif ($orig_count == 1) {
        my $offset = index($data, $orig);
        substr($data, $offset, length($orig), $repl);
        printf("[+] %s : Patch appliqué à l'offset 0x%x !\n", $label, $offset);
        $changed = 1;
    } else {
        print STDERR "[-] ERREUR : Empreinte introuvable ou ambiguë pour $label (orig=$orig_count, patched=$repl_count).\n";
        print STDERR "[-] Binaire non modifié pour protéger votre jeu.\n";
        exit 1;
    }
}

if ($changed) {
    open(my $out, ">:raw", $exe_path) or die "Impossible d'écrire le binaire / Cannot write binary: $!\n";
    print {$out} $data;
    close($out);
    chmod(0755, $exe_path);
    print "[+] Binaire mis à jour sur le disque / Binary written to disk.\n";
} else {
    print "[i] Aucune écriture nécessaire / Binary already up to date.\n";
}
PERLEOF
then
    echo -e "${RED}[-] Le patch binaire a échoué / Binary patch failed.${NC}"
    pause_exit 1
fi

# 5. Ad-hoc Code Signing
echo ""
echo -e "${BOLD}[3/4] Re-signature cryptographique ad-hoc (codesign)...${NC}"
if sudo /usr/bin/codesign --force --deep --sign - "$APP_PATH"; then
    echo -e "${GREEN}[+] Signature valide appliquée / Valid ad-hoc signature applied.${NC}"
else
    echo -e "${RED}[-] Erreur lors du codesign / codesign failed.${NC}"
    pause_exit 1
fi

# 6. One-Shot Sandbox Cache Purge in REAL user context (Finder AppleScript bypasses TCC EPERM)
echo ""
echo -e "${BOLD}[4/4] Assainissement des caches Sandbox / Purging corrupted caches...${NC}"

run_finder_purge() {
    /usr/bin/osascript <<'OSAEOF'
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
}

if [ "$(id -u)" -eq 0 ]; then
    REAL_USER="${SUDO_USER:-$(stat -f "%Su" /dev/console)}"
    CACHE_RESULT=$(sudo -u "$REAL_USER" bash -c "$(declare -f run_finder_purge); run_finder_purge")
else
    CACHE_RESULT=$(run_finder_purge)
fi

case "$CACHE_RESULT" in
    DELETED:*)
        FILES_CLEANED="${CACHE_RESULT#DELETED:}"
        echo -e "${GREEN}[+] Caches corrompus purgés / Corrupted caches purged:${NC} $FILES_CLEANED"
        ;;
    ALREADY_CLEAN)
        echo -e "${GREEN}[+] Caches Sandbox déjà propres / Sandbox caches already clean.${NC}"
        ;;
    NO_CONTAINER)
        echo -e "${YELLOW}[i] Aucun cache existant (première exécution) / No cache folder yet (fresh install).${NC}"
        ;;
    ERROR:*)
        echo -e "${YELLOW}[!] Avertissement lors de la purge Finder:${NC} ${CACHE_RESULT#ERROR:}"
        echo "    Vous pourrez exécuter clean_sims2_cache.command si besoin."
        ;;
esac

echo ""
echo -e "${GREEN}${BOLD}"
echo "=================================================================="
echo "  SUCCÈS TOTAL / PATCH & CACHE HEALING COMPLETE !                 "
echo "=================================================================="
echo -e "${NC}"
echo "  Vous pouvez maintenant lancer The Sims 2 normalement depuis"
echo "  le Launchpad ou votre dossier Applications !"
echo ""
echo "  You can now launch The Sims 2 normally from Launchpad or your"
echo "  Applications folder — no need to lower your 120Hz display!"
echo "=================================================================="

pause_exit 0
