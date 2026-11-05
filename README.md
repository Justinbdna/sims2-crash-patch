# 💎 Sims 2 Crash Patch — Super Collection on macOS (Apple Silicon)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20(M1--M4)-black.svg?style=flat&logo=apple)](https://apple.com)
[![Tested on](https://img.shields.io/badge/Tested%20on-ProMotion%20120Hz-success)](https://apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Fix permanent à 60 FPS pour *The Sims 2: Super Collection* sur les Mac équipés d'écrans ProMotion (120 Hz).**  
> *A permanent surgical 60 FPS compatibility fix for The Sims 2: Super Collection (Mac App Store version by Aspyr) on Apple Silicon Macs with 120 Hz ProMotion displays.*

---

## 🎮 The Problem / Le Problème

Sur les MacBook Pro Apple Silicon (M1/M2/M3/M4 Pro & Max) avec écran **ProMotion 120 Hz**, le jeu plante systématiquement ~2 secondes après le lancement (`SIGSEGV` / `std::__terminate` à l'adresse `0x10081cfca`).

Jusqu'à présent, la seule solution de repli était de **brider tout l'écran de son Mac à 60 Hz** dans les *Réglages Système > Écrans*.

Puisqu'Aspyr n'a **pas mis à jour le jeu sur le Mac App Store depuis plus de 5 ans**, ce patch communautaire résout définitivement le problème à la racine dans le binaire du jeu :
* ✅ Votre Mac reste à **120 Hz ProMotion fluide** pour tout le reste de votre système.
* ✅ Le jeu tourne à **60 FPS stables sans jamais planter**.
* ✅ 100 % réversible en un clic grâce au script de restauration.

---

## 🚀 Quick Install (1-Click) / Installation Rapide

### Option A: Double-Click (Recommandé pour tous les joueurs)
1. Téléchargez ou clonez ce dossier (*ou téléchargez l'archive `.zip`*).
2. Double-cliquez sur **`patch_sims2.command`**.
3. Entrez votre mot de passe administrateur Mac si demandé (nécessaire pour autoriser l'écriture dans `/Applications`).
4. **C'est tout !** Lancez Les Sims 2 normalement depuis vos Applications.

### Option B: Terminal One-Liner (Pour les geeks)
Ouvrez le Terminal et copiez-collez cette commande :
```bash
sudo python3 -c '
path = "/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe"
with open(path, "rb") as f: data = bytearray(f.read())
target = bytes.fromhex("f20f1045d0f2440f2cf8")
patched = bytes.fromhex("41bf3c00000090909090")
if target in data:
    data = data.replace(target, patched, 1)
    with open(path, "wb") as f: f.write(data)
    print("SUCCÈS : Patch appliqué !")
else:
    print("Déjà patché ou motif introuvable.")
' && sudo codesign --force --deep --sign - "/Applications/The Sims 2.app"
```

---

## 🔬 Technical Root Cause Analysis / Analyse Technique

### Target Environment
* **Application:** *The Sims 2: Super Collection* (Mac App Store, `com.aspyr.sims2.appstore`, version 1.2.5).
* **Binary:** `/Applications/The Sims 2.app/Contents/MacOS/Sims2XP_Exe` (Mach-O x86_64 émulé via Rosetta 2).
* **Outillage utilisé :** **Ghidra 12.2** (*Sims2Debug project*) & **Antigravity** (Analyse binaire machine).
* **Crash Stack :**
  ```text
  0  libc++abi.dylib    std::__terminate(void (*)()) + 6
  1  libc++abi.dylib    __cxxabiv1::failed_throw(__cxxabiv1::__cxa_exception*) + 27
  2  libc++abi.dylib    __cxa_throw + 69
  3  Sims2XP_Exe        0x10081cfc6 (FUN_10081a5c0 + offset 8507334)
  ```

### Mécanisme du Bug
1. Dans `FUN_1000fe510` (à `0x1000fe665`), le jeu interroge Quartz via `_CGDisplayModeGetRefreshRate`.
2. Sur écran ProMotion (120 Hz), Quartz renvoie `120.0`.
3. À `0x1000fe6e1`, `cvttsd2si %xmm0, %r15d` convertit le flottant en entier `120` (`0x78`) dans le registre `R15D`.
4. À `0x1000fe6f7`, `testl %r15d, %r15d` suivi de `jne 0x1000fe745` saute immédiatement vers `0x1000fe745`, court-circuitant le code de repli standard.
5. À `0x1000fe790`, `movl %r15d, 0xc(%rbx)` écrit `120` dans la structure du mode d'affichage.
6. Dans `FUN_10081a5c0`, le validateur de modes vidéo (`0x101769030`) rejette les résolutions à 120 Hz et renvoie `0` (aucun mode compatible).
7. À `0x10081a8ca`, `je 0x10081cf8f` branche sur `___cxa_throw` à `0x10081cfca`. Faute de bloc `catch`, `std::__terminate` déclenche un crash matériel immédiat (`SIGSEGV` / Code 11).

### Le Patch Chirurgical
Le patch remplace la conversion dynamique par une affectation immédiate de `60` (`0x3C`) dans `R15D` juste avant le `_CFRelease` :

* **Adresse virtuelle (VA) :** `0x1000fe6dc`
* **Offset fichier Mach-O :** `0x000fe6dc`
* **Octets d'origine (10 octets) :**
  ```text
  F2 0F 10 45 D0 F2 44 0F 2C F8
  (movsd -0x30(%rbp), %xmm0 ; cvttsd2si %xmm0, %r15d)
  ```
* **Octets patchés (10 octets) :**
  ```text
  41 BF 3C 00 00 00 90 90 90 90
  (movl $0x3c, %r15d ; nop ; nop ; nop ; nop)
  ```

**Résultat :** `R15D` vaut toujours 60, la mémoire CoreFoundation est libérée proprement (aucune fuite), tous les modes vidéo énumérés sont validés à 60 Hz par le moteur, et le jeu démarre sans lever la moindre exception !

---

## ⚖️ Legal Disclaimer & Fan Preservation Notice

* **Projet communautaire bénévole :** Développé par des passionnés dans le seul but de préserver *Les Sims 2* sur les Mac récents.
* **Aucun contournement de DRM / Aucun crack :** Ce patch ne contourne aucune protection Apple FairPlay ni aucun reçu du Mac App Store. Vous **devez** posséder une copie légalement achetée de *The Sims 2: Super Collection*.
* **Contexte :** Le jeu a été abandonné sans mise à jour depuis plus de 5 ans. Ce projet relève des exceptions légales d'interopérabilité logicielle (Directive européenne 2009/24/CE Art. 6 et US DMCA 17 U.S.C. § 1201(f)).

---

## 🔄 Uninstallation / Restauration

Pour revenir à tout moment au binaire officiel non patché d'origine :
```bash
sudo python3 restore_sims2.py
```

---

## 📄 License
MIT License. Created for software preservation and community interoperability.
