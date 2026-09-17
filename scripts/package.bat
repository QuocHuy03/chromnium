@echo off
setlocal

REM ============================================================
REM  package.bat
REM  Copy build output into release\chronium\, rename chrome.exe
REM  to chronium.exe, and patch Win32 resources (icon, ProductName).
REM
REM  Requires: tools\rcedit.exe (download from
REM    https://github.com/electron/rcedit/releases)
REM ============================================================

set "SRC_OUT=C:\cr\src\out\Release"
set "ROOT=%~dp0.."
set "DEST=%ROOT%\release\chronium"
set "RCEDIT=%ROOT%\tools\rcedit.exe"
set "RESHACKER=%ROOT%\tools\reshacker\ResourceHacker.exe"
set "ICON=%ROOT%\assets\chronium.ico"

if not exist "%SRC_OUT%\chrome.exe" (
    echo [FAIL] %SRC_OUT%\chrome.exe missing. Run scripts\build.bat first.
    exit /b 1
)

if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%"

echo [1/4] Copying top-level binaries and data files
robocopy "%SRC_OUT%" "%DEST%" *.exe *.dll *.pak *.bin *.dat *.manifest /NJH /NJS /NDL /NP /NFL >nul
if errorlevel 8 (
    echo [FAIL] robocopy of top-level files failed.
    exit /b 1
)

echo [2/4] Copying resource directories
for %%D in (Locales swiftshader MEIPreload resources) do (
    if exist "%SRC_OUT%\%%D" (
        xcopy /E /I /Y /Q "%SRC_OUT%\%%D" "%DEST%\%%D" >nul
    )
)

echo [3/4] Rename chrome.exe -^> chronium.exe
ren "%DEST%\chrome.exe" chronium.exe
if errorlevel 1 (
    echo [FAIL] Could not rename chrome.exe.
    exit /b 1
)

echo [4/4] Icon + version branding
REM Chromium's exe ships 5 icon groups (IDR_MAINFRAME, IDR_X001_APP_LIST,
REM IDR_X003_INCOGNITO, IDR_X006_HTML_DOC, IDR_X007_PDF_DOC) as STRING-named
REM RT_GROUP_ICON resources, not the single numeric-ID icon rcedit's
REM --set-icon expects to find and replace -- rcedit silently ADDS a new
REM icon group instead of replacing the one Explorer/taskbar actually show
REM (IDR_MAINFRAME). Resource Hacker's -mask lets us target that resource
REM by name directly, so it does the icon swap; rcedit still handles the
REM version-string fields below, which it does correctly.
if not exist "%RESHACKER%" (
    echo [WARN] tools\reshacker\ResourceHacker.exe missing. Skipping icon patch.
    echo        Download from http://www.angusj.com/resourcehacker/resource_hacker.zip
) else if not exist "%ICON%" (
    echo [WARN] %ICON% missing. Skipping icon patch.
) else (
    if exist "%DEST%\chronium.exe.tmp" del /f /q "%DEST%\chronium.exe.tmp"
    call "%RESHACKER%" -open "%DEST%\chronium.exe" -save "%DEST%\chronium.exe.tmp" -action addoverwrite -res "%ICON%" -mask ICONGROUP,IDR_MAINFRAME, -log "%ROOT%\reshacker.log"
    if exist "%DEST%\chronium.exe.tmp" (
        move /y "%DEST%\chronium.exe.tmp" "%DEST%\chronium.exe" >nul
    ) else (
        echo [WARN] Resource Hacker did not produce output ^(see reshacker.log^); icon left unchanged.
    )

    REM chrome.exe is only a small bootstrap stub -- the actual browser
    REM window (title bar / taskbar icon while running) loads its icon at
    REM runtime from chrome.dll's own icon group #101 (IDR_MAINFRAME's
    REM compiled numeric id there), not from the exe. Patching only the exe
    REM changes what Explorer shows for the file but not the running
    REM window's icon, so chrome.dll needs the same treatment.
    if exist "%DEST%\chrome.dll.tmp" del /f /q "%DEST%\chrome.dll.tmp"
    call "%RESHACKER%" -open "%DEST%\chrome.dll" -save "%DEST%\chrome.dll.tmp" -action addoverwrite -res "%ICON%" -mask ICONGROUP,101, -log "%ROOT%\reshacker-dll.log"
    if exist "%DEST%\chrome.dll.tmp" (
        move /y "%DEST%\chrome.dll.tmp" "%DEST%\chrome.dll" >nul
    ) else (
        echo [WARN] Resource Hacker did not produce output for chrome.dll ^(see reshacker-dll.log^); running-window icon left unchanged.
    )
)

if not exist "%RCEDIT%" (
    echo [WARN] tools\rcedit.exe missing. Skipping version-string patch.
    echo        Download from https://github.com/electron/rcedit/releases
    goto done
)

REM Chain each rcedit call separately -- accumulating multi-word quoted
REM values (e.g. "Chronium Browser") through one %RCARGS% variable loses
REM the quoting on re-expansion and rcedit sees two bare arguments instead.
set "RCFAIL=0"
call "%RCEDIT%" "%DEST%\chronium.exe" --set-version-string "ProductName" "Chronium"
if errorlevel 1 set "RCFAIL=1"
call "%RCEDIT%" "%DEST%\chronium.exe" --set-version-string "CompanyName" "Interlink"
if errorlevel 1 set "RCFAIL=1"
call "%RCEDIT%" "%DEST%\chronium.exe" --set-version-string "FileDescription" "Chronium Browser"
if errorlevel 1 set "RCFAIL=1"
call "%RCEDIT%" "%DEST%\chronium.exe" --set-version-string "OriginalFilename" "chronium.exe"
if errorlevel 1 set "RCFAIL=1"
if "%RCFAIL%"=="1" (
    echo [WARN] rcedit failed on at least one property. Binary is functional but may be partially un-branded.
)

:done
echo.
echo ============================================================
echo  Package ready: %DEST%\chronium.exe
echo.
echo  Quick smoke test:
echo    "%DEST%\chronium.exe" ^
echo        --user-data-dir=D:\profiles\test1 ^
echo        --fingerprint-profile=%ROOT%\config\example-profile.json ^
echo        --remote-debugging-port=9222
echo ============================================================
exit /b 0
