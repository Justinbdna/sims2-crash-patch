#!/usr/bin/env python3
"""
restore_sims2.py
Restaure le binaire original de 'The Sims 2: Super Collection'.
"""

import os
import sys
import shutil
import subprocess

TARGET_APP = "/Applications/The Sims 2.app"
TARGET_EXE = os.path.join(TARGET_APP, "Contents/MacOS/Sims2XP_Exe")
BACKUP_EXE = os.path.join(TARGET_APP, "Contents/MacOS/Sims2XP_Exe.backup_original")
ALT_BACKUP = os.path.join(TARGET_APP, "Contents/MacOS/Sims2XP_Exe.backup")

def check_root():
    if os.geteuid() != 0:
        print("[!] Ce script doit être exécuté avec les privilèges root (sudo).")
        print("    Usage : sudo python3 restore_sims2.py")
        sys.exit(1)

def restore():
    src = None
    if os.path.exists(BACKUP_EXE):
        src = BACKUP_EXE
    elif os.path.exists(ALT_BACKUP):
        src = ALT_BACKUP

    if not src:
        print("[-] Aucune sauvegarde trouvée.")
        sys.exit(1)

    print(f"[+] Restauration depuis {src} vers {TARGET_EXE}...")
    shutil.copy2(src, TARGET_EXE)

    print("[+] Re-signature du bundle avec codesign...")
    cmd = ["codesign", "--force", "--deep", "--sign", "-", TARGET_APP]
    subprocess.run(cmd, check=True)
    print("[+] Restauration terminée avec succès !")

if __name__ == "__main__":
    check_root()
    restore()
