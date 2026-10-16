import express from "express";
import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JSONFilePreset } from 'lowdb/node';
import { spawn } from "child_process";
import fs from "fs";
import chokidar from 'chokidar';

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

// app.get('/stream-logs', (req, res) => {

// 	// SSE Headers
// 	res.writeHead(200, {
// 		'Content-Type': 'text/event-stream',
// 		'Cache-Control': 'no-cache',
// 		'Connection': 'keep-alive',
// 	});

// 	const sendLog = (data) => {
//     const message = data.trim();
//     if (message) {
//         res.write(`data: ${JSON.stringify({ message })}\n\n`);
//     }
// };

// let fileSize = 0;

// try {
//     if (!fs.existsSync(LOG_FILE)) {
//         fs.writeFileSync(LOG_FILE, '');
//     }

//     fileSize = fs.statSync(LOG_FILE).size;
// } catch (err) {
//     console.error('Log file initialization error:', err);
//     return res.end();
// }

// const readNewBytes = (path, start, end) => {
//     if (end <= start) return;

//     const stream = fs.createReadStream(path, {
//         start,
//         end: end - 1
//     });

//     stream.on('data', (chunk) => {
//         chunk.toString().split('\n').forEach(sendLog);
//     });

//     stream.on('error', (err) => {
//         console.error('Log stream error:', err);
//     });
// };

// const watcher = chokidar.watch(LOG_FILE, {
//     persistent: true,
//     usePolling: true,
//     interval: 100
// });

// watcher.on('change', (path) => {
//     try {
//         const stats = fs.statSync(path);

//         if (stats.size > fileSize) {
//             const previousSize = fileSize;
//             fileSize = stats.size;
//             readNewBytes(path, previousSize, stats.size);
//         } else if (stats.size < fileSize) {
//             fileSize = stats.size;
//         }
//     } catch (err) {
//         console.error('Log watcher error:', err);
//     }
// });

// watcher.on('error', (err) => {
//     console.error('Chokidar error:', err);
// });

// req.on('close', () => {
//     watcher.close();
// });
// });

const MAX_LOG_SIZE = 256 * 1024; // 256 KB max file size before trimming
const KEEP_LOG_SIZE = 64 * 1024; // Retain newest 64 KB after trimming
let isRotatingLog = false;

function trimLogFileIfNeeded() {
    if (isRotatingLog) return;
    try {
        if (!fs.existsSync(LOG_FILE)) return;
        const stats = fs.statSync(LOG_FILE);
        if (stats.size <= MAX_LOG_SIZE) return;

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
    } catch (err) {
        console.error("Error auto-trimming log file:", err);
    } finally {
        isRotatingLog = false;
    }
}

function appendAndRotateLog(logMessage) {
    try {
        fs.appendFile(LOG_FILE, `${logMessage}\n`, (err) => {
            if (err) {
                console.error("Failed to write log:", err);
                return;
            }
            if (!isRotatingLog) {
                fs.stat(LOG_FILE, (statErr, stats) => {
                    if (!statErr && stats && stats.size > MAX_LOG_SIZE) {
                        trimLogFileIfNeeded();
                    }
                });
            }
        });
    } catch (err) {
        console.error("Unexpected error in appendAndRotateLog:", err);
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

        // Trim immediately if the log file is already heavy when opening the page
        trimLogFileIfNeeded();

        let fileSize = fs.statSync(LOG_FILE).size;

        const readNewBytes = (filePath, start, end) => {
            if (end <= start || res.writableEnded) return;

            const stream = fs.createReadStream(filePath, {
                start,
                end: end - 1
            });

            let leftover = "";

            stream.on("data", (chunk) => {
                const lines = (leftover + chunk.toString()).split("\n");
                leftover = lines.pop() || "";
                lines.forEach(sendLog);
            });

            stream.on("end", () => {
                if (leftover) sendLog(leftover);
            });

            stream.on("error", (err) => {
                console.error("Log stream error:", err);
            });
        };

        // Delay initial history load by 600ms so the browser UI renders without freezing
        const INITIAL_DELAY_MS = 600;
        initialLoadTimer = setTimeout(() => {
            try {
                if (!res.writableEnded && fs.existsSync(LOG_FILE)) {
                    const currentSize = fs.statSync(LOG_FILE).size;
                    fileSize = currentSize;
                    if (currentSize > 0) {
                        const startByte = Math.max(0, currentSize - KEEP_LOG_SIZE);
                        readNewBytes(LOG_FILE, startByte, currentSize);
                    }
                }
            } catch (err) {
                console.error("Error reading initial log history:", err);
            }
        }, INITIAL_DELAY_MS);

        watcher = chokidar.watch(LOG_FILE, {
            persistent: true,
            usePolling: true,
            interval: 150
        });

        watcher.on("change", (filePath) => {
            try {
                if (!fs.existsSync(filePath)) return;
                const stats = fs.statSync(filePath);

                if (stats.size > fileSize) {
                    readNewBytes(filePath, fileSize, stats.size);
                    fileSize = stats.size;
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

app.listen(port, () => {
	console.log(`Server running at http://localhost:${port}`);
});
