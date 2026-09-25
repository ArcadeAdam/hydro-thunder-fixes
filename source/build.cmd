@echo off
setlocal
rem Build from source using the x86 C++ tools in Visual Studio Build Tools.
rem Optionally pass a full vcvarsall.bat path as the first argument.
set "HYDRO_VCVARS=%~1"
if defined HYDRO_VCVARS goto compiler_found
set "HYDRO_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%HYDRO_VSWHERE%" goto compiler_missing
for /f "usebackq tokens=*" %%I in (`"%HYDRO_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "HYDRO_VCVARS=%%I\VC\Auxiliary\Build\vcvarsall.bat"
:compiler_found
if not exist "%HYDRO_VCVARS%" goto compiler_missing
call "%HYDRO_VCVARS%" x86
if errorlevel 1 exit /b 1
if not exist "%~dp0..\build" mkdir "%~dp0..\build"
if not exist "%~dp0..\payload" mkdir "%~dp0..\payload"
pushd "%~dp0..\build"
set "HYDRO_FLAGS=/nologo /W4 /WX /O2 /MT /GS /guard:cf /EHsc /std:c++17 /FAs /DUNICODE /D_UNICODE /DWIN32_LEAN_AND_MEAN /DNOMINMAX"
cl %HYDRO_FLAGS% /LD ..\source\HydroSave.cpp ..\source\HydroSaveCore.cpp /Fe:HydroSave.dll /link /DEF:..\source\HydroSave.def /MACHINE:X86 /DYNAMICBASE /NXCOMPAT /Brepro
if errorlevel 1 goto failed
cl %HYDRO_FLAGS% ..\tests\HydroSaveTests.cpp ..\source\HydroSaveCore.cpp /Fe:HydroSaveTests.exe /link /MACHINE:X86 /DYNAMICBASE /NXCOMPAT /Brepro
if errorlevel 1 goto failed
cl %HYDRO_FLAGS% ..\tests\SmallStackSmoke.cpp ..\source\HydroSaveCore.cpp /Fe:SmallStackSmoke.exe /link /MACHINE:X86 /STACK:8192,8192 /DYNAMICBASE /NXCOMPAT /Brepro
if errorlevel 1 goto failed
copy /y HydroSave.dll "..\payload\HydroSave.dll" >nul
if errorlevel 1 goto failed
HydroSaveTests.exe "%~dp0..\tests\results" "%CD%\HydroSave.dll"
if errorlevel 1 goto failed
SmallStackSmoke.exe "%~dp0..\tests\results" "%CD%\HydroSave.dll"
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
:compiler_missing
echo Install Visual Studio Build Tools with Desktop development with C++, or pass vcvarsall.bat.
exit /b 2
