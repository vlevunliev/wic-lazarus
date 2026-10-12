@echo off
REM ============================================================
REM  run_test.bat - kompilira i pusksa wictest.exe
REM  Tarsi fpc.exe v PATH, posle v C:\lazarus\fpc\*\bin\x86_64-win64
REM  Exit code = broi failove (0 = ALL GREEN)
REM ============================================================
setlocal
cd /d "%~dp0"
set FPC=
for /f "delims=" %%i in ('where fpc 2^>nul') do if not defined FPC set FPC=%%i
if not defined FPC for /d %%d in (C:\lazarus\fpc\*) do if exist "%%d\bin\x86_64-win64\fpc.exe" set FPC=%%d\bin\x86_64-win64\fpc.exe
if not defined FPC ( echo Ne namiram fpc.exe - dobavi go v PATH & exit /b 1 )
echo Kompilator: %FPC%
if not exist lib mkdir lib
if exist wictest.exe del wictest.exe
"%FPC%" -Twin64 -Px86_64 -O2 -Fu.. -FUlib wictest.lpr >build.log 2>&1
if not exist wictest.exe ( type build.log & exit /b 1 )
chcp 65001 >nul
wictest.exe
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" ( echo ####  ALL GREEN  #### ) else ( echo ####  %RC% FAIL - prati izhoda na Claude  #### )
exit /b %RC%
