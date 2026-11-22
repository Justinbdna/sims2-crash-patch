---
name: "🧪 Compatibility & Test Report / Rapport de Test"
about: "Report your Mac hardware, chip (M1/M2/M3/M4), macOS version, and test result / Signalez votre configuration Mac et le résultat du patch"
title: "[Test Report] MacBook Pro/Air (M1/M2/M3/M4) - macOS XX.X"
labels: ["compatibility", "test-report"]
assignees: ""
---

## 🖥️ Hardware & macOS Configuration / Configuration Matérielle

- **Mac Model / Modèle de Mac :** (e.g., MacBook Pro 14" / MacBook Pro 16" / MacBook Air / Mac Studio / iMac)
- **Apple Silicon Chip / Puce :** (e.g., M1 Pro / M1 Max / M2 Pro / M3 Pro / M4 Pro / Base M1-M4)
- **Display Refresh Rate / Écran :** (e.g., Built-in Liquid Retina XDR 120 Hz ProMotion / External 120 Hz+ Monitor)
- **macOS Version :** (e.g., macOS Sequoia 15.x / macOS 27.0)
- **Keyboard Layout / Clavier :** (e.g., French AZERTY / US QWERTY / Other)
- **Patch Version :** `v1.4.1` (or `v1.4.0`)

---

## ✅ Test Results / Résultats du Test

- [ ] **1. Installation (`patch_sims2.command`) :** Succeeded without error (`codesign --verify --deep --strict`) / Réussie sans erreur
- [ ] **2. Game Startup (120 Hz enabled) :** Game launches into the main neighborhood menu without crashing / Le jeu démarre jusqu'au menu des quartiers sans planter
- [ ] **3. Save Migration (`~/Library/Application Support/Aspyr/The Sims 2/`) :** Existing neighborhoods & saves preserved without overwrite / Sauvegardes existantes conservées sans écrasement
- [ ] **4. 3D Neighborhood & Graphics (`Graphics Rules.sgr`):** Plays smoothly at 60 FPS, Retina resolutions & `$High` graphics work / Quartier 3D fluide à 60 FPS, résolutions Retina et profil `$High` OK
- [ ] **5. Native Trackpad & SDL2 (`libsims2_trackpad.dylib`):** `Control (^)`+drag 3D orbit (`Option`+drag native pan), 2-finger pinch zoom, 2-finger swipe/rotate (`,`/`.`), and Fullscreen Space / Dock hiding work properly
- [ ] **6. Maintenance & Restore (`clean_sims2_cache.command` & `restore_sims2.command`):** Cache purge / `userProps.xml` reset / full restore verified / Nettoyage, `userProps.xml` et restauration OK

---

## 📝 Additional Notes or Terminal Output / Notes ou Sortie Terminal (Optional)

```text
Paste any terminal messages or observations here / Collez ici vos observations éventuelles
```
