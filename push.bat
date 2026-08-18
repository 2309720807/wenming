@echo off
chcp 65001 >nul
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
REM 第一个非 / 开头参数为提交说明（如 push.bat "feat: 新功能"）
REM /nopause  : 全程不暂停（供自动化运行）
set NO_PAUSE=0
set MSG=
for %%a in (%*) do (
    set "arg=%%a"
    if /i "!arg!"=="/nopause" (set NO_PAUSE=1) else if not defined MSG set "MSG=!arg!"
)

"%GIT%" config core.hooksPath .githooks

echo ==================================
echo  收工流程：提交推送 + 释放占用锁
echo ==================================

REM 1. 提交全部改动（含未跟踪文件，以用户确认为准）
echo [步骤1] 提交全部改动...
"%GIT%" add .
if errorlevel 1 (
    echo [错误] git add 失败
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM 支持通过环境变量 COMMIT_MSG 指定提交说明（优先级低于首参数）
if not defined MSG if defined COMMIT_MSG set "MSG=%COMMIT_MSG%"
if not defined MSG (
    set /p MSG=请输入本次提交说明（直接回车则使用自动消息）:
)
if not defined MSG set "MSG=自动提交 %date% %time%"

"%GIT%" commit -m "%MSG%"
if errorlevel 1 (
    echo [提示] 没有改动需要提交
)

set ALLOW_PUSH=1
"%GIT%" push
if errorlevel 1 (
    echo [错误] 推送失败，请检查当前状态
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)
set ALLOW_PUSH=

REM 2. 释放占用锁
if exist LOCK.md (
    echo [步骤2] 释放占用锁...
    del LOCK.md
    "%GIT%" add LOCK.md
    "%GIT%" commit -m "chore: 收工释放占用锁"
    "%GIT%" push
    if errorlevel 1 (
        echo [错误] 释放占用锁失败，请检查状态
        if not "%NO_PAUSE%"=="1" pause
        exit /b 1
    )
    echo [完成] 占用锁已释放
) else (
    echo [提示] 未找到占用锁（可能未开工），跳过释放步骤
)

echo.
echo [完成] 改动已推送至 GitHub

REM 3. 增量备份
echo.
echo [步骤3] 执行增量备份...
call "%~dp0backup.bat" /nopause

echo.
echo [完成] 收工流程结束
if not "%NO_PAUSE%"=="1" pause
