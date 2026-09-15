# BUILD-ONE-MACHINE.md — Chronium 153 build runbook (for an AI agent)

You are on a build machine. Your job: build the Chronium browser (a patched
Chromium **153.0.8010.36** fork) from this repo, on **one Windows x64
machine**, produce `chronium.exe`, and smoke-test it. Follow the steps in
order. Do not skip step 5 (license secret) — the build fails without it.

This branch (`rebase/chromium-153`) ships the patch series **already resolved
for 153**: `scripts\apply-patches.bat` applies all 20 patches via
`git am --3way` with **no manual conflict resolution**.

Report back to the user: the result of each step, and — if anything fails —
the FIRST error block verbatim (do not truncate compiler errors).

---

## 0. Hard requirements (verified by `scripts\setup-env.bat`)

Install these before anything else. Each line is a hard gate.

| Requirement | How to install / check |
|---|---|
| Windows 10/11 x64 | `ver` |
| **Visual Studio 2022 Build Tools**, workload "Desktop development with C++" (MSVC v143 x64/x86) | https://aka.ms/vs/17/release/vs_BuildTools.exe |
| **Windows 11 SDK 10.0.22621.0** | VS Installer → Individual components |
| **Debugging Tools for Windows** (`dbghelp.dll`) | Apps & Features → "Windows Software Development Kit" → Modify → check "Debugging Tools for Windows". REQUIRED (Chromium copies dbghelp.dll during gn gen). |
| **Python 3.11+** from python.org, on PATH. NOT the Microsoft Store build (its disabled symlinks break `gclient sync`). | `where python` must NOT contain `WindowsApps`. If it does: Settings → Apps → App execution aliases → turn off python.exe/python3.exe. |
| **depot_tools** at `C:\cr\depot_tools`, prepended to PATH before any other Python | Download https://storage.googleapis.com/chrome-infra/depot_tools.zip, extract, add to system PATH. `where gclient` must resolve. |
| **~150 GB free** on C: (source ~50GB + build ~70GB + output) | Chromium will not fit otherwise. |
| **≥ 8 logical CPUs, ≥ 32 GB RAM** | args.gn is tuned for 32GB (`-j12`). Less RAM → lower `-j` in step 6. |

Set these **system** environment variables (then reopen the shell):

```
setx DEPOT_TOOLS_WIN_TOOLCHAIN 0
setx GYP_MSVS_VERSION 2022
setx vs2022_install "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
```

---

## 1. Clone this repo

```
git clone -b rebase/chromium-153 https://github.com/QuocHuy03/chromnium.git C:\chronium-build
cd C:\chronium-build
```

All `scripts\*.bat` below are run from `C:\chronium-build`. They drive a
separate Chromium checkout at **`C:\cr\src`** (created in step 3).

---

## 2. Verify the environment

```
scripts\setup-env.bat
```

Fix every `[FAIL]` and re-run until it prints "Environment looks OK".
`[WARN]` lines about env vars are safe to fix by setting the vars in step 0.

---

## 3. Fetch Chromium 153 source (~1–2 h, ~50 GB)

```
scripts\fetch.bat
```

`STABLE_TAG` in `scripts\fetch.bat` is already `153.0.8010.36`. This creates
`C:\cr\src`, checks out the tag on branch `chronium-base`, and runs
`gclient sync` + `gclient runhooks`.

- On HTTP 429 / RESOURCE_EXHAUSTED: wait 10–15 min, re-run `scripts\fetch.bat`
  (it resumes).

---

## 4. Apply the patch series

```
scripts\apply-patches.bat
```

This `git am --3way` applies `patches\0001..0020` onto `chronium-base`.
It should run to the end without stopping ("All 20 patches applied").

- If it stops saying it cannot 3-way merge because it lacks ancestor blobs,
  fetch the 148 base once, then re-run:
  ```
  git -C C:\cr\src fetch --tags https://chromium.googlesource.com/chromium/src refs/tags/148.0.7778.217
  scripts\apply-patches.bat
  ```
- Do NOT copy `patches\post-patched\` onto the tree — those are 148 file
  versions and are not used for the 153 build.

---

## 5. ⚠️ Generate the license secret (BEFORE building)

```
python scripts\gen-license-secret.py
```

This writes two files:
- `C:\cr\src\chrome\browser\license\license_secret.h` — the 32-byte secret
  baked into the binary. **`license_gate.cc` (patch 0020) `#include`s this;
  the build will not compile without it.**
- `config\.profile_key` — the same 32 bytes, used in step 8 to mint a launch
  token.

If a secret already exists and you must rotate it, pass `--force` (this
invalidates every previously-built binary). Keep `.profile_key` safe; it is
gitignored and never committed.

---

## 6. Build (4–8 h first time)

```
scripts\build.bat
```

Runs `gn gen out\Release` with `config\args.gn`, then
`autoninja -C out\Release -j 12 chrome`.

- **RAM < 32 GB**: edit `scripts\build.bat`, change `-j 12` to `-j 8` or
  `-j 6` to avoid OOM during link.
- On a compile error: the run stops. Copy the FIRST error block verbatim and
  report it — it is almost certainly a 153 Blink / `//base` API change in one
  patched file, fixable with a small patch edit.

Output on success: `C:\cr\src\out\Release\chrome.exe`.

---

## 7. Package

```
scripts\package.bat
```

Produces `release\chronium\chronium.exe` (+ DLLs, paks, locales). If
`tools\rcedit.exe` is missing it skips icon/name branding with a warning; the
binary still works. To brand, download rcedit from
https://github.com/electron/rcedit/releases into `tools\`.

---

## 8. Smoke test / run

The binary has a license gate (patch 0020): it exits immediately without a
valid token. Mint one bound to the CURRENT shell PID and launch from the same
PowerShell window:

```powershell
$t = python scripts\gen-debug-token.py --ppid $PID
& release\chronium\chronium.exe `
    --user-data-dir=C:\tmp\p1 `
    --fingerprint-profile=C:\chronium-build\config\profiles\win-rtx3060.json `
    ($t -split ' ') `
    https://browserleaks.com
```

- The token binds to `$PID`; launch from the same window that made it. Do NOT
  name the variable `$args` (PowerShell reserves it).
- Profiles in `config\profiles\*.json` are plaintext and already carry the
  153 UA; use one directly. (`scripts\encrypt-profiles.py` is only needed to
  ship the `.json.enc` bundle.)
- If chrome opens then closes instantly → the token step was skipped, or you
  launched from a different window than the one `$PID` came from.

---

## 9. Verification (report these)

1. `chrome://version` in the running browser → Chromium **153.0.8010.36**,
   and the command line shows `--fingerprint-profile` (and, for new profiles
   driven by the backend, `--fingerprint-noise-version=2`).
2. Create **two new profiles of the same template** (two different
   `--user-data-dir`, same `--fingerprint-profile`), open BrowserScan /
   CreepJS / the project's `fp-probe.js` in each, and confirm:
   - Canvas / WebGL hashes DIFFER between the two profiles.
   - BrowserScan: no "WebGL exception", no "Canvas Tampering".
   - CreepJS Audio (if `noise.audio_amplitude > 0`): `data == copy`,
     `trap == 0.7284930725495119`.
3. Report the build duration, the final binary path, and any warnings.

---

## Quick reference — full sequence

```
git clone -b rebase/chromium-153 https://github.com/QuocHuy03/chromnium.git C:\chronium-build
cd C:\chronium-build
scripts\setup-env.bat
scripts\fetch.bat
scripts\apply-patches.bat
python scripts\gen-license-secret.py
scripts\build.bat
scripts\package.bat
:: run:
:: $t = python scripts\gen-debug-token.py --ppid $PID
:: & release\chronium\chronium.exe --user-data-dir=C:\tmp\p1 --fingerprint-profile=config\profiles\win-rtx3060.json ($t -split ' ') https://browserleaks.com
```
