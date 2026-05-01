@chcp 65001 >nul
@echo off
REM build_windows.bat — Build UniDock-Pro on Windows
REM
REM Prerequisites:
REM   Visual Studio 2019/2022 with C++ workload
REM   CUDA Toolkit >= 11.8  (https://developer.nvidia.com/cuda-downloads)
REM   CMake >= 3.16
REM   Boost >= 1.72  OR use --fetch-boost
REM
REM Run in "x64 Native Tools Command Prompt for VS"
REM Usage:
REM   build_windows.bat                 -- build both GPU and CPU variants
REM   build_windows.bat --cpu-only      -- build CPU variant only
REM   build_windows.bat --gpu-only      -- build GPU variant only

setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set DIST_DIR=%SCRIPT_DIR%dist
set FETCH_BOOST=OFF
set PORTABLE=OFF
set BUILD_CPU=ON
set BUILD_GPU=ON
set CMAKE_GENERATOR_ARGS=-G "Visual Studio 17 2022" -A x64
set CUDA_TOOLSET_ARG=

if defined CUDA_PATH if exist "%CUDA_PATH%\bin\nvcc.exe" (
  set CUDA_TOOLSET_ARG=-T cuda="%CUDA_PATH%"
) else (
  for /f "delims=" %%I in ('where nvcc 2^>nul') do (
    for %%J in ("%%~dpI..") do (
      if exist "%%~fJ\bin\nvcc.exe" (
        set CUDA_TOOLSET_ARG=-T cuda="%%~fJ"
        goto :cuda_toolset_ready
      )
    )
  )
)

:cuda_toolset_ready

:parse_args
if "%~1"=="--cpu"          set BUILD_GPU=OFF & shift & goto parse_args
if "%~1"=="--cpu-only"     set BUILD_GPU=OFF & shift & goto parse_args
if "%~1"=="--gpu-only"     set BUILD_CPU=OFF & shift & goto parse_args
if "%~1"=="--fetch-boost"  set FETCH_BOOST=ON & shift & goto parse_args
if "%~1"=="--portable"     set PORTABLE=ON & shift & goto parse_args
if "%~1"=="--no-portable"  set PORTABLE=OFF & shift & goto parse_args

if "%BUILD_CPU%"=="OFF" if "%BUILD_GPU%"=="OFF" (
  echo ERROR: both CPU and GPU builds are disabled.
  exit /b 1
)

echo === UniDock-Pro Windows Build ===
echo   Source   : %SCRIPT_DIR%
echo   Portable : %PORTABLE%
echo   Build CPU: %BUILD_CPU%
echo   Build GPU: %BUILD_GPU%
if defined CUDA_TOOLSET_ARG echo   CUDA Toolset: %CUDA_TOOLSET_ARG%
echo.

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

call :build_variant CPU ON OFF "%SCRIPT_DIR%build_cpu" UniDock-Pro.exe
if errorlevel 1 exit /b 1

call :build_variant GPU OFF ON "%SCRIPT_DIR%build_gpu" UniDock-Pro-GPU.exe
if errorlevel 1 exit /b 1

echo.
echo === Build complete ===
echo Dist dir: %DIST_DIR%
exit /b 0

:build_variant
set VARIANT=%~1
set CPU_ONLY=%~2
set REQUIRE_CUDA=%~3
set BUILD_DIR=%~4
set OUTPUT_NAME=%~5
set OUTPUT_STEM=%~n5
set BUNDLE_DIR=%DIST_DIR%\%OUTPUT_STEM%.bundle
set TARGET_EXE=%BUNDLE_DIR%\%OUTPUT_NAME%

if "%VARIANT%"=="CPU" if "%BUILD_CPU%"=="OFF" goto :eof
if "%VARIANT%"=="GPU" if "%BUILD_GPU%"=="OFF" goto :eof

echo --- Building %VARIANT% variant ---
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

if "%VARIANT%"=="GPU" if not defined CUDA_TOOLSET_ARG (
  echo ERROR: CUDA toolkit root could not be detected for GPU build.
  echo        Ensure CUDA_PATH is set or nvcc is on PATH, and install CUDA Visual Studio integration.
  exit /b 1
)

cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" %CMAKE_GENERATOR_ARGS% %CUDA_TOOLSET_ARG% ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DFORCE_CPU_ONLY=%CPU_ONLY% ^
  -DREQUIRE_CUDA=%REQUIRE_CUDA% ^
  -DFETCH_BOOST=%FETCH_BOOST% ^
  -DBUILD_PORTABLE=%PORTABLE%

if errorlevel 1 ( echo ERROR: CMake config failed. & exit /b 1 )

cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 ( echo ERROR: Build failed. & exit /b 1 )

if exist "%BUNDLE_DIR%" rmdir /S /Q "%BUNDLE_DIR%"
mkdir "%BUNDLE_DIR%" >nul

copy /Y "%BUILD_DIR%\Release\udp.exe" "%TARGET_EXE%" >nul
if errorlevel 1 ( echo ERROR: Failed to copy output binary. & exit /b 1 )

call :bundle_runtime "%TARGET_EXE%" "%BUNDLE_DIR%" "%VARIANT%"
echo   Output: %TARGET_EXE%
goto :eof

:bundle_runtime
set TARGET_EXE=%~1
set TARGET_DIR=%~2
set TARGET_VARIANT=%~3
set FOUND_DLLS=
set MISSING_DLLS=
if /I not "%PORTABLE%"=="ON" goto :eof
if not exist "%TARGET_EXE%" goto :eof
call :copy_candidate_dll "%TARGET_DIR%" vcomp140.dll
call :record_dll_status vcomp140.dll
call :copy_candidate_dll "%TARGET_DIR%" vcomp140_1.dll
call :record_dll_status vcomp140_1.dll
call :copy_candidate_dll "%TARGET_DIR%" libomp140.x86_64.dll
call :record_dll_status libomp140.x86_64.dll
call :copy_candidate_dll "%TARGET_DIR%" msvcp140.dll
call :record_dll_status msvcp140.dll
call :copy_candidate_dll "%TARGET_DIR%" vcruntime140.dll
call :record_dll_status vcruntime140.dll
call :copy_candidate_dll "%TARGET_DIR%" vcruntime140_1.dll
call :record_dll_status vcruntime140_1.dll
call :copy_candidate_dll "%TARGET_DIR%" concrt140.dll
call :record_dll_status concrt140.dll
echo   Portable bundle ready: %TARGET_DIR%
call :print_dll_summary "Copied runtime DLLs:" "!FOUND_DLLS!"
call :print_dll_summary "Missing runtime DLLs:" "!MISSING_DLLS!"
if /I "%TARGET_VARIANT%"=="GPU" echo   NOTE: GPU bundle still requires a compatible NVIDIA driver on the target machine.
goto :eof

:record_dll_status
if /I "%DLL_STATUS%"=="FOUND" (
  set FOUND_DLLS=!FOUND_DLLS!;%~1
) else (
  set MISSING_DLLS=!MISSING_DLLS!;%~1
)
goto :eof

:print_dll_summary
set SUMMARY_TITLE=%~1
set SUMMARY_ITEMS=%~2
echo   %SUMMARY_TITLE%
if not defined SUMMARY_ITEMS (
  echo     (none)
  goto :eof
)
set SUMMARY_ITEMS=%SUMMARY_ITEMS:~1%
for %%I in (%SUMMARY_ITEMS:;= %) do echo     %%I
goto :eof

:copy_candidate_dll
set COPY_TARGET_DIR=%~1
set DLL_NAME=%~2
set DLL_STATUS=MISSING
if exist "%COPY_TARGET_DIR%\%DLL_NAME%" (
  set DLL_STATUS=FOUND
  goto :eof
)
if defined VCToolsRedistDir (
  for /f "delims=" %%I in ('where /r "%VCToolsRedistDir%" "%DLL_NAME%" 2^>nul') do (
    copy /Y "%%~fI" "%COPY_TARGET_DIR%\%DLL_NAME%" >nul
    set DLL_STATUS=FOUND
    goto :eof
  )
)
if defined VCINSTALLDIR (
  for /f "delims=" %%I in ('where /r "%VCINSTALLDIR%" "%DLL_NAME%" 2^>nul') do (
    copy /Y "%%~fI" "%COPY_TARGET_DIR%\%DLL_NAME%" >nul
    set DLL_STATUS=FOUND
    goto :eof
  )
)
for /f "delims=" %%I in ('where "%DLL_NAME%" 2^>nul') do (
  copy /Y "%%~fI" "%COPY_TARGET_DIR%\%DLL_NAME%" >nul
  set DLL_STATUS=FOUND
  goto :eof
)
goto :eof
