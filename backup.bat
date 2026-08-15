@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

REM ===== Git 路径检测（与 push.bat 一致）=====
set GIT=F:\software\Git\cmd\git.exe
if exist "%GIT%" goto :GIT_OK
set "GIT="
for %%p in ("C:\Program Files\Git\cmd\git.exe" "C:\Program Files\Git\bin\git.exe" "%LOCALAPPDATA%\Programs\Git\cmd\git.exe") do (
    if not defined GIT if exist %%p set "GIT=%%~p"
)
if not defined GIT set "GIT=git"
:GIT_OK

REM ===== 路径配置 =====
set BACKUP_WORKTREE=F:\software\Git\wenmingzengliang.git
set SOURCE_DIR=%~dp0
set NO_PAUSE=0
for %%a in (%*) do (
    set "arg=%%a"
    if /i "!arg!"=="/nopause" set NO_PAUSE=1
)

echo ==================================
echo  增量备份：复制项目到备份仓库
echo ==================================

REM 1. 进入备份仓库 worktree，拉取最新
echo [步骤1] 进入备份仓库并拉取最新...
cd /d "%BACKUP_WORKTREE%"
if errorlevel 1 (
    echo [错误] 无法进入备份仓库路径: %BACKUP_WORKTREE%
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

"%GIT%" pull origin main
if errorlevel 1 (
    echo [警告] 拉取远程失败，尝试继续...
)

REM 2. 获取当前时间戳作为文件夹名
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "dt=%%I"
set "TIMESTAMP=%dt:~0,4%%dt:~4,2%%dt:~6,2%_%dt:~8,2%%dt:~10,2%%dt:~12,2%"
set "BACKUP_DIR=%BACKUP_WORKTREE%\%TIMESTAMP%"

echo [步骤2] 创建备份文件夹: %TIMESTAMP%
mkdir "%BACKUP_DIR%"

REM 3. 从源项目复制文件（排除 .git、addons、.godot）
echo [步骤3] 复制项目文件...
xcopy "%SOURCE_DIR%" "%BACKUP_DIR%\" /E /I /Q /Y /EXCLUDE:"%~dp0backup_exclude.txt"

REM 4. 提交并推送
echo [步骤4] 提交备份到云端...
"%GIT%" add .
"%GIT%" commit -m "backup: 增量备份 %TIMESTAMP%"
"%GIT%" push origin main

if errorlevel 1 (
    echo [错误] 推送失败
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

echo.
echo [完成] 增量备份已成功推送至云端
cd /d "%~dp0"
if not "%NO_PAUSE%"=="1" pause
