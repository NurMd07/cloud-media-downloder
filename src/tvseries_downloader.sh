#!/usr/bin/env bash

# -E ensures ERR traps are inherited by functions and subshells
set -Eeuo pipefail

# 1. Early CLI Argument Parsing
MEDIA_TYPE=""
MEDIA_NAME=""
DL_LINK=""
DL_MODE="gdrive" # Default download mode: gdrive | siteDL | magnet
DB_ID=""
KILL_JOB_ID=""
USE_COOKIES="false"
COOKIE_BROWSER="firefox"
CUSTOM_OUTPUT_DIR=""
INTERACTIVE=0
SOURCE_PATH=""
FINAL_OUTPUT_PATH=""
COMPLETED="false"
ERROR_HANDLED="false"

# Optional qBittorrent WebUI credentials (can be set via environment variables)
QB_URL="${QB_URL:-http://127.0.0.1:8080}"
QB_USER="${QB_USER:-admin}"
QB_PASS="${QB_PASS:-adminadmin}"

# Pre-generate a fallback ID immediately so even CLI argument errors have an ID
FALLBACK_ID="noid_$$_$(date +%s)"

show_help() {
    cat << 'EOF'
Usage: ./tvseries_downloader.sh [OPTIONS]

Media Downloader & Organizer Automation Script
If run without arguments, starts in Interactive Mode.

Download Source Modes (Default: -g / Google Drive):
  -g, --gdrive [url]                Download from Google Drive using gdown (Default mode)
  -s, --site, --sitedl [url]        Direct download (.zip, .mkv, .mp4, etc.) from a website using aria2c
  -m, --magnet [magnet_link]        Download via magnet/torrent link using qbittorrent-nox

Core Options:
  -t, -type, --type <type>          Media type: tv, movie, or anime (Required for downloads)
  -n, -name, --name <name>          Media title/name (Required for downloads)
  -l, -link, --link <url/magnet>    Download URL or Magnet link (can also be passed directly to -g, -s, or -m)
  -i, -id, --id <id>                Database/Job ID for tracking
  -k, -kill, --kill, --cancel <id>  Cancel/Kill a running job by its Job ID, cleanup processes/torrents/temp_dl
  -c, -cookies, --cookies <bool>    Use browser cookies for gdown: true/yes or false/no (Default: false)
  -b, -browser, --browser <name>    Browser to load cookies from (Default: firefox)
  -o, -output, --output <path>      Custom base output directory (Default: ../output)
  -h, -help, --help                 Show this help message and exit

Environment Variables (Optional for qBittorrent-nox WebUI):
  QB_URL                            qBittorrent WebUI URL (Default: http://127.0.0.1:8080)
  QB_USER                           qBittorrent WebUI Username (Default: admin)
  QB_PASS                           qBittorrent WebUI Password (Default: adminadmin)

Examples:
  # 1. Google Drive Download (Default mode, with or without -g)
  ./tvseries_downloader.sh -i 101 -t anime -n "Black Clover" -l "https://drive.google.com/..." -c true -b firefox

  # 2. Direct Site Download (siteDL via aria2c)
  ./tvseries_downloader.sh -s -i 102 -t movie -n "Inception" -l "https://example.com/Inception.mkv"

  # 3. Magnet / Torrent Download (via qbittorrent-nox)
  ./tvseries_downloader.sh -m -i 103 -t tv -n "Severance" -l "magnet:?xt=urn:btih:..."

  # 4. Cancel / Kill a running download by Job ID
  ./tvseries_downloader.sh -k 103
EOF
}

if [[ $# -eq 0 ]]; then
    INTERACTIVE=1
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-help|--help)
                COMPLETED="true"
                show_help
                exit 0
                ;;
            -t|-type|--type) MEDIA_TYPE="${2:-}"; shift 2 ;;
            -n|-name|--name) MEDIA_NAME="${2:-}"; shift 2 ;;
            -l|-link|--link) DL_LINK="${2:-}"; shift 2 ;;
            -g|-gdrive|--gdrive)
                DL_MODE="gdrive"
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    if [[ "$2" =~ ^(gdrive|sitedl|site|magnet|torrent)$ ]]; then
                        DL_MODE="$2"
                    else
                        DL_LINK="$2"
                    fi
                    shift 2
                else
                    shift 1
                fi
                ;;
            -s|-site|--site|-sitedl|--sitedl)
                DL_MODE="siteDL"
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    DL_LINK="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            -m|-magnet|--magnet)
                DL_MODE="magnet"
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    DL_LINK="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            -i|-id|--id) DB_ID="${2:-}"; shift 2 ;;
            -k|-kill|--kill|-cancel|--cancel) KILL_JOB_ID="${2:-}"; shift 2 ;;
            -c|-cookies|--cookies)
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    USE_COOKIES="$2"
                    shift 2
                else
                    USE_COOKIES="true"
                    shift 1
                fi
                ;;
            -b|-browser|--browser) COOKIE_BROWSER="${2:-firefox}"; shift 2 ;;
            -o|-output|--output) CUSTOM_OUTPUT_DIR="${2:-}"; shift 2 ;;
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

# Resolve Root & Output Paths early so -k / --kill can locate the PID file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -n "$CUSTOM_OUTPUT_DIR" ]]; then
    mkdir -p "$CUSTOM_OUTPUT_DIR"
    BASE_DIR="$(cd "$CUSTOM_OUTPUT_DIR" && pwd)"
else
    BASE_DIR="$ROOT_DIR/output"
fi

DOWNLOADS_DIR="$BASE_DIR/downloads"
STAGING_BASE="$BASE_DIR/staging"
TEMP_DL_BASE="$STAGING_BASE/temp_dl"
MOVIES_DIR="$BASE_DIR/movies"
SHOWS_DIR="$BASE_DIR/shows"
ANIME_DIR="$BASE_DIR/anime"

mkdir -p "$DOWNLOADS_DIR" "$STAGING_BASE" "$TEMP_DL_BASE" "$MOVIES_DIR" "$SHOWS_DIR" "$ANIME_DIR"

# Handle "-k <job_id>" / "--kill <job_id>" mode to cancel a running job by ID
if [[ -n "$KILL_JOB_ID" ]]; then
    COMPLETED="true"
    TARGET_PID_FILE="$TEMP_DL_BASE/job_${KILL_JOB_ID}.pid"
    if [[ -f "$TARGET_PID_FILE" ]]; then
        TARGET_PID=$(cat "$TARGET_PID_FILE" 2>/dev/null || true)
        if [[ -n "$TARGET_PID" ]] && kill -0 "$TARGET_PID" 2>/dev/null; then
            # Send SIGTERM to trigger on_interrupt_trap in the running job script
            kill -TERM "$TARGET_PID" 2>/dev/null || true
            echo "Sent cancel signal (SIGTERM) to running job $KILL_JOB_ID (PID: $TARGET_PID)." >&2
            exit 0
        fi
    fi
    # Fallback: search running process tree for "-i <KILL_JOB_ID>"
    FOUND_PIDS=$(pgrep -f "tvseries_downloader.sh.*-i ${KILL_JOB_ID}([[:space:]]|$)" 2>/dev/null || true)
    if [[ -n "$FOUND_PIDS" ]]; then
        for pid in $FOUND_PIDS; do
            if [[ "$pid" != "$$" ]]; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        echo "Sent cancel signal (SIGTERM) to running job $KILL_JOB_ID." >&2
        exit 0
    fi
    echo "{\"id\": \"${KILL_JOB_ID//\"/\\\"}\", \"status\": \"error\", \"type\": null, \"message\": \"No active running job found for ID $KILL_JOB_ID.\", \"source_path\": null, \"output_path\": null}"
    exit 1
fi

# Track ONLY this process's temporary directories, child PIDs, and resources for isolated cleanup
JOB_DL_DIR=""
EXTRACT_DIR=""
STAGE_DIR=""
QB_COOKIE_FILE=""
JOB_PID_FILE=""
ACTIVE_TORRENT_HASH=""
ACTIVE_CHILD_PID=""

# Helper to recursively kill a process and all of its descendants (e.g. subshell -> gdown / aria2c / filebot)
kill_process_tree() {
    local parent_pid="$1"
    if [[ -z "$parent_pid" ]]; then
        return 0
    fi
    local child_pids
    child_pids=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    for cpid in $child_pids; do
        kill_process_tree "$cpid"
    done
    kill -TERM "$parent_pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL "$parent_pid" 2>/dev/null || true
}

# Helper to Run a Blocking Command Interruptibly (so SIGTERM/SIGINT wakes up trap immediately)
run_interruptible() {
    "$@" &
    ACTIVE_CHILD_PID=$!
    local rc=0
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || rc=$?
    ACTIVE_CHILD_PID=""
    return $rc
}

# Helper to stop and remove the active torrent from qBittorrent
# Usage: remove_qb_torrent <delete_files: true|false>
remove_qb_torrent() {
    local delete_files="${1:-true}"

    if [[ "$DL_MODE" != "magnet" ]]; then
        return 0
    fi

    # Ensure we have a valid auth cookie even if interrupted very early
    if [[ -z "$QB_COOKIE_FILE" || ! -f "$QB_COOKIE_FILE" ]]; then
        QB_COOKIE_FILE="$TEMP_DL_BASE/qb_cookie_cleanup_$$.txt"
        curl -s -i -c "$QB_COOKIE_FILE" \
            --header "Referer: $QB_URL" \
            --data-urlencode "username=$QB_USER" \
            --data-urlencode "password=$QB_PASS" \
            "$QB_URL/api/v2/auth/login" >/dev/null 2>&1 || true
    fi

    # If hash wasn't captured yet, look it up by JOB_DL_DIR save_path
    if [[ -z "$ACTIVE_TORRENT_HASH" && -n "$JOB_DL_DIR" && -f "$QB_COOKIE_FILE" ]]; then
        local info_json
        info_json=$(curl -s -b "$QB_COOKIE_FILE" "$QB_URL/api/v2/torrents/info" 2>/dev/null || true)
        if [[ -n "$info_json" ]]; then
            ACTIVE_TORRENT_HASH=$(python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    save_dir = sys.argv[1].rstrip("/")
    for t in data:
        if t.get("save_path", "").rstrip("/") == save_dir:
            print(t.get("hash", "").lower())
            break
except Exception:
    pass
' "$JOB_DL_DIR" <<< "$info_json" 2>/dev/null || true)
        fi
    fi

    if [[ -n "$ACTIVE_TORRENT_HASH" ]]; then
        local cookie_args=()
        if [[ -n "$QB_COOKIE_FILE" && -f "$QB_COOKIE_FILE" ]]; then
            cookie_args=(-b "$QB_COOKIE_FILE")
        fi

        # Pause/Stop torrent first (supports both qBittorrent v4 'pause' and v5 'stop' endpoints)
        curl -s "${cookie_args[@]}" --header "Referer: $QB_URL" \
            --data-urlencode "hashes=$ACTIVE_TORRENT_HASH" \
            "$QB_URL/api/v2/torrents/pause" >/dev/null 2>&1 || true
        curl -s "${cookie_args[@]}" --header "Referer: $QB_URL" \
            --data-urlencode "hashes=$ACTIVE_TORRENT_HASH" \
            "$QB_URL/api/v2/torrents/stop" >/dev/null 2>&1 || true

        # Delete torrent entry from client
        curl -s "${cookie_args[@]}" --header "Referer: $QB_URL" \
            --data-urlencode "hashes=$ACTIVE_TORRENT_HASH" \
            --data-urlencode "deleteFiles=$delete_files" \
            "$QB_URL/api/v2/torrents/delete" >/dev/null 2>&1 || true

        ACTIVE_TORRENT_HASH=""
    fi
    return 0
}

cleanup_self() {
    # Disable traps inside cleanup to prevent recursive triggers
    trap - INT TERM ERR EXIT

    # 1. Kill any active child process tree (gdown, aria2c, unzip, filebot, sleep)
    if [[ -n "$ACTIVE_CHILD_PID" ]]; then
        kill_process_tree "$ACTIVE_CHILD_PID"
        ACTIVE_CHILD_PID=""
    fi
    # Also kill any remaining direct child processes of this script PID
    local direct_children
    direct_children=$(pgrep -P $$ 2>/dev/null || true)
    for cpid in $direct_children; do
        kill_process_tree "$cpid"
    done

    # 2. If a torrent is still active during cleanup (error, timeout, or cancel), remove it and its files from qBittorrent
    if [[ "$DL_MODE" == "magnet" && ( -n "$ACTIVE_TORRENT_HASH" || -n "$JOB_DL_DIR" ) ]]; then
        remove_qb_torrent "true"
    fi

    # 3. Clean up temporary directories and files
    if [[ -n "$JOB_DL_DIR" && -d "$JOB_DL_DIR" ]]; then
        rm -rf "$JOB_DL_DIR" 2>/dev/null || true
    fi
    if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
        rm -rf "$EXTRACT_DIR" 2>/dev/null || true
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR" 2>/dev/null || true
    fi
    if [[ -n "$QB_COOKIE_FILE" && -f "$QB_COOKIE_FILE" ]]; then
        rm -f "$QB_COOKIE_FILE" 2>/dev/null || true
    fi
    if [[ -n "$JOB_PID_FILE" && -f "$JOB_PID_FILE" ]]; then
        rm -f "$JOB_PID_FILE" 2>/dev/null || true
    fi
    return 0
}

# 2. Universal JSON Error Handler (Called on ANY error, Ctrl+C, SIGTERM, or unexpected exit)
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

# Guarantee JSON output and complete cleanup on Ctrl+C (SIGINT), SIGTERM, SIGHUP, or unexpected crash
on_interrupt_trap() {
    echo -e "\n[CANCELLED] Job ${DB_ID:-$FALLBACK_ID} received cancel/kill signal. Terminating active download and cleaning up..." >&2
    json_error "Download cancelled/killed for job ID ${DB_ID:-$FALLBACK_ID}."
}

on_exit_trap() {
    local exit_code=$?
    if [[ "$COMPLETED" != "true" && "$ERROR_HANDLED" != "true" ]]; then
        json_error "Script terminated unexpectedly (exit code $exit_code)."
    fi
}
trap 'on_interrupt_trap' INT TERM HUP
trap 'json_error "Unexpected command failure at line $LINENO."' ERR
trap 'on_exit_trap' EXIT

# 3. Input Gathering (Interactive Mode)
if [[ $INTERACTIVE -eq 1 ]]; then
    read -r -p "Database ID (optional): " DB_ID
    read -r -p "Type [tv/movie/anime]: " MEDIA_TYPE
    read -r -p "Title/Name: " MEDIA_NAME
    read -r -p "Download Mode [gdrive/siteDL/magnet] (default: gdrive): " INPUT_MODE
    DL_MODE="${INPUT_MODE:-gdrive}"
    read -r -p "Download URL / Magnet Link: " DL_LINK
    
    if [[ "$DL_MODE" =~ ^([gG][dD][rR][iI][vV][eE]|[gG])$ ]]; then
        read -r -p "Use browser cookies for download? [y/N]: " USE_COOKIES_INPUT
        if [[ "$USE_COOKIES_INPUT" =~ ^([yY][eE][sS]|[yY]|[tT][rR][uU][eE])$ ]]; then
            USE_COOKIES="true"
            read -r -p "Browser for cookies [default: firefox]: " BROWSER_INPUT
            COOKIE_BROWSER="${BROWSER_INPUT:-firefox}"
        else
            USE_COOKIES="false"
        fi
    fi

    read -r -e -p "Output directory path (leave blank for default ../output): " CUSTOM_OUTPUT_DIR
fi

# Lock in RUN_ID and DB_ID immediately so all subsequent logs/errors have the exact ID
RUN_ID="${DB_ID:-noid}_$$_$(date +%s)"
if [[ -z "$DB_ID" ]]; then
    DB_ID="$RUN_ID"
fi

# Register PID file mapped to DB_ID so job can be cancelled by ID from anywhere
JOB_PID_FILE="$TEMP_DL_BASE/job_${DB_ID}.pid"
echo "$$" > "$JOB_PID_FILE"

SAFE_START_ID="\"${DB_ID//\"/\\\"}\""
echo "=== Media Downloader & Organizer (Run: $RUN_ID, PID: $$) ===" >&2
echo "{\"id\": $SAFE_START_ID, \"status\": \"pending\", \"pid\": $$, \"message\": \"Job started and pending completion.\"}" >&2
echo >&2

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

# 6. Input Normalization & Mode-Specific Dependency Checking
DL_MODE_LOWER=$(echo "$DL_MODE" | tr '[:upper:]' '[:lower:]')
case "$DL_MODE_LOWER" in
    g|gdrive|drive|"") DL_MODE="gdrive" ;;
    s|site|sitedl|direct|aria2|aria2c) DL_MODE="siteDL" ;;
    m|magnet|torrent|qbit|qbittorrent) DL_MODE="magnet" ;;
    *) json_error "Invalid download mode '$DL_MODE'. Must be 'gdrive', 'siteDL', or 'magnet'." ;;
esac

check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        json_error "Required command '$cmd' is not installed or not in PATH."
    fi
}

check_dependency "unzip"
check_dependency "filebot"
check_dependency "java"

if [[ "$DL_MODE" == "gdrive" ]]; then
    check_dependency "gdown"
elif [[ "$DL_MODE" == "siteDL" ]]; then
    check_dependency "aria2c"
elif [[ "$DL_MODE" == "magnet" ]]; then
    check_dependency "qbittorrent-nox"
    check_dependency "curl"
    check_dependency "python3"
fi

USE_COOKIES=$(echo "$USE_COOKIES" | tr '[:upper:]' '[:lower:]')
case "$USE_COOKIES" in
    true|yes|y|1) USE_COOKIES="true" ;;
    false|no|n|0|"") USE_COOKIES="false" ;;
    *) json_error "Invalid cookies option '$USE_COOKIES'. Must be 'true' or 'false'." ;;
esac

COOKIE_BROWSER="${COOKIE_BROWSER:-firefox}"

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

if [[ -z "$DL_LINK" ]]; then
    json_error "Download URL or magnet link is required."
fi

# 7. Helper for Magnet / qBittorrent-nox Download with Progress Reporting & Stall Timeout (5 mins)
download_with_qbittorrent() {
    local magnet="$1"
    local save_dir="$2"

    # Extract 40-char hex or 32-char base32 infohash from magnet link
    local hash=""
    if [[ "$magnet" =~ xt=urn:btih:([a-fA-F0-9]{40}) ]]; then
        hash=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    elif [[ "$magnet" =~ xt=urn:btih:([a-zA-Z2-7]{32}) ]]; then
        hash=$(python3 -c "import base64, sys; print(base64.b32decode(sys.argv[1].upper()).hex().lower())" "${BASH_REMATCH[1]}" 2>/dev/null || true)
    fi

    # Pre-assign ACTIVE_TORRENT_HASH immediately so Ctrl+C / kill during early startup can still delete it
    ACTIVE_TORRENT_HASH="$hash"

    # Ensure qbittorrent-nox daemon is running
    if ! pgrep -x "qbittorrent-nox" >/dev/null 2>&1; then
        echo "Starting qbittorrent-nox daemon..." >&2
        qbittorrent-nox -d >/dev/null 2>&1 || true
        run_interruptible sleep 3
    fi

    QB_COOKIE_FILE="$TEMP_DL_BASE/qb_cookie_${RUN_ID}.txt"

    # Authenticate with qBittorrent WebUI API
    curl -s -i -c "$QB_COOKIE_FILE" \
        --header "Referer: $QB_URL" \
        --data-urlencode "username=$QB_USER" \
        --data-urlencode "password=$QB_PASS" \
        "$QB_URL/api/v2/auth/login" >/dev/null 2>&1 || true

    # Add magnet link assigned to our isolated JOB_DL_DIR
    local add_resp
    add_resp=$(curl -s -b "$QB_COOKIE_FILE" \
        --header "Referer: $QB_URL" \
        -F "urls=$magnet" \
        -F "savepath=$save_dir" \
        "$QB_URL/api/v2/torrents/add" 2>/dev/null || true)

    if [[ -z "$add_resp" ]]; then
        json_error "Failed to connect to qbittorrent-nox WebUI at $QB_URL. Check if WebUI is enabled."
    fi

    run_interruptible sleep 2

    local stalled_seconds=0
    local last_completed_size="-1"
    local max_stall_limit=300 # 5 minutes (300 seconds) timeout for metaDL or stalledDL

    # Poll progress every 5 seconds until torrent completes or times out
    while true; do
        local info_json
        info_json=$(curl -s -b "$QB_COOKIE_FILE" "$QB_URL/api/v2/torrents/info" 2>/dev/null || true)

        local status_line
        status_line=$(python3 -c '
import sys, json

try:
    data = json.load(sys.stdin)
except Exception:
    print("WAIT|0%|0.0MB/s|0.0MB/0.0MB|Connecting to qBittorrent...|")
    sys.exit(0)

target_hash = sys.argv[1].lower()
save_dir = sys.argv[2].rstrip("/")

match = None
for t in data:
    t_hash = t.get("hash", "").lower()
    t_save = t.get("save_path", "").rstrip("/")
    if (target_hash and t_hash == target_hash) or (t_save == save_dir):
        match = t
        break

if not match:
    print("WAIT|0%|0.0MB/s|0.0MB/0.0MB|Waiting for torrent metadata...|")
    sys.exit(0)

state = match.get("state", "")
prog = match.get("progress", 0) * 100
dlspeed = match.get("dlspeed", 0) / (1024 * 1024)
completed = match.get("completed", 0) / (1024 * 1024)
total = match.get("size", 0) / (1024 * 1024)
eta = match.get("eta", 0)
t_hash = match.get("hash", "")

done_states = {"uploading", "stalledUP", "queuedUP", "pausedUP", "stoppedUP", "checkingUP", "forcedUP"}
error_states = {"error", "missingFiles"}

if state in error_states:
    print(f"ERROR|{state}|{t_hash}")
elif prog >= 100.0 or state in done_states:
    print(f"DONE|100%|{completed:.1f}MB/{total:.1f}MB|{dlspeed:.2f}MB/s|{t_hash}")
else:
    eta_str = f"{eta}s" if eta < 8640000 else "inf"
    print(f"PROG|{prog:.0f}%| {completed:.1f}MB/{total:.1f}MB [{dlspeed:.2f}MB/s, ETA: {eta_str}, State: {state}]|{t_hash}")
' "$hash" "$save_dir" <<< "$info_json")

        local status_type="${status_line%%|*}"
        local rest="${status_line#*|}"
        local reported_hash="${rest##*|}"
        if [[ -n "$reported_hash" ]]; then
            ACTIVE_TORRENT_HASH="$reported_hash"
        fi

        if [[ "$status_type" == "ERROR" ]]; then
            local err_state="${rest%%|*}"
            # Clean up torrent and files from qBittorrent on error
            remove_qb_torrent "true"
            json_error "qBittorrent download failed (torrent state: $err_state)."
        elif [[ "$status_type" == "DONE" ]]; then
            echo "100%|██████████| Torrent download complete! Removing from qBittorrent client..." >&2
            # Stop seeding and remove torrent from qBittorrent (keep downloaded files in JOB_DL_DIR)
            remove_qb_torrent "false"
            run_interruptible sleep 1
            break
        elif [[ "$status_type" == "PROG" || "$status_type" == "WAIT" ]]; then
            local msg="${rest%|*}"
            echo "$msg" >&2

            # Extract state and completed size from python output to check for stalls
            local current_state=""
            if [[ "$msg" =~ State:\ ([a-zA-Z]+) ]]; then
                current_state="${BASH_REMATCH[1]}"
            fi
            local current_completed="${msg%%/*}"

            # Check if stuck in metaDL, stalledDL, or if downloaded size hasn't budged
            if [[ "$current_state" == "metaDL" || "$current_state" == "stalledDL" || "$current_completed" == "$last_completed_size" ]]; then
                stalled_seconds=$((stalled_seconds + 5))
            else
                stalled_seconds=0 # Reset timer if progress moves
                last_completed_size="$current_completed"
            fi

            # Timeout check (5 minutes / 300 seconds)
            if [[ $stalled_seconds -ge $max_stall_limit ]]; then
                echo "Torrent stuck at state '${current_state:-stalled}' with no progress for 5 minutes. Aborting." >&2
                remove_qb_torrent "true"
                json_error "Torrent download timed out: stuck at state '${current_state:-stalled}' for over 5 minutes."
            fi
        else
            echo "$rest" >&2
        fi

        run_interruptible sleep 5
    done
}

# 8. Download Phase
JOB_DL_DIR="$TEMP_DL_BASE/dl_${RUN_ID}"
mkdir -p "$JOB_DL_DIR"

echo >&2
echo "Starting download (Mode: $DL_MODE) into $JOB_DL_DIR..." >&2
echo >&2

if [[ "$DL_MODE" == "gdrive" ]]; then
    if [[ "$USE_COOKIES" == "true" ]]; then
        echo "Using cookies from browser: $COOKIE_BROWSER" >&2
    fi

    GDOWN_ARGS=()
    if [[ "$USE_COOKIES" == "true" ]]; then
        GDOWN_ARGS+=(--cookies-from-browser "$COOKIE_BROWSER")
    fi

    GDOWN_CODE=0
    (
        cd "$JOB_DL_DIR"
        exec env TQDM_MININTERVAL=5 gdown "${GDOWN_ARGS[@]}" "$DL_LINK" >&2
    ) &
    ACTIVE_CHILD_PID=$!
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || GDOWN_CODE=$?
    ACTIVE_CHILD_PID=""

    if [[ $GDOWN_CODE -ne 0 ]]; then
        json_error "Google Drive download failed or was cancelled (gdown exit code $GDOWN_CODE)."
    fi

elif [[ "$DL_MODE" == "siteDL" ]]; then
    ARIA_CODE=0
    # Run aria2c in background and wait on it so SIGTERM/SIGINT triggers cleanup immediately
    (
        cd "$JOB_DL_DIR"
        aria2c \
            --summary-interval=5 \
            --console-log-level=warn \
            --download-result=hide \
            --human-readable=true \
            --max-connection-per-server=8 \
            --split=8 \
            --min-split-size=10M \
            --continue=true \
            "$DL_LINK" 2>&1 | stdbuf -oL tr '\r' '\n' | while IFS= read -r line; do
                if [[ "$line" =~ \(([0-9]{1,3}%)\) ]]; then
                    pct="${BASH_REMATCH[1]}"
                    echo "${pct}| ${line}" >&2
                elif [[ -n "${line// /}" ]]; then
                    echo "$line" >&2
                fi
            done
    ) &
    ACTIVE_CHILD_PID=$!
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || ARIA_CODE=$?
    ACTIVE_CHILD_PID=""

    if [[ $ARIA_CODE -ne 0 ]]; then
        json_error "Direct site download failed (aria2c exit code $ARIA_CODE)."
    fi

elif [[ "$DL_MODE" == "magnet" ]]; then
    download_with_qbittorrent "$DL_LINK" "$JOB_DL_DIR"
fi

# Locate downloaded payload inside JOB_DL_DIR (supports single file OR multi-file torrent directory)
DL_ITEM=$(find "$JOB_DL_DIR" -mindepth 1 -maxdepth 1 ! -name "*.aria2" ! -name "*.parts" -print -quit 2>/dev/null || true)

if [[ -z "$DL_ITEM" ]]; then
    json_error "No valid file or directory found after download."
fi

ITEM_COUNT=$(find "$JOB_DL_DIR" -mindepth 1 -maxdepth 1 ! -name "*.aria2" ! -name "*.parts" | wc -l)

if [[ $ITEM_COUNT -gt 1 ]]; then
    # Multiple loose files downloaded at root of JOB_DL_DIR -> group them into a folder
    DL_FILENAME="${MEDIA_NAME// /_}_${RUN_ID}"
    TARGET_DL_PATH="$DOWNLOADS_DIR/$DL_FILENAME"
    mkdir -p "$TARGET_DL_PATH"
    mv -f "$JOB_DL_DIR"/* "$TARGET_DL_PATH/" || json_error "Failed to move downloaded files to $TARGET_DL_PATH."
else
    DL_FILENAME=$(basename "$DL_ITEM")
    if [[ -e "$DOWNLOADS_DIR/$DL_FILENAME" ]]; then
        if [[ -f "$DL_ITEM" && "$DL_FILENAME" == *.* ]]; then
            DL_EXT="${DL_FILENAME##*.}"
            DL_BASE="${DL_FILENAME%.*}"
            DL_FILENAME="${DL_BASE}_${RUN_ID}.${DL_EXT}"
        else
            DL_FILENAME="${DL_FILENAME}_${RUN_ID}"
        fi
    fi
    TARGET_DL_PATH="$DOWNLOADS_DIR/$DL_FILENAME"
    mv -f "$DL_ITEM" "$TARGET_DL_PATH" || json_error "Failed to move downloaded item to $DOWNLOADS_DIR."
fi

rm -rf "$JOB_DL_DIR" 2>/dev/null || true
JOB_DL_DIR=""

WORKING_SOURCE="$TARGET_DL_PATH"
SOURCE_PATH="$WORKING_SOURCE"

echo -e "\nDownload complete. Moved to: $SOURCE_PATH" >&2

WAS_EXTRACTED="false"

# 9. Extraction Phase (Unpacks into staging/extracted_<RUN_ID> if ZIP archive)
if [[ -f "$WORKING_SOURCE" ]] && ([[ "$WORKING_SOURCE" =~ \.[Zz][Ii][Pp]$ ]] || file "$WORKING_SOURCE" 2>/dev/null | grep -qi "zip archive"); then
    WAS_EXTRACTED="true"
    SOURCE_FILENAME=$(basename "$WORKING_SOURCE")
    EXTRACT_DIR="$STAGING_BASE/${SOURCE_FILENAME%.*}_extracted_${RUN_ID}"
    
    echo -e "\nExtracting ZIP into: $EXTRACT_DIR\n" >&2
    mkdir -p "$EXTRACT_DIR"

    UNZIP_CODE=0
    run_interruptible unzip -o "$WORKING_SOURCE" -d "$EXTRACT_DIR" >&2 || UNZIP_CODE=$?
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
    run_interruptible filebot -rename -r "$FILEBOT_INPUT" \
        --action "$FILEBOT_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "$MEDIA_NAME/Season {s.pad(2)}/{n} - S{s.pad(2)}E{e.pad(2)}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        json_error "FileBot TV renaming process failed (exit code $FB_CODE)."
    fi
elif [[ "$MEDIA_TYPE" == "anime" ]]; then
    run_interruptible filebot -rename -r "$FILEBOT_INPUT" \
        --action "$FILEBOT_ACTION" \
        --db TVmaze \
        --q "$MEDIA_NAME" \
        -non-strict \
        --output "$STAGE_DIR" \
        --format "$MEDIA_NAME/{any{'Season '+s.pad(2)}{'Season 01'}}/{n} - S{s.pad(2)}E{e.pad(2)}" >&2 || FB_CODE=$?
    
    if [[ $FB_CODE -ne 0 ]]; then
        echo "TVmaze lookup failed for anime, falling back to AniDB..." >&2
        FB_CODE=0
        run_interruptible filebot -rename -r "$FILEBOT_INPUT" \
            --action "$FILEBOT_ACTION" \
            --db AniDB \
            --q "$MEDIA_NAME" \
            -non-strict \
            --output "$STAGE_DIR" \
            --format "$MEDIA_NAME/{any{'Season '+s.pad(2)}{'Season 01'}}/{n} - S{s.pad(2)}E{e.pad(2)}" >&2 || FB_CODE=$?
        
        if [[ $FB_CODE -ne 0 ]]; then
            json_error "FileBot Anime renaming process failed on both TVmaze and AniDB (exit code $FB_CODE)."
        fi
    fi
else
    run_interruptible filebot -rename -r "$FILEBOT_INPUT" \
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