# Patch de Compatibilité ProMotion (120 Hz) pour "The Sims 2: Super Collection" (macOS)

## 1. Contexte & Diagnostic de la cause racine

### Pourquoi le jeu plantait-il ?
1. **L'appel Quartz :** Lors de l'initialisation de l'affichage dans `FUN_1000fe510` (`0x1000fe665`), le jeu appelle `_CGDisplayModeGetRefreshRate`.
2. **Écrans ProMotion Apple Silicon :** Sur un écran ProMotion à 120 Hz, cette API renvoie `120.0`.
3. **Le piège du saut conditionnel :** 
   - L'instruction à `0x1000fe6e1` convertit ce flottant en entier dans `R15D` (`cvttsd2si %xmm0, %r15d`). `R15D` vaut donc `120` (`0x78`).
   - À `0x1000fe6f7`, le test `TEST R15D, R15D` vérifie si `R15D != 0`.
   - Comme `120 != 0`, le saut `JNE 0x1000fe745` est **immédiatement pris**.
   - **Conséquence directe :** Le code de repli `_CVDisplayLinkGetNominalOutputVideoRefreshPeriod` (adresses `0x1000fe700` à `0x1000fe744`) est **totalement contourné**. Le patch n°1 qui NOPait `0x1000fe741` n'était donc jamais exécuté pour les modes 120 Hz !
4. **Propagation de la fréquence non supportée :**
   - À `0x1000fe790`, `MOV dword ptr [RBX + 0xc], R15D` écrit `120` dans la structure du mode vidéo.
   - Tous les modes d'affichage retournés par le système sont ainsi enregistrés à 120 Hz.
5. **Le Crash à 0x10081cfca :**
   - Dans `FUN_10081a5c0` (étape 2 de la machine à états de démarrage), la fonction appelle `0x101769030` pour valider et sélectionner un mode vidéo compatible.
   - Le moteur Sims 2 rejetant les modes 120 Hz, aucun mode n'est retenu et la fonction renvoie `0` (échec).
   - À `0x10081a8ca`, l'instruction `JE 0x10081cf8f` branche vers le bloc de levée d'exception C++ `___cxa_throw`.
   - Faute de bloc `catch`, `std::__terminate()` est appelé, déclenchant le crash immédiat (SIGSEGV / code 11).

---

## 2. Solution & Spécification chirurgicale du Patch

Pour garantir que le moteur vidéo reçoive **strictement 60 Hz** sans perturber la mémoire CoreFoundation :

### Patch Principal (0x1000fe6dc)
- **Adresse virtuelle (VA) :** `0x1000fe6dc`
- **Offset fichier Mach-O :** `0x000fe6dc`
- **Octets d'origine (10 octets) :**
  `F2 0F 10 45 D0 F2 44 0F 2C F8`
  *(Désassemblage : `movsd -0x30(%rbp), %xmm0` suivi de `cvttsd2si %xmm0, %r15d`)*
- **Octets de remplacement (10 octets) :**
  `41 BF 3C 00 00 00 90 90 90 90`
  *(Désassemblage : `movl $0x3c, %r15d` suivi de 4 `nop`)*

**Effets :**
- `R15D` est forcé à `60` (`0x3C`) de façon garantie.
- La libération mémoire `_CFRelease` s'exécute normalement à `0x1000fe6e9` (zéro fuite mémoire).
- Le saut `JNE 0x1000fe745` saute vers l'écriture finale du mode vidéo avec `R15D = 60`.
- Tous les modes vidéo énumérés sont typés à 60 Hz, le sélecteur `0x101769030` trouve son mode, et l'exception n'est jamais levée !

---

## 3. Utilisation des scripts fournis

Dans ce dossier (`Sims2-Patch_Workspace`) :

### Pour appliquer le patch :
```bash
sudo ./patch_sims2.sh
```
ou directement en Python :
```bash
sudo python3 patch_sims2.py
```
Le script :
1. Crée automatiquement une sauvegarde `Sims2XP_Exe.backup_original`.
2. Vérifie l'unicité de l'empreinte d'octets (`count == 1`).
3. Écrit les 10 octets du patch.
4. Re-signe le bundle via `codesign --force --deep --sign - "/Applications/The Sims 2.app"`.

### Pour restaurer le binaire original :
```bash
sudo python3 restore_sims2.py
```
