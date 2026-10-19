#!/bin/bash

set -e

LOCK_DIR="${TMPDIR:-/tmp}/media-move.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Move already in progress. Ignoring this request."
    exit 0
fi

trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

MEDIA_DIR="/media"
MEDIA_MOVIES_DIR="$MEDIA_DIR/Movies"
MEDIA_SHOWS_DIR="$MEDIA_DIR/Shows"
MEDIA_ANIME_DIR="$MEDIA_DIR/Animes"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

UPLOADS_DIR="$PROJECT_DIR/output"
LOG_FILE="$PROJECT_DIR/downloader.log"

if [ ! -d "$UPLOADS_DIR" ]; then
    echo "Error: Uploads directory does not exist: $UPLOADS_DIR"
    exit 1
fi

UPLOADS_MOVIES_DIR="$UPLOADS_DIR/movies"
UPLOADS_SHOWS_DIR="$UPLOADS_DIR/shows"
UPLOADS_ANIME_DIR="$UPLOADS_DIR/anime"

for DIR in \
    "$MEDIA_MOVIES_DIR" \
    "$MEDIA_SHOWS_DIR" \
    "$MEDIA_ANIME_DIR" \
    "$UPLOADS_MOVIES_DIR" \
    "$UPLOADS_SHOWS_DIR" \
    "$UPLOADS_ANIME_DIR"
do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
        echo "Created: $DIR"
    fi
done

log_message() {
    local msg="$1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_message "=== Moving started: Transferring media files to /media ==="

# Rsync with --progress piped to console and downloader.log
rsync -a --progress --remove-source-files "$UPLOADS_MOVIES_DIR/" "$MEDIA_MOVIES_DIR/" 2>&1 | tee -a "$LOG_FILE"
rsync -a --progress --remove-source-files "$UPLOADS_SHOWS_DIR/" "$MEDIA_SHOWS_DIR/" 2>&1 | tee -a "$LOG_FILE"
rsync -a --progress --remove-source-files "$UPLOADS_ANIME_DIR/" "$MEDIA_ANIME_DIR/" 2>&1 | tee -a "$LOG_FILE"

find "$UPLOADS_MOVIES_DIR" -mindepth 1 -depth -type d -empty -delete
find "$UPLOADS_SHOWS_DIR" -mindepth 1 -depth -type d -empty -delete
find "$UPLOADS_ANIME_DIR" -mindepth 1 -depth -type d -empty -delete

log_message "=== Media transfer completed successfully ==="