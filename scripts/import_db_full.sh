#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP_DIR="$PROJECT_DIR/dump"
CONFIG_DIR="$PROJECT_DIR/config"

if docker compose version >/dev/null 2>&1; then
	DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	DC=(docker-compose)
else
	echo "Error: neither 'docker compose' nor 'docker-compose' is available."
	exit 1
fi

IN_FILE="${1:-}"

if [[ -z "$IN_FILE" ]]; then
	if [[ -d "$DUMP_DIR" ]]; then
		IN_FILE="$(ls -1t "$DUMP_DIR"/odoo_backup_*.dump 2>/dev/null | head -n 1 || true)"
	fi
	if [[ -z "$IN_FILE" ]]; then
		echo "No backup provided and no dump found in $DUMP_DIR"
		exit 1
	fi
fi

if [[ ! -f "$IN_FILE" ]]; then
	echo "File not found: $IN_FILE"
	exit 1
fi

FS_FILE="${IN_FILE%.dump}_filestore.tar.gz"
CONFIG_FILE="${IN_FILE%.dump}_config.tar.gz"

cd "$PROJECT_DIR"

echo "========================================="
echo "  Odoo Full Database Import"
echo "========================================="
echo ""

echo "Input backup: $(basename "$IN_FILE")"
echo ""

echo "Stopping containers..."
"${DC[@]}" stop web odoo 2>/dev/null || true
"${DC[@]}" stop db 2>/dev/null || true

echo "Starting db container..."
"${DC[@]}" up -d db >/dev/null

echo "Waiting for PostgreSQL to be ready..."
until "${DC[@]}" exec -T db pg_isready -U odoo >/dev/null 2>&1; do
	sleep 1
done

echo "Recreating database..."
"${DC[@]}" exec -T db dropdb -U odoo --if-exists postgres 2>/dev/null || true
"${DC[@]}" exec -T db createdb -U odoo postgres

echo "Restoring database from: $IN_FILE"
"${DC[@]}" exec -T db pg_restore -U odoo -d postgres --no-owner --clean --disable-triggers < "$IN_FILE" 2>/dev/null || {
	echo "⚠ Database restore had issues but continuing..."
}
echo "✓ Database restored"

echo "Restoring filestore..."
if [[ -f "$FS_FILE" ]]; then
	echo "  From: $FS_FILE"
	"${DC[@]}" run --rm -v odoo-web-data:/data alpine sh -c \
		"mkdir -p /data/.local/share/Odoo/filestore/postgres && \
		 rm -rf /data/.local/share/Odoo/filestore/postgres/* && \
		 tar xzf - -C /data/.local/share/Odoo/filestore/postgres" < "$FS_FILE"
	echo "✓ Filestore restored"
else
	echo "⚠ No filestore backup found at $FS_FILE"
	echo "  Initializing empty filestore directories..."
	"${DC[@]}" run --rm -v odoo-web-data:/data alpine sh -c \
		"mkdir -p /data/.local/share/Odoo/filestore/postgres && \
		 chmod 755 /data/.local/share/Odoo/filestore /data/.local/share/Odoo/filestore/postgres"
	echo "✓ Empty filestore initialized"
fi

echo "Restoring config..."
if [[ -f "$CONFIG_FILE" ]]; then
	echo "  From: $CONFIG_FILE"
	mkdir -p "$CONFIG_DIR"
	tar xzf "$CONFIG_FILE" -C "$CONFIG_DIR" 2>/dev/null || {
		echo "⚠ Config extraction had issues"
	}
	echo "✓ Config restored"
else
	echo "⚠ No config backup found at $CONFIG_FILE (skipped)"
fi

echo ""
echo "Starting full stack..."
"${DC[@]}" up -d

echo "Waiting for services to be ready..."
sleep 5

echo ""
echo "========================================="
echo "  IMPORT COMPLETE"
echo "========================================="
echo ""
echo "Services starting, please wait for web service to initialize."
echo "Check logs with: docker compose logs -f web"
echo ""
