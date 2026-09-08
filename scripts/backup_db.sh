#!/usr/bin/env bash
set -euo pipefail

# Determine repository root relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Define paths
DB_FILE="${BASE_DIR}/storage/database/language_database.db"
BACKUP_DIR="${BASE_DIR}/storage/backups"
TIMESTAMP="$(date +"%Y-%m-%d_%H%M%S")"
TARGET_RAW="${BACKUP_DIR}/language_database_${TIMESTAMP}.db"
TARGET_GZ="${TARGET_RAW}.gz"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Verify the live database file exists
if [ ! -f "${DB_FILE}" ]; then
  echo "Error: Database file not found at ${DB_FILE}" >&2
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting safe SQLite hot backup..."

# 1. Safe atomic snapshot that safely absorbs WAL pages
sqlite3 "${DB_FILE}" ".backup '${TARGET_RAW}'"

# 2. Fast, high-ratio compression
gzip -f "${TARGET_RAW}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup created: ${TARGET_GZ}"

# 3. Retain last 14 days of backups (prune older)
find "${BACKUP_DIR}" -name "language_database_*.db.gz" -type f -mtime +14 -delete

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Old backups pruned (>14 days)."