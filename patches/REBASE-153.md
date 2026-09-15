# Rebase onto Chromium 153.0.8010.36

Branch `rebase/chromium-153`. `scripts\fetch.bat` is set to
**153.0.8010.36**. The chronium series ships as apply-able `.patch` files
(0001-0020); the full-file `post-patched/` snapshot is kept for reference
only (those are 148 file versions — do NOT copy them onto 153).

## Build steps (on the build machine, C:\cr\src)

```
git fetch --tags
scripts\fetch.bat                 :: STABLE_TAG = 153.0.8010.36 (~1-2h)
scripts\apply-patches.bat         :: git am --3way; stops on the 9 files below
:: resolve each (see below); git add <file>; git am --continue
scripts\build.bat                 :: 4-8h
scripts\package.bat
```

`git am --3way` needs the 148 blobs as merge ancestors; C:\cr\src already
has the 148 tag, so they're present. Every patch not listed below applies
clean. **These are text-level resolutions; 153 API changes may still
surface as compile errors — fix at build time.**

## The 9 conflicts

Delete the `<<<<<<< ======= >>>>>>>` markers, keeping both sides unless a
note says otherwise. "Keep 153 + add chronium" = union of both.

### 0001 — `chrome/browser/BUILD.gn`  (add 2 source entries)
Keep 153's whole `sources` list; ensure these two lines are present, in
alphabetical order right after the `enterprise/signals/device_info_fetcher.h`
entry and before `first_run/bookmark_importer.cc`:
```
      "fingerprint/fingerprint_profile.cc",
      "fingerprint/fingerprint_profile.h",
```
(Discard the huge `>>>>>>>` block; it is 148's list. Only these 2 lines are
the real change.)

### 0002 — `chrome/browser/chrome_browser_interface_binders.cc`  (include)
Keep 153's includes and add:
```cpp
#include "chrome/browser/fingerprint/fingerprint_profile.h"
```

### 0004 — `chrome/browser/chrome_content_browser_client.cc`  (include)
Keep both:
```cpp
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/fingerprint/fingerprint_profile.h"
```

### 0007 — `third_party/blink/renderer/core/frame/local_dom_window.cc`
Keep chronium's devicePixelRatio override, then 153's **braced** `if`:
```cpp
  if (const auto* fp = FingerprintState::Screen();
      fp && fp->device_pixel_ratio > 0.0) {
    return fp->device_pixel_ratio;
  }
  if (!GetFrame()) {
```

### 0009 — `third_party/blink/renderer/core/dom/element.cc`
153 renamed the layout call. Use **153's** `EnsurePaintLocationDataValidForNode`
line, then chronium's `result` + noise + `return result`:
```cpp
  GetDocument().EnsurePaintLocationDataValidForNode(
      this, DocumentUpdateReason::kJavaScript);
  DOMRect* result =
      DOMRect::FromRectF(GetBoundingClientRectNoLifecycleUpdate());
  if (FingerprintState::IsActive()) {
    auto noise = [](uint32_t h) -> double {
      return (static_cast<double>(h) * (1.0 / 2147483648.0) - 1.0) * 1e-5;
    };
    const uint32_t node_id = static_cast<uint32_t>(GetDomNodeId());
    result->setX(result->x() +
                 noise(FingerprintState::HashAt("rect", node_id, 0u)));
    result->setY(result->y() +
                 noise(FingerprintState::HashAt("rect", node_id, 1u)));
    result->setWidth(result->width() +
                     noise(FingerprintState::HashAt("rect", node_id, 2u)));
    result->setHeight(result->height() +
                      noise(FingerprintState::HashAt("rect", node_id, 3u)));
  }
  return result;
```
(Discard the patch's `UpdateStyleAndLayoutForNode` line — that was 148's name.)

### 0012 — `chrome/browser/ui/startup/infobar_utils.cc`  (2 hunks)
Hunk 1 (include): keep 153's includes and add:
```cpp
#include "chrome/browser/fingerprint/fingerprint_profile.h"
```
Hunk 2: 153 wrapped the Google-API-keys infobar in an `IsInfoBarMigrated`
branch. Gate that **whole** 153 branch on the chronium `!IsLoaded()` guard —
keep 153's body, just add the guard to the `if`:
```cpp
  if (!chronium::FingerprintProfile::GetInstance()->IsLoaded() &&
      !google_apis::HasAPIKeyConfigured()) {
    if (infobars::IsInfoBarMigrated(
            infobars::InfoBarDelegate::GOOGLE_API_KEYS_INFOBAR_DELEGATE)) {
      if (auto* manager =
              infobars::BrowserInfoBarManager::From(g_browser_process)) {
        manager->Show(
            tabs::TabInterface::GetFromContents(web_contents),
            infobars::InfoBarDelegate::GOOGLE_API_KEYS_INFOBAR_DELEGATE);
      }
    } else {
      GoogleApiKeysInfoBarDelegate::Create(infobar_manager);
    }
  }
```

### 0014 — `third_party/blink/renderer/modules/permissions/permissions.cc`
Keep chronium's DENIED->ASK block, then 153's call form (153 already passes
`result` without `std::move`):
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

  PermissionStatusListener* listener =
      GetOrCreatePermissionStatusListener(result, std::move(descriptor));
```

### 0019 — `chrome/browser/ui/views/location_bar/location_bar_view.cc`  (include)
Keep 153's includes and add chronium's four:
```cpp
#include "base/command_line.h"
#include "base/hash/hash.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/common/chrome_switches.h"
```

### 0019 — `chrome/browser/ui/views/location_bar/location_bar_view.h`
153 already declares the `merchant_trust_chip_*` members. Add **only**
chronium's one member (do not duplicate merchant_trust):
```cpp
  // Chronium: account label chip; nullptr when --account-label= is absent.
  raw_ptr<views::Label> account_label_chip_ = nullptr;
```

### 0020 — `third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc`
Two include conflicts. Keep 153's includes and add chronium's:
```cpp
#include <algorithm>
...
#include "base/numerics/safe_conversions.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
```

## After it builds

- The 170 profile templates in `config/profiles/*.json` are ALREADY bumped
  to 153 (measured on real CfT 153.0.8010.36 / GTX 1060):
  - `user_agent` -> `Chrome/153.0.0.0`
  - `user_agent_data.brands` -> Google Chrome/Chromium `153`, GREASE
    `Not_A Brand`/`8`
  - `user_agent_data.full_version_list` -> `153.0.8010.36`, GREASE `8.0.0.0`
  - `platform` / `platform_version` left as-is (OS-specific, not Chrome).
  Re-encrypt them to the shipped `.json.enc` with `scripts\encrypt-profiles.py`
  after the build. Timezone canonical names (Asia/Saigon etc.) and the
  WebGL1/WebGL2 extension lists were identical to 148 on this GPU, so no
  other profile change is needed.
- All 170 full_version_list entries now read `153.0.8010.36` (the one build
  measured). Real fleets cluster on the latest during a rollout, so this is
  fine; vary it later if you obtain other real 153 build numbers.
- Re-export the resolved series so the next build is conflict-free:
  `git format-patch refs/tags/148.0.7778.217..HEAD -o patches\` after the
  final commit — or better, once on 153, re-base the tag reference.
