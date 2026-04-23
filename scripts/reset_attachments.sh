#!/usr/bin/env bash
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

echo "========================================="
echo "  Odoo Full Database Reset (Nuclear Option)"
echo "========================================="
echo ""
echo "⚠️  WARNING: This will:"
echo "  • Delete ALL attachment files"
echo "  • Reset all attachments to database storage"
echo "  • Clear filestore directory"
echo ""
read -p "Continue? (y/N) " -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Cancelled."
	exit 0
fi

echo ""
echo "Starting services..."
"${DC[@]}" up -d db >/dev/null

echo "Waiting for PostgreSQL..."
until "${DC[@]}" exec -T db pg_isready -U odoo >/dev/null 2>&1; do
	sleep 1
done

echo "Cleaning database attachments..."
"${DC[@]}" exec -T db psql -U odoo -d postgres << 'SQL'
-- Remove ALL attachment records (they reference missing files)
DELETE FROM ir_attachment WHERE type = 'binary';

-- Store all attachments in database
UPDATE ir_attachment SET type = 'db';

-- Commit
COMMIT;
SQL

echo "✓ Database cleaned"

echo "Clearing filestore directory..."
"${DC[@]}" run --rm -v odoo-web-data:/data alpine sh -c \
	"rm -rf /data/.local/share/Odoo/filestore/postgres/* && \
	 mkdir -p /data/.local/share/Odoo/filestore/postgres && \
	 chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres"

echo "✓ Filestore cleared and reinitialized"

echo ""
echo "========================================="
echo "  RESET COMPLETE"
echo "========================================="
echo ""
echo "Now restart the web container:"
echo "  docker compose restart web"
echo ""
echo "Open http://localhost:8069 to test"
echo ""
