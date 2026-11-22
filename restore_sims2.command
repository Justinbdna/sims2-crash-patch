#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — Official Binary Restore Utility
# Version: 1.5.0-rc2
# Verifies pristine fingerprints before atomically restoring Sims2XP_Exe.backup.
# License: MIT — Free, non-profit community software preservation & bug-fix
# utility for lawful owners. No copyrighted game binaries or DRM bypass.
# ==============================================================================

set -u

SCRIPT_VERSION="1.5.0-rc2"

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
RESTORE_STATUS=""
LOG_FILE=""
LOG_FINALIZED=0

init_diagnostic_log() {
    local label="${1:-restore_sims2.command v${SCRIPT_VERSION}}"
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
App    : ${APP_PATH:-unknown}
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
    [ -n "${RESTORE_STATUS:-}" ] && log_diag "SUMMARY restore=$RESTORE_STATUS"
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
    echo "    -> Connectez-vous sur une session Administrateur puis relancez restore_sims2.command."
    echo ""
    echo "    Your macOS account is Standard (non-Admin). Log into an Admin account to run restore_sims2.command."
}

print_pre_sudo_guidance() {
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}CE QUI VA SE PASSER / WHAT TO EXPECT NEXT :${NC}"
    echo "  Tapez votre mot de passe Mac puis appuyez sur Entrée."
    echo -e "  ${YELLOW}NOTE : Aucun caractère (ni '*', ni point) ne s'affichera quand vous tapez,${NC}"
    echo -e "  ${YELLOW}c'est une sécurité normale de macOS (le clavier fonctionne bien).${NC}"
    echo ""
    echo "  Enter your Mac Admin password and press Enter."
    echo -e "  ${YELLOW}NOTE: No characters or '*' appear while typing — this is normal on Mac.${NC}"
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    echo ""
}

cleanup_managed_maxfiles_daemon() {
    local target_plist="${1:-$MANAGED_MAXFILES_PLIST}"
    if [ ! -f "$target_plist" ]; then
        return 0
    fi
    if grep -q "Managed by sims2-crash-patch" "$target_plist" 2>/dev/null; then
        if [ "$target_plist" = "$MANAGED_MAXFILES_PLIST" ]; then
            run_privileged "$target_plist" /bin/launchctl unload -w "$target_plist" >/dev/null 2>&1 || true
        fi
        if run_privileged "$target_plist" rm -f "$target_plist"; then
            echo -e "${GREEN}[+] LaunchDaemon maxfiles géré par le patch supprimé :${NC} $target_plist"
            return 0
        else
            echo -e "${YELLOW}[!] Impossible de supprimer $target_plist (droits insuffisants).${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[i] Fichier conservé :${NC} $target_plist (créé hors sims2-crash-patch, non modifié)."
        return 0
    fi
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
my $repl_asl     = pack("H*", "39f190904139f89090");
my $repl_fb_1280 = pack("H*", "4989c19090909090c745b000040000");
my $repl_fb_1024 = pack("H*", "4c8d4dd090909090904c89e8");
my $repl_fb_1344 = pack("H*", "4c8d4dd09090909090488b9d48ffffff");
my $repl_aspect  = pack("H*", "3b45c077063b4dc4764190");
my $repl_val_p3  = pack("H*", "3d000a0000771581f940060000770deb4b9090909090909090909090");
my $repl_stretch = pack("H*", "e86277fbff84c0eb108b43183b45f0");

if (count_occurrences($buf, $orig1) == 1 &&
    count_occurrences($buf, $orig2) == 1 &&
    count_occurrences($buf, $repl1) == 0 &&
    count_occurrences($buf, $repl2) == 0 &&
    index($buf, $repl_asl) == -1 &&
    index($buf, $repl_fb_1280) == -1 &&
    index($buf, $repl_fb_1024) == -1 &&
    index($buf, $repl_fb_1344) == -1 &&
    index($buf, $repl_aspect) == -1 &&
    index($buf, $repl_val_p3) == -1 &&
    index($buf, $repl_stretch) == -1 &&
    index($buf, "libsims2_trackpad.dylib") == -1) {
    exit 0;
}
exit 1;
PERLEOF
}

restore_auxiliary_files() {
    local app_path="${1:-$APP_PATH}"
    local dylib_path="$app_path/Contents/MacOS/libsims2_trackpad.dylib"
    local grules_path="$app_path/Contents/Resources/Config/Graphics Rules.sgr"
    local grules_backup="$app_path/Contents/Resources/Config/Graphics Rules.sgr.backup"
    local rc=0

    if [ -L "$dylib_path" ]; then
        echo -e "${RED}[-] Erreur de sécurité : lien symbolique inattendu sur $dylib_path.${NC}"
        rc=1
    elif [ -e "$dylib_path" ]; then
        if run_privileged "$app_path" rm -f "$dylib_path"; then
            echo -e "${GREEN}[+] Module Trackpad supprimé :${NC} $dylib_path"
        else
            echo -e "${RED}[-] Impossible de supprimer $dylib_path.${NC}"
            rc=1
        fi
    fi

    if [ -L "$grules_backup" ] || [ -L "$grules_path" ]; then
        echo -e "${RED}[-] Erreur de sécurité : lien symbolique inattendu sur Graphics Rules.sgr.${NC}"
        return 1
    fi

    if [ -f "$grules_backup" ]; then
        local tmp_grules="${grules_path}.tmp.$$"
        run_privileged "$app_path" rm -f "$tmp_grules" 2>/dev/null || true
        if run_privileged "$app_path" cp -f "$grules_backup" "$tmp_grules" && \
           run_privileged "$app_path" chmod 644 "$tmp_grules" && \
           run_privileged "$app_path" mv -f "$tmp_grules" "$grules_path" && \
           run_privileged "$app_path" chmod 644 "$grules_path"; then
            echo -e "${GREEN}[+] Graphics Rules.sgr restauré depuis Graphics Rules.sgr.backup.${NC}"
        else
            run_privileged "$app_path" rm -f "$tmp_grules" 2>/dev/null || true
            echo -e "${RED}[-] Échec de la restauration atomique de Graphics Rules.sgr.${NC}"
            rc=1
        fi
    fi

    return "$rc"
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2 — Utilitaire de Restauration / Restore Utility (v${SCRIPT_VERSION})"
    echo "========================================================================"
    echo -e "${NC}"

    if ! resolve_real_user; then
        pause_exit 1
    fi

    init_diagnostic_log "restore_sims2.command v${SCRIPT_VERSION}"

    # 1. Verify the game is not currently running
    if pgrep -x "Sims2XP_Exe" >/dev/null 2>&1 || pgrep -x "AppBundleExe" >/dev/null 2>&1; then
        RESTORE_STATUS="ABORTED (game running)"
        echo -e "${YELLOW}[!] Attention / Warning:${NC} Le jeu est actuellement en cours d'exécution."
        echo "    Veuillez fermer Les Sims 2 avant de restaurer le binaire d'origine."
        echo "    Please quit The Sims 2 before restoring the original binary."
        pause_exit 1
    fi

    # 2. Locate application bundle (/Applications or ~/Applications)
    if ! locate_app_bundle; then
        RESTORE_STATUS="FAILED (app not found)"
        echo -e "${RED}[-] Erreur / Error:${NC} Jeu introuvable / Game not found at:"
        echo "    /Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
        echo "    (ni dans ~/Applications/The Sims 2.app)"
        pause_exit 1
    fi
    log_diag "TARGET app=$APP_PATH sudo_required=$APP_REQUIRES_SUDO"

    # 3. Locate and verify a pristine backup file
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

    # 4. Request sudo authorization only if needed
    local needs_daemon_sudo=0
    if [ -f "$MANAGED_MAXFILES_PLIST" ] && grep -q "Managed by sims2-crash-patch" "$MANAGED_MAXFILES_PLIST" 2>/dev/null; then
        needs_daemon_sudo=1
    fi

    echo -e "${BOLD}[1/3] Vérification des droits & autorisation administrateur...${NC}"
    if [ "$APP_REQUIRES_SUDO" -eq 1 ] || [ "$needs_daemon_sudo" -eq 1 ]; then
        if ! check_admin_rights "$REAL_USER"; then
            print_non_admin_error
            pause_exit 1
        fi
        if [ "$(id -u)" -ne 0 ]; then
            print_pre_sudo_guidance
        fi
        if ! sudo -v; then
            echo -e "${RED}[-] Échec d'authentification / Authentication failed.${NC}"
            pause_exit 1
        fi
    else
        echo -e "${GREEN}[+] Droits utilisateur suffisants pour $APP_PATH (sudo non requis).${NC}"
    fi

    echo ""
    echo -e "${BOLD}[2/3] Restauration atomique & Re-signature (codesign)...${NC}"
    if [ -L "$SOURCE_BACKUP" ] || [ -L "$EXE_PATH" ]; then
        RESTORE_STATUS="FAILED (symlink target refused)"
        log_diag "RESTORE FAILED symlink refused"
        echo -e "${RED}[-] Erreur de sécurité : lien symbolique inattendu sur le binaire ou la sauvegarde.${NC}"
        pause_exit 1
    fi
    local TMP_RESTORE="$EXE_PATH.tmp.$$"
    run_privileged "$APP_PATH" rm -f "$TMP_RESTORE" 2>/dev/null
    if ! run_privileged "$APP_PATH" cp -f "$SOURCE_BACKUP" "$TMP_RESTORE" || \
       ! run_privileged "$APP_PATH" chmod 755 "$TMP_RESTORE" || \
       ! run_privileged "$APP_PATH" mv -f "$TMP_RESTORE" "$EXE_PATH" || \
       ! run_privileged "$APP_PATH" chmod 755 "$EXE_PATH"; then
        run_privileged "$APP_PATH" rm -f "$TMP_RESTORE" 2>/dev/null
        RESTORE_STATUS="FAILED (atomic restore error)"
        log_diag "RESTORE FAILED"
        echo -e "${RED}[-] Échec de la restauration atomique / Atomic restore failed.${NC}"
        pause_exit 1
    fi

    if ! restore_auxiliary_files "$APP_PATH"; then
        RESTORE_STATUS="FAILED (auxiliary restore error)"
        log_diag "RESTORE AUXILIARY FAILED"
        pause_exit 1
    fi

    if sign_and_verify_app "$APP_PATH"; then
        RESTORE_STATUS="OK (original binary restored & codesign strict verified)"
        log_diag "RESTORE OK + CODESIGN OK"
        echo -e "${GREEN}[+] Signature locale appliquée et vérifiée (--strict) / Ad-hoc signature applied & verified.${NC}"
    else
        RESTORE_STATUS="FAILED (codesign error)"
        log_diag "CODESIGN FAILED"
        pause_exit 1
    fi

    echo ""
    echo -e "${BOLD}[3/3] Nettoyage optionnel (LaunchDaemon maxfiles géré & backups config)...${NC}"
    cleanup_managed_maxfiles_daemon "$MANAGED_MAXFILES_PLIST"

    local USERPROPS_BAK="$REAL_HOME/Library/Application Support/Aspyr/The Sims 2/Config/userProps.xml.backup"
    if [ -f "$USERPROPS_BAK" ]; then
        echo -e "${GREEN}[i] Config affichage :${NC} Votre sauvegarde userProps.xml.backup est intacte dans"
        echo "    $USERPROPS_BAK"
        echo "    (renommez-la en userProps.xml si vous souhaitez rétablir exactement l'ancien fichier)."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "${GREEN}${BOLD}  RESTAURATION TERMINÉE / RESTORATION COMPLETE (v${SCRIPT_VERSION})            ${NC}"
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
