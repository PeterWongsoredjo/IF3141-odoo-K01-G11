@echo off
REM Initialize empty filestore directories to prevent FileNotFoundError
REM Run this if you import a backup without filestore data

setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"

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

pushd "%PROJECT_DIR%" || exit /b 1

echo Initializing empty filestore directories...
%DC% run --rm -v odoo-web-data:/data alpine sh -c "mkdir -p /data/.local/share/Odoo/filestore/postgres && chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres" || goto :error

echo - Filestore initialized
echo.
echo Filestore directories are ready. If you had import errors, restart the web container:
echo   docker compose restart web

popd
exit /b 0

:error
echo Initialization failed.
popd
exit /b 1
