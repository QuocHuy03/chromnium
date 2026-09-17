# Chromium 153.0.8010.36 — pre-resolved patch series

Branch `rebase/chromium-153`. `scripts\fetch.bat` targets **153.0.8010.36**.
The patch series (0001-0020) is **already resolved against 153** and applies
with **no manual conflict resolution** — verified in a clean room: all 20
apply via `git am --3way` onto the 153 source tree with zero conflicts.

The full-file `post-patched/` snapshot is 148-only and is NOT used for the
153 build; ignore it here.

## Build steps (build machine, C:\cr\src)

```
git fetch --tags
scripts\fetch.bat            :: STABLE_TAG = 153.0.8010.36 (~1-2h)
scripts\apply-patches.bat    :: git am --3way of 0001-0020; applies clean
scripts\build.bat            :: 4-8h
scripts\package.bat
scripts\encrypt-profiles.py  :: re-encrypt the 153-bumped profiles to .json.enc
```

`git am --3way` needs the 148 blobs as merge ancestors; C:\cr\src already
has the 148 tag fetched, so they are present. If `apply-patches.bat` ever
stops (e.g. the checkout lacks the 148 objects), fetch them once:
`git fetch --tags https://chromium.googlesource.com/chromium/src refs/tags/148.0.7778.217`.

## What was resolved for 153 (already baked into the patches)

- `chrome/browser/BUILD.gn`: 153 sharded the giant sources list. The two
  `fingerprint/fingerprint_profile.{cc,h}` entries are added to the desktop
  (`if (!is_android)`) `sources += [` block next to
  `intranet_redirect_detector.cc`. **If this is the wrong GN target it fails
  LOUDLY at link** (`chrome_content_browser_client.cc` references
  `FingerprintProfile`) — send me the link error and I'll move it.
- `element.cc`: merged with 153's surrounding changes to `GetBoundingClientRect()`.
  (Earlier notes here claimed 153 renamed `UpdateStyleAndLayoutForNode` to
  `EnsurePaintLocationDataValidForNode` — that was wrong; 153.0.8010.36 still
  has `Document::UpdateStyleAndLayoutForNode`, confirmed by a real build
  failure on 2026-09-16. Fixed in patch 0009 and in the applied tree.)
- `infobar_utils.cc`: 153's new `IsInfoBarMigrated` Google-API-keys branch is
  gated on the chronium `!IsLoaded()` guard.
- `permissions.cc`, `local_dom_window.cc`: merged with 153's changed call /
  brace.
- `location_bar_view.{cc,h}`, `chrome_browser_interface_binders.cc`,
  `webgl_rendering_context_base.cc`: include / member merges.

## Known residual risks (only a real build reveals these)

- **Compile errors from 153 Blink/`//base` API changes** are still possible;
  the resolutions above are source-level. Send me `build.bat` errors.
- `location_bar_view.h`: the `account_label_chip_` member is added where the
  patch anchored; if 153 moved the surrounding members it may need
  repositioning (loud compile error).

## Fixes found by an actual build.bat run (2026-09-16, patched into patches/)

The pre-resolved patches were only verified to *apply* cleanly (`git am`), not
to *compile*. A real build on 153.0.8010.36 (VS 18 Build Tools, local SDK
10.0.28000.0) turned up two real API mismatches, both now fixed in the
patch files themselves (not just the applied tree):

- **patch 0009** (`element.cc`): `Document::UpdateStyleAndLayoutForNode` was
  NOT renamed in 153 — the earlier "resolved" hunk incorrectly called it
  `EnsurePaintLocationDataValidForNode`, which doesn't exist and fails to
  compile. Reverted to the real method name.
- **patch 0003** (`html_canvas_element.cc`): `StaticBitmapImage::Create(sk_sp<SkData>, SkImageInfo)`
  gained a required third `const gfx::HDRMetadata&` parameter in 153. Fixed
  by passing `gfx::HDRMetadata()`.

- **patch 0014** (`permissions.cc`): the DENIED→ASK block treated `result`
  (a `mojom::blink::PermissionStatusWithDetailsPtr`, i.e. a move-only
  `mojo::StructPtr`, unchanged from upstream — not a 153 API change, just a
  wrong assumption in the original patch) as if it were the bare
  `PermissionStatus` enum. Fixed to compare/assign `result->status`, and
  restored the `std::move(result)` at the `GetOrCreatePermissionStatusListener`
  call the patch had dropped (that param is taken by value, so passing the
  bare pointer without moving it fails to compile — it's move-only).
- **patch 0019** (link step, not compile): `license_gate.cc`/`.h` are created
  by this patch but were never added to `chrome/browser/BUILD.gn`'s
  `sources` list (the 148-era `post-patched/` reference has them; the
  regenerated-for-153 patch dropped that hunk). Result: `chrome_browser_main.cc`
  calls `chronium::EnforceLicenseGate()` but nothing defines it —
  `chrome.dll` fails at LINK with an undefined symbol, ~23000/~23500 steps
  in (i.e. after a full successful compile). Added a new BUILD.gn hunk to
  patch 0019 putting `license/license_gate.{cc,h}` and `license/license_secret.h`
  next to the `fingerprint/fingerprint_profile.{cc,h}` entries patch 0001
  already adds in that same `sources += [...]` block.

- **`scripts/package.bat`** (not a patch — packaging bug): the `robocopy`
  file filter only copied `*.exe *.dll *.pak *.bin *.dat`, missing
  `*.manifest`. Chromium's exe carries an embedded manifest that requires a
  side-by-side dependent assembly named `<version>.manifest`
  (`153.0.8010.36.manifest`, sitting next to chrome.exe in `out/Release`) to
  pin it to the matching chrome.dll. Without it, `chronium.exe` fails to
  even start: "Activation context generation failed ... Dependent Assembly
  153.0.8010.36 ... could not be found" (Windows Application event log,
  not visible on stdout — the process just silently fails to launch).
  Added `*.manifest` to the robocopy filter.

Build reached ~14k/~46k objects before the first of these, further before the
second, ~4k more before the third, and all the way to link (~23k/~23.5k)
before the fourth — the entire compile phase is clean against 153 + local
SDK 28000; only link-time wiring was missing. The fifth was packaging, after
a fully successful build. Smoke-tested 2026-09-16: `chronium.exe` launches,
passes the patch-0020 license gate, and runs as a normal healthy
multi-process Chromium (11 `chronium.exe` processes: browser, GPU, network
service, renderer). Treat any other spot in these
patches that reads or reassigns a mojo result type as if it were a bare
enum/value with the same suspicion if you hit further compile errors — check
the real struct/method signature in the checkout before
guessing.

## Profiles

`config/profiles/*.json` (170) are already bumped to 153.0.8010.36
(user_agent `Chrome/153.0.0.0`, UA-CH brands 153 + GREASE `Not_A Brand`/`8`,
full_version_list `153.0.8010.36`). platform/platform_version untouched.
Timezone canonical names and WebGL1/WebGL2 extension lists were identical to
148 on the test GPU, so no other profile change was needed.
