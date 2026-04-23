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
echo "  Odoo Database Cleanup"
echo "========================================="
echo ""

echo "Ensuring db container is running..."
"${DC[@]}" up -d db >/dev/null

echo "Waiting for PostgreSQL..."
until "${DC[@]}" exec -T db pg_isready -U odoo >/dev/null 2>&1; do
	sleep 1
done

echo "Cleaning up orphaned attachments..."
"${DC[@]}" exec -T db psql -U odoo -d postgres << 'SQL'
-- Remove attachment records that reference non-existent files
DELETE FROM ir_attachment 
WHERE type = 'binary' 
  AND store_fname IS NOT NULL
  AND store_fname NOT IN (
    SELECT DISTINCT store_fname 
    FROM ir_attachment 
    WHERE store_fname IS NOT NULL 
    LIMIT 0
  );

-- Reset attachment type to 'db' for any remaining records
UPDATE ir_attachment 
SET type = 'db' 
WHERE type != 'db' 
  AND store_fname IS NULL;

-- Commit changes
COMMIT;
SQL

echo "✓ Database cleanup completed"

echo ""
echo "========================================="
echo "  CLEANUP COMPLETE"
echo "========================================="
echo ""
echo "Restart the web container with:"
echo "  docker compose restart web"
echo ""
