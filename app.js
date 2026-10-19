import express from "express";
import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JSONFilePreset } from 'lowdb/node';
import { spawn } from "child_process";
import fs from "fs";
import chokidar from 'chokidar';
import si from 'systeminformation';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const port = process.env.PORT || 8000;

const db = await JSONFilePreset('db.json', []);
await db.read();
await db.write();

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));
app.use(express.static(path.join(__dirname, "public")));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());


async function getStorageInfo() {
    const disks = await si.fsSize();

    const result = disks
        .sort((a, b) => b.size - a.size)
        .slice(0, 3)
        .filter(name=> name.mount !== '/media')
        .map(disk => ({
            mount: disk.mount,
            filesystem: disk.fs,
            totalGB: +(disk.size / 1024 ** 3).toFixed(2),
            usedGB: +(disk.used / 1024 ** 3).toFixed(2),
            freeGB: +((disk.size - disk.used) / 1024 ** 3).toFixed(2),
            usagePercent: disk.use
        }));

  
    return result;
}

app.get("/", (req, res) => {
	res.render("index");
});

const googleDriveFileRegex =
	/^https?:\/\/drive\.google\.com\/file\/d\/[^/?#]+(?:\/[^?#]*)?(?:\?[^#]*)?(?:#.*)?$/i;

app.post("/download", async (req, res) => {
	try {
		let { url, override, name, category } = req.body;
		url = url.trim().replace(/\s+/g, '');
		name = name.trim();
		category = category.trim();

		if (!url || !googleDriveFileRegex.test(url) || !name || name.trim() === "") {
			return res.status(400).json({ error: "Invalid Google Drive URL" });
		}

		await db.read();
		const existingEntry = db.data.find(entry => entry.url === url);
		if (existingEntry && existingEntry.status === "pending") {
			return res.status(400).json({ error: "This URL is already in the download queue" });
		} else if (existingEntry && existingEntry.status === "completed" && !override) {
			return res.status(400).json({ error: "This URL has already been downloaded! Click download again to override ⚠️", override: true });
		}
		if (existingEntry && (existingEntry.status === "failed" || existingEntry.status === "completed")) {
			// Remove the existing entry from the database
			db.data = db.data.filter(entry => entry.url !== url);
			await db.write();
		}
		await db.read();
		const lastId = db.data.sort((a, b) => b.id - a.id)[0]?.id || 0;
		
		db.data.push({ id: lastId + 1, url: url, timestamp: new Date().toISOString(), status: "pending", category: category || "tv", name: name });
		await db.write();

		const process = spawn(`${__dirname}/src/tvseries_downloader.sh`, [
			'-i', `${lastId + 1}`,
			'-t', `${category || "tv"}`,
			'-n', `${name}`,
			'-l', `${url}`
		]);

		let jsonOutput = '';

		process.stdout.on('data', (data) => {
			jsonOutput += data.toString();
		});

		process.stderr.on('data', (data) => {
			// data is a Buffer. Convert to string and trim extra newlines so it looks clean
			const logMessage = data.toString().trim();

			// Ignore empty lines
			if (logMessage) {
				fs.appendFile(
					"./downloader.log",
					`${logMessage}\n`,
					(err) => {
						if (err) console.error("Failed to write log:", err);
					}
				);
			}
		});

		process.on('close', async () => {

			const result = JSON.parse(jsonOutput);

			const dbId = parseInt(result.id);
			await db.read();
			if (result.status === "error") {
				console.log(`Task with ID ${dbId} FAILED. Reason: ${result.message}`);

				const entryIndex = db.data.findIndex(entry => entry.id === dbId);
				if (entryIndex !== -1) {
					db.data[entryIndex].status = "failed";
				}
				await db.write();
			} else {
				console.log(`Task with ID ${dbId} SUCCESS. Path: ${result.output_directory || result.output_file}`);

				const entryIndex = db.data.findIndex(entry => entry.id === dbId);
				if (entryIndex !== -1) {
					db.data[entryIndex].status = "completed";
					db.data[entryIndex].output_path = result.output_path;
					db.data[entryIndex].source_path = result.source_path;
				}
				await db.write();
			}
		});

		return res.status(200).json({ message: "Download started" });

	} catch (error) {
		console.error("Error in /download route:", error);
		return res.status(500).json({ error: "Internal Server Error" });
	}

});

app.get("/items", async (req, res) => {
	await db.read();
	res.json(db.data);
});

app.get("/deleteAll", async (req, res) => {
	await db.read();
	db.data = db.data.filter(entry => entry.status === "pending" && entry.timestamp > new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString());
	await db.write();
	console.log("Deleting all files in the download directory...");
	res.json({ message: "Deleting all files in the download directory..." });

});



app.post("/deleteOne", async (req, res) => {
	const { id } = req.body;

	await db.read();
	db.data = db.data.filter(entry => entry.id !== id);

	await db.write();
	res.json({ message: "Deleting one file in the download directory..." });

});

app.get("/clearData", async (req, res) => {
	try {
		fs.rmSync(path.join(__dirname, "output"), {
			recursive: true,
			force: true
		});
	} catch (err) {
		console.error("Error clearing data:", err);
		res.status(500).json({ error: "Failed to clear data" });
		return;
	}
	res.json({ message: "CLeared all data from the output directory" });
});

app.get("/moveData", async (req, res) => {
	try {
		const scriptPath = path.join(__dirname, "src", "move_media.sh");

		const child = spawn("bash", [scriptPath], {
			detached: true,
			stdio: "ignore"
		});

		child.unref();

		res.json({ message: "Moving all completed data to a /media directory..." });
	} catch (err) {
		console.error("Error moving data:", err);
		res.status(500).json({ error: "Failed to move data" });
		return;
	}

});

const LOG_FILE = path.resolve(__dirname, 'downloader.log');


const MAX_LOG_SIZE = 64 * 1024; // 128 KB max before auto-trimming
const KEEP_LOG_SIZE = 32 * 1024; // Keep the newest 64 KB after trimming
let isRotatingLog = false;

function trimLogFileIfNeeded() {
    if (isRotatingLog) return false;
    try {
        if (!fs.existsSync(LOG_FILE)) return false;
        const stats = fs.statSync(LOG_FILE);
        if (stats.size <= MAX_LOG_SIZE) return false;

        isRotatingLog = true;
        const fd = fs.openSync(LOG_FILE, "r");
        const buffer = Buffer.alloc(KEEP_LOG_SIZE);
        const startPos = stats.size - KEEP_LOG_SIZE;

        fs.readSync(fd, buffer, 0, KEEP_LOG_SIZE, startPos);
        fs.closeSync(fd);

        let trimmedContent = buffer.toString("utf8");
        const firstNewline = trimmedContent.indexOf("\n");
        if (firstNewline !== -1) {
            trimmedContent = trimmedContent.slice(firstNewline + 1);
        }

        const header = `--- [SYSTEM] Old logs auto-cleared to keep page fast ---\n`;
        fs.writeFileSync(LOG_FILE, header + trimmedContent, "utf8");
        return true;
    } catch (err) {
        console.error("Error auto-trimming log file:", err);
        return false;
    } finally {
        isRotatingLog = false;
    }
}

app.get("/stream-logs", (req, res) => {
    let watcher = null;
    let heartbeat = null;
    let initialLoadTimer = null;

    try {
        res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        });

        const sendLog = (data) => {
            try {
                const message = data.trim();
                if (message && !res.writableEnded) {
                    res.write(`data: ${JSON.stringify({ message })}\n\n`);
                }
            } catch (err) {
                console.error("SSE write error:", err);
            }
        };

        if (!fs.existsSync(LOG_FILE)) {
            fs.writeFileSync(LOG_FILE, "", "utf8");
        }

        // 1. Trim immediately if the log file is already over 128 KB when opening the page
        trimLogFileIfNeeded();

        let fileSize = fs.statSync(LOG_FILE).size;

        // Helper to read only newly appended bytes during live chokidar updates
        const readNewBytes = (filePath, start, end, onComplete) => {
            if (end <= start || res.writableEnded) {
                if (onComplete) onComplete();
                return;
            }

            const stream = fs.createReadStream(filePath, { start, end: end - 1 });
            let leftover = "";

            stream.on("data", (chunk) => {
                const lines = (leftover + chunk.toString()).split("\n");
                leftover = lines.pop() || "";
                lines.forEach(sendLog);
            });

            stream.on("end", () => {
                if (leftover && !res.writableEnded) sendLog(leftover);
                if (onComplete) onComplete();
            });

            stream.on("error", (err) => {
                console.error("Log stream error:", err);
                if (onComplete) onComplete();
            });
        };

        // 2. Delayed Initial History Load (Gentle batching: 10 lines every 15ms)
        const INITIAL_DELAY_MS = 0;
        initialLoadTimer = setTimeout(() => {
            try {
                if (!res.writableEnded && fs.existsSync(LOG_FILE)) {
                    const content = fs.readFileSync(LOG_FILE, "utf8");
                    fileSize = Buffer.byteLength(content, "utf8");

                    const lines = content.split("\n").map(l => l.trim()).filter(Boolean);
                    // Keep only the last 150 lines on initial load so it opens instantly
                    const recentLines = lines.slice(-150);

                    let index = 0;
                    const batchSize = 10; // Push 10 lines at a time

                    const sendBatch = () => {
                        if (res.writableEnded || index >= recentLines.length) return;

                        const batch = recentLines.slice(index, index + batchSize);
                        batch.forEach(sendLog);
                        index += batchSize;

                        setTimeout(sendBatch, 15); // 15ms pause between batches = perfectly smooth
                    };

                    sendBatch();
                }
            } catch (err) {
                console.error("Error reading initial log history:", err);
            }
        }, INITIAL_DELAY_MS);

        // 3. Watch for live changes (Instant delivery + auto-trim if > 128 KB)
        watcher = chokidar.watch(LOG_FILE, {
            persistent: true,
            usePolling: true,
            interval: 150
        });

        watcher.on("change", (filePath) => {
            try {
                if (!fs.existsSync(filePath) || isRotatingLog) return;
                const stats = fs.statSync(filePath);

                if (stats.size > fileSize) {
                    const previousSize = fileSize;
                    fileSize = stats.size;

                    // Stream live updates instantly, then trim if file crossed 128 KB
                    readNewBytes(filePath, previousSize, stats.size, () => {
                        if (stats.size > MAX_LOG_SIZE && trimLogFileIfNeeded()) {
                            fileSize = fs.statSync(filePath).size;
                        }
                    });
                } else if (stats.size < fileSize) {
                    // File was cleared or auto-rotated
                    fileSize = stats.size;
                    if (stats.size === 0) {
                        sendLog("--- [SYSTEM] Logs cleared ---");
                    }
                }
            } catch (err) {
                console.error("Watcher change error:", err);
            }
        });

        watcher.on("error", (err) => {
            console.error("Chokidar error:", err);
        });

        heartbeat = setInterval(() => {
            try {
                if (!res.writableEnded) {
                    res.write(": heartbeat\n\n");
                }
            } catch (err) {
                clearInterval(heartbeat);
            }
        }, 30000);

        req.on("close", () => {
            if (initialLoadTimer) clearTimeout(initialLoadTimer);
            if (heartbeat) clearInterval(heartbeat);
            if (watcher) watcher.close().catch((err) => console.error("Failed to close watcher:", err));
        });
    } catch (err) {
        console.error("Error setting up /stream-logs:", err);
        if (initialLoadTimer) clearTimeout(initialLoadTimer);
        if (heartbeat) clearInterval(heartbeat);
        if (watcher) watcher.close().catch(() => {});
        if (!res.headersSent) {
            res.status(500).json({ error: "Failed to stream logs" });
        }
    }
});

app.get("/clearLog", async (req, res) => {
	try {
		fs.writeFileSync("./downloader.log", "");
		res.json({ message: "Log cleared successfully" });
	} catch (err) {
		console.log(err);
		res.status(500).json({ error: "Failed to clear Logs" });
	}

});

async function deleteFileOrDirectory(filePath, isDirectory = false) {
    if (!filePath) return;

    try {
        if (isDirectory) {
            await fs.promises.rm(filePath, {
                recursive: true,
                force: true
            });
        } else {
            await fs.promises.unlink(filePath);
        }
    } catch (err) {
        if (err.code === 'ENOENT') return;
        throw err;
    }
}
			
app.get("/removeRecent", async (req, res) => {
	await db.read();
	const recentData = db.data.sort((a, b) => b.id - a.id)[0]; // Keep all but the most recent entry
	console.log("Most recent entry:", recentData);
	if (recentData) {
		console.log(recentData);
		switch (recentData.category) {
			case "movie":
				try {
					await deleteFileOrDirectory(recentData.output_path,false);
					await deleteFileOrDirectory(recentData.source_path,false);
					await deleteFileOrDirectory(path.join('/media/Movies', path.basename(recentData.output_path)),false);
					db.data = db.data.filter(entry => entry.id !== recentData.id);
				} catch (err) { console.error("Error deleting movie file:", err); }

				break;
			case "tv":
				try {
					await deleteFileOrDirectory(recentData.output_path, true);
					await deleteFileOrDirectory(recentData.source_path, true);
					await deleteFileOrDirectory(path.join('/media/Shows', path.basename(recentData.output_path)), true);
					db.data = db.data.filter(entry => entry.id !== recentData.id);
				} catch (err) {
					console.error("Error deleting show files:", err);
				}
				break;
			case "anime":
				try {
					await deleteFileOrDirectory(recentData.output_path, true);
					await deleteFileOrDirectory(recentData.source_path, true);
					await deleteFileOrDirectory(path.join('/media/Anime', path.basename(recentData.output_path)), true);
					db.data = db.data.filter(entry => entry.id !== recentData.id);
				} catch (err) {
					console.error("Error deleting anime files:", err);
				}
				break;
		}
	}
	await db.write();
	res.json({ message: "Removed the most recent entry from the database" });
});


app.get("/getStorageInfo", async (req, res) => {
    try {
        const storageInfo = await getStorageInfo();
        res.json(storageInfo);
    } catch (error) {
        console.error("Error fetching storage info:", error);
        res.status(500).json({ error: "Failed to fetch storage info" });
    }
});

app.listen(port, () => {
	console.log(`Server running at http://localhost:${port}`);
});
