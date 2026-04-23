@echo off
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

echo =========================================
echo   Odoo Database Cleanup
echo =========================================
echo.

echo Ensuring db container is running...
%DC% up -d db >nul 2>&1 || goto :error

echo Waiting for PostgreSQL...
:wait_db
%DC% exec -T db pg_isready -U odoo >nul 2>&1
if %errorlevel% neq 0 (
	timeout /t 1 /nobreak >nul
	goto :wait_db
)

echo Cleaning up orphaned attachments...
%DC% exec -T db psql -U odoo -d postgres << EOF
-- Remove attachment records with file references
DELETE FROM ir_attachment 
WHERE type = 'binary' AND store_fname IS NOT NULL;

-- Reset remaining attachments to database storage
UPDATE ir_attachment 
SET type = 'db' 
WHERE store_fname IS NOT NULL;

-- Clear any dangling references
DELETE FROM ir_attachment 
WHERE res_model IS NULL OR res_id IS NULL;

COMMIT;
EOF

echo - Database cleanup completed

echo.
echo =========================================
echo   CLEANUP COMPLETE
echo =========================================
echo.
echo Restart the web container with:
echo   docker compose restart web
echo.

popd
exit /b 0

:error
echo Cleanup failed.
popd
exit /b 1
