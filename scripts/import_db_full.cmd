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

set "IN_FILE=%~1"
if "%IN_FILE%"=="" (
	for /f "delims=" %%F in ('dir /b /a-d /o-n "%DUMP_DIR%\odoo_backup_*.dump" 2^>nul') do (
		set "IN_FILE=%DUMP_DIR%\%%F"
		goto :found_latest
	)
	echo No backup provided and no dump found in %DUMP_DIR%
	exit /b 1
)

:found_latest

if not exist "%IN_FILE%" (
	echo File not found: %IN_FILE%
	exit /b 1
)

set "FS_FILE=%IN_FILE:.dump=_filestore.tar.gz%"
set "CONFIG_FILE=%IN_FILE:.dump=_config.tar.gz%"

pushd "%PROJECT_DIR%" || exit /b 1

echo =========================================
echo   Odoo Full Database Import
echo =========================================
echo.

echo Input backup: %IN_FILE%
echo.

echo Stopping containers...
%DC% stop web >nul 2>&1
%DC% stop odoo >nul 2>&1
%DC% stop db >nul 2>&1

echo Starting db container...
%DC% up -d db >nul 2>&1 || goto :error

echo Waiting for PostgreSQL to be ready...
:wait_db
%DC% exec -T db pg_isready -U odoo >nul 2>&1
if %errorlevel% neq 0 (
	timeout /t 1 /nobreak >nul
	goto :wait_db
)

echo Recreating database...
%DC% exec -T db dropdb -U odoo --if-exists postgres >nul 2>&1
%DC% exec -T db createdb -U odoo postgres || goto :error

echo Restoring database from: %IN_FILE%
%DC% exec -T db pg_restore -U odoo -d postgres --no-owner --clean --disable-triggers < "%IN_FILE%" 2>nul
echo - Database restored

echo Restoring filestore...
if exist "%FS_FILE%" (
	echo   From: %FS_FILE%
	%DC% run --rm -v odoo-web-data:/data alpine sh -c "mkdir -p /data/.local/share/Odoo/filestore/postgres && rm -rf /data/.local/share/Odoo/filestore/postgres/* && tar xzf - -C /data/.local/share/Odoo/filestore/postgres" < "%FS_FILE%" || goto :error
	echo - Filestore restored
) else (
	echo - No filestore backup found at %FS_FILE%
	echo   Initializing empty filestore directories...
	%DC% run --rm -v odoo-web-data:/data alpine sh -c "mkdir -p /data/.local/share/Odoo/filestore/postgres && chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres" || goto :error
	echo - Empty filestore initialized
)

echo Restoring config...
if exist "%CONFIG_FILE%" (
	echo   From: %CONFIG_FILE%
	if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
	tar xzf "%CONFIG_FILE%" -C "%CONFIG_DIR%" 2>nul
	if %errorlevel% neq 0 (
		echo - Config extraction had issues but continuing...
	)
	echo - Config restored
) else (
	echo - No config backup found (skipped)
)

echo.
echo Starting full stack...
%DC% up -d || goto :error

echo Waiting for services to start...
timeout /t 5 /nobreak >nul

echo.
echo =========================================
echo   IMPORT COMPLETE
echo =========================================
echo.
echo Services starting, please wait for web service to initialize.
echo Check logs with: docker compose logs -f web
echo.

popd
exit /b 0

:error
echo Import failed.
popd
exit /b 1
