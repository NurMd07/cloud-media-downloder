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

app.get('/stream-logs', (req, res) => {
	// SSE Headers
	res.writeHead(200, {
		'Content-Type': 'text/event-stream',
		'Cache-Control': 'no-cache',
		'Connection': 'keep-alive',
	});

	// Helper to send data
	const sendLog = (data) => {
		res.write(`data: ${JSON.stringify({ message: data.trim() })}\n\n`);
	};

	// 1. Initial State: Track the size
	let fileSize = fs.existsSync(LOG_FILE) ? fs.statSync(LOG_FILE).size : 0;
	if (fileSize <= 0) {
		fs.writeFileSync(LOG_FILE, '');
	}
	const stream = fs.createReadStream(LOG_FILE);

	stream.on('data', (chunk) => {
		const lines = chunk.toString().split('\n');
		lines.forEach(line => {
			if (line.trim()) sendLog(line);
		});
	});
	// 2. Use Chokidar with 'usePolling' enabled (works everywhere)
	const watcher = chokidar.watch(LOG_FILE, {
		persistent: true,
		usePolling: true,
		interval: 100, // Check every 100ms
	});

	watcher.on('change', (path) => {
		const stats = fs.statSync(path);

		if (stats.size > fileSize) {
			// Read only the NEW bytes
			const stream = fs.createReadStream(path, {
				start: fileSize,
				end: stats.size
			});

			stream.on('data', (chunk) => {
				const lines = chunk.toString().split('\n');
				lines.forEach(line => {
					if (line.trim()) sendLog(line);
				});
			});

			fileSize = stats.size;
		} else if (stats.size < fileSize) {
			// File was truncated or cleared
			fileSize = stats.size;
		}
	});

	// Keep connection alive with a heartbeat every 30s
	const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), 30000);

	req.on('close', () => {
		clearInterval(heartbeat);
		watcher.close();

	});
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
