#!/bin/bash
# ==============================================================================
# The Sims 2: Super Collection — Maintenance, Caches & Display Reset Utility
# Version: 1.4.0
# Safe dual-location cache cleaner, userProps.xml display reset, CC/maxfiles check.
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
DISPLAY_CUR=""
DISPLAY_MODES=""
USERPROPS_STATUS=""
MAXFILES_SOFT=""
MAXFILES_HARD=""
CC_MAXFILES_STATUS=""
CACHE_STATUS=""
MANAGED_MAXFILES_PLIST="/Library/LaunchDaemons/limit.maxfiles.plist"
LOG_FILE=""
LOG_FINALIZED=0

init_diagnostic_log() {
    local label="${1:-clean_sims2_cache.command v1.4.0}"
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
    sudo "$@"
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
    echo "    -> Connectez-vous sur une session Administrateur pour modifier /Library/LaunchDaemons."
    echo ""
    echo "    Your macOS account is Standard (non-Admin). Log into an Admin account to install LaunchDaemons."
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
// Real macOS hardware modes only (no synthetic catalog): whitelist + current desktop mode.
var whitelist = {
    "1280x800": 1, "1440x900": 1, "1512x982": 1, "1680x1050": 1,
    "1800x1169": 1, "2048x1280": 1, "2560x1600": 1,
    "1728x1080": 1, "1920x1080": 1, "1920x1200": 1, "2560x1440": 1
};
var notchedMap = {};
function isAllowedNonNotched(w, h) {
    if (w < 800 || h < 600 || w <= h || w > 2560 || h > 1600) return false;
    if (w === curW && h === curH) return true;
    return whitelist[w + "x" + h] === 1;
}
var seen = {};
if (isAllowedNonNotched(curW, curH)) seen[curW + "x" + curH] = 1;
var optsDict = $.CFDictionaryCreateMutable($(), 1, $.kCFTypeDictionaryKeyCallBacks, $.kCFTypeDictionaryValueCallBacks);
$.CFDictionarySetValue(optsDict, $.kCGDisplayShowDuplicateLowResolutionModes, $.kCFBooleanTrue);
var arr = ObjC.castRefToObject($.CGDisplayCopyAllDisplayModes(did, optsDict) || $.CGDisplayCopyAllDisplayModes(did, $()));
if (arr && arr.count) {
    for (var i = 0; i < arr.count; i++) {
        var m = arr.objectAtIndex(i);
        var w = Math.round($.CGDisplayModeGetWidth(m));
        var h = Math.round($.CGDisplayModeGetHeight(m));
        if (isAllowedNonNotched(w, h)) {
            seen[w + "x" + h] = 1;
        }
    }
}
var screens = $.NSScreen.screens;
if (screens && screens.count) {
    for (var j = 0; j < screens.count; j++) {
        var f = screens.objectAtIndex(j).frame;
        var sw = Math.round(f.size.width);
        var sh = Math.round(f.size.height);
        if (isAllowedNonNotched(sw, sh)) {
            seen[sw + "x" + sh] = 1;
        }
        if ((curW === 0 || curH === 0) && sw > 0 && sh > 0) {
            curW = sw;
            curH = sh;
        }
    }
}
var curKey = curW + "x" + curH;
if (notchedMap[curKey]) {
    var mapped = notchedMap[curKey].split("x");
    curW = parseInt(mapped[0], 10);
    curH = parseInt(mapped[1], 10);
}
if (curW > 2560 || curH > 1600) {
    curW = 1280;
    curH = 800;
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
    my $tmp = "$p.tmp.$$";
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

# Native notched modes (1800x1169, 1512x982...) are kept as-is: the engine's
# cDeviceEnumDX only accepts modes really exposed by macOS.
my %notched_map = ();

my $fallback_res = ($cur_res && $cur_res =~ /^\d+x\d+$/) ? $cur_res : "1280x800";
if (exists $notched_map{$fallback_res} && $supported{$notched_map{$fallback_res}}) {
    $fallback_res = $notched_map{$fallback_res};
}
if ($fallback_res =~ /^(\d+)x(\d+)$/ && ($1 > 2560 || $2 > 1600)) {
    $fallback_res = "1280x800";
}
my $target_mode = "";
my $need_fix = 0;

if ($old_mode =~ /^(\d+)x(\d+)x(\d+)x(\d+)$/) {
    my ($w, $h, $bpp, $hz) = ($1, $2, $3, $4);
    my $res_key = "${w}x${h}";
    my $res_known_ok = 1;

    if ($w < 800 || $h < 600 || $w > 2560 || $h > 1600) {
        $res_known_ok = 0;
    } elsif (exists $notched_map{$res_key} && $supported{$notched_map{$res_key}}) {
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
            echo -e "${GREEN}[+] userProps.xml : Réparé ($change) !${NC}"
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

    if [ "$target_plist" = "$MANAGED_MAXFILES_PLIST" ] && [ "$(id -u)" -ne 0 ]; then
        echo ""
        echo -e "  ${YELLOW}NOTE MOT DE PASSE : Aucun caractère (ni '*') ne s'affichera quand vous tapez,${NC}"
        echo -e "  ${YELLOW}c'est une sécurité normale de macOS. Tapez votre mot de passe Mac + Entrée.${NC}"
        echo ""
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
    else
        echo -e "${GREEN}[i] Mods / CC (Downloads) :${NC} Dossier Downloads absent (aucun CC installé)."
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

purge_all_caches() {
    local TARGET_DATA_DIR="$1"
    local CACHE_FILES=("Groups.cache" "Accessory.cache" "cAstGroupCache.package")
    local POSIX_DELETED=()
    local cf

    # 1. Location 1: Direct POSIX path (Option A un-sandboxed active folder)
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

    # 2. Location 2: Sandbox container via Finder Automation permission (moves to Trash)
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
}

run_menu_choice() {
    local choice="$1"
    local TARGET_DATA_DIR="$2"

    case "$choice" in
        1|2|3)
            init_diagnostic_log "clean_sims2_cache.command v1.4.0 (menu=$choice)"
            ;;
    esac

    case "$choice" in
        1)
            echo ""
            echo -e "${BOLD}[1/1] Purge des caches corrompus (Actif + Sandbox)...${NC}"
            purge_all_caches "$TARGET_DATA_DIR"
            if [ "$SANDBOX_FAILED" -eq 0 ]; then
                CACHE_STATUS="Purge réussie (Actif + Sandbox)"
            else
                CACHE_STATUS="Actif traité ; avertissement Sandbox ($SANDBOX_FAILED)"
            fi
            echo ""
            if [ "$SANDBOX_FAILED" -eq 0 ]; then
                echo -e "${GREEN}${BOLD}========================================================================${NC}"
                echo -e "${GREEN}${BOLD}  NETTOYAGE TERMINÉ / CACHE PURGE COMPLETE (v1.4.0) !                   ${NC}"
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
                echo -e "${YELLOW}${BOLD}  NETTOYAGE PARTIEL / PARTIAL CLEANUP (v1.4.0)                          ${NC}"
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
            ;;
        2)
            echo ""
            echo -e "${BOLD}[*] Réinitialisation sécurité affichage / Display reset (userProps.xml)...${NC}"
            local userprops_path="$TARGET_DATA_DIR/Config/userProps.xml"
            query_display_modes
            if [ -n "$DISPLAY_CUR" ]; then
                echo -e "    Résolution logique détectée sur cet écran : ${BOLD}${DISPLAY_CUR}${NC} (60 Hz cible)"
            else
                echo "    Écran principal non lu — fallback sûr 1280x800x32x60."
            fi
            if repair_userprops_xml "$userprops_path" "$DISPLAY_CUR" "$DISPLAY_MODES" 1; then
                if [ -f "$userprops_path.backup" ]; then
                    echo "    Pour annuler ce changement : remplacez userProps.xml par userProps.xml.backup."
                fi
                pause_exit 0
            else
                pause_exit 1
            fi
            ;;
        3)
            echo ""
            echo -e "${BOLD}[*] Diagnostic Mods / CC & Limite système macOS (maxfiles)...${NC}"
            count_cc_and_check_maxfiles "$TARGET_DATA_DIR/Downloads" 1
            pause_exit 0
            ;;
        4)
            echo "Fermeture / Exiting."
            exit 0
            ;;
    esac
}

main() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "  The Sims 2 — Maintenance, Caches & Affichage / Utility (v1.4.0)       "
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
        echo "    Fermez le jeu avant d'utiliser cet utilitaire pour éviter toute corruption."
        echo "    Please quit The Sims 2 before running this utility."
        pause_exit 1
    fi

    local TARGET_DATA_DIR="$REAL_HOME/Library/Application Support/Aspyr/The Sims 2"
    echo -e "[i] Utilisateur actif : ${BOLD}$REAL_USER${NC} ($REAL_HOME)"

    if [ "${1:-}" = "--auto" ] || [ "${1:-}" = "--clean" ]; then
        run_menu_choice 1 "$TARGET_DATA_DIR"
        return $?
    fi

    if [ -n "${SIMS2_MENU_CHOICE:-}" ]; then
        case "$SIMS2_MENU_CHOICE" in
            1|2|3|4)
                run_menu_choice "$SIMS2_MENU_CHOICE" "$TARGET_DATA_DIR"
                return $?
                ;;
        esac
    fi

    echo ""
    echo -e "${BOLD}Que souhaitez-vous faire ? / What would you like to do?${NC}"
    echo "  [1] Nettoyer les caches (recommandé — appui sur Entrée) / Clean caches [Default]"
    echo "  [2] Réparer / réinitialiser l'affichage (userProps.xml 60Hz) / Reset screen resolution"
    echo "  [3] Vérifier vos Mods (.package, .zip) & limite maxfiles / Diagnostics"
    echo "  [4] Quitter / Quit"
    echo ""

    local choice=""
    while true; do
        if ! read -r -p "Votre choix [1/2/3/4] (Entrée = 1) : " choice; then
            echo ""
            exit 0
        fi
        [ -z "$choice" ] && choice="1"
        case "$choice" in
            1|2|3|4)
                run_menu_choice "$choice" "$TARGET_DATA_DIR"
                return $?
                ;;
            *)
                echo -e "${YELLOW}[!] Choix invalide ($choice). Tapez 1, 2, 3 ou 4.${NC}"
                ;;
        esac
    done
}

if [ "${SIMS2_LIB_ONLY:-0}" != "1" ]; then
    main "$@"
fi
