# Security Policy

## Supported Versions

Only the latest stable release series receives security and stability fixes:

| Version | Supported |
| :--- | :--- |
| `v1.5.x` | ✅ Supported |
| `< v1.5.0` | ❌ Unsupported (please update to [latest release](https://github.com/Justinbdna/sims2-crash-patch/releases/latest)) |

## Reporting a Vulnerability

Please **do not** open a public GitHub Issue for security vulnerabilities (e.g., privilege escalation in shell scripts, unsafe file handling, or code-signing issues).

Instead, report vulnerabilities privately via **GitHub Private Vulnerability Reporting**:

1. Open the [**Security** tab](https://github.com/Justinbdna/sims2-crash-patch/security) of this repository.
2. Click **Report a vulnerability** (or go directly to [New Security Advisory](https://github.com/Justinbdna/sims2-crash-patch/security/advisories/new)).
3. Include affected version, macOS/Windows version, reproduction steps, and any relevant anonymized logs.

We aim to acknowledge reports within **72 hours** and coordinate a fix before public disclosure.

## Transparency & Trust Model

* **100% open source:** All installer, cache, and restore scripts (`*.command`, `windows/*.py`) are human-readable plain text under the [MIT License](LICENSE).
* **Reproducible `.dylib`:** `trackpad_mod/libsims2_trackpad.dylib` is compiled from [`trackpad_mod/sims2_trackpad.m`](trackpad_mod/sims2_trackpad.m) via [`trackpad_mod/build_trackpad.sh`](trackpad_mod/build_trackpad.sh) and compile-checked on every push in macOS GitHub Actions CI.
* **Zero telemetry & zero DRM bypass:** The patch makes no network calls, writes zero normal gameplay logs, and requires a legitimately owned copy of *The Sims 2: Super Collection*.
