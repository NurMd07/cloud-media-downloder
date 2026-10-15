#!/usr/bin/env bash

# -E ensures ERR traps are inherited by functions and subshells
set -Eeuo pipefail

# 1. Early CLI Argument Parsing
MEDIA_TYPE=""
MEDIA_NAME=""
INPUT_PATH=""
DB_ID=""
FILEBOT_ACTION="copy"
INTERACTIVE=0
SOURCE_PATH=""
FINAL_OUTPUT_PATH=""
COMPLETED="false"
ERROR_HANDLED="false"

FALLBACK_ID="noid_$$_$(date +%s)"

if [[ $# -eq 0 ]]; then
    INTERACTIVE=1
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|-type|--type) MEDIA_TYPE="${2:-}"; shift 2 ;;
            -n|-name|--name) MEDIA_NAME="${2:-}"; shift 2 ;;
            -f|-file|--file|-input|--input) INPUT_PATH="${2:-}"; shift 2 ;;
            -i|-id|--id) DB_ID="${2:-}"; shift 2 ;;
            -a|-action|--action) FILEBOT_ACTION="${2:-}"; shift 2 ;;
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

STAGE_DIR=""
EXTRACT_DIR=""

cleanup_self() {
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR" 2>/dev/null || true
    fi
    if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
        rm -rf "$EXTRACT_DIR" 2>/dev/null || true
    fi
    return 0
}

# 2. Universal JSON Error Handler
json_error() {
    if [[ "$ERROR_HANDLED" == "true" ]]; then
        exit 1
    fi
    ERROR_HANDLED="true"

    local msg="${1//\"/\\\"}"
    
    cleanup_self
    
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

on_exit_trap() {
    local exit_code=$?
    if [[ "$COMPLETED" != "true" && "$ERROR_HANDLED" != "true" ]]; then
        json_error "Script terminated unexpectedly (exit code $exit_code)."
    fi
}
trap 'json_error "Unexpected command failure at line $LINENO."' ERR
trap 'on_exit_trap' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 3. Interactive Input Gathering
if [[ $INTERACTIVE -eq 1 ]]; then
    read -r -p "Database ID (optional): " DB_ID
    read -r -p "Type [tv/movie/anime]: " MEDIA_TYPE
    read -r -p "Title/Name: " MEDIA_NAME
    read -r -e -p "Path to local file or folder (leave blank to auto-detect): " INPUT_PATH
    read -r -p "Action [copy/move] (default: copy): " USER_ACTION
    if [[ -n "$USER_ACTION" ]]; then
        FILEBOT_ACTION="$USER_ACTION"
    fi
fi

RUN_ID="${DB_ID:-noid}_$$_$(date +%s)"
if [[ -z "$DB_ID" ]]; then
    DB_ID="$RUN_ID"
fi

SAFE_START_ID="\"${DB_ID//\"/\\\"}\""
echo "=== Standalone FileBot Organizer (Run: $RUN_ID) ===" >&2
echo "{\"id\": $SAFE_START_ID, \"status\": \"pending\", \"message\": \"Job started and pending completion.\"}" >&2
echo >&2

# 4. Cross-Platform Java & FileBot Environment Setup
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

# 5. Dependency Checker
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        json_error "Required command '$cmd' is not installed or not in PATH."
    fi
}

check_dependency "filebot"
check_dependency "java"
check_dependency "unzip"

# 6. Input Normalization
INPUT_PATH="${INPUT_PATH#\"}"
INPUT_PATH="${INPUT_PATH%\"}"
INPUT_PATH="${INPUT_PATH#\'}"
INPUT_PATH="${INPUT_PATH%\'}"

if [[ "$INPUT_PATH" =~ ^[A-Za-z]:\\ ]] || [[ "$INPUT_PATH" =~ ^[A-Za-z]:/ ]]; then
    if command -v wslpath >/dev/null 2>&1; then
        INPUT_PATH="$(wslpath -u "$INPUT_PATH")"
    fi
fi

MEDIA_TYPE=$(echo "$MEDIA_TYPE" | tr '[:upper:]' '[:lower:]')
case "$MEDIA_TYPE" in
    tv|tvseries|series|show) MEDIA_TYPE="tv" ;;
    movie|film) MEDIA_TYPE="movie" ;;
    anime|animation) MEDIA_TYPE="anime" ;;
    *) json_error "Invalid type '$MEDIA_TYPE'. Must be 'tv', 'movie', or 'anime'." ;;
esac

FILEBOT_ACTION=$(echo "$FILEBOT_ACTION" | tr '[:upper:]' '[:lower:]')
case "$FILEBOT_ACTION" in
    copy|move|hardlink|symlink) ;;
    *) json_error "Invalid action '$FILEBOT_ACTION'. Must be 'copy' or 'move'." ;;
esac

if [[ -z "$MEDIA_NAME" ]]; then
    json_error "Title/Name (-n) is required."
fi

if [[ -z "$INPUT_PATH" ]]; then
    AUTO_FILE=$(find "$(pwd)" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
    if [[ -z "$AUTO_FILE" ]]; then
        AUTO_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
    fi

    if [[ -n "$AUTO_FILE" ]]; then
        INPUT_PATH="$AUTO_FILE"
    else
        json_error "Input path (-f) was not specified and no media/zip file was found."
    fi
fi

if [[ ! -e "$INPUT_PATH" ]]; then
    json_error "Specified input path '$INPUT_PATH' does not exist."
fi

# 7. Resolve Absolute Source Path & Set Output Directory Next to Source
if [[ -d "$INPUT_PATH" ]]; then
    SOURCE_PATH="$(cd "$INPUT_PATH" && pwd)"
else
    SOURCE_PATH="$(cd "$(dirname "$INPUT_PATH")" && pwd)/$(basename "$INPUT_PATH")"
fi

OUTPUT_DIR="$(dirname "$SOURCE_PATH")"
STAGE_DIR="$OUTPUT_DIR/.filebot_staging_${RUN_ID}"
mkdir -p "$STAGE_DIR"

# 8. Auto-Extract if Input is a ZIP File
if [[ -f "$SOURCE_PATH" ]] && { [[ "$SOURCE_PATH" =~ \.[Zz][Ii][Pp]$ ]] || file "$SOURCE_PATH" 2>/dev/null | grep -qi "zip archive"; }; then
    EXTRACT_DIR="$OUTPUT_DIR/.filebot_extracted_${RUN_ID}"
    mkdir -p "$EXTRACT_DIR"
    echo "Detected ZIP archive. Extracting into temporary folder..." >&2
    
    UNZIP_CODE=0
    unzip -o "$SOURCE_PATH" -d "$EXTRACT_DIR" >&2 || UNZIP_CODE=$?
    if [[ $UNZIP_CODE -gt 1 ]]; then
        json_error "ZIP Extraction failed (exit code $UNZIP_CODE). File might be corrupted."
    fi
    
    FILEBOT_INPUT="$EXTRACT_DIR"
    EFFECTIVE_ACTION="move"
else
    FILEBOT_INPUT="$SOURCE_PATH"
    EFFECTIVE_ACTION="$FILEBOT_ACTION"
fi

echo "Source Path : $SOURCE_PATH" >&2
echo "Output Dir  : $OUTPUT_DIR (Action: $EFFECTIVE_ACTION)" >&2
echo -e "\nRunning FileBot...\n" >&2

# 9. FileBot Phase
FB_CODE=0
if [[ "$MEDIA_TYPE" == "tv" ]]; then
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$EFFECTIVE_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "{n}/Season {s.pad(2)}/Episode {e.pad(2)} - {t}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        json_error "FileBot TV renaming process failed (exit code $FB_CODE)."
    fi
elif [[ "$MEDIA_TYPE" == "anime" ]]; then
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$EFFECTIVE_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "{n}/{any{'Season '+s.pad(2)}{'Season 01'}}/Episode {e.pad(2)} - {t}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        echo "TVmaze lookup failed for anime, falling back to AniDB..." >&2
        FB_CODE=0
        filebot -rename -r "$FILEBOT_INPUT" \
            --action "$EFFECTIVE_ACTION" \
            --db AniDB \
            --q "$MEDIA_NAME" \
            -non-strict \
            --output "$STAGE_DIR" \
            --format "{n}/{any{'Season '+s.pad(2)}{'Season 01'}}/Episode {e.pad(2)} - {t}" >&2 || FB_CODE=$?
        
        if [[ $FB_CODE -ne 0 ]]; then
            json_error "FileBot Anime renaming process failed on both TVmaze and AniDB (exit code $FB_CODE)."
        fi
    fi
else
    filebot -rename -r "$FILEBOT_INPUT" \
        --action "$EFFECTIVE_ACTION" \
        --db TheMovieDB \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "{n} ({y})" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        json_error "FileBot Movie renaming process failed (exit code $FB_CODE)."
    fi
fi

# 10. Finalizing (Places final folder or movie file right next to the source file/folder)
if [[ "$MEDIA_TYPE" == "tv" || "$MEDIA_TYPE" == "anime" ]]; then
    PROCESSED_DIR=$(find "$STAGE_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)
    if [[ -z "$PROCESSED_DIR" ]]; then
        json_error "FileBot finished, but no output series/anime folder was generated (no matching episodes found)."
    fi

    FOLDER_NAME=$(basename "$PROCESSED_DIR")
    mkdir -p "$OUTPUT_DIR/$FOLDER_NAME"
    cp -rf "$PROCESSED_DIR/"* "$OUTPUT_DIR/$FOLDER_NAME/" || json_error "Failed to copy processed episodes to $OUTPUT_DIR/$FOLDER_NAME."
    FINAL_OUTPUT_PATH="$OUTPUT_DIR/$FOLDER_NAME"
else
    PROCESSED_MOVIE=$(find "$STAGE_DIR" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -print -quit 2>/dev/null || true)
    if [[ -z "$PROCESSED_MOVIE" ]]; then
        PROCESSED_MOVIE=$(find "$STAGE_DIR" -type f -print -quit 2>/dev/null || true)
    fi

    if [[ -z "$PROCESSED_MOVIE" ]]; then
        json_error "FileBot finished, but no movie file was generated (no matching movie found)."
    fi

    MOVIE_NAME_BASE=$(basename "$PROCESSED_MOVIE")
    mv -f "$PROCESSED_MOVIE" "$OUTPUT_DIR/$MOVIE_NAME_BASE" || json_error "Failed to move processed Movie file to $OUTPUT_DIR."
    FINAL_OUTPUT_PATH="$OUTPUT_DIR/$MOVIE_NAME_BASE"
fi

cleanup_self

COMPLETED="true"
echo -e "\nFileBot processing completed successfully." >&2

# 11. Clean JSON Output to stdout (and stderr for logging)
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