@echo off
set GIT=F:\software\Git\cmd\git.exe
cd /d "%~dp0"

echo ==================================
echo  开工：拉取远程最新版本...
echo ==================================

"%GIT%" pull
if errorlevel 1 (
    echo [提示] 拉取可能有冲突或没有远程改动
    pause
    exit /b 1
)

echo.
echo [完成] 已同步到最新版本，可以开始开发了
pause