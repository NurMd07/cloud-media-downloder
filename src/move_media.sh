#!/usr/bin/env bash

set -e

LOCK_DIR="${TMPDIR:-/tmp}/media-move.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Move already in progress. Ignoring this request."
    exit 0
fi

trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/downloader.log"

show_help() {
    cat << 'EOF'
Usage: ./move_media.sh [OPTIONS]

Moves organized media from the output directory to the target media library.

Options:
  -o, --output <path>       Source output directory (Default: ../output)
  -m, --media-dir <path>    Destination base media directory (Default: /media)
  --movies-dir <name>       Movies folder name inside media-dir (Default: Movies)
  --shows-dir <name>        Shows folder name inside media-dir (Default: Shows)
  --anime-dir <name>        Anime folder name inside media-dir (Default: Animes)
  -i, --interactive         Prompt interactively for directory paths/names
  -h, --help                Show this help message and exit
EOF
}

# 1. Read from environment variables if present, otherwise empty (defaults applied below)
CUSTOM_OUTPUT="${output:-${OUTPUT_DIR:-}}"
CUSTOM_MEDIA_DIR="${MEDIA_DIR:-}"
MOVIES_FOLDER_NAME="${MOVIES_DIR_NAME:-${MEDIA_MOVIES_NAME:-}}"
SHOWS_FOLDER_NAME="${SHOWS_DIR_NAME:-${MEDIA_SHOWS_NAME:-}}"
ANIME_FOLDER_NAME="${ANIME_DIR_NAME:-${MEDIA_ANIME_NAME:-}}"
INTERACTIVE=0

# 2. Parse CLI Arguments (overrides env vars if passed)
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--interactive)
            INTERACTIVE=1
            shift 1
            ;;
        -o|--output)
            CUSTOM_OUTPUT="${2:-}"
            shift 2
            ;;
        -m|--media-dir)
            CUSTOM_MEDIA_DIR="${2:-}"
            shift 2
            ;;
        --movies-dir)
            MOVIES_FOLDER_NAME="${2:-}"
            shift 2
            ;;
        --shows-dir)
            SHOWS_FOLDER_NAME="${2:-}"
            shift 2
            ;;
        --anime-dir)
            ANIME_FOLDER_NAME="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# 3. Interactive Prompts (if run with -i / --interactive)
if [[ $INTERACTIVE -eq 1 ]]; then
    read -r -e -p "Source output folder path [default: $PROJECT_DIR/output]: " INPUT_OUTPUT
    CUSTOM_OUTPUT="${INPUT_OUTPUT:-$CUSTOM_OUTPUT}"

    read -r -e -p "Base destination media path [default: /media]: " INPUT_MEDIA
    CUSTOM_MEDIA_DIR="${INPUT_MEDIA:-$CUSTOM_MEDIA_DIR}"

    read -r -p "Movies folder name inside media dir [default: Movies]: " INPUT_MOVIES
    MOVIES_FOLDER_NAME="${INPUT_MOVIES:-$MOVIES_FOLDER_NAME}"

    read -r -p "Shows folder name inside media dir [default: Shows]: " INPUT_SHOWS
    SHOWS_FOLDER_NAME="${INPUT_SHOWS:-$SHOWS_FOLDER_NAME}"

    read -r -p "Anime folder name inside media dir [default: Animes]: " INPUT_ANIME
    ANIME_FOLDER_NAME="${INPUT_ANIME:-$ANIME_FOLDER_NAME}"
fi

# 4. Apply Defaults if still empty
UPLOADS_DIR="${CUSTOM_OUTPUT:-$PROJECT_DIR/output}"
MEDIA_DIR="${CUSTOM_MEDIA_DIR:-/media}"
MOVIES_SUBDIR="${MOVIES_FOLDER_NAME:-Movies}"
SHOWS_SUBDIR="${SHOWS_FOLDER_NAME:-Shows}"
ANIME_SUBDIR="${ANIME_FOLDER_NAME:-Animes}"

MEDIA_MOVIES_DIR="$MEDIA_DIR/$MOVIES_SUBDIR"
MEDIA_SHOWS_DIR="$MEDIA_DIR/$SHOWS_SUBDIR"
MEDIA_ANIME_DIR="$MEDIA_DIR/$ANIME_SUBDIR"

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

log_message "=== Moving started: Transferring media files from $UPLOADS_DIR to $MEDIA_DIR ==="

# Rsync with --progress piped to console and downloader.log
rsync -a --progress --remove-source-files "$UPLOADS_MOVIES_DIR/" "$MEDIA_MOVIES_DIR/" 2>&1 | tee -a "$LOG_FILE"
rsync -a --progress --remove-source-files "$UPLOADS_SHOWS_DIR/" "$MEDIA_SHOWS_DIR/" 2>&1 | tee -a "$LOG_FILE"
rsync -a --progress --remove-source-files "$UPLOADS_ANIME_DIR/" "$MEDIA_ANIME_DIR/" 2>&1 | tee -a "$LOG_FILE"

find "$UPLOADS_MOVIES_DIR" -mindepth 1 -depth -type d -empty -delete
find "$UPLOADS_SHOWS_DIR" -mindepth 1 -depth -type d -empty -delete
find "$UPLOADS_ANIME_DIR" -mindepth 1 -depth -type d -empty -delete

log_message "=== Media transfer completed successfully ==="