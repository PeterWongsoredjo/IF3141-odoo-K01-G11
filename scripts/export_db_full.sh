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

cd "$PROJECT_DIR"
mkdir -p "$DUMP_DIR"

TS=$(date +%Y%m%d_%H%M%S)
DB_FILE="${1:-$DUMP_DIR/odoo_backup_${TS}.dump}"
FS_FILE="${DB_FILE%.dump}_filestore.tar.gz"
CONFIG_FILE="${DB_FILE%.dump}_config.tar.gz"
MANIFEST_FILE="${DB_FILE%.dump}_manifest.txt"

echo "========================================="
echo "  Odoo Full Backup Export"
echo "========================================="
echo ""

echo "Starting db container..."
"${DC[@]}" up -d db >/dev/null

echo "Waiting for PostgreSQL..."
until "${DC[@]}" exec -T db pg_isready -U odoo >/dev/null 2>&1; do
	sleep 1
done

echo "Exporting database to: $DB_FILE"
"${DC[@]}" exec -T db pg_dump -U odoo -d postgres -Fc > "$DB_FILE"
DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
echo "✓ Database exported ($DB_SIZE)"

echo "Exporting filestore to: $FS_FILE"
"${DC[@]}" run --rm -v odoo-web-data:/filestore alpine tar czf - -C /filestore . 2>/dev/null > "$FS_FILE" || {
	echo "⚠ Filestore unavailable, creating empty archive"
	tar czf "$FS_FILE" --files-from=/dev/null
}
FS_SIZE=$(du -h "$FS_FILE" | cut -f1)
echo "✓ Filestore exported ($FS_SIZE)"

echo "Exporting config to: $CONFIG_FILE"
if [[ -d "$CONFIG_DIR" ]]; then
	tar czf "$CONFIG_FILE" -C "$CONFIG_DIR" . 2>/dev/null || {
		echo "⚠ Config export failed, creating empty archive"
		tar czf "$CONFIG_FILE" --files-from=/dev/null
	}
	CONFIG_SIZE=$(du -h "$CONFIG_FILE" | cut -f1)
	echo "✓ Config exported ($CONFIG_SIZE)"
else
	tar czf "$CONFIG_FILE" --files-from=/dev/null
	echo "⚠ Config directory not found, created empty archive"
fi

echo "Creating manifest..."
cat > "$MANIFEST_FILE" << EOF
ODOO BACKUP MANIFEST
Generated: $(date)
Version: 1.0

Files:
  • Database:  $(basename "$DB_FILE") ($DB_SIZE)
  • Filestore: $(basename "$FS_FILE") ($FS_SIZE)
  • Config:    $(basename "$CONFIG_FILE") ($(du -h "$CONFIG_FILE" | cut -f1))

To restore, use: ./scripts/import_db_full.sh $(basename "$DB_FILE")
EOF
echo "✓ Manifest created"

echo ""
echo "========================================="
echo "  BACKUP COMPLETE"
echo "========================================="
echo ""
echo "Location: $DUMP_DIR/"
echo "  • $(basename "$DB_FILE")"
echo "  • $(basename "$FS_FILE")"
echo "  • $(basename "$CONFIG_FILE")"
echo "  • $(basename "$MANIFEST_FILE")"
echo ""
