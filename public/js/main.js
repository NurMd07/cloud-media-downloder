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
    console.log(sidebar.scrollTop);

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
			
				console.log('Disk Info:', disk); // Log the disk info to the console for debugging
			const storage = document.createElement('div');
			storage.classList.add('storage');

			const storageName = document.createElement('span');
			storageName.classList.add('storage-name');

			storageName.textContent = disk.mount.split('/').pop()===""?"Root":disk.mount.split('/').pop();
			
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
	if (!url || !name) {

		if (!url && !name) {
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-error';
			statusElement.innerHTML = 'Please enter both a valid Google Drive URL and a file name';

		} else if (!url) {
			urlInput.className = 'urlInput-error';
			nameInput.className = 'nameInput-success';
			statusElement.innerHTML = 'Please enter a valid Google Drive URL';
		} else if (!name) {
			nameInput.className = 'nameInput-error';
			urlInput.className = 'urlInput-success';
			statusElement.innerHTML = 'Please enter a file name';
		}

		return;

	} else if (!googleDriveFileRegex.test(url)) {
		statusElement.innerHTML = 'Please enter a valid Google Drive URL';
		urlInput.className = 'urlInput-error';
		nameInput.className = 'nameInput-error';
		return;
	}
	urlInput.className = 'urlInput-success';
	nameInput.className = 'nameInput-success';
	downloadButton.classList.add('disabled');
	loader.classList.remove('hidden');

	let category = document.querySelector('input[name="category"]:checked').value;

	fetch('/download', {
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




