@echo off
set GIT=F:\software\Git\cmd\git.exe
cd /d "%~dp0"

echo ==================================
echo  正在提交并推送项目...
echo ==================================

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
    pause
    exit /b 1
)

"%GIT%" push
if errorlevel 1 (
    echo [错误] 推送失败，请检查网络或登录状态
    pause
    exit /b 1
)

echo.
echo [完成] 已成功推送到 GitHub
pause