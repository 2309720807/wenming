@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

REM ===== Git ·����⣨���ȱ���·�������˳�����װλ���� PATH��=====
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
    echo [����] δ�ҵ� Git���밲װ���޸Ľű��е� GIT ·��
    exit /b 1
)

REM ===== �������� =====
REM ��һ���� / ��ͷ������Ϊ�ύ˵������ push.bat "feat: �չ�"��
REM /nopause  : ȫ�̲���ͣ�����Զ������У�
set NO_PAUSE=0
set MSG=
for %%a in (%*) do (
    set "arg=%%a"
    if /i "!arg!"=="/nopause" (set NO_PAUSE=1) else if not defined MSG set "MSG=!arg!"
)

"%GIT%" config core.hooksPath .githooks

echo ==================================
echo  �չ����̣����͸Ķ� + �ͷ�ռ����
echo ==================================

REM 1. �ύȫ���Ķ������б��ű���Ϊ�û�ȷ���չ���
echo [����1] �ύ���������б��ظĶ�...
"%GIT%" add .
if errorlevel 1 (
    echo [����] git add ʧ��
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

REM ֧�ֻ������� COMMIT_MSG ָ���ύ˵�����������������Ĵ������⣩
if not defined MSG if defined COMMIT_MSG set "MSG=%COMMIT_MSG%"
if not defined MSG (
    set /p MSG=�����뱾���ύ˵����ֱ�ӻس����Զ���Ϣ��:
)
if not defined MSG set "MSG=�Զ��ύ %date% %time%"

"%GIT%" commit -m "%MSG%"
if errorlevel 1 (
    echo [��ʾ] û�иĶ���Ҫ�ύ
)

set ALLOW_PUSH=1
"%GIT%" push
if errorlevel 1 (
    echo [����] ����ʧ�ܣ����ֵ�ǰ״̬
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)
set ALLOW_PUSH=

REM 2. �ͷ�ռ����
if exist LOCK.md (
    echo [����2] �ͷ�ռ����...
    del LOCK.md
    "%GIT%" add LOCK.md
    "%GIT%" commit -m "chore: �չ��ͷ�ռ����"
    "%GIT%" push
    if errorlevel 1 (
        echo [����] ���ͷ�����ʧ�ܣ����ֶ�����
        if not "%NO_PAUSE%"=="1" pause
        exit /b 1
    )
    echo [���] ռ�������ͷ�
) else (
    echo [��ʾ] δ��⵽ռ�����������ϴ�δ������
)

echo.
echo [���] �ѳɹ����͵� GitHub

REM 3. ��������
echo.
echo [����3] ִ��������...
call "%~dp0backup.bat" /nopause

echo.
echo [���] �չ����̾���
if not "%NO_PAUSE%"=="1" pause