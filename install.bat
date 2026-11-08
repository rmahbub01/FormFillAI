@echo off
REM ==============================================================================
REM FormFillAI - 1-Click Installer for Xournal++ (Windows)
REM ==============================================================================

echo =====================================================
echo      FormFillAI - Xournal++ Plugin Installer
echo =====================================================

set "SCRIPT_DIR=%~dp0"

REM Try python installer first
python --version >nul 2>&1
if %errorlevel% equ 0 (
    python "%SCRIPT_DIR%install.py" %*
    goto :end
)

py --version >nul 2>&1
if %errorlevel% equ 0 (
    py "%SCRIPT_DIR%install.py" %*
    goto :end
)

REM Fallback manual copy if python is not in PATH
set "TARGET_DIR=%LOCALAPPDATA%\xournalpp\plugins\FormFillAI"
echo Target Directory: %TARGET_DIR%

if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo Copying plugin files...
copy /Y "%SCRIPT_DIR%plugin.ini" "%TARGET_DIR%\" >nul
copy /Y "%SCRIPT_DIR%main.lua" "%TARGET_DIR%\" >nul
copy /Y "%SCRIPT_DIR%json.lua" "%TARGET_DIR%\" >nul
copy /Y "%SCRIPT_DIR%config.json" "%TARGET_DIR%\" >nul

if not exist "%TARGET_DIR%\backend" mkdir "%TARGET_DIR%\backend"
xcopy /E /I /Y "%SCRIPT_DIR%backend" "%TARGET_DIR%\backend\" >nul

echo.
echo =====================================================
echo  FormFillAI has been successfully installed!
echo =====================================================
echo To use FormFillAI:
echo   1. Launch Xournal++.
echo   2. Open any PDF document.
echo   3. Look under Plugin menu: FormFillAI.
echo   4. Press Ctrl + Shift + D to detect form fields!
echo.
pause

:end
