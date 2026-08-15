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
REM 无参数                : 交互式菜单
REM view                          : 查看提交历史
REM show ^<提交号^>               : 查看某次提交改动的文件与统计
REM file ^<提交号^> ^<文件路径^>   : 查看某版本中某文件的内容
REM checkout ^<提交号^>           : 临时切到某版本试运行（用 git checkout main 切回）
REM reset ^<提交号^> /y           : 永久回退到某版本（危险，必须显式 /y 确认）

set CMD=%~1
set ID=%~2
set FILE=%~3
set FLAG=%~4

if "%CMD%"=="" goto :MENU
if /i "%CMD%"=="view" goto :VIEW
if /i "%CMD%"=="show" goto :SHOW
if /i "%CMD%"=="file" goto :FILE
if /i "%CMD%"=="checkout" goto :CHECKOUT
if /i "%CMD%"=="reset" goto :RESET
echo [错误] 未知命令: %CMD%
echo 用法:
echo   history.bat view
echo   history.bat show ^<提交号^>
echo   history.bat file ^<提交号^> ^<文件路径^>
echo   history.bat checkout ^<提交号^>
echo   history.bat reset ^<提交号^> /y
exit /b 1

:MENU
echo ==================================
echo  历史记录工具（仅操作本地 git）
echo ==================================
echo  1. 查看提交历史
echo  2. 查看某次提交改动详情
echo  3. 查看某版本某文件内容
echo  4. 临时切到某版本试运行
echo  5. 永久回退到某版本（危险）
echo  0. 退出
echo.
set /p MENU_CHOICE=请输入数字选择:
if "%MENU_CHOICE%"=="1" goto :VIEW
if "%MENU_CHOICE%"=="2" goto :MENU_SHOW
if "%MENU_CHOICE%"=="3" goto :MENU_FILE
if "%MENU_CHOICE%"=="4" goto :MENU_CHECKOUT
if "%MENU_CHOICE%"=="5" goto :MENU_RESET
if "%MENU_CHOICE%"=="0" exit /b 0
echo [错误] 无效选择: %MENU_CHOICE%
goto :MENU

:VIEW
echo.
echo ===== 提交历史（最新在前）=====
"%GIT%" log --oneline
echo.
if "%CMD%"=="" pause
exit /b 0

:MENU_SHOW
set /p ID=请输入提交号（直接回车查看最新提交）:
if "%ID%"=="" set ID=HEAD
goto :SHOW

:SHOW
if "%ID%"=="" set /p ID=请输入提交号（直接回车查看最新提交）:
if "%ID%"=="" set ID=HEAD
echo.
echo ===== 提交 %ID% 的改动 =====
"%GIT%" show %ID% --stat
echo.
if "%CMD%"=="" pause
exit /b 0

:MENU_FILE
set /p ID=请输入提交号:
set /p FILE=请输入文件路径（如 scenes/ui/login.tscn）:
goto :FILE

:FILE
if "%ID%"=="" set /p ID=请输入提交号:
if "%FILE%"=="" set /p FILE=请输入文件路径（如 scenes/ui/login.tscn）:
echo.
echo ===== 提交 %ID% 中 %FILE% 的内容 =====
"%GIT%" show %ID%:%FILE%
echo.
if "%CMD%"=="" pause
exit /b 0

:MENU_CHECKOUT
set /p ID=请输入提交号:
goto :CHECKOUT

:CHECKOUT
if "%ID%"=="" set /p ID=请输入提交号:
echo.
echo [提示] 将临时切换到提交 %ID%（工作区文件变为该版本，不丢失任何提交）
if "%CMD%"=="" (
    set /p CONFIRM=确认切换? Y=确认 N=取消:
    if /i not "!CONFIRM!"=="Y" (echo 已取消 & exit /b 0)
)
"%GIT%" checkout %ID%
if errorlevel 1 (
    echo [错误] 切换失败（可能有本地未提交改动，请先提交或备份）
    if not "%CMD%"=="" exit /b 1
    pause
    exit /b 1
)
echo.
echo [完成] 已切换到 %ID%（分离头指针状态）
echo 查看/试运行后切回最新版：git checkout main
echo.
if "%CMD%"=="" pause
exit /b 0

:MENU_RESET
set /p ID=请输入提交号:
echo.
echo [警告] 永久回退将丢弃 %ID% 之后的所有提交与改动！
echo 请再次输入提交号确认（输入 取消 退出）:
set /p CONFIRM2=
if not "%CONFIRM2%"=="%ID%" (echo 已取消 & exit /b 0)
goto :RESET_EXEC

:RESET
if not "%FLAG%"=="/y" (
    echo [错误] 永久回退是危险操作，必须显式确认：
    echo   history.bat reset ^<提交号^> /y
    echo 交互模式请直接运行 history.bat 后选择菜单 5
    exit /b 1
)
goto :RESET_EXEC

:RESET_EXEC
"%GIT%" status --porcelain 2>nul | findstr /r /c:"." >nul
if not errorlevel 1 (
    echo [警告] 检测到本地未提交改动，永久回退将丢失它们！
    echo 建议先提交或备份：git stash
)
echo.
echo [执行] 永久回退到 %ID% ...
"%GIT%" reset --hard %ID%
if errorlevel 1 (
    echo [错误] 回退失败
    pause
    exit /b 1
)
echo [完成] 已永久回退到 %ID%
pause
exit /b 0