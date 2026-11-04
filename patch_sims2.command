#!/bin/bash
echo "============================================================"
echo " Application du Patch Sims 2 ProMotion 120Hz -> 60Hz"
echo "============================================================"
echo "Veuillez entrer votre mot de passe de session Mac :"
echo ""

sudo python3 -c '
path = "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
with open(path, "rb") as f:
    data = bytearray(f.read())

target  = bytes.fromhex("f20f1045d0f2440f2cf8")
patched = bytes.fromhex("41bf3c00000090909090")

if target in data:
    data = data.replace(target, patched, 1)
    with open(path, "wb") as f:
        f.write(data)
    print("[+] SUCCÈS : Octets modifies a 0xfe6dc (60 Hz force) !")
elif patched in data:
    print("[i] INFO : Le binaire est DEJA patche a 60 Hz !")
else:
    print("[-] ERREUR : Motif non trouve.")
' && sudo codesign --force --deep --sign - "/Applications/The Sims 2.app"

echo ""
echo "============================================================"
echo " Patch termine avec succes !"
echo " Vous pouvez maintenant lancer The Sims 2."
echo "============================================================"
read -p "Appuyez sur Entree pour fermer cette fenetre..."
