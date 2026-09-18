# Package chronium for end-user distribution.
#
# Produces a self-contained folder + .zip containing:
#   - chronium.exe (renamed chrome.exe) + chrome.dll + paks + locales
#   - 170 device fingerprints
#   - PowerShell launcher + auto-localizer (no Python required)
#   - README.md with quick-start
#
# The output zip is ~300 MB. End users extract it anywhere and run
# scripts\chronium.ps1 directly — no installer, no admin, no Python.
#
# Run from chronium-build\scripts:
#   .\make-package.ps1                  # ./release/chronium-vX.X.X.zip
#   .\make-package.ps1 -Output D:\out   # custom output dir
#   .\make-package.ps1 -SkipZip         # leave the staging dir, skip zip

param(
    [string]$Output = $null,
    [string]$Version = 'v0.1.0',
    [switch]$SkipZip
)

$ScriptDir   = $PSScriptRoot
$BuildRoot   = Resolve-Path (Join-Path $ScriptDir '..')
$ReleaseSrc  = 'C:\cr\src\out\Release'
$ProfilesSrc = Join-Path $BuildRoot 'config\profiles'

if (-not $Output) { $Output = Join-Path $BuildRoot 'release' }
$Staging = Join-Path $Output "chronium-$Version"
$Zip     = "$Staging.zip"

# --- Validate sources ---
if (-not (Test-Path "$ReleaseSrc\chrome.exe")) {
    Write-Error "chronium build not found at $ReleaseSrc\chrome.exe. Run autoninja first."
    exit 2
}
if (-not (Test-Path $ProfilesSrc)) {
    Write-Error "Profiles not found at $ProfilesSrc. Run convert-shardx-profiles.py first."
    exit 2
}

# --- Clean staging ---
Write-Host "[1/6] Cleaning $Staging ..." -ForegroundColor Cyan
if (Test-Path $Staging) { Remove-Item -Recurse -Force $Staging }
New-Item -ItemType Directory -Path $Staging -Force | Out-Null

# --- Copy chronium binary ---
Write-Host "[2/6] Copying chronium binary..." -ForegroundColor Cyan
$BinDir = Join-Path $Staging 'bin'
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

# Component build ships ~586 separate DLLs that chrome.exe loads at
# runtime, so the old "shortlist that real Chrome distributes" approach
# doesn't work — every component_*_*.dll needs to be present or the
# loader fails with WinError 14001 (side-by-side configuration is
# incorrect). Mirror the entire Release/ tree minus build-time
# artifacts (pdb / lib / obj / siso traces) instead.
#
# Renaming chrome.exe -> chronium.exe is safe as long as the SxS
# <version>.manifest file (e.g. 153.0.8010.36.manifest) travels alongside
# it -- that external manifest is what the exe's embedded manifest
# actually resolves its dependent assembly against, not the filename.
# robocopy /E below doesn't exclude *.manifest, so it's already included.
# (package.bat hit and fixed the same "renamed exe won't launch" issue
# when its file-extension allowlist was missing *.manifest -- see
# patches/REBASE-153.md. chronium.ps1 in this package already expects
# bin\chronium.exe, so NOT renaming here just leaves that launcher
# pointed at a file that doesn't exist.)
Write-Host "    mirroring Release/ -> bin/ (component build needs ~600 DLLs)"
robocopy $ReleaseSrc $BinDir /E `
    /XF "*.pdb" "*.lib" "*.o" "*.obj" "*.tlog" "*.ilk" `
        "siso_metrics*.json" "siso_trace*.json" "package.json" `
        "args.gn" "args.gn.d" "build.ninja" "build.ninja.d" `
        "toolchain.ninja" ".ninja_log" ".ninja_deps" `
    /XD "obj" "gen" `
    /NFL /NDL /NJH /NJS /NP /NS | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed with exit $LASTEXITCODE"
    exit $LASTEXITCODE
}
# robocopy returns 1-7 for successful copies, only >=8 is a real error.
$LASTEXITCODE = 0

Rename-Item -Path (Join-Path $BinDir 'chrome.exe') -NewName 'chronium.exe'

# --- Brand the icon (chronium.exe + chrome.dll) ---
# chrome.exe is just a bootstrap stub; the running browser window's
# icon actually loads from chrome.dll's icon group #101 (IDR_MAINFRAME),
# so both need patching -- see patches/REBASE-153.md. rcedit's
# --set-icon only replaces chrome.exe's own icon (fine for Explorer/
# taskbar-pin display) and can't target chrome.dll's group by number,
# so Resource Hacker does the dll. Both are optional/best-effort: a
# missing tool or icon just leaves the stock Chromium icon, not a
# packaging failure.
$RcEdit     = Join-Path $BuildRoot 'tools\rcedit.exe'
$ResHacker  = Join-Path $BuildRoot 'tools\reshacker\ResourceHacker.exe'
$IconFile   = Join-Path $BuildRoot 'assets\chronium.ico'
$ChroniumExe = Join-Path $BinDir 'chronium.exe'
$ChromeDll   = Join-Path $BinDir 'chrome.dll'

if ((Test-Path $ResHacker) -and (Test-Path $IconFile)) {
    Write-Host "    branding icon (chronium.exe + chrome.dll)..."
    foreach ($target in @($ChroniumExe, $ChromeDll)) {
        $mask = if ($target -eq $ChroniumExe) { 'ICONGROUP,IDR_MAINFRAME,' } else { 'ICONGROUP,101,' }
        $tmp = "$target.tmp"
        if (Test-Path $tmp) { Remove-Item -Force $tmp }
        & $ResHacker -open $target -save $tmp -action addoverwrite -res $IconFile -mask $mask -log (Join-Path $BuildRoot 'reshacker-makepkg.log') | Out-Null
        if (Test-Path $tmp) {
            Move-Item -Force $tmp $target
        } else {
            Write-Warning "Resource Hacker did not produce output for $target (see reshacker-makepkg.log); icon left unchanged."
        }
    }
} else {
    Write-Warning "tools\reshacker\ResourceHacker.exe or assets\chronium.ico missing -- shipping the stock Chromium icon."
}

if (Test-Path $RcEdit) {
    & $RcEdit $ChroniumExe --set-version-string "ProductName" "Chronium" | Out-Null
    & $RcEdit $ChroniumExe --set-version-string "CompanyName" "Interlink" | Out-Null
    & $RcEdit $ChroniumExe --set-version-string "FileDescription" "Chronium Browser" | Out-Null
    & $RcEdit $ChroniumExe --set-version-string "OriginalFilename" "chronium.exe" | Out-Null
}

$binSize = (Get-ChildItem $BinDir -Recurse | Measure-Object Length -Sum).Sum / 1MB
$fileCount = (Get-ChildItem $BinDir -Recurse -File).Count
Write-Host "    bin/ size: $([math]::Round($binSize,1)) MB ($fileCount files)"

# --- Copy fingerprint profiles ---
# Ship the AES-GCM encrypted .json.enc variants only — see
# scripts/encrypt-profiles.py + backend/app/engine/license.py. A user who
# extracts the zip without the matching CHRONIUM_LICENSE_KEY can't read
# any fingerprint, so the bin/ folder is useless even if they bypass the
# Layer-1 HMAC gate (DRM defense in depth).
#
# If .json.enc is missing from the source tree, the dev forgot to run
# encrypt-profiles.py; fall back to plaintext .json with a loud warning
# so packaging still works during the v0.1.2 -> v0.1.3 transition.
Write-Host "[3/6] Copying encrypted fingerprint profiles..." -ForegroundColor Cyan
$ProfilesDst = Join-Path $Staging 'config\profiles'
New-Item -ItemType Directory -Path $ProfilesDst -Force | Out-Null

$encCount = (Get-ChildItem $ProfilesSrc -Filter '*.json.enc' -ErrorAction SilentlyContinue).Count
if ($encCount -gt 0) {
    Copy-Item -Path "$ProfilesSrc\*.json.enc" -Destination $ProfilesDst -Force
    Write-Host ("    {0} encrypted profiles copied (.json.enc)" -f $encCount)
} else {
    Write-Warning ("No .json.enc found at {0}. Run scripts/encrypt-profiles.py first." -f $ProfilesSrc)
    Write-Warning "Falling back to plaintext .json - the release will NOT be DRM-protected."
    Copy-Item -Path "$ProfilesSrc\*.json" -Destination $ProfilesDst -Force
    $plainCount = (Get-ChildItem $ProfilesDst -Filter '*.json').Count
    Write-Host ("    {0} plaintext profiles copied" -f $plainCount)
}

# --- Copy scripts ---
# Bundle the PowerShell launcher pair (back-compat with the old "no
# Python required" zip) plus the three Python helpers that drive the
# DRM-aware standalone flow: decrypt-profile.py (AES-GCM decrypt +
# optional auto-localize), gen-debug-token.py (per-launch HMAC token),
# encrypt-profiles.py (kept so a dev with .profile_key can re-encrypt
# after editing a JSON in-place).
Write-Host "[4/6] Copying scripts..." -ForegroundColor Cyan
$ScriptsDst = Join-Path $Staging 'scripts'
New-Item -ItemType Directory -Path $ScriptsDst -Force | Out-Null
$scriptsToShip = @(
    'chronium.ps1',
    'prepare-profile.ps1',
    'decrypt-profile.py',
    'gen-debug-token.py',
    'encrypt-profiles.py'
)
foreach ($f in $scriptsToShip) {
    $src = Join-Path $ScriptDir $f
    if (-not (Test-Path $src)) {
        Write-Warning "Missing $f at $src"
        continue
    }
    Copy-Item -Path $src -Destination $ScriptsDst -Force
}

# --- Compile gen-token.exe (native HMAC token generator) ---
# chronium.ps1's launch path needs a valid --license-ts/-nonce/-token or
# license_gate.cc silently _exits(0) on startup -- see
# patches/REBASE-153.md. gen-debug-token.py can make this token too, but
# requires Python (defeats the "no Python required" zip). The secret
# can't live in chronium.ps1 itself (plaintext script, trivially
# readable) so it goes in a tiny COMPILED helper instead -- same
# protection level as chrome.dll's embedded copy, not committed to git
# (see .gitignore), rebuilt fresh from the current config\.profile_key
# on every package run so it can never drift out of sync with whatever
# secret this build's chrome.dll actually has baked in.
$KeyFile = Join-Path $BuildRoot 'config\.profile_key'
$Csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ((Test-Path $KeyFile) -and $Csc) {
    Write-Host "    compiling gen-token.exe from config\.profile_key..."
    $genTokenCs = Join-Path $env:TEMP "gen-token-$([guid]::NewGuid()).cs"
    $genTokenExeOut = Join-Path $ScriptsDst 'gen-token.exe'
    $genOut = & (Join-Path $ScriptDir 'gen-token-source.ps1') -KeyPath $KeyFile -OutCs $genTokenCs 2>&1
    $cscOut = & $Csc /nologo "/out:$genTokenExeOut" $genTokenCs 2>&1
    Remove-Item -Force $genTokenCs -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $ScriptsDst 'gen-token.exe'))) {
        Write-Warning "gen-token.exe compile failed -- chronium.ps1 will fall back to gen-debug-token.py (needs Python) or fail the license gate."
        Write-Warning "gen-token-source.ps1 output: $genOut"
        Write-Warning "csc.exe output: $cscOut"
    }
} else {
    Write-Warning "config\.profile_key or csc.exe not found -- skipping gen-token.exe. chronium.ps1's launch will hit the license gate without it."
}

# Patch chronium.ps1 paths so the script resolves chronium.exe relative
# to the package layout (bin/chronium.exe) instead of C:\cr\src\out.
$ChroniumPs = Join-Path $ScriptsDst 'chronium.ps1'
$content = Get-Content $ChroniumPs -Raw
$content = $content -replace "(?ms)\`$Chronium\s+=.*?if \(-not \(Test-Path \`$Chronium\)\) \{\s*\`$Chronium = 'C:\\cr\\src\\out\\Release\\chrome\.exe'\s*\}", @'
$Chronium = Join-Path (Resolve-Path (Join-Path $ScriptDir '..\bin')) 'chronium.exe'
'@
Set-Content -Path $ChroniumPs -Value $content -Encoding utf8

# --- Make launcher batch for double-click setup ---
Write-Host "[5/6] Writing launcher + README..." -ForegroundColor Cyan

$BatchLauncher = Join-Path $Staging 'chronium.bat'
@'
@echo off
REM Wrapper around scripts\chronium.ps1 so end users can drag-and-drop /
REM double-click without typing PowerShell syntax. Arguments are passed
REM straight through.
setlocal
set "SCRIPT=%~dp0scripts\chronium.ps1"
if "%1"=="" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT%" list
) else (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT%" %*
)
'@ | Set-Content -Path $BatchLauncher -Encoding ascii

# Quick-start README.
$Readme = Join-Path $Staging 'README.md'
@"
# Chronium $Version — Anti-Detect Browser

Self-contained chronium binary + 170 device fingerprints + account
manager. No installer, no admin rights, no Python required.

## Quick start

Extract the zip anywhere (e.g. ``C:\Tools\chronium\``), then open
Command Prompt or PowerShell in the extracted folder.

``````
:: Create a new account (random unused fingerprint, opens grok.com)
chronium.bat new acc1 -Url https://grok.com

:: List all accounts and their assigned fingerprint
chronium.bat list

:: Reopen an existing account (same fingerprint, persistent cookies)
chronium.bat open acc1

:: Refresh fingerprint (gives the account a different device profile)
chronium.bat reassign acc1

:: Wipe an account (deletes user-data + registry entry)
chronium.bat delete acc1
``````

PowerShell users can call ``scripts\chronium.ps1`` directly with the
same arguments.

## What happens behind the scenes

Each account stores its browser data under
``C:\ChroniumProfiles\<accountName>\`` (cookies, history, login state).
The account-to-fingerprint mapping lives at
``C:\ChroniumProfiles\accounts.json`` and is read every launch — the
same account always loads the same fingerprint, so canvas / WebGL /
audio / Sec-CH-UA hashes stay paired with that identity forever.

The launcher auto-localizes each profile at startup:

* **Geo region** is derived from the exit IP (ip-api.com lookup).
  Timezone, locale, Accept-Language, and navigator.geolocation get
  swapped to match.
* **Screen + DPR** are pinned to the host's real values via the
  registry's AppliedDPI + wmic CurrentResolution. This is what kept
  iphey's pixel-DPI cross-check from failing the profile.

If you pass ``-Proxy socks5://user:pass@host:port`` the lookup uses
that proxy as well.

## File layout

``````
chronium-$Version/
  bin/                      # chronium.exe + chrome.dll + paks + locales
  config/
    profiles/               # 170 device fingerprints (.json)
  scripts/
    chronium.ps1            # account manager (new/open/list/delete/reassign)
    prepare-profile.ps1     # auto-localizer (geo + display)
  chronium.bat              # Windows wrapper for chronium.ps1
  README.md
``````

## Known limits

* iphey returns Trustworthy with the bundled win-* profiles on Windows
  hosts. Mac/Linux profiles run too but cross-platform detection trips
  the "Masking detected" check on stricter sites (Pixelscan, etc.).
* Pixelscan stays at "Collecting Data" — their JS crashes with a
  ``TypeError ... 'toString'`` against the bundled probe. ShardX,
  Multilogin and Kameleo all get the same stall. Not a chronium-side
  fix; it's their anti-detect signature list.
"@ | Set-Content -Path $Readme -Encoding utf8

# --- Zip ---
if (-not $SkipZip) {
    Write-Host "[6/6] Creating zip $Zip ..." -ForegroundColor Cyan
    if (Test-Path $Zip) { Remove-Item -Force $Zip }
    Compress-Archive -Path "$Staging\*" -DestinationPath $Zip -CompressionLevel Optimal
    $zipSize = (Get-Item $Zip).Length / 1MB
    Write-Host ""
    Write-Host "===" -ForegroundColor Green
    Write-Host "DONE" -ForegroundColor Green
    Write-Host "Staging: $Staging"
    Write-Host "Zip:     $Zip ($([math]::Round($zipSize,1)) MB)"
    Write-Host "===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "===" -ForegroundColor Green
    Write-Host "Staging built (zip skipped): $Staging" -ForegroundColor Green
    Write-Host "===" -ForegroundColor Green
}
