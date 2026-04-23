@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
set "DUMP_DIR=%PROJECT_DIR%\dump"
set "CONFIG_DIR=%PROJECT_DIR%\config"

docker compose version >nul 2>&1
if %errorlevel%==0 (
	set "DC=docker compose"
) else (
	docker-compose --version >nul 2>&1
	if %errorlevel%==0 (
		set "DC=docker-compose"
	) else (
		echo Error: neither "docker compose" nor "docker-compose" is available.
		exit /b 1
	)
)

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"

set "OUT_FILE=%~1"
if "%OUT_FILE%"=="" set "OUT_FILE=%DUMP_DIR%\odoo_backup_%TS%.dump"
set "FS_FILE=%OUT_FILE:.dump=_filestore.tar.gz%"
set "CONFIG_FILE=%OUT_FILE:.dump=_config.tar.gz%"
set "MANIFEST_FILE=%OUT_FILE:.dump=_manifest.txt%"

pushd "%PROJECT_DIR%" || exit /b 1
if not exist "%DUMP_DIR%" mkdir "%DUMP_DIR%"

echo =========================================
echo   Odoo Full Backup Export
echo =========================================
echo.

echo Starting db container...
%DC% up -d db >nul 2>&1 || goto :error

echo Waiting for PostgreSQL...
:wait_db
%DC% exec -T db pg_isready -U odoo >nul 2>&1
if %errorlevel% neq 0 (
	timeout /t 1 /nobreak >nul
	goto :wait_db
)

echo Exporting database to: %OUT_FILE%
%DC% exec -T db pg_dump -U odoo -d postgres -Fc > "%OUT_FILE%" || goto :error
for /f %%S in ('powershell -NoProfile -Command "(Get-Item \"'%OUT_FILE%'\").Length / 1MB | {[math]::Round($_, 2)}"') do set "DB_SIZE=%%S MB"
echo - Database exported (!DB_SIZE!)

echo Exporting filestore to: %FS_FILE%
%DC% run --rm -v odoo-web-data:/filestore alpine tar czf - -C /filestore . > "%FS_FILE%" 2>nul
if %errorlevel% neq 0 (
	echo - Filestore unavailable, creating empty archive
	tar czf "%FS_FILE%" --files-from=nul
)
for /f %%S in ('powershell -NoProfile -Command "(Get-Item \"'%FS_FILE%'\").Length / 1MB | {[math]::Round($_, 2)}"') do set "FS_SIZE=%%S MB"
echo - Filestore exported (!FS_SIZE!)

echo Exporting config to: %CONFIG_FILE%
if exist "%CONFIG_DIR%" (
	tar czf "%CONFIG_FILE%" -C "%CONFIG_DIR%" . >nul 2>&1
	if %errorlevel% equ 0 (
		for /f %%S in ('powershell -NoProfile -Command "(Get-Item \"'%CONFIG_FILE%'\").Length / 1MB | {[math]::Round($_, 2)}"') do set "CFG_SIZE=%%S MB"
		echo - Config exported (!CFG_SIZE!)
	) else (
		echo - Config export failed, creating empty archive
		tar czf "%CONFIG_FILE%" --files-from=nul
	)
) else (
	tar czf "%CONFIG_FILE%" --files-from=nul
	echo - Config directory not found, created empty archive
)

echo Creating manifest...
(
	echo ODOO BACKUP MANIFEST
	echo Generated: %date% %time%
	echo Version: 1.0
	echo.
	echo Files:
	echo   * Database:  %OUT_FILE%
	echo   * Filestore: %FS_FILE%
	echo   * Config:    %CONFIG_FILE%
	echo.
	echo To restore, use: .\scripts\import_db.cmd %OUT_FILE%
) > "%MANIFEST_FILE%"
echo - Manifest created

echo.
echo =========================================
echo   BACKUP COMPLETE
echo =========================================
echo.
echo Location: %DUMP_DIR%\
echo   * %OUT_FILE%
echo   * %FS_FILE%
echo   * %CONFIG_FILE%
echo   * %MANIFEST_FILE%
echo.

popd
exit /b 0

:error
echo Export failed.
popd
exit /b 1
