@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

REM ===== Git path detection =====
set GIT=F:\software\Git\cmd\git.exe
if exist "%GIT%" goto :GIT_OK
set "GIT="
for %%p in ("C:\Program Files\Git\cmd\git.exe" "C:\Program Files\Git\bin\git.exe" "%LOCALAPPDATA%\Programs\Git\cmd\git.exe") do (
    if not defined GIT if exist %%p set "GIT=%%~p"
)
if not defined GIT set "GIT=git"
:GIT_OK

REM ===== Config =====
REM bare �ֿ⣺���� git ����⣨ѹ���������������ĸ�������ʡ���ش���
set BARE_REPO=F:\software\Git\wenmingzengliang.git
set SOURCE_DIR=%~dp0
set TMP_WORKTREE=%TEMP%\wm_backup_worktree
set NO_PAUSE=0
for %%a in (%*) do (
    set "arg=%%a"
    if /i "!arg!"=="/nopause" set NO_PAUSE=1
)

echo ==================================
echo  Incremental Backup (temp worktree)
echo ==================================

REM 1. Prepare temporary worktree
echo [Step 1] Prepare temp worktree...
if exist "%TMP_WORKTREE%" (
    "%GIT%" -C "%BARE_REPO%" worktree remove --force "%TMP_WORKTREE%" >nul 2>&1
    rmdir /s /q "%TMP_WORKTREE%" 2>nul
)
"%GIT%" -C "%BARE_REPO%" worktree prune

"%GIT%" -C "%BARE_REPO%" worktree add --force "%TMP_WORKTREE%" main
if errorlevel 1 (
    echo [ERROR] Cannot create temp worktree
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM 2. Pull latest from GitHub
echo [Step 2] Pull latest from GitHub...
"%GIT%" -C "%TMP_WORKTREE%" pull origin main
if errorlevel 1 (
    echo [WARN] Pull failed, continuing...
)

REM 3. Get timestamp for folder name
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "dt=%%I"
set "TIMESTAMP=%dt:~0,4%%dt:~4,2%%dt:~6,2%_%dt:~8,2%%dt:~10,2%%dt:~12,2%"
set "BACKUP_DIR=%TMP_WORKTREE%\%TIMESTAMP%"

REM 3.1 Find latest previous backup folder (format: YYYYMMDD_HHMMSS)
REM Must scan BEFORE creating the new folder, otherwise the new empty folder would be picked
REM dir /b /ad sorts by name; timestamp format is fixed-length, so the last match is the newest
set "LAST_BACKUP="
for /f "delims=" %%D in ('dir /b /ad "%TMP_WORKTREE%" ^| findstr /r "^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]$"') do set "LAST_BACKUP=%%D"

echo [Step 3] Create folder: %TIMESTAMP%
mkdir "%BACKUP_DIR%"

REM 4. Copy previous backup as local base copy (fast, no upload)
REM NOTE: robocopy must be wrapped in powershell because %~dp0 ends with "\"
REM and cmd would mangle the quote escaping (\" at end of path)
if defined LAST_BACKUP (
    echo [Step 4] Copy previous backup "%LAST_BACKUP%" as base copy...
    powershell -Command "robocopy '%TMP_WORKTREE%\!LAST_BACKUP!' '%BACKUP_DIR%' /E /NFL /NDL /NJH /NJS /NC /NS /NP"
) else (
    echo [Step 4] No previous backup, full copy mode
)

REM 5. Sync only changed files onto the new folder
REM /MIR = mirror (purge files deleted locally), /XO = skip files newer in destination (unchanged)
echo [Step 5] Sync changed files...
powershell -Command "robocopy '%SOURCE_DIR%' '%BACKUP_DIR%' /MIR /XO /XD .git addons .godot wenmingzengliang /XF backup_exclude.txt backup.bat run_robocopy.bat run_robocopy.ps1 /NFL /NDL /NJH /NJS /NC /NS /NP"

REM 6. Commit and push
echo [Step 6] Commit and push...
"%GIT%" -C "%TMP_WORKTREE%" add .
"%GIT%" -C "%TMP_WORKTREE%" commit -m "backup: %TIMESTAMP%"
"%GIT%" -C "%TMP_WORKTREE%" push origin main

if errorlevel 1 (
    echo [ERROR] Push failed
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM 7. Remove temp worktree (���ز������ĸ���)
echo [Step 7] Remove temp worktree...
"%GIT%" -C "%BARE_REPO%" worktree remove --force "%TMP_WORKTREE%"
rmdir /s /q "%TMP_WORKTREE%" 2>nul

echo.
echo [DONE] Backup completed successfully
cd /d "%~dp0"
if not "%NO_PAUSE%"=="1" pause