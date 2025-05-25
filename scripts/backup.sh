#!/bin/bash
set -euo pipefail

# Logging functions
log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }
log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"; }

# Check required commands
for cmd in restic pg_dump gzip; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "$cmd could not be found"

    exit 1
  fi
done

BACKUP_DIR=${BACKUP_DIR:-/data}
BACKUP_EXTENSION=${BACKUP_EXTENSION:-sql.gz}
VERIFY_BACKUP=${VERIFY_BACKUP:-true}

function initialize() {
  log_info "Initializing restic repository..."

  if restic snapshots &> /dev/null; then
    log_info "Restic repository already exists at ${RESTIC_REPOSITORY}"
  else
    log_info "No restic repository found at ${RESTIC_REPOSITORY}. Initializing..."
    restic init
    log_success "Repository initialized successfully"
  fi
}

function backup() {
  log_info "Starting backup..."

  if restic backup "$BACKUP_DIR" $RESTIC_BACKUP_EXTRA_ARGS; then
    log_success "Backup completed successfully"
  else
    log_error "Backup failed"

    exit 1
  fi

  if [ "$VERIFY_BACKUP" = "true" ]; then
    log_info "Verifying backup..."

    if ! restic check --read-data-subset=10%; then
      log_error "Backup verification failed"

      exit 1
    fi

    log_success "Backup verification completed"
  fi
}

function dump_database() {
  export PGPASSWORD=$DB_PASS

  local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
  local filename="${DB_NAME}_${timestamp}.${BACKUP_EXTENSION}"
  local temp_file=$(mktemp)

  log_info "Dumping database ${DB_NAME}..."

  # First dump to a temporary file
  if ! pg_dump \
      --host "$DB_HOST" \
      --port "$DB_PORT" \
      --username "$DB_USER" \
      --large-objects \
      "$DB_NAME" > "$temp_file"; then
      log_error "Database dump failed"

      rm -f "$temp_file"

      exit 1
  fi

  # Then compress it
  if ! gzip -c "$temp_file" > "${BACKUP_DIR}/${filename}"; then
    log_error "Compression failed"
    rm -f "$temp_file"
    exit 1
  fi

  rm -f "$temp_file"
  log_success "Database dump completed: ${filename}"
}

function cleanup() {
  log_info "Cleaning up database dumps..."
  rm -f $BACKUP_DIR/*.${BACKUP_EXTENSION}

  log_info "Running retention policy..."
  if ! restic forget $RESTIC_FORGET_ARGS; then
    log_error "Failed to prune old backups"

    exit 1
  fi

  log_success "Cleanup completed"
}


function main() {
  log_info "Starting backup process..."

  initialize
  dump_database
  backup
  cleanup

  log_success "Backup process completed successfully"
}

main