@echo off
set GIT=F:\software\Git\cmd\git.exe
cd /d "%~dp0"

echo ==================================
echo  收工流程：推送改动 + 释放占用锁
echo ==================================

REM 1. 提交并推送所有改动
"%GIT%" add .
if errorlevel 1 (
    echo [错误] git add 失败
    pause
    exit /b 1
)

set /p MSG=请输入本次提交说明（直接回车则使用自动日期）:
if "%MSG%"=="" set MSG=自动提交 %date% %time%

"%GIT%" commit -m "%MSG%"
if errorlevel 1 (
    echo [提示] 可能没有改动需要提交
)

"%GIT%" push
if errorlevel 1 (
    echo [错误] 推送失败，请检查网络或登录状态
    pause
    exit /b 1
)

REM 2. 释放占用锁（若存在）
if exist LOCK.md (
    echo [步骤2] 释放占用锁...
    del LOCK.md
    "%GIT%" add LOCK.md
    "%GIT%" commit -m "chore: 收工释放占用锁"
    "%GIT%" push
    if errorlevel 1 (
        echo [错误] 锁释放推送失败，请手动处理
        pause
        exit /b 1
    )
    echo [完成] 已收工，占用锁已释放
) else (
    echo [提示] 未检测到占用锁（本次可能未开工）
)

echo.
echo [完成] 已成功推送到 GitHub
pause