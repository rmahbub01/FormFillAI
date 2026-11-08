@echo off
REM ==============================================================================
REM FormFillAI - 1-Click Complete Uninstaller for Xournal++ (Windows)
REM ==============================================================================

echo =====================================================
echo    FormFillAI - 1-Click Complete Uninstaller
echo =====================================================

set "SCRIPT_DIR=%~dp0"

REM Try python uninstaller first
python --version >nul 2>&1
if %errorlevel% equ 0 (
    python "%SCRIPT_DIR%install.py" --uninstall
    goto :end
)

py --version >nul 2>&1
if %errorlevel% equ 0 (
    py "%SCRIPT_DIR%install.py" --uninstall
    goto :end
)

REM Fallback manual cleanup
echo Removing plugin folders...
if exist "%LOCALAPPDATA%\xournalpp\plugins\FormFillAI" (
    rmdir /S /Q "%LOCALAPPDATA%\xournalpp\plugins\FormFillAI"
)
if exist "%APPDATA%\xournalpp\plugins\FormFillAI" (
    rmdir /S /Q "%APPDATA%\xournalpp\plugins\FormFillAI"
)

echo Cleaning cache...
if exist "%USERPROFILE%\.cache\formfillai" (
    rmdir /S /Q "%USERPROFILE%\.cache\formfillai"
)

echo.
echo =====================================================
echo  FormFillAI has been completely uninstalled.
echo =====================================================
echo.
pause

:end
