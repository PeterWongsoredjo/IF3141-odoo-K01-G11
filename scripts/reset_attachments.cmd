@echo off
setlocal enabledelayedexpansion

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

echo =========================================
echo   Odoo Full Database Reset ^(Nuclear Option^)
echo =========================================
echo.
echo WARNING: This will:
echo   * Delete ALL attachment files
echo   * Reset all attachments to database storage
echo   * Clear filestore directory
echo.
set /p REPLY="Continue? (y/N) "
if /i not "%REPLY%"=="y" (
	echo Cancelled.
	popd
	exit /b 0
)

echo.
echo Starting services...
%DC% up -d db >nul 2>&1 || goto :error

echo Waiting for PostgreSQL...
:wait_db
%DC% exec -T db pg_isready -U odoo >nul 2>&1
if %errorlevel% neq 0 (
	timeout /t 1 /nobreak >nul
	goto :wait_db
)

echo Cleaning database attachments...
%DC% exec -T db psql -U odoo -d postgres << EOF
-- Remove ALL attachment records
DELETE FROM ir_attachment WHERE type = 'binary';

-- Store attachments in database
UPDATE ir_attachment SET type = 'db';

-- Commit
COMMIT;
EOF

echo - Database cleaned

echo Clearing filestore directory...
%DC% run --rm -v odoo-web-data:/data alpine sh -c "rm -rf /data/.local/share/Odoo/filestore/postgres/* && mkdir -p /data/.local/share/Odoo/filestore/postgres && chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres"

echo - Filestore cleared and reinitialized

echo.
echo =========================================
echo   RESET COMPLETE
echo =========================================
echo.
echo Now restart the web container:
echo   docker compose restart web
echo.
echo Open http://localhost:8069 to test
echo.

popd
exit /b 0

:error
echo Reset failed.
popd
exit /b 1
