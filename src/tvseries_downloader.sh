#!/usr/bin/env bash

# -E ensures ERR traps are inherited by functions and subshells
set -Eeuo pipefail

# 1. Early CLI Argument Parsing
MEDIA_TYPE=""
MEDIA_NAME=""
GDRIVE_LINK=""
LOCAL_FILE=""
SKIP_DL="false"
DB_ID=""
INTERACTIVE=0
SOURCE_PATH=""
FINAL_OUTPUT_PATH=""
COMPLETED="false"
ERROR_HANDLED="false"

# Pre-generate a fallback ID immediately so even CLI argument errors have an ID
FALLBACK_ID="noid_$$_$(date +%s)"

if [[ $# -eq 0 ]]; then
    INTERACTIVE=1
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|-type|--type) MEDIA_TYPE="${2:-}"; shift 2 ;;
            -n|-name|--name) MEDIA_NAME="${2:-}"; shift 2 ;;
            -l|-link|--link) GDRIVE_LINK="${2:-}"; shift 2 ;;
            -f|-file|--file) LOCAL_FILE="${2:-}"; shift 2 ;;
            -s|-skip|--skip) SKIP_DL="true"; shift 1 ;;
            -i|-id|--id) DB_ID="${2:-}"; shift 2 ;;
            *) 
                UNKNOWN_ARG="$1"
                DB_ID="${DB_ID:-$FALLBACK_ID}"
                echo "{\"id\": \"${DB_ID//\"/\\\"}\", \"status\": \"error\", \"type\": null, \"message\": \"Unknown parameter $UNKNOWN_ARG\", \"source_path\": null, \"output_path\": null}"
                echo "{\"id\": \"${DB_ID//\"/\\\"}\", \"status\": \"error\", \"type\": null, \"message\": \"Unknown parameter $UNKNOWN_ARG\", \"source_path\": null, \"output_path\": null}" >&2
                exit 1 
                ;;
        esac
    done
fi

# Track ONLY this process's temporary directories for isolated cleanup
JOB_DL_DIR=""
EXTRACT_DIR=""
STAGE_DIR=""

cleanup_self() {
    if [[ -n "$JOB_DL_DIR" && -d "$JOB_DL_DIR" ]]; then
        rm -rf "$JOB_DL_DIR" 2>/dev/null || true
    fi
    if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
        rm -rf "$EXTRACT_DIR" 2>/dev/null || true
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR" 2>/dev/null || true
    fi
    return 0
}

# 2. Universal JSON Error Handler (Called on ANY error or unexpected exit)
json_error() {
    if [[ "$ERROR_HANDLED" == "true" ]]; then
        exit 1
    fi
    ERROR_HANDLED="true"

    local msg="${1//\"/\\\"}"
    
    cleanup_self
    
    # Ensure DB_ID is never empty
    local current_id="${DB_ID:-$FALLBACK_ID}"
    local safe_id="\"${current_id//\"/\\\"}\""
    
    local safe_type="null"
    if [[ -n "$MEDIA_TYPE" ]]; then
        safe_type="\"${MEDIA_TYPE//\"/\\\"}\""
    fi
    
    local safe_source="null"
    if [[ -n "$SOURCE_PATH" ]]; then
        safe_source="\"${SOURCE_PATH//\"/\\\"}\""
    fi

    local safe_output="null"
    if [[ -n "$FINAL_OUTPUT_PATH" ]]; then
        safe_output="\"${FINAL_OUTPUT_PATH//\"/\\\"}\""
    fi
    
    local payload="{\"id\": $safe_id, \"status\": \"error\", \"type\": $safe_type, \"message\": \"$msg\", \"source_path\": $safe_source, \"output_path\": $safe_output}"
    echo "$payload"
    echo "$payload" >&2
    exit 1
}

# Guarantee JSON output even if an unexpected command fails or crashes anywhere
on_exit_trap() {
    local exit_code=$?
    if [[ "$COMPLETED" != "true" && "$ERROR_HANDLED" != "true" ]]; then
        json_error "Script terminated unexpectedly (exit code $exit_code)."
    fi
}
trap 'json_error "Unexpected command failure at line $LINENO."' ERR
trap 'on_exit_trap' EXIT

# 3. Input Gathering (Interactive Mode)
if [[ $INTERACTIVE -eq 1 ]]; then
    read -r -p "Database ID (optional): " DB_ID
    read -r -p "Type [tv/movie/anime]: " MEDIA_TYPE
    read -r -p "Title/Name: " MEDIA_NAME
    read -r -p "Google Drive link (or type 'skip' to use local file): " GDRIVE_LINK
    
    if [[ "$GDRIVE_LINK" =~ ^[Ss][Kk][Ii][Pp]$ ]]; then
        SKIP_DL="true"
        GDRIVE_LINK=""
        read -r -e -p "Path to local file (.zip, .mkv, .mp4, etc.): " LOCAL_FILE
    fi
fi

# Lock in RUN_ID and DB_ID immediately so all subsequent logs/errors have the exact ID
RUN_ID="${DB_ID:-noid}_$$_$(date +%s)"
if [[ -z "$DB_ID" ]]; then
    DB_ID="$RUN_ID"
fi

SAFE_START_ID="\"${DB_ID//\"/\\\"}\""
echo "=== Media Downloader & Organizer (Run: $RUN_ID) ===" >&2
echo "{\"id\": $SAFE_START_ID, \"status\": \"pending\", \"message\": \"Job started and pending completion.\"}" >&2
echo >&2

# 4. Resolve Root Path (Script is in src/, output/ is in Project Root next to app.js)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

BASE_DIR="$ROOT_DIR/output"
DOWNLOADS_DIR="$BASE_DIR/downloads"
STAGING_BASE="$BASE_DIR/staging"
TEMP_DL_BASE="$STAGING_BASE/temp_dl"
MOVIES_DIR="$BASE_DIR/movies"
SHOWS_DIR="$BASE_DIR/shows"
ANIME_DIR="$BASE_DIR/anime"

mkdir -p "$DOWNLOADS_DIR" "$STAGING_BASE" "$TEMP_DL_BASE" "$MOVIES_DIR" "$SHOWS_DIR" "$ANIME_DIR"

# 5. Cross-Platform Environment Setup
if [[ -n "${PREFIX:-}" ]] && [[ -d "${PREFIX}/lib/jvm" ]]; then
    JVM_BASE_DIR="${PREFIX}/lib/jvm"
elif [[ -d "/usr/lib/jvm" ]]; then
    JVM_BASE_DIR="/usr/lib/jvm"
else
    JVM_BASE_DIR=""
fi

if [[ -z "${JAVA_HOME:-}" ]] && [[ -n "$JVM_BASE_DIR" ]]; then
    DYNAMIC_JAVA_HOME=$(find "$JVM_BASE_DIR" -maxdepth 1 -mindepth 1 -type d \( -name "default-java" -o -name "java-*" \) -print -quit 2>/dev/null || true)
    if [[ -n "$DYNAMIC_JAVA_HOME" ]]; then
        export JAVA_HOME="$DYNAMIC_JAVA_HOME"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
fi

# 6. Dependency Checker
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        json_error "Required command '$cmd' is not installed or not in PATH."
    fi
}

check_dependency "gdown"
check_dependency "unzip"
check_dependency "filebot"
check_dependency "java"

# 7. Input Normalization
if [[ "$GDRIVE_LINK" =~ ^[Ss][Kk][Ii][Pp]$ ]]; then
    SKIP_DL="true"
    GDRIVE_LINK=""
fi

MEDIA_TYPE=$(echo "$MEDIA_TYPE" | tr '[:upper:]' '[:lower:]')
case "$MEDIA_TYPE" in
    tv|tvseries|series|show) MEDIA_TYPE="tv" ;;
    movie|film) MEDIA_TYPE="movie" ;;
    anime|animation) MEDIA_TYPE="anime" ;;
    *) json_error "Invalid type '$MEDIA_TYPE'. Must be 'tv', 'movie', or 'anime'." ;;
esac

if [[ -z "$MEDIA_NAME" ]]; then
    json_error "Title/Name is required."
fi

if [[ "$SKIP_DL" == "true" ]]; then
    if [[ -z "$LOCAL_FILE" ]]; then
        AUTO_FILE=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
        if [[ -z "$AUTO_FILE" ]]; then
            AUTO_FILE=$(find "$ROOT_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
        fi
        
        if [[ -n "$AUTO_FILE" ]]; then
            LOCAL_FILE="$AUTO_FILE"
        else
            json_error "Skip requested, but no local file was specified or found in $DOWNLOADS_DIR."
        fi
    fi

    if [[ ! -f "$LOCAL_FILE" ]]; then
        json_error "Specified file '$LOCAL_FILE' does not exist."
    fi
    WORKING_SOURCE="$(cd "$(dirname "$LOCAL_FILE")" && pwd)/$(basename "$LOCAL_FILE")"
    SOURCE_PATH="$WORKING_SOURCE"
    
    echo "Using existing local file: $SOURCE_PATH" >&2
else
    if [[ -z "$GDRIVE_LINK" ]]; then
        json_error "Google Drive link is required when not skipping."
    fi
fi

# 8. Download Phase
if [[ "$SKIP_DL" == "false" ]]; then
    JOB_DL_DIR="$TEMP_DL_BASE/dl_${RUN_ID}"
    mkdir -p "$JOB_DL_DIR"

    echo >&2
    echo "Downloading from Google Drive into $JOB_DL_DIR..." >&2
    echo >&2

    GDOWN_CODE=0
    (cd "$JOB_DL_DIR" && gdown --cookies-from-browser firefox "$GDRIVE_LINK" >&2) || GDOWN_CODE=$?
    if [[ $GDOWN_CODE -ne 0 ]]; then
        json_error "Download failed or was cancelled (gdown exit code $GDOWN_CODE)."
    fi

    DL_FILE=$(find "$JOB_DL_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
    if [[ -z "$DL_FILE" ]]; then
        DL_FILE=$(find "$JOB_DL_DIR" -maxdepth 1 -type f -print -quit 2>/dev/null || true)
    fi

    if [[ -z "$DL_FILE" ]]; then
        json_error "No valid file found after download."
    fi

    DL_FILENAME=$(basename "$DL_FILE")
    
    # Prevent overwriting if a previous download had the exact same archive name
    if [[ -f "$DOWNLOADS_DIR/$DL_FILENAME" ]]; then
        DL_EXT="${DL_FILENAME##*.}"
        DL_BASE="${DL_FILENAME%.*}"
        DL_FILENAME="${DL_BASE}_${RUN_ID}.${DL_EXT}"
    fi

    mv -f "$DL_FILE" "$DOWNLOADS_DIR/$DL_FILENAME" || json_error "Failed to move downloaded file to $DOWNLOADS_DIR."
    
    rm -rf "$JOB_DL_DIR" 2>/dev/null || true
    JOB_DL_DIR=""
    
    WORKING_SOURCE="$DOWNLOADS_DIR/$DL_FILENAME"
    SOURCE_PATH="$WORKING_SOURCE"
    
    echo -e "\nDownload complete. Moved to: $SOURCE_PATH" >&2
fi

WAS_EXTRACTED="false"

# 9. Extraction Phase (Unpacks into staging/extracted_<RUN_ID>)
if [[ "$WORKING_SOURCE" =~ \.[Zz][Ii][Pp]$ ]] || file "$WORKING_SOURCE" 2>/dev/null | grep -qi "zip archive"; then
    WAS_EXTRACTED="true"
    SOURCE_FILENAME=$(basename "$WORKING_SOURCE")
    EXTRACT_DIR="$STAGING_BASE/${SOURCE_FILENAME%.*}_extracted_${RUN_ID}"
    
    echo -e "\nExtracting ZIP into: $EXTRACT_DIR\n" >&2
    mkdir -p "$EXTRACT_DIR"

    UNZIP_CODE=0
    unzip -o "$WORKING_SOURCE" -d "$EXTRACT_DIR" >&2 || UNZIP_CODE=$?
    if [[ $UNZIP_CODE -gt 1 ]]; then
        json_error "ZIP Extraction failed (exit code $UNZIP_CODE). File might be corrupted."
    fi
    FILEBOT_INPUT="$EXTRACT_DIR"
    FILEBOT_ACTION="move" # Moves out of extracted folder into FileBot staging (zero duplicate space)
    echo "Extraction complete." >&2
else
    FILEBOT_INPUT="$WORKING_SOURCE"
    FILEBOT_ACTION="copy"
fi

echo -e "\nRunning FileBot into Staging...\n" >&2

# 10. FileBot Phase (Organizes inside staging/filebot_<RUN_ID>)
STAGE_DIR="$STAGING_BASE/filebot_${RUN_ID}"
mkdir -p "$STAGE_DIR"

FB_CODE=0
if [[ "$MEDIA_TYPE" == "tv" ]]; then
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$FILEBOT_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "$MEDIA_NAME/Season {s.pad(2)}/Episode {e.pad(2)}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        json_error "FileBot TV renaming process failed (exit code $FB_CODE)."
    fi
elif [[ "$MEDIA_TYPE" == "anime" ]]; then
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$FILEBOT_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "$MEDIA_NAME/{any{'Season '+s.pad(2)}{'Season 01'}}/Episode {e.pad(2)}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        echo "TVmaze lookup failed for anime, falling back to AniDB..." >&2
        FB_CODE=0
        filebot -rename -r "$FILEBOT_INPUT" \
            --action "$FILEBOT_ACTION" \
            --db AniDB \
            --q "$MEDIA_NAME" \
            -non-strict \
            --output "$STAGE_DIR" \
            --format "$MEDIA_NAME/{any{'Season '+s.pad(2)}{'Season 01'}}/Episode {e.pad(2)}" >&2 || FB_CODE=$?
        
        if [[ $FB_CODE -ne 0 ]]; then
            json_error "FileBot Anime renaming process failed on both TVmaze and AniDB (exit code $FB_CODE)."
        fi
    fi
else
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$FILEBOT_ACTION" \
        --db TheMovieDB \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "{n} ({y})" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        json_error "FileBot Movie renaming process failed (exit code $FB_CODE)."
    fi
fi

# Helper function to move staged files/seasons into target directory without failing if Season folders already exist
move_staged_tree() {
    local src_dir="$1"
    local dst_dir="$2"
    mkdir -p "$dst_dir"

    while IFS= read -r -d '' src_file; do
        local rel_path="${src_file#$src_dir/}"
        local target_file="$dst_dir/$rel_path"
        mkdir -p "$(dirname "$target_file")"
        mv -f "$src_file" "$target_file" || return 1
    done < <(find "$src_dir" -type f -print0)
}

# 11. Finalizing (Instantly moves from FileBot Staging to output/shows, output/anime, or output/movies)
if [[ "$MEDIA_TYPE" == "tv" ]]; then
    PROCESSED_SHOW_DIR=$(find "$STAGE_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)
    if [[ -z "$PROCESSED_SHOW_DIR" ]]; then
        json_error "FileBot finished, but no TV series folder was generated (no matching episodes found)."
    fi

    SHOW_FOLDER_NAME=$(basename "$PROCESSED_SHOW_DIR")
    move_staged_tree "$PROCESSED_SHOW_DIR" "$SHOWS_DIR/$SHOW_FOLDER_NAME" || json_error "Failed to move TV episodes to $SHOWS_DIR."
    FINAL_OUTPUT_PATH="$SHOWS_DIR/$SHOW_FOLDER_NAME"
elif [[ "$MEDIA_TYPE" == "anime" ]]; then
    PROCESSED_ANIME_DIR=$(find "$STAGE_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)
    if [[ -z "$PROCESSED_ANIME_DIR" ]]; then
        json_error "FileBot finished, but no Anime folder was generated (no matching episodes found)."
    fi

    ANIME_FOLDER_NAME=$(basename "$PROCESSED_ANIME_DIR")
    move_staged_tree "$PROCESSED_ANIME_DIR" "$ANIME_DIR/$ANIME_FOLDER_NAME" || json_error "Failed to move Anime episodes to $ANIME_DIR."
    FINAL_OUTPUT_PATH="$ANIME_DIR/$ANIME_FOLDER_NAME"
else
    PROCESSED_MOVIE=$(find "$STAGE_DIR" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
    if [[ -z "$PROCESSED_MOVIE" ]]; then
        PROCESSED_MOVIE=$(find "$STAGE_DIR" -type f -print -quit 2>/dev/null || true)
    fi

    if [[ -z "$PROCESSED_MOVIE" ]]; then
        json_error "FileBot finished, but no movie file was generated (no matching movie found)."
    fi

    MOVIE_NAME_BASE=$(basename "$PROCESSED_MOVIE")
    mv -f "$PROCESSED_MOVIE" "$MOVIES_DIR/$MOVIE_NAME_BASE" || json_error "Failed to move processed Movie file to $MOVIES_DIR."
    FINAL_OUTPUT_PATH="$MOVIES_DIR/$MOVIE_NAME_BASE"
fi

# Clean up ONLY this job's extraction and FileBot directories
cleanup_self

COMPLETED="true"
echo -e "\nProcessing completed successfully." >&2

# 12. Clean JSON Output to stdout (and stderr for logging)
SAFE_SOURCE_PATH="${SOURCE_PATH//\"/\\\"}"
SAFE_OUTPUT="${FINAL_OUTPUT_PATH//\"/\\\"}"
JSON_ID="\"${DB_ID//\"/\\\"}\""

if [[ "$MEDIA_TYPE" == "tv" ]]; then
    SUCCESS_JSON="{\"id\": $JSON_ID, \"status\": \"success\", \"type\": \"tv\", \"message\": \"Successfully processed TV series.\", \"source_path\": \"$SAFE_SOURCE_PATH\", \"output_path\": \"$SAFE_OUTPUT\", \"output_directory\": \"$SAFE_OUTPUT\"}"
elif [[ "$MEDIA_TYPE" == "anime" ]]; then
    SUCCESS_JSON="{\"id\": $JSON_ID, \"status\": \"success\", \"type\": \"anime\", \"message\": \"Successfully processed Anime.\", \"source_path\": \"$SAFE_SOURCE_PATH\", \"output_path\": \"$SAFE_OUTPUT\", \"output_directory\": \"$SAFE_OUTPUT\"}"
else
    SUCCESS_JSON="{\"id\": $JSON_ID, \"status\": \"success\", \"type\": \"movie\", \"message\": \"Successfully processed Movie.\", \"source_path\": \"$SAFE_SOURCE_PATH\", \"output_path\": \"$SAFE_OUTPUT\", \"output_file\": \"$SAFE_OUTPUT\"}"
fi

echo "$SUCCESS_JSON"
echo "$SUCCESS_JSON" >&2