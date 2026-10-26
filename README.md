# Cloud Media Downloader

An automated media downloader and organizer with a web interface. It supports Google Drive links, direct media URLs, and BitTorrent magnet links, then uses FileBot to organize downloaded content as movies, TV series, or anime.

## Features

- Google Drive downloads with `gdown`
- Direct URL downloads accelerated by `aria2c`
- Magnet downloads managed by `qbittorrent-nox`
- ZIP extraction and media organization with FileBot
- Web interface for queueing and tracking downloads
- CLI workflow through the included Bash scripts

## Requirements

The application and download scripts are intended for Linux (Ubuntu/Debian instructions are below).

### Required for the web app

- Node.js **20.19 or newer** and npm

### Required for every download mode

- FileBot, available as the `filebot` command
- Java runtime compatible with your FileBot build; OpenJDK 11 is the requested runtime for this setup
- `unzip`

### Required by download mode

- Google Drive: `gdown` and Python 3
- Direct URL: `aria2c`
- Magnet: `qbittorrent-nox`, `curl`, and Python 3

Install the FileBot build you are authorized to use and follow its Linux installation instructions. The [FB-Mod project](https://github.com/barry-allen07/FB-Mod) is the referenced FileBot distribution; follow that project's documentation for its installation and compatibility requirements. Make sure the `filebot` executable is on `PATH`. FileBot builds can require different Java versions, so verify the selected build works with Java 11 before using it.

## Installation (Ubuntu/Debian)

### 1. Install system packages

```bash
sudo apt update
sudo apt install -y git curl aria2 qbittorrent-nox openjdk-11-jre unzip python3 pipx nodejs npm
```

The Node.js package in some Ubuntu/Debian releases is older than this project's minimum. If so, install Node.js 20.19 or newer and npm from a trusted Node.js package source. Check the versions before continuing:

```bash
node --version
npm --version
java -version
```

### 2. Install gdown

`gdown` is only needed for the Google Drive mode. Install it with `pipx` so it does not interfere with system Python packages:

```bash
pipx ensurepath
pipx install gdown
```

Open a new shell if needed so the `pipx` application directory is on `PATH`, then verify:

```bash
gdown --version
```

### 3. Install FileBot

Install FileBot using the instructions for the FileBot distribution you chose. For the referenced [FB-Mod project](https://github.com/barry-allen07/FB-Mod), use its own Linux installation instructions and confirm its Java compatibility. Verify that both commands are available:

```bash
filebot -version
java -version
```

### 4. Configure qBittorrent-nox (magnet downloads)

Run qBittorrent once interactively to initialize its configuration:

```bash
qbittorrent-nox
```

Open [http://localhost:8080](http://localhost:8080) on the same machine. In the WebUI settings:

1. If prompted, use the temporary password printed by `qbittorrent-nox` in the terminal, then set the WebUI username to `admin` and password to `adminadmin`.
2. Enable **Bypass authentication for clients on localhost** (only on a trusted host).
3. In the connection settings, enable **UPnP / NAT-PMP**.
4. Keep the WebUI bound to localhost and do not expose port `8080` to the public internet.

Stop the foreground process after configuration with `Ctrl+C`. The downloader starts `qbittorrent-nox` when needed. The script defaults to `http://127.0.0.1:8080`, username `admin`, and password `adminadmin`; if you choose different credentials or a different WebUI URL, set `QB_USER`, `QB_PASS`, and/or `QB_URL` in the environment where the app runs.

### 5. Get the project and install Node dependencies

```bash
git clone https://github.com/NurMd07/gdrive-media-downloder.git
cd gdrive-media-downloder
npm install
```

### 6. Start the web app

```bash
node app.js
```

Open [http://localhost:8000](http://localhost:8000). Keep the terminal or service running while using the web app.

## CLI usage

The downloader script is `src/tvseries_downloader.sh`. Each download requires a media type (`tv`, `movie`, or `anime`), a name, and a link:

```bash
# Google Drive
./src/tvseries_downloader.sh -g -t anime -n "Example Series" \
  -l "https://drive.google.com/file/d/FILE_ID/view"

# Direct media URL
./src/tvseries_downloader.sh -s -t movie -n "Example Movie" \
  -l "https://example.com/movie.mkv"

# Magnet link
./src/tvseries_downloader.sh -m -t tv -n "Example Show" \
  -l "magnet:?xt=urn:btih:INFO_HASH"
```

Use `./src/tvseries_downloader.sh --help` for all options, including browser-cookie support and job cancellation.

## Configuration

The web app accepts these optional environment variables:

- `PORT`: web server port (default: `8000`)
- `COOKIES`: whether to use browser cookies for Google Drive downloads
- `BROWSER`: browser to read cookies from
- `QB_URL`, `QB_USER`, `QB_PASS`: qBittorrent WebUI connection settings

Downloads default to the project's `output/` directory. The CLI can take a custom output directory with `-o`.

## Troubleshooting

- **A command is reported missing:** install the dependency required by the selected mode and confirm it is on `PATH`. FileBot, Java, and `unzip` are required for every mode.
- **FileBot fails to start:** check `java -version` and confirm the Java runtime is supported by the installed FileBot build.
- **Google Drive download fails:** confirm `gdown` is installed and that the link is accessible. For restricted links, try the CLI cookie options.
- **Magnet download cannot connect:** check that `qbittorrent-nox` is running and that its WebUI URL and credentials match `QB_URL`, `QB_USER`, and `QB_PASS`.
