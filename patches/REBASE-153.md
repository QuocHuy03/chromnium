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
- `element.cc`: adapted to 153's `EnsurePaintLocationDataValidForNode`
  (renamed from `UpdateStyleAndLayoutForNode`).
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

## Profiles

`config/profiles/*.json` (170) are already bumped to 153.0.8010.36
(user_agent `Chrome/153.0.0.0`, UA-CH brands 153 + GREASE `Not_A Brand`/`8`,
full_version_list `153.0.8010.36`). platform/platform_version untouched.
Timezone canonical names and WebGL1/WebGL2 extension lists were identical to
148 on the test GPU, so no other profile change was needed.
