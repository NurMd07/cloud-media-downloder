const downloadButton = document.getElementById('downloadButton');
const urlInput = document.getElementById('urlInput');
const statusElement = document.getElementById('status');
const loader = document.querySelector('.loader');
const nameInput = document.getElementById('nameInput');
const resetButton = document.querySelector('.reset');
const deleteOne = document.querySelector('.deleteone');
const deleteAll = document.querySelector('.deleteall');

const sidebarHeaderMenu = document.querySelector('.side-check');
const itemList = document.querySelector('.sidebar-list');
const clearData = document.querySelector('.cleardata');
const moveData = document.querySelector('.movedata');
const clearLog = document.querySelector('.clearlog');
const logContent = document.querySelector('.log-content');
const sidebar = document.querySelector('.sidebar');
const mainContent = document.querySelector('.main');
const moreOptions = document.querySelector('.more-options');
const moviesLabel = document.querySelector('label[for="movies"]');
const seriesLabel = document.querySelector('label[for="tv-series"]');
const animeLabel = document.querySelector('label[for="anime"]');
const moreOptionsIcon = document.querySelector('.more-options svg');
const moreOptionsIconLeft = document.querySelector('.more-options svg:nth-child(2)');
const removeRecent = document.querySelector('.removerecent');
const logSwitcher = document.querySelector('.log-switcher');
const logContainer = document.querySelector('.options-log');
const optionsContainer = document.querySelector('.options-menu');
const listOutput = document.querySelector('.listoutput');
const modeGdrive = document.querySelector('.mode-gdrive');
const modeSiteDL = document.querySelector('.mode-siteDL');
const modeMagnet = document.querySelector('.mode-magnet');
const headingGdriveSvg = document.querySelector('h1 svg');
const headingMagnetSvg = document.querySelector('h1 svg:nth-child(2)');
const headingSiteDLSvg = document.querySelector('h1 svg:nth-child(3)');
const infoButton = document.querySelector('.info');
const infoContentContainer = document.querySelector('.infoContent-container');
const infoContent = document.querySelector('.infoContent');
const closeInfoContent = document.querySelector('.closeInfoContent');

infoButton.addEventListener('click', () => {
	infoContentContainer.classList.toggle('hidden');
	mainContent.classList.toggle('blurred');
	sidebar.classList.toggle('blurred');
	optionsContainer.classList.toggle('blurred');
});

window.addEventListener('click', (event) => {
	if ( (event.target === infoContentContainer || closeInfoContent.contains(event.target) ) &&  !infoButton.contains(event.target)) {
		infoContentContainer.classList.add('hidden');
		mainContent.classList.remove('blurred');
		sidebar.classList.remove('blurred');
		optionsContainer.classList.remove('blurred');
	}
});

if (localStorage.getItem('mode')) {
	setMode(localStorage.getItem('mode'));
} else {
	setMode('gdrive');
}

function setMode(mode) {
	const title = document.querySelector('.title');
	const urlInput = document.getElementById('urlInput');
	const urlLabel = document.querySelector('label[for="urlInput"]');
	const typeDescription = document.querySelector('.typeDescription');

	const modeGdriveSvg1 = modeGdrive.querySelector('svg');
	const modeGdriveSvg2 = modeGdrive.querySelector('svg:nth-child(2)');
	const modeSiteDLSvg1 = modeSiteDL.querySelector('svg');
	const modeSiteDLSvg2 = modeSiteDL.querySelector('svg:nth-child(2)');
	const modeMagnetSvg1 = modeMagnet.querySelector('svg');
	const modeMagnetSvg2 = modeMagnet.querySelector('svg:nth-child(2)');

	if (mode === 'gdrive') {
		title.textContent = 'GDrive Media Downloader';
		urlLabel.textContent = 'Google Drive URL:';
		urlInput.placeholder = 'Enter Google Drive URL';
		typeDescription.textContent = '(Only ZIP and Media files are supported)';

		headingGdriveSvg.classList.remove('hidden');
		headingMagnetSvg.classList.add('hidden');
		headingSiteDLSvg.classList.add('hidden');

		modeGdrive.classList.add('selected');
		modeSiteDL.classList.remove('selected');
		modeMagnet.classList.remove('selected');
		modeGdriveSvg1.classList.add('hidden');
		modeGdriveSvg2.classList.remove('hidden');
		modeSiteDLSvg1.classList.remove('hidden');
		modeSiteDLSvg2.classList.add('hidden');
		modeMagnetSvg1.classList.remove('hidden');
		modeMagnetSvg2.classList.add('hidden');

	} else if (mode === 'siteDL') {
		title.textContent = 'Direct Media Downloader';
		urlLabel.textContent = 'Direct URL:';
		urlInput.placeholder = 'Enter direct Download URL';
		typeDescription.textContent = '(Only ZIP and Media files are supported)';

		headingGdriveSvg.classList.add('hidden');
		headingMagnetSvg.classList.add('hidden');
		headingSiteDLSvg.classList.remove('hidden');

		modeGdrive.classList.remove('selected');
		modeSiteDL.classList.add('selected');
		modeMagnet.classList.remove('selected');
		modeGdriveSvg1.classList.remove('hidden');
		modeGdriveSvg2.classList.add('hidden');
		modeSiteDLSvg1.classList.add('hidden');
		modeSiteDLSvg2.classList.remove('hidden');
		modeMagnetSvg1.classList.remove('hidden');
		modeMagnetSvg2.classList.add('hidden');

	} else if (mode === 'magnet') {
		title.textContent = 'Torrent Media Downloader';
		urlLabel.textContent = 'Magnet Link:';
		urlInput.placeholder = 'Enter Magnet Link';
		typeDescription.textContent = '(Only Media files are supported)';

		headingGdriveSvg.classList.add('hidden');
		headingMagnetSvg.classList.remove('hidden');
		headingSiteDLSvg.classList.add('hidden');

		modeGdrive.classList.remove('selected');
		modeSiteDL.classList.remove('selected');
		modeMagnet.classList.add('selected');
		modeGdriveSvg1.classList.remove('hidden');
		modeGdriveSvg2.classList.add('hidden');
		modeSiteDLSvg1.classList.remove('hidden');
		modeSiteDLSvg2.classList.add('hidden');
		modeMagnetSvg1.classList.add('hidden');
		modeMagnetSvg2.classList.remove('hidden');
	}

}


modeGdrive.addEventListener('click', () => {
	setMode('gdrive');
	localStorage.setItem('mode', 'gdrive');
	sidebarHeaderMenu.click();
});


modeSiteDL.addEventListener('click', () => {
	setMode('siteDL');
	localStorage.setItem('mode', 'siteDL');
	sidebarHeaderMenu.click();
});

modeMagnet.addEventListener('click', () => {
	setMode('magnet');
	localStorage.setItem('mode', 'magnet');
	sidebarHeaderMenu.click();
});

listOutput.addEventListener('click', async function () {

	fetch('/listDir', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	}).then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
				sidebarHeaderMenu.click();
			} else {
				if (window.innerWidth < 768) {
					logContainer.classList.toggle('show');
					optionsContainer.classList.toggle('hide');
				}

			}

		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';
			sidebarHeaderMenu.click();
		})


})

logSwitcher.addEventListener('click', function () {

	logContainer.classList.toggle('show');

	optionsContainer.classList.toggle('hide');

});



removeRecent.addEventListener('click', function () {
	fetch('/removeRecent', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	}).then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
			} else {
				statusElement.innerHTML = ' ✓&nbsp;&nbsp;Recent item removed successfully';
			}
			fetchItems();
		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';
			fetchItems();
		})
});
moreOptions.addEventListener('click', () => {

	moreOptionsIcon.classList.toggle('hidden');
	moreOptionsIconLeft.classList.toggle('hidden');

	seriesLabel.classList.toggle('hidden');
	moviesLabel.classList.toggle('hidden');

	animeLabel.classList.toggle('hidden');
});


let scrollTimeout;
let isFirstScroll = true;


sidebar.addEventListener('scroll', () => {

	if (sidebar.scrollTop > 0 && !sidebar.classList.contains('expanded')) {
		sidebar.classList.add('expanded');

		isFirstScroll = true;
	} else if (sidebar.scrollTop === 0 && sidebar.classList.contains('expanded') && !isFirstScroll) {
		sidebar.classList.remove('expanded');
		isFirstScroll = false;
	}

});

let touchStartY = 0;

sidebar.addEventListener('touchstart', (e) => {
	touchStartY = e.touches[0].clientY;
}, { passive: true });

sidebar.addEventListener('touchmove', (e) => {
	const currentY = e.touches[0].clientY;
	const deltaY = currentY - touchStartY;

	if (
		sidebar.classList.contains('expanded') &&
		sidebar.scrollTop === 0 &&
		deltaY > 1
	) {
		e.preventDefault();
	}
}, { passive: false });



sidebar.addEventListener('touchend', (e) => {
	const deltaY = e.changedTouches[0].clientY - touchStartY;

	if (
		sidebar.classList.contains('expanded') &&
		sidebar.scrollTop === 0 &&
		deltaY > 50
	) {
		sidebar.classList.remove('expanded');
		isFirstScroll = false;
	}
}, { passive: true });

let clearState = false;

function updateItemList(items) {

	items = items.sort((a, b) => b.id - a.id);
	items.forEach(item => {

		const li = document.createElement('li');
		li.classList.add('item');

		li.innerHTML = `
      <span class="item-id">${item.id}</span>
        <span class="item-name">📛 Name: <span id="nameDisplay"> ${item.name}</span></span>
         <span class="item-category">🎬 Category: <span id="categoryDisplay"> ${item.category}</span></span>
         <span class="item-timestamp">⌚ Added on: <span id="timestampDisplay"> ${new Date(item.timestamp).toLocaleString("en-US", {
			day: "2-digit",
			month: "short",
			hour: "numeric",
			minute: "2-digit",
			hour12: true
		})}</span></span>
         <span class="item-status">📥 Status: <span id="statusDisplay"> ${item.status.toUpperCase()}</span></span>
         <span class="item-url">🔗 URL: <span id="urlDisplay"> ${item.url}</span></span>
         <span class="item-output-path">📂 Output Path: <span id="outputPathDisplay"> ${'~/output/' + (item.output_path ? item.output_path.split('/output/')[1] : '')}</span></span>
         <span class="item-source-path">🗂️ Source Path: <span id="sourcePathDisplay"> ${'~/output/' + (item.source_path ? item.source_path.split('/output/')[1] : '')}</span></span>
 

	`;


		itemList.appendChild(li);
	});
}

function fetchItems() {
	itemList.innerHTML = ''; // Clear the existing list before fetching new items
	fetch('/items', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {

			// Update the UI with the fetched items
			updateItemList(data);

		}).catch(error => {
			console.error('Error fetching items:', error);
		});

}


const storageInfoContainer = document.querySelector('.storageinfo');

function fetchStorageInfo() {
	fetch('/getStorageInfo', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {
			storageInfoContainer.innerHTML = ''; // Clear the existing storage info before fetching new data
			data.forEach(disk => {


				const storage = document.createElement('div');
				storage.classList.add('storage');

				const storageName = document.createElement('span');
				storageName.classList.add('storage-name');

				storageName.textContent = disk.mount.split('/').pop() === "" ? "Root" : disk.mount.split('/').pop();

				storage.appendChild(storageName);

				const storagePath = document.createElement('span');
				storagePath.classList.add('storage-path');
				storagePath.textContent = disk.mount;

				storage.appendChild(storagePath);

				const storageProgress = document.createElement('div');
				storageProgress.classList.add('storage-progress');
				const progressBar = document.createElement('progress');
				progressBar.max = 100;
				progressBar.value = disk.usagePercent;
				storageProgress.appendChild(progressBar);

				storage.appendChild(storageProgress);

				const storageSubinfo = document.createElement('div');
				storageSubinfo.classList.add('storage-subinfo');
				const storageUsagePercentage = document.createElement('span');
				storageUsagePercentage.classList.add('storage-usage-percentage');
				const storageUsage = document.createElement('span');
				storageUsage.classList.add('storage-usage');
				storageUsagePercentage.textContent = `${disk.usagePercent.toFixed(2)}%`;
				storageUsage.textContent = `${disk.usedGB.toFixed(2)} GB / ${disk.totalGB.toFixed(2)} GB`;
				storageSubinfo.appendChild(storageUsagePercentage);
				storageSubinfo.appendChild(storageUsage);
				storage.appendChild(storageSubinfo);

				storageInfoContainer.appendChild(storage);
			});
		}).catch(error => {
			console.error('Error fetching storage info:', error);
		});
}

fetchItems();
fetchStorageInfo();

window.setInterval(fetchItems, 15000); // Fetch items every 5 seconds
window.setInterval(fetchStorageInfo, 30000); // Fetch storage info every 30 seconds	

function waitForItemClick() {
	return new Promise((resolve) => {
		function handleClick(e) {

			const item = e.target.closest(".item");

			if (!clearState) {
				resolve(null);
				return;
			} else if (!item) {

				if (e.target.classList.contains("side-check")) {
					resolve(null);
					return;
				}

				e.stopPropagation();
				e.preventDefault();
				return;

			}

			const value = item.querySelector("span").textContent.trim();

			window.removeEventListener("click", handleClick);

			resolve(value);
		}

		window.addEventListener("click", handleClick);
	});
}

deleteOne.addEventListener('click', async function () {

	clearState = !clearState;
	if (!clearState) {
		statusElement.innerHTML = ' ';
		deleteOne.classList.remove('deleteone-active');
		deleteAll.classList.remove("disabled");
		clearLog.classList.remove("disabled");
		clearData.classList.remove("disabled");
		moveData.classList.remove("disabled");

		return;
	}
	deleteAll.classList.add("disabled");
	clearLog.classList.add("disabled");
	deleteOne.classList.add('deleteone-active');
	clearData.classList.add("disabled");
	moveData.classList.add("disabled");

	const value = await waitForItemClick();

	clearState = false;

	deleteAll.classList.remove("disabled");
	clearLog.classList.remove("disabled");
	deleteOne.classList.remove('deleteone-active');
	clearData.classList.remove("disabled");
	moveData.classList.remove("disabled");



	if (!value) {
		clearState = false;
		return;
	}

	fetch('/deleteOne', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({ id: parseInt(value) })
	})
		.then(response => response.json())

		.then(data => {
			fetchItems();
			if (data.error) {
				statusElement.innerHTML = data.error;
			} else {
				statusElement.innerHTML = ' ✓&nbsp;&nbsp;File deleted successfully';
				sidebarHeaderMenu.click();
			}
		}).catch(error => {
			fetchItems();
			statusElement.innerHTML = 'An error occurred. Please try again.';
		})

});

deleteAll.addEventListener('click', function (e) {

	fetch('/deleteAll', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
			} else {
				statusElement.innerHTML = ' ✓&nbsp;&nbsp;All files deleted successfully';
			}
			fetchItems();
		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';
			fetchItems();
		})

	sidebarHeaderMenu.click();
});


clearData.addEventListener('click', function () {
	fetch('/clearData', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
			}
			statusElement.innerHTML = ' ✓&nbsp;&nbsp;All data cleared successfully&nbsp; ( ~/output )';
			fetchItems();
		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';
			fetchItems();
		})
	sidebarHeaderMenu.click();
});

moveData.addEventListener('click', function () {
	fetch('/moveData', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
			}
			statusElement.innerHTML = ' ✓&nbsp;&nbsp;All data moved successfully&nbsp; ( to /media )';
			fetchItems();
		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';
			fetchItems();
		})
	sidebarHeaderMenu.click();
});


clearLog.addEventListener('click', function () {
	fetch('/clearLog', {
		method: 'GET',
		headers: {
			'Content-Type': 'application/json'
		}
	})
		.then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
			}
			logContent.innerHTML = "";
			statusElement.innerHTML = ' ✓&nbsp;&nbsp;Log cleared successfully';
		}).catch(error => {
			statusElement.innerHTML = 'An error occurred. Please try again.';

		})

});

resetButton.addEventListener('click', function () {
	urlInput.value = '';
	nameInput.value = '';
	statusElement.innerHTML = ' ';
	urlInput.className = '';
	nameInput.className = '';
	loader.classList.add('hidden');
	downloadButton.classList.remove('disabled');
	resetButton.classList.add('hidden');
});

const googleDriveFileRegex =
	/^https?:\/\/drive\.google\.com\/file\/d\/[^/?#]+(?:\/[^?#]*)?(?:\?[^#]*)?(?:#.*)?$/i;

const magnetLinkRegex =
	/^magnet:\?(?=[^#\s]*\bxt=urn:btih:[a-z0-9]{32,40}(?:&|#|$))[^#\s]+(?:#.*)?$/i;

const mediaFileRegex =
	/^https?:\/\/[^\s?#]+\.(?:mkv|mp4|zip)(?:\?[^#]*)?(?:#.*)?$/i;

let overrideConfirmation = false;

urlInput.addEventListener('input', function () {
	resetButton.classList.remove('hidden');
	downloadButton.classList.remove('disabled');
	urlInput.className = '';
	nameInput.className = '';
	statusElement.innerHTML = '';
	overrideConfirmation = false;
});
nameInput.addEventListener('input', function () {
	resetButton.classList.remove('hidden');
	downloadButton.classList.remove('disabled');
});

downloadButton.addEventListener('click', function () {
	const url = urlInput.value;
	const name = nameInput.value;
	const mode = localStorage.getItem('mode');

	if (!url || !name) {

		if (!url && !name) {
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			if (mode === 'gdrive') {
				statusElement.innerHTML = 'Please enter both a valid Google Drive URL and a file name';
			} else if (mode === 'siteDL') {
				statusElement.innerHTML = 'Please enter both a valid direct download URL and a file name';
			} else {
				statusElement.innerHTML = 'Please enter both a valid Magnet Link and a file name';
			}
		} else if (!url) {
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-success';
			if (mode === 'gdrive') {
				statusElement.innerHTML = 'Please enter a valid Google Drive URL';
			} else if (mode === 'siteDL') {
				statusElement.innerHTML = 'Please enter a valid direct download URL (ZIP or Media file)';
			} else {
				statusElement.innerHTML = 'Please enter a valid Magnet Link';
			}
		} else if (!name) {
			nameInput.className = 'nameInput-error';
			urlInput.className = 'urlInput-success';
			statusElement.innerHTML = 'Please enter a file name';
		}

		return;

	}

	if (mode === 'gdrive') {
		if ((!googleDriveFileRegex.test(url))) {
			statusElement.innerHTML = 'Please enter a valid Google Drive URL';
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			return;
		}
	} else if (mode === 'siteDL') {
		if ((!mediaFileRegex.test(url))) {
			statusElement.innerHTML = 'Please enter a valid direct download URL (ZIP or Media file)';
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			return;
		}
	} else {
		if ((!magnetLinkRegex.test(url))) {
			statusElement.innerHTML = 'Please enter a valid Magnet Link';
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			return;
		}
	}


	urlInput.className = 'urlInput-success';
	nameInput.className = 'nameInput-success';
	downloadButton.classList.add('disabled');
	loader.classList.remove('hidden');

	let category = document.querySelector('input[name="category"]:checked').value;

	fetch(`/download/${mode}`, {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({ url: url.trim().replace(/\s+/g, ''), override: overrideConfirmation, category: category, name: name.trim() })
	})
		.then(response => response.json())
		.then(data => {
			if (data.error) {
				statusElement.innerHTML = data.error;
				urlInput.className = 'urlInput-error';
				nameInput.className = 'nameInput-error';
				loader.classList.add('hidden');
				downloadButton.classList.remove('disabled');
				if (data.override) {
					overrideConfirmation = true;
				}
			} else {
				statusElement.innerHTML = ' ✓&nbsp;&nbsp;Download started';
				loader.classList.add('hidden');
			}
			fetchItems()
		})
		.catch(error => {

			statusElement.innerHTML = 'An error occurred. Please try again.';
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			loader.classList.add('hidden');
			downloadButton.classList.remove('disabled');
			fetchItems()
		});



});

const eventSource = new EventSource(`/stream-logs`);

eventSource.onmessage = (event) => {

	const data = JSON.parse(event.data);


	const timestamp = `[${new Date().toLocaleString("en-GB", {
		day: "2-digit",
		month: "short",
		hour: "numeric",
		minute: "2-digit",
		hour12: false
	}).replace(",", "")}]`;
	;

	logContent.innerHTML += `<div class="log-line"><span class="log-timestamp">${timestamp}</span><span> ${data.message}</span></div>\n`;

	logContent.scrollTop = logContent.scrollHeight;
};

eventSource.onerror = (err) => {
	console.error("SSE failed:", err);
	eventSource.close();
};




