@echo off
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 1
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%i"
if not defined VSROOT exit /b 1
set "CMAKE=%VSROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set "CTEST=%VSROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe"
if not exist "%CMAKE%" exit /b 1
set "BUILD=%~dp0build-x64"
if not "%~1"=="" set "BUILD=%~f1"
"%CMAKE%" -S "%~dp0." -B "%BUILD%" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 exit /b 1
"%CMAKE%" --build "%BUILD%" --config Release
if errorlevel 1 exit /b 1
"%CTEST%" --test-dir "%BUILD%" -C Release --output-on-failure
exit /b %errorlevel%
