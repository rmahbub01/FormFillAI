@echo off
REM ==============================================================================
REM FormFillAI - 1-Click Installer for Xournal++ (Windows)
REM ==============================================================================

echo =====================================================
echo      FormFillAI - Xournal++ Plugin Installer
echo =====================================================

REM 1. Target Directory
set "TARGET_DIR=%LOCALAPPDATA%\xournalpp\plugins\FormFillAI"
echo Target Directory: %TARGET_DIR%

if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

REM 2. Copy Plugin Files
set "SCRIPT_DIR=%~dp0"
echo Copying plugin files...

copy /Y "%SCRIPT_DIR%plugin.ini" "%TARGET_DIR%\"
copy /Y "%SCRIPT_DIR%main.lua" "%TARGET_DIR%\"
copy /Y "%SCRIPT_DIR%json.lua" "%TARGET_DIR%\"

if not exist "%TARGET_DIR%\backend" mkdir "%TARGET_DIR%\backend"
xcopy /E /I /Y "%SCRIPT_DIR%backend" "%TARGET_DIR%\backend\"

REM 3. Python Verification
echo Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python not found in PATH. Please install Python 3.9+ from python.org.
    pause
    exit /b 1
)

REM 4. Setup Requirements
echo Installing requirements (onnxruntime, pillow, numpy)...
python -m pip install --user onnxruntime pillow numpy requests >nul 2>&1

echo.
echo =====================================================
echo  FormFillAI has been successfully installed!
echo =====================================================
echo To use FormFillAI:
echo   1. Launch Xournal++.
echo   2. Open any PDF document.
echo   3. Look under Plugin menu: FormFillAI.
echo   4. Press Ctrl + Alt + F to detect form fields!
echo.
pause
