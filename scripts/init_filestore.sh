#!/usr/bin/env bash
# Initialize empty filestore directories to prevent FileNotFoundError
# Run this if you import a backup without filestore data

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if docker compose version >/dev/null 2>&1; then
	DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	DC=(docker-compose)
else
	echo "Error: neither 'docker compose' nor 'docker-compose' is available."
	exit 1
fi

cd "$PROJECT_DIR"

echo "Initializing empty filestore directories..."
"${DC[@]}" run --rm -v odoo-web-data:/data alpine sh -c \
	"mkdir -p /data/.local/share/Odoo/filestore/postgres && \
	 chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres"

echo "✓ Filestore initialized"
echo ""
echo "Filestore directories are ready. If you had import errors, restart the web container:"
echo "  docker compose restart web"
