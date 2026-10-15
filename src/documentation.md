================================================================================
MEDIA AUTOMATION SCRIPTS DOCUMENTATION
================================================================================

This suite consists of two modular Bash scripts designed for backend integration 
(such as Node.js via child_process.spawn). Both scripts output clean JSON status 
payloads on `stdout` and route live progress logs to `stderr`.

---

### SCRIPT 1: Standalone FileBot Organizer (`filebot.sh`)
Organizes, renames, and sorts local media files (movies, TV shows, or anime) 
directly into the directory next to the source file/folder. Supports auto-extraction 
if a `.zip` archive is provided.

- USAGE (CLI):
  ./filebot.sh -t <type> -n "<title>" [-f "<path>"] [-a <action>] [-i <id>]

- USAGE (Interactive):
  ./filebot.sh

- OPTIONS:
  -t, --type <type>        Media category: `movie`, `tv`, or `anime` (Required).
  -n, --name <title>       Official media title used for database matching (Required).
  -f, --file <path>        Path to local video, folder, or zip. (Auto-detects if omitted).
  -a, --action <action>    FileBot operation: `copy`, `move`, `hardlink`, `symlink` (Default: `copy`).
  -i, --id <id>            Custom Database/Job ID echoed back in the JSON output.

- OUTPUT:
  JSON object on `stdout` containing `id`, `status`, `type`, `message`, `source_path`, 
  and `output_path` (`output_file` for movies, `output_directory` for TV/anime).

---

### SCRIPT 2: GDrive Downloader & Organizer (`downloaderscript.sh`)
Handles the full pipeline: downloads a `.zip` archive from Google Drive into a persistent 
staging download directory, moves the archive into `output/downloads/`, extracts it, 
processes it via FileBot, and organizes the final media into `output/movies/`, 
`output/shows/`, or `output/anime/`.

- USAGE (CLI):
  ./downloaderscript.sh -t <type> -n "<title>" -l "<gdrive_link>" [-i <id>]
  ./downloaderscript.sh -t <type> -n "<title>" -s [-f "<local_file>"] [-i <id>]

- USAGE (Interactive):
  ./downloaderscript.sh

- OPTIONS:
  -t, --type <type>        Media category: `movie`, `tv`, or `anime` (Required).
  -n, --name <title>       Official media title for FileBot matching (Required).
  -l, --link <url>         Google Drive file link or share URL (Required unless skipping).
  -s, --skip               Skip Google Drive download and use an existing local file.
  -f, --file <path>        Specific local file path to use when `--skip` is active.
  -i, --id <id>            Custom Database/Job ID echoed back in the JSON output.

- OUTPUT:
  JSON object on `stdout` containing `id`, `status`, `type`, `message`, `source_path` 
  (pointing to the saved `.zip` in `output/downloads/`), and `output_path`.

---

### COMMON NOTES FOR WSL / WINDOWS USERS:
1. Ensure scripts have Unix line endings (`LF`, not `CRLF`). If edited on Windows, run:
   `sed -i 's/\r$//' script_name.sh`
2. Both scripts generate unique run IDs (`RUN_ID`) using process IDs and timestamps, 
   making them fully safe for concurrent parallel execution without file contention.
================================================================================