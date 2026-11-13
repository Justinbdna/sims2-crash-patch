#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — Official Binary Restore Utility
# Version: 1.2.2
# Verifies pristine fingerprints before atomically restoring Sims2XP_Exe.backup.
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

is_pristine_binary() {
    local candidate="$1"
    [ -f "$candidate" ] || return 1
    /usr/bin/perl - "$candidate" <<'PERLEOF'
use strict;
use warnings;

my ($p) = @ARGV;
open(my $fh, "<:raw", $p) or exit 1;
local $/;
my $buf = <$fh>;
close($fh);

sub count_occurrences {
    my ($haystack, $needle) = @_;
    my $count = 0;
    my $pos = -1;
    while (($pos = index($haystack, $needle, $pos + 1)) != -1) {
        $count++;
    }
    return $count;
}

my $orig1 = pack("H*", "f20f1045d0f2440f2cf84889df");
my $repl1 = pack("H*", "41bf3c000000909090904889df");
my $orig2 = pack("H*", "41bf3c000000440f45f8c70300000000");
my $repl2 = pack("H*", "41bf3c00000090909090c70300000000");

if (count_occurrences($buf, $orig1) == 1 &&
    count_occurrences($buf, $orig2) == 1 &&
    count_occurrences($buf, $repl1) == 0 &&
    count_occurrences($buf, $repl2) == 0) {
    exit 0;
}
exit 1;
PERLEOF
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2 — Utilitaire de Restauration / Restore Utility (v1.2.2)    "
    echo "========================================================================"
    echo -e "${NC}"

    # 1. Verify the game is not currently running
    if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Attention / Warning:${NC} Le jeu est actuellement en cours d'exécution."
        echo "    Veuillez fermer Les Sims 2 avant de restaurer le binaire d'origine."
        echo "    Please quit The Sims 2 before restoring the original binary."
        pause_exit 1
    fi

    # 2. Locate and verify a pristine backup file
    local SOURCE_BACKUP=""
    if is_pristine_binary "$BACKUP_PATH"; then
        SOURCE_BACKUP="$BACKUP_PATH"
    elif is_pristine_binary "$ALT_BACKUP_PATH"; then
        SOURCE_BACKUP="$ALT_BACKUP_PATH"
    elif [ ! -f "$BACKUP_PATH" ] && [ ! -f "$ALT_BACKUP_PATH" ]; then
        echo -e "${RED}[-] Erreur / Error:${NC} Aucune sauvegarde trouvée :"
        echo "    $BACKUP_PATH"
        echo "    Le patch n'a peut-être jamais été appliqué sur cette installation."
        pause_exit 1
    else
        echo -e "${RED}[-] Erreur d'intégrité / Backup Integrity Error:${NC}"
        echo "    Le fichier de sauvegarde présent ne contient pas les octets d'origine"
        echo "    non modifiés (il a probablement été créé à partir d'un binaire déjà patché)."
        echo "    Pour restaurer une copie 100 % officielle, supprimez l'application et"
        echo "    retéléchargez-la depuis le Mac App Store."
        echo ""
        echo "    The existing backup file does not contain the pristine unpatched bytes."
        echo "    To restore a 100% clean copy, delete the app and re-download it from"
        echo "    the Mac App Store."
        pause_exit 1
    fi

    echo -e "${GREEN}[+] Empreintes d'origine vérifiées dans / Verified pristine backup:${NC} $(basename "$SOURCE_BACKUP")"
    echo ""

    # 3. Request sudo authorization
    echo -e "${BOLD}[1/2] Autorisation administrateur / Administrator authorization${NC}"
    echo "      Requise pour restaurer le binaire d'origine dans /Applications."
    echo ""

    if ! sudo -v; then
        echo -e "${RED}[-] Échec d'authentification / Authentication failed.${NC}"
        pause_exit 1
    fi

    echo ""
    echo -e "${BOLD}[*] Restauration atomique depuis / Atomic restore from:${NC} $(basename "$SOURCE_BACKUP")"
    local TMP_RESTORE="$EXE_PATH.tmp.$$"
    if ! sudo cp -f "$SOURCE_BACKUP" "$TMP_RESTORE" || ! sudo chmod 755 "$TMP_RESTORE" || ! sudo mv -f "$TMP_RESTORE" "$EXE_PATH"; then
        sudo rm -f "$TMP_RESTORE" 2>/dev/null
        echo -e "${RED}[-] Échec de la restauration atomique / Atomic restore failed.${NC}"
        pause_exit 1
    fi

    # 4. Re-sign application bundle locally & verify strictly
    echo ""
    echo -e "${BOLD}[2/2] Re-signature locale & vérification (codesign)...${NC}"
    if sign_and_verify_app "$APP_PATH"; then
        echo -e "${GREEN}[+] Signature locale appliquée et vérifiée (--strict) / Ad-hoc signature applied & verified.${NC}"
    else
        pause_exit 1
    fi

    echo ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "${GREEN}${BOLD}  RESTAURATION TERMINÉE / RESTORATION COMPLETE (v1.2.2)                 ${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo ""
    echo "Le binaire d'origine (vérifié intègre) a été restauré. Note : pour rétablir"
    echo "la signature commerciale officielle d'Aspyr et réactiver l'isolation"
    echo "Sandbox initiale d'Apple, supprimez l'application et retéléchargez-la"
    echo "gratuitement depuis le Mac App Store."
    echo ""
    echo "Important concernant vos sauvegardes : vos fichiers dans"
    echo "~/Library/Application Support/Aspyr/The Sims 2/ ne sont jamais supprimés,"
    echo "mais une version Mac App Store réinstallée (en Sandbox) relira uniquement"
    echo "le conteneur ~/Library/Containers/com.aspyr.sims2.appstore/... (et plantera"
    echo "à nouveau au démarrage si votre écran est réglé sur 120 Hz)."
    echo ""
    echo "------------------------------------------------------------------------"
    echo ""
    echo "The verified original binary has been restored. Note: to restore Aspyr's"
    echo "official commercial signature and re-enable Apple's initial App Sandbox"
    echo "isolation, delete the app and re-download it for free from the Mac App Store."
    echo ""
    echo "Important note about your saves: your files inside"
    echo "~/Library/Application Support/Aspyr/The Sims 2/ are never deleted, but a"
    echo "reinstalled Mac App Store version (running inside the Sandbox) will read"
    echo "from ~/Library/Containers/com.aspyr.sims2.appstore/... (and will crash"
    echo "again on startup if your display is set to 120 Hz)."
    echo "========================================================================"

    pause_exit 0
}

if [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
    main "$@"
fi
