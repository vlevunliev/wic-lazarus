@echo off
REM Pusni: wicprobe.bat "D:\Snimki\DSC06780.dng" [drug fail ...]
REM Pri parvo pusksane kompilira wicprobe.exe (tarsi fpc.exe kakto run_test.bat)
REM Rezultatat otiva i v wicprobe.txt v tekushtata papka
setlocal
if exist "%~dp0wicprobe.exe" goto :run
set FPC=
for /f "delims=" %%i in ('where fpc 2^>nul') do if not defined FPC set FPC=%%i
if not defined FPC for /d %%d in (C:\lazarus\fpc\*) do if exist "%%d\bin\x86_64-win64\fpc.exe" set FPC=%%d\bin\x86_64-win64\fpc.exe
if not defined FPC ( echo Ne namiram fpc.exe - dobavi go v PATH & exit /b 1 )
if not exist "%~dp0lib" mkdir "%~dp0lib"
"%FPC%" -Twin64 -Px86_64 -O2 -Fu"%~dp0.." -FU"%~dp0lib" -o"%~dp0wicprobe.exe" "%~dp0wicprobe.lpr" >"%~dp0build.log" 2>&1
if not exist "%~dp0wicprobe.exe" ( type "%~dp0build.log" & exit /b 1 )
:run
chcp 65001 >nul
"%~dp0wicprobe.exe" %* > wicprobe.txt 2>&1
type wicprobe.txt
