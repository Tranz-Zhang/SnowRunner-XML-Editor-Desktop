@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "SNOWPAKTOOL=%~1"
if "%SNOWPAKTOOL%"=="" set "SNOWPAKTOOL=snowpaktool"
set "SEVENZIP=%~2"
if "%SEVENZIP%"=="" set "SEVENZIP=7z"

set "SOURCE_PAK=%SCRIPT_DIR%initial.pak"
set "WORK_DIR=%SCRIPT_DIR%snowpaktool-roundtrip"
set "BASIC_UNPACK_DIR=%WORK_DIR%\basic\initial-pak"
set "BASIC_VERIFY_DIR=%WORK_DIR%\basic\verify-initial-pak"
set "BASIC_REPACKED_PAK=%WORK_DIR%\basic\initial.basic-repacked.pak"
set "MIXED_UNPACK_DIR=%WORK_DIR%\mixed-cache-block\initial-pak"
set "MIXED_VERIFY_DIR=%WORK_DIR%\mixed-cache-block\verify-initial-pak"
set "MIXED_REPACKED_PAK=%WORK_DIR%\mixed-cache-block\initial.mixed-cache-block.pak"

if not exist "%SOURCE_PAK%" (
  echo Missing source pak: "%SOURCE_PAK%"
  echo Put initial.pak in the same folder as this script.
  exit /b 1
)

echo Usage: %~nx0 [snowpaktool.exe] [7z.exe]
echo.
echo SnowPakTool: "%SNOWPAKTOOL%"
echo 7-Zip:       "%SEVENZIP%"
echo Source pak:  "%SOURCE_PAK%"
echo Work dir:    "%WORK_DIR%"
echo.

if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"

echo === Candidate A: basic pak pack, no cache_block expansion ===
mkdir "%BASIC_UNPACK_DIR%" || exit /b 1
mkdir "%BASIC_VERIFY_DIR%" || exit /b 1

echo [A1/3] Unpack initial.pak with 7-Zip
call :Run "%SEVENZIP%" x -y -o"%BASIC_UNPACK_DIR%" "%SOURCE_PAK%"
if errorlevel 1 exit /b 1

echo [A2/3] Repack unpacked folder
call :Run "%SNOWPAKTOOL%" pak pack "%BASIC_UNPACK_DIR%" "%BASIC_REPACKED_PAK%"
if errorlevel 1 exit /b 1

if not exist "%BASIC_REPACKED_PAK%" (
  echo Repack command finished but output was not created: "%BASIC_REPACKED_PAK%"
  exit /b 1
)

echo [A3/3] Verify basic repacked pak can be unpacked with 7-Zip
call :Run "%SEVENZIP%" x -y -o"%BASIC_VERIFY_DIR%" "%BASIC_REPACKED_PAK%"
if errorlevel 1 exit /b 1

echo.
echo === Candidate B: mixed-cache-block pak pack ===
mkdir "%MIXED_UNPACK_DIR%" || exit /b 1
mkdir "%MIXED_VERIFY_DIR%" || exit /b 1

echo [B1/5] Unpack initial.pak with 7-Zip
call :Run "%SEVENZIP%" x -y -o"%MIXED_UNPACK_DIR%" "%SOURCE_PAK%"
if errorlevel 1 exit /b 1

if exist "%MIXED_UNPACK_DIR%\initial.cache_block" (
  echo [B2/5] Unpack initial.cache_block
  call :Run "%SNOWPAKTOOL%" cb unpack --allow-mixing "%MIXED_UNPACK_DIR%\initial.cache_block" "%MIXED_UNPACK_DIR%"
  if errorlevel 1 exit /b 1

  echo [B3/5] Remove unpacked cache_block placeholder
  del /f /q "%MIXED_UNPACK_DIR%\initial.cache_block"
  if errorlevel 1 exit /b 1
) else (
  echo [B2/5] initial.cache_block not found; skipping cache_block unpack.
  echo [B3/5] Nothing to remove.
)

echo [B4/5] Repack unpacked folder
call :Run "%SNOWPAKTOOL%" pak pack --mixed-cache-block "%MIXED_UNPACK_DIR%" "%MIXED_REPACKED_PAK%"
if errorlevel 1 exit /b 1

if not exist "%MIXED_REPACKED_PAK%" (
  echo Repack command finished but output was not created: "%MIXED_REPACKED_PAK%"
  exit /b 1
)

echo [B5/5] Verify mixed-cache-block repacked pak can be unpacked with 7-Zip
call :Run "%SEVENZIP%" x -y -o"%MIXED_VERIFY_DIR%" "%MIXED_REPACKED_PAK%"
if errorlevel 1 exit /b 1

echo.
echo SnowPakTool test candidates created.
for %%F in ("%SOURCE_PAK%") do set "SOURCE_SIZE=%%~zF"
for %%F in ("%BASIC_REPACKED_PAK%") do set "BASIC_SIZE=%%~zF"
for %%F in ("%MIXED_REPACKED_PAK%") do set "MIXED_SIZE=%%~zF"
echo Source:            "%SOURCE_PAK%" ^(%SOURCE_SIZE% bytes^)
echo Candidate A basic: "%BASIC_REPACKED_PAK%" ^(%BASIC_SIZE% bytes^)
echo Candidate B mixed: "%MIXED_REPACKED_PAK%" ^(%MIXED_SIZE% bytes^)
echo.
echo Test Candidate A in game first. If A launches but B crashes, the problem is cache_block handling.
echo Replace the game file manually only after backing up the original initial.pak.
exit /b 0

:Run
%*
if not "%ERRORLEVEL%"=="0" (
  echo Command failed with exit code %ERRORLEVEL%: %*
  exit /b 1
)
exit /b 0
