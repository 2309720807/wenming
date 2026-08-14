@echo off
set GIT=F:\software\Git\cmd\git.exe
cd /d "%~dp0"

echo ==================================
echo  开工流程：同步云端 + 建立占用锁
echo ==================================

REM 1. 检查本地是否有未推送改动
"%GIT%" status --porcelain 2>nul | findstr /r /c:"." >nul
if not errorlevel 1 (
    echo [步骤1] 检测到本地有未推送改动，先推送再开工...
    "%GIT%" push
    if errorlevel 1 (
        echo [错误] 推送失败，无法开工
        pause
        exit /b 1
    )
) else (
    echo [步骤1] 本地无未推送改动
)

REM 2. 拉取云端最新（此时本地=云端，无冲突）
echo [步骤2] 拉取云端最新版本...
"%GIT%" pull
if errorlevel 1 (
    echo [错误] pull 失败，请检查网络
    pause
    exit /b 1
)

REM 3. 检查是否被他人占用
if exist LOCK.md (
    echo.
    echo [占用] 项目已被占用，无法开工：
    type LOCK.md
    echo.
    echo 若占用超过24小时且已与对方确认，请手动删除 LOCK.md 后重新运行本脚本
    pause
    exit /b 1
)

REM 4. 建立占用锁并推送（锁生效）
for /f "delims=" %%n in ('"%GIT%" config --get user.name') do set UNAME=%%n
echo 占用者: %UNAME% > LOCK.md
echo 开工时间: %date% %time% >> LOCK.md
"%GIT%" add LOCK.md
"%GIT%" commit -m "chore: 开工占用锁（%UNAME%）"
"%GIT%" push
if errorlevel 1 (
    echo [错误] 锁推送失败，占用未生效，请检查网络
    pause
    exit /b 1
)

echo.
echo [完成] 开工成功，占用锁已生效，开始开发吧
pause