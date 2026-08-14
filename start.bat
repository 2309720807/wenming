@echo off
set GIT=F:\software\Git\cmd\git.exe
cd /d "%~dp0"
set DEVICE=%COMPUTERNAME%

echo ==================================
echo  开工流程：查锁 + 同步 + 建锁
echo ==================================

REM 1. 获取云端最新状态（仅 fetch，不合并）
echo [步骤1] 检查云端占用锁...
"%GIT%" fetch origin
if errorlevel 1 (
    echo [错误] 无法连接云端，请检查网络
    pause
    exit /b 1
)

REM 2. 检查云端是否有锁
"%GIT%" cat-file -e origin/main:LOCK.md 2>nul
if not errorlevel 1 (
    REM 云端有锁，判断是否为当前设备
    "%GIT%" show origin/main:LOCK.md | findstr /c:"设备: %DEVICE%" >nul
    if not errorlevel 1 (
        echo [提示] 云端存在本设备的锁（上次可能未收工），可继续编辑
        goto :AFTER_LOCK_CHECK
    )
    echo.
    echo [占用] 项目已被其他设备占用，禁止开工：
    "%GIT%" show origin/main:LOCK.md
    echo.
    echo 若锁超时（24小时），需与占用者确认后方可接管
    pause
    exit /b 1
)
echo [步骤1] 云端无占用锁

:AFTER_LOCK_CHECK
REM 3. 检查本地是否有未推送改动
"%GIT%" status --porcelain 2>nul | findstr /r /c:"." >nul
if not errorlevel 1 (
    echo [步骤2] 检测到本地有未推送改动，先推送（迷你收工）...
    "%GIT%" push
    if errorlevel 1 (
        echo [错误] 本地改动推送失败，无法开工
        pause
        exit /b 1
    )
) else (
    echo [步骤2] 本地无未推送改动
)

REM 4. 拉取云端最新（此时本地=云端，无冲突）
echo [步骤3] 拉取云端最新版本...
"%GIT%" pull
if errorlevel 1 (
    echo [错误] pull 失败，请检查网络
    pause
    exit /b 1
)

REM 5. 建立占用锁（若本地无锁，且云端无锁）
if exist LOCK.md (
    echo [步骤4] 已存在锁（本设备），无需重建
    goto :DONE
)
"%GIT%" cat-file -e origin/main:LOCK.md 2>nul
if not errorlevel 1 (
    echo [提示] 云端存在锁，无需重建
    goto :DONE
)

for /f "delims=" %%n in ('"%GIT%" config --get user.name') do set UNAME=%%n
echo 设备: %DEVICE% > LOCK.md
echo 占用者: %UNAME% >> LOCK.md
echo 开工时间: %date% %time% >> LOCK.md
"%GIT%" add LOCK.md
"%GIT%" commit -m "chore: 开工占用锁（%DEVICE%/%UNAME%）"
"%GIT%" push
if errorlevel 1 (
    echo [错误] 锁推送失败，占用未生效，请检查网络
    pause
    exit /b 1
)
echo [步骤4] 占用锁已建立并生效

:DONE
echo.
echo [完成] 开工成功，开始开发吧
pause