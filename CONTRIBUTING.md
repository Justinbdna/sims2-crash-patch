# Contributing to Sims 2 Crash Patch

Thank you for helping preserve *The Sims 2: Super Collection* on macOS (Apple Silicon M1–M5 & Intel) and Windows!

## Ways to Contribute

### 1. Report a Bug
* Run `patch_sims2.command` → **`[2] Diagnostic & Support GitHub`** to generate an anonymized (`~`) `github_support_report.md` copied directly to your clipboard.
* Attach any relevant crash report from `~/Library/Logs/Sims2-Crash-Patch/` (e.g., `sims2_crash_001.log` or `crash_report.log`).
* Open a [**Bug Report**](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=bug_report.md).

### 2. Share a Compatibility Report (M1–M5 / Intel)
* Help other players by submitting your Mac model, chip (`M1 / M2 / M3 / M4 / M5 / Intel`), macOS version, and display setup via the [**Compatibility & Test Report**](https://github.com/Justinbdna/sims2-crash-patch/issues/new?template=test-report.md) template or in [**GitHub Discussions**](https://github.com/Justinbdna/sims2-crash-patch/discussions).

### 3. Submit a Pull Request
1. **Branch workflow:** Fork the repo and create your feature/fix branch from **`staging`** (never directly from `main`; releases are promoted `staging` → `main`).
2. **Keep macOS scripts clean:** Pure LF line endings, zero Xcode CLT dependencies, and idempotent backup/restore behavior.
3. **Run the full cross-platform QA suite before opening a PR:**
   ```bash
   python3 scripts/verify_and_package.py
   ```
   All tests (`38/38`) must pass without errors.
4. Open a Pull Request targeting **`staging`** and fill out the PR checklist.

## Code of Conduct

Please note that this project follows our [Code of Conduct](CODE_OF_CONDUCT.md).
