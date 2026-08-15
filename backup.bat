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
set BACKUP_WORKTREE=F:\software\Godot\project\wenmingzengliang
set SOURCE_DIR=%~dp0
set NO_PAUSE=0
for %%a in (%*) do (
    set "arg=%%a"
    if /i "!arg!"=="/nopause" set NO_PAUSE=1
)

echo ==================================
echo  Incremental Backup
echo ==================================

REM 1. Enter backup worktree and pull latest
echo [Step 1] Enter backup worktree...
cd /d "%BACKUP_WORKTREE%"
if errorlevel 1 (
    echo [ERROR] Cannot access: %BACKUP_WORKTREE%
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

"%GIT%" pull origin main
if errorlevel 1 (
    echo [WARN] Pull failed, continuing...
)

REM 2. Clean old backup folders (keep only latest)
echo [Step 2] Clean old backup folders...
for /d %%D in ("%BACKUP_WORKTREE%\20*") do (
    rmdir /s /q "%%D"
    echo     Removed: %%~nxD
)

REM 3. Get timestamp for folder name
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "dt=%%I"
set "TIMESTAMP=%dt:~0,4%%dt:~4,2%%dt:~6,2%_%dt:~8,2%%dt:~10,2%%dt:~12,2%"
set "BACKUP_DIR=%BACKUP_WORKTREE%\%TIMESTAMP%"

echo [Step 3] Create folder: %TIMESTAMP%
mkdir "%BACKUP_DIR%"

REM 4. Copy files using robocopy via PowerShell
echo [Step 4] Copy project files...
powershell -Command "robocopy '%SOURCE_DIR%' '%BACKUP_DIR%' /E /XD .git addons .godot /XF backup_exclude.txt backup.bat run_robocopy.bat run_robocopy.ps1 /NFL /NDL /NJH /NJS /NC /NS /NP"

REM 5. Commit and push
echo [Step 5] Commit and push...
"%GIT%" add .
"%GIT%" commit -m "backup: %TIMESTAMP%"
"%GIT%" push origin main

if errorlevel 1 (
    echo [ERROR] Push failed
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

echo.
echo [DONE] Backup completed successfully
cd /d "%~dp0"
if not "%NO_PAUSE%"=="1" pause
