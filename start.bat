@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

REM ===== Git 路径检测（优先本机路径，回退常见安装位置与 PATH）=====
set GIT=F:\software\Git\cmd\git.exe
if exist "%GIT%" goto :GIT_OK
set "GIT="
for %%p in ("C:\Program Files\Git\cmd\git.exe" "C:\Program Files\Git\bin\git.exe" "%LOCALAPPDATA%\Programs\Git\cmd\git.exe") do (
    if not defined GIT if exist %%p set "GIT=%%~p"
)
if not defined GIT set "GIT=git"
:GIT_OK
"%GIT%" --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Git，请安装或修改脚本中的 GIT 路径
    exit /b 1
)

REM ===== 参数解析 =====
REM /y        : 迷你收工时自动确认推送（供自动化使用；人工运行仍会弹 choice 确认）
REM /nopause  : 全程不暂停（供自动化运行）
set AUTO_YES=0
set NO_PAUSE=0
for %%a in (%*) do (
    if /i "%%a"=="/y" set AUTO_YES=1
    if /i "%%a"=="/nopause" set NO_PAUSE=1
)

"%GIT%" config core.hooksPath .githooks

echo ==================================
echo  开工流程：查锁 + 同步 + 建锁
echo ==================================

REM 1. 获取云端状态（fetch，不合并，只查看）
echo [步骤1] 检查云端占用锁...
"%GIT%" fetch origin
if errorlevel 1 (
    echo [错误] 无法连接云端，终止开工
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM 2. 检查云端是否有锁（LOCK.md）
"%GIT%" cat-file -e origin/main:LOCK.md 2>nul
if not errorlevel 1 (
    REM 云端有锁，判断是否为本设备（匹配英文设备名，避免编码差异）
    "%GIT%" show origin/main:LOCK.md | findstr /c:"%COMPUTERNAME%" >nul
    if not errorlevel 1 (
        echo [提示] 云端存在本设备锁（上次未收工），可继续编辑
        goto :AFTER_LOCK_CHECK
    )
    echo.
    echo [占用] 项目已被其他设备占用，禁止开工！
    "%GIT%" show origin/main:LOCK.md
    echo.
    echo 锁超时（24小时）需与占用者确认后方可接管
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)
echo [步骤1] 云端无占用锁

:AFTER_LOCK_CHECK
REM 3. 检查本地未推送改动（上次未收工的残留）
"%GIT%" status --porcelain 2>nul | findstr /r /c:"." >nul
if not errorlevel 1 (
    echo.
    echo [步骤2] 检测到本地未推送改动（上次未收工）
    for /f %%i in ('"%GIT%" rev-list --count HEAD..origin/main 2^>nul') do set REMOTE_NEW=%%i
    if not "!REMOTE_NEW!"=="0" (
        echo.
        echo [警告] 云端已被他人修改（领先 !REMOTE_NEW! 个提交），禁止直接推送！
        echo 处理流程：先本地备份，再回退到云端版本：
        echo   git stash
        echo   git reset --hard origin/main
        echo 请手动备份后与占用者协调，再重新开工
        if not "%NO_PAUSE%"=="1" pause
        exit /b 1
    )
    echo [判断] 云端未被他人修改，可执行迷你收工（推送本地改动）
    if "%AUTO_YES%"=="1" (
        echo [步骤2] 自动确认（/y），推送本地改动...
    ) else (
        choice /c YN /m "是否确认推送本地改动到云端? Y=确认 N=跳过"
        if errorlevel 2 (
            echo [提示] 已取消推送，改为从云端最新版本开始
            goto :SKIP_PUSH
        )
        echo [步骤2] 用户已确认，推送本地改动...
    )
    set ALLOW_PUSH=1
    "%GIT%" push
    if errorlevel 1 (
        echo [错误] 推送本地改动失败，无法开工
        if not "%NO_PAUSE%"=="1" pause
        exit /b 1
    )
    set ALLOW_PUSH=
) else (
    echo [步骤2] 本地无未推送改动
)

:SKIP_PUSH
REM 4. 拉取云端最新版本
echo [步骤3] 拉取云端最新版本...
"%GIT%" pull
if errorlevel 1 (
    echo [错误] pull 失败，终止开工
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM 5. 建立占用锁（本设备已锁则不重建）
if exist LOCK.md (
    echo [步骤4] 本地已有占用锁，无需重建
    goto :DONE
)
"%GIT%" cat-file -e origin/main:LOCK.md 2>nul
if not errorlevel 1 (
    echo [提示] 云端已存在占用锁，无需重建
    goto :DONE
)
for /f "delims=" %%n in ('"%GIT%" config --get user.name') do set UNAME=%%n
if not defined UNAME set UNAME=unknown
echo 设备: %COMPUTERNAME% > LOCK.md
echo 占用者: %UNAME% >> LOCK.md
echo 占用时间: %date% %time% >> LOCK.md
"%GIT%" add LOCK.md
"%GIT%" commit -m "chore: 建立占用锁（%COMPUTERNAME%/%UNAME%）"
REM 锁推送属开工流程一部分，自动执行
"%GIT%" push
if errorlevel 1 (
    echo [错误] 锁推送失败，占用未生效，终止开工
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)
echo [步骤4] 占用锁已建立并生效

:DONE
echo.
echo [完成] 开工成功，可以开始编辑
if not "%NO_PAUSE%"=="1" pause