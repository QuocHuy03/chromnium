# Rebase onto Chromium 152.0.7977.83

This branch (`rebase/chromium-152`) bumps `scripts\fetch.bat` to
**152.0.7977.83** and ships the chronium series as apply-able `.patch`
files (0001-0020). The old full-file `post-patched/` snapshot is kept only
for reference — the 152 build does **not** copy it (those are 148 file
versions and would break 152).

## Patch layout on this branch

- `0001`-`0018` — unchanged from the 148 series.
- `0019-chronium-patches-0019-0020-0021-post-patched-snapsho.patch` — the
  old 0019+0020+0021 (WebGL getParameter virtualization, license gate,
  account-label chip) as one real diff.
- `0020-chronium-render-time-noise-v2-per-context-WebGL-exte.patch` — patch
  0022's content (render-time canvas/WebGL noise v2, per-context WebGL
  extension allowlists, render-time audio noise, drops the V8 Intl remaps).

## Build steps on the build machine (C:\cr\src)

```
git fetch --tags
scripts\fetch.bat                 :: STABLE_TAG is now 152.0.7977.83
scripts\apply-patches.bat         :: git am --3way; stops on the 6 conflicts below
:: ... resolve each conflict (see below), git add <file>, git am --continue ...
scripts\build.bat
scripts\package.bat
```

`apply-patches.bat` uses `git am --3way`. Because C:\cr\src already has the
148 tag fetched, the 3-way ancestor blobs are present and every non-listed
patch applies clean. Only the 6 files below conflict — all mechanical
(includes / an insertion point), no logic changes.

## The 6 conflicts and how to resolve each

All are "keep 152's line, add chronium's line(s)". Delete the
`<<<<<<< ======= >>>>>>>` markers, keeping both real sides unless noted.

### 0001 — `chrome/browser/BUILD.gn`
152 rewrote this sources list. The patch only needs to add two entries.
Keep the whole 152 (`HEAD`) list, and make sure these two lines are present
in the alphabetical `sources` block (152 already lists them right after the
`enterprise/...` entries — if so, take `HEAD` and drop the chronium side
entirely):
```
      "fingerprint/fingerprint_profile.cc",
      "fingerprint/fingerprint_profile.h",
```

### 0004 — `chrome/browser/chrome_content_browser_client.cc`
Include conflict. Keep both:
```
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/fingerprint/fingerprint_profile.h"
```

### 0007 — `third_party/blink/renderer/core/frame/local_dom_window.cc`
Keep chronium's devicePixelRatio override, then 152's braced `if`:
```cpp
  if (const auto* fp = FingerprintState::Screen();
      fp && fp->device_pixel_ratio > 0.0) {
    return fp->device_pixel_ratio;
  }
  if (!GetFrame()) {
```
(Use 152's `if (!GetFrame()) {` with the brace, not the patch's braceless one.)

### 0014 — `third_party/blink/renderer/modules/permissions/permissions.cc`
Keep chronium's DENIED->ASK block, then 152's call form (152 passes
`std::move(result)`):
```cpp
  if (result == mojom::blink::PermissionStatus::DENIED &&
      FingerprintState::IsActive()) {
    using mojom::blink::PermissionName;
    switch (descriptor->name) {
      case PermissionName::NOTIFICATIONS:
      case PermissionName::GEOLOCATION:
      case PermissionName::AUDIO_CAPTURE:
      case PermissionName::VIDEO_CAPTURE:
      case PermissionName::MIDI:
        result = mojom::blink::PermissionStatus::ASK;
        break;
      default:
        break;
    }
  }

  PermissionStatusListener* listener = GetOrCreatePermissionStatusListener(
      std::move(result), std::move(descriptor));
```

### 0019 — `chrome/browser/ui/views/location_bar/location_bar_view.cc`
Include conflict. Keep 152's includes and add chronium's four:
```cpp
#include "base/command_line.h"
#include "base/hash/hash.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/common/chrome_switches.h"
```

### 0019 — `chrome/browser/ui/views/location_bar/location_bar_view.h`
152 already has the `merchant_trust_chip_*` members. **Only** add
chronium's one member (do not duplicate the merchant_trust lines):
```cpp
  // Chronium: account label chip (Multilogin-style). nullptr when
  // --account-label= is empty / absent.
  raw_ptr<views::Label> account_label_chip_ = nullptr;
```

### 0020 — `third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc`
Two include conflicts. Keep 152's includes and add chronium's:
```cpp
#include <algorithm>
...
#include "base/numerics/safe_conversions.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
```

## After it builds

- The 6 resolutions above are text-level only; **compile errors from 152
  API changes may still surface** — fix them at build time.
- Bump the version fields in the 170 bundled fingerprint JSONs to
  152.0.7977.83 (`user_agent`, `user_agent_data`, full version list), or
  CreepJS "Features" will read a 148 UA against a 152 binary. Ideally
  re-measure the WebGL extension lists (A7) from the real 152 build; on a
  GTX 1060 / D3D11 they matched 148 exactly.
- Re-export the resolved series so the next build is clean:
  `git format-patch <148-tag or new base>..HEAD -o patches\`  — or on 152:
  run `scripts\rebase.bat` is **not** needed; just re-`format-patch` from
  the tag once conflicts are committed.
