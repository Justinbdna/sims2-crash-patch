#!/usr/bin/env python3
"""
patch_sims2.py
Patch chirurgical pour 'The Sims 2: Super Collection' sur macOS (Apple Silicon / ProMotion 120 Hz).
Force le taux de rafraîchissement à 60 Hz pour éviter le crash SIGSEGV à 0x10081cfca.
"""

import os
import sys
import shutil
import subprocess

TARGET_APP = "/Applications/The Sims 2.app"
TARGET_EXE = os.path.join(TARGET_APP, "Contents/MacOS/Sims2XP_Exe")
BACKUP_EXE = os.path.join(TARGET_APP, "Contents/MacOS/Sims2XP_Exe.backup_original")

# Patch 1 (Principal) : Remplacement de movsd + cvttsd2si par movl $0x3c, %r15d + NOPs
# Adresse VA: 0x1000fe6dc, Offset: 0xfe6dc
P1_ORIG = bytes.fromhex("f2 0f 10 45 d0 f2 44 0f 2c f8")
P1_PATCH = bytes.fromhex("41 bf 3c 00 00 00 90 90 90 90")

# Patch 2 (Fallback CVDisplayLink) : NOP sur CMOVNZ R15D, EAX
# Adresse VA: 0x1000fe741, Offset: 0xfe741
P2_ORIG = bytes.fromhex("44 0f 45 f8")
P2_PATCH = bytes.fromhex("90 90 90 90")

def check_root():
    if os.geteuid() != 0:
        print("[!] Ce script doit être exécuté avec les privilèges root (sudo).")
        print("    Usage : sudo python3 patch_sims2.py")
        sys.exit(1)

def apply_patch():
    print("=" * 60)
    print("Patch Sims 2 Super Collection - ProMotion 120Hz Compatibility")
    print("=" * 60)

    if not os.path.exists(TARGET_EXE):
        print(f"[-] Erreur : Binaire introuvable à {TARGET_EXE}")
        sys.exit(1)

    print(f"[+] Binaire cible : {TARGET_EXE}")

    # 1. Sauvegarde originale
    if not os.path.exists(BACKUP_EXE):
        print(f"[+] Création de la sauvegarde : {BACKUP_EXE}")
        shutil.copy2(TARGET_EXE, BACKUP_EXE)
    else:
        print(f"[i] Sauvegarde déjà existante : {BACKUP_EXE}")

    with open(TARGET_EXE, "rb") as f:
        data = bytearray(f.read())

    # Vérification Patch 1
    p1_count_orig = data.count(P1_ORIG)
    p1_count_patched = data.count(P1_PATCH)

    if p1_count_patched == 1:
        print("[i] Patch 1 (0x1000fe6dc -> 60 Hz) est DÉJÀ appliqué.")
    elif p1_count_orig == 1:
        idx1 = data.index(P1_ORIG)
        print(f"[+] Application du Patch 1 à l'offset 0x{idx1:x} (VA 0x{idx1 + 0x100000000:x})")
        data[idx1 : idx1 + len(P1_PATCH)] = P1_PATCH
    else:
        print(f"[-] Erreur : Empreinte Patch 1 introuvable (count={p1_count_orig}). Binaire non reconnu ou corrompu.")
        sys.exit(1)

    # Vérification Patch 2
    p2_count_orig = data.count(P2_ORIG)
    p2_count_patched = data.count(P2_PATCH)

    # Note: P2_ORIG est court (4 octets), vérifions son offset précis si présent
    if data[0xfe741 : 0xfe741 + 4] == P2_PATCH:
        print("[i] Patch 2 (0x1000fe741 -> NOP CMOVNZ) est DÉJÀ appliqué.")
    elif data[0xfe741 : 0xfe741 + 4] == P2_ORIG:
        print(f"[+] Application du Patch 2 à l'offset 0xfe741 (VA 0x1000fe741)")
        data[0xfe741 : 0xfe741 + 4] = P2_PATCH
    else:
        print(f"[w] Avertissement : Patch 2 offset 0xfe741 octets inattendus ({data[0xfe741:0xfe741+4].hex(' ')}), Patch 1 est prioritaire.")

    # Écriture du binaire patché
    print(f"[+] Écriture du binaire patché...")
    with open(TARGET_EXE, "wb") as f:
        f.write(data)

    # 2. Re-signature ad-hoc avec codesign
    print("[+] Re-signature du bundle avec codesign...")
    cmd = ["codesign", "--force", "--deep", "--sign", "-", TARGET_APP]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[-] Erreur lors du codesign : {res.stderr}")
        sys.exit(1)
    print("[+] Signature ad-hoc appliquée avec succès !")

    print("\n" + "=" * 60)
    print("PATCH APPLIQUÉ AVEC SUCCÈS !")
    print("Le jeu Sims 2 s'exécutera désormais à 60 FPS constants sans planter")
    print("sur votre écran ProMotion 120 Hz.")
    print("=" * 60)

if __name__ == "__main__":
    check_root()
    apply_patch()
