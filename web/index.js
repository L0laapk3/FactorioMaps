"use strict";
let DEBUG = false;
const EXT = ".jpg";



let TILESPERIMAGE = 16;

let COORDSCALE = 2**19 / 16 * window.devicePixelRatio;

//let _getTileUrl = L.TileLayer.prototype.getTileUrl;
//L.TileLayer.prototype.getTileUrl = function(coords) { return _getTileUrl.call(this, {x: coords.x - 1 * Math.pow(2, coords.z - 2), y: coords.y, z: coords.z}); };

L.TileLayer.prototype.getTileUrl = function(c) {
	let mapIndex = this.tileIndex[c.z] && this.tileIndex[c.z][c.y] && this.tileIndex[c.z][c.y][c.x];
	if (isNaN(mapIndex))
		mapIndex = this.tileIndex.fallback;
	if (isNaN(mapIndex))
		return "";
	return "Images/" + mapInfo.maps[mapIndex].path + "/" + this.surface + "/" + this.daytime + "/" + c.z + "/" + c.x + "/" + c.y + EXT;
}

//TODO: iterate over surfaces
//let surface = Object.keys(mapInfo.maps[0].surfaces)[0];


let layers = [], saves = [], countAvailableSaves = 0, layersByTimestamp = [], labels = [];
let globalTileIndex = {};
let globalTileNightIndex = {};
const maxZoomExtra = 2 + Math.round(Math.log2(window.devicePixelRatio));
let globalMaxZoom = NaN;

for (let i = 0; i < mapInfo.maps.length; i++) {
	if (DEBUG) {
		globalTileIndex = {};
		globalTileNightIndex = {};
	}

	let map = mapInfo.maps[i];
	layersByTimestamp[i] = {};

	for (const surface of Object.keys(map.surfaces)) {
		let layer = map.surfaces[surface];


		if (!layer.captured)
			continue;

		if (!(surface in layers))
			layers[surface] = {};
		layers[surface][i] = {};

		TILESPERIMAGE = layer.zoom.max == 20 ? 16 : 8;

		if (!globalTileNightIndex[surface]) {
			globalTileNightIndex[surface] = layer.chunks ? {} : {fallback: i};
			globalTileIndex[surface] = layer.chunks ? {} : {fallback: i};
		}
		for (let z = layer.zoom.min; z <= layer.zoom.max; z++)
			if (!globalTileNightIndex[surface][z]) {
				globalTileNightIndex[surface][z] = {};
				globalTileIndex[surface][z] = {};
			}
		(layer.chunks || "").split('=').forEach(function(row) {
			function B64Parse(offset) {
				return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(row[offset])
				+ 64 * "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(row[offset+1])
				+64*64*"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(row[offset+2])
				- 2**16;
			}

			console.assert(row.length % 3 == 0); //corrupted data, prevent infinite loop
			let j = 3, y = B64Parse(0) - 2**17;

			if (!globalTileNightIndex[surface][layer.zoom.max][y]){
				globalTileNightIndex[surface][layer.zoom.max][y] = {};
				globalTileIndex[surface][layer.zoom.max][y] = {};
			}
			while (j < row.length) {
				let stop = B64Parse(j + 3)
				let start = B64Parse(j);
				let mode = start > 2**16;
				for (let x = start - mode*2**17; x < (stop - (stop>2**16)*2**17); x++) {
					globalTileNightIndex[surface][layer.zoom.max][y][x] = i;
					if (mode)
						globalTileIndex[surface][layer.zoom.max][y][x] = i;
					for (let z = 1; z <= layer.zoom.max - layer.zoom.min; z++)  {
						if (!globalTileNightIndex[surface][layer.zoom.max-z][y >> z]) {
							globalTileNightIndex[surface][layer.zoom.max-z][y >> z] = {};
							globalTileIndex[surface][layer.zoom.max-z][y >> z] = {};
						}
						if ((mode ? globalTileIndex : globalTileNightIndex)[surface][layer.zoom.max-z][y >> z][x >> z] == i)
							break;
						globalTileNightIndex[surface][layer.zoom.max-z][y >> z][x >> z] = i;
						if (mode)
							globalTileIndex[surface][layer.zoom.max-z][y >> z][x >> z] = i;
					}
				}
				j += mode == stop > 2**16 ? 6 : 3;
			}
		});

		let tileIndex = { fallback: globalTileIndex[surface].fallback };
		for (const z in globalTileIndex[surface]) {
			if (z == "fallback")
				continue;
			tileIndex[z] = {};
			for (const y in globalTileIndex[surface][z]) {
				tileIndex[z][y] = {};
				for (const x in globalTileIndex[surface][z][y])
					tileIndex[z][y][x] = globalTileIndex[surface][z][y][x];
			}
		}
		let tileNightIndex = { fallback: globalTileNightIndex[surface].fallback };
		for (const z in globalTileNightIndex[surface]) {
			if (z == "fallback")
				continue;
			tileNightIndex[z] = {};
			for (const y in globalTileNightIndex[surface][z]) {
				tileNightIndex[z][y] = {};
				for (const x in globalTileNightIndex[surface][z][y])
					tileNightIndex[z][y][x] = globalTileNightIndex[surface][z][y][x];
			}
		}


		layersByTimestamp[i][surface] = {};
		map.surfaces[surface].layers = {};


		layer.tags.sort((a, b) => a.position.y - b.position.y);
		const mapInfoTimeLayer = Object.values(mapInfo.maps).find(m => m.path == map.path);
		for (const tag of layer.tags) {
			let label = {
				surface: surface,
				path: map.path,
				visible: false,
				marker: L.marker(convertCoordinates(tag.position), {
					icon: new L.DivIcon({
						className: 'map-tag',
						html: 	(tag.iconPath ? '<map-marker><img src="' + tag.iconPath + '"/>' : '<map-marker class="map-marker-default">') +
								'<span>' + tag.text.replaceAll(/</g, "&lt;").replaceAll(/>/g, "&gt;").replaceAll(/\[([^=]+)=([^\]]+)\]/g, (a, type, name) => {
									return '<img src="Images/labels/' + type + "/" + name + '.png">';
								}) + '</span></map-marker>',
						iconSize: null,
					})
				}),
			};

			labels.push(label);
		}


		let maxZOffset = 0;
		for (const link of layer.links) {
			if (link.daynight) {
				if (layer.day)
					createLink(link, "day")
				if (layer.night)
					createLink(link, "night")
			} else
				createLink(link);
		}
		function createLink(link, daytime, recursion, subMarkers) {
			let marker;
			recursion = recursion || [];
			const totalZ = recursion.reduce((p, a) => p + a[1], 0);
			const scale = Math.pow(2, totalZ);
			if (link.type == "link_renderbox_area") {
				let options = { zIndex: recursion.length + 1 }
				if (daytime == "night")
					options.pane = nightOverlayPane;
				marker = L.imageOverlay("", convertCoordinateSet(link.renderFrom, recursion), options );
				marker.zOffset = totalZ + link.zoomDifference;
				if (!(marker.zOffset <= maxZOffset))
					maxZOffset = marker.zOffset;
			} else {
				// TODO: implement as overlay?
				marker = L.marker(convertCoordinates({x: (link.from[0].x+link.from[1].x) / 2, y: (link.from[0].y+link.from[1].y) / 2}, recursion), {
					icon: new L.DivIcon({
						className: 'map-link',
						html: 	'<map-link style="--x:' + (link.from[1].x-link.from[0].x)/scale + ';--y:' + (link.from[1].y-link.from[0].y)/scale + '"/>',
						iconSize: null,
					})
				});
			}
			marker.link = link;

			if (subMarkers) {
				subMarkers.push(marker);
			} else {
				subMarkers = [];
				let label = {
					surface: surface,
					path: map.path,
					visible: false,
					link: link,
					marker: marker,
					subMarkers: subMarkers,
					daytime: daytime
				}

				labels.push(label);
			}

			if (link.type == "link_renderbox_area") {
				recursion = [[link.renderFrom[0], link.zoomDifference, link.to[0]], ...recursion];
				for (let nextIndex of link.chain) {
					createLink(mapInfoTimeLayer.surfaces[link.toSurface].links[nextIndex], daytime, recursion, subMarkers);
				}
			}
		}



		["day", "night"].forEach(function(daytime) {
			if (layer[daytime]) {
				let maxZoom = layer.zoom.max + maxZoomExtra;
				if (!(maxZoom <= globalMaxZoom))
					globalMaxZoom = maxZoom;
				let LLayer = L.tileLayer(undefined, {
					id: layer.path,
					attribution: '<a href="https://github.com/L0laapk3/FactorioMaps">FactorioMaps</a>',
					minNativeZoom: DEBUG ? 20 : layer.zoom.min,
					maxNativeZoom: layer.zoom.max,
					minZoom: layer.zoom.min >= 1 ? layer.zoom.min - 1 : 1,
					maxZoom: maxZoom + maxZOffset,
					noWrap: true,
					tileSize: 512 / window.devicePixelRatio,
					keepBuffer: 99
				});
				LLayer.surface = surface;
				LLayer.daytime = daytime;
				LLayer.path = map.path;
				LLayer.tileIndex = daytime == "day" ? tileIndex : tileNightIndex;


				map.surfaces[surface].layers[daytime] = layersByTimestamp[i][surface][daytime] = layers[surface][i][daytime] = LLayer;
			}
		});



		if (layer.save && layer.save.download) {
			saves.push({
				layer: layer.save.name || layer.name,
				url: layer.save.url
			});
			if (layer.save.url) {
				countAvailableSaves++;
			}
		}



		layers[surface][i].tags = layer.tags;
		layers[surface][i].links = layer.links;
		layers[surface][i].path = map.path;

		// todo: group tags.. ?
		for (const tag in layer.tags) {
			//console.log(tag);
		}

	}
}



document.body.style.setProperty("--devicepixelratio", window.devicePixelRatio);
function updateLabelScaling(e) {
	document.getElementById("map").style.setProperty("--scale", Math.pow(2, e.zoom - 15));
}

let allTimestamps = mapInfo.maps.map(m => m.path.split("-").map(parseFloat));
function updateLabels() {
	let currentTime = timestamp.split("-").map(parseFloat);
	let next = allTimestamps.find(m => m[0] >= currentTime[0] && (m[1] || 0) >= (currentTime[1] || 0)).join("-");
	let previousIndex;
	for (previousIndex = allTimestamps.length - 1; previousIndex >= 0; previousIndex--) {
		const m = allTimestamps[previousIndex];
		if (m[0] <= currentTime[0] && (m[1] || 0) <= (currentTime[1] || 0))
			break;
	}
	let previous = allTimestamps[previousIndex].join("-");

	for (const label of labels) {
		let shouldBeVisible = currentSurface == label.surface
						   && (label.path == next || label.path == previous)
						   && (label.daytime != "night" || nightOpacity > 0)
						   && (label.daytime != "day" || nightOpacity < 1);

		if (shouldBeVisible && !label.visible) {
			for (const marker of [label.marker, ...label.subMarkers || []]) {
				if (label.visible && label.daytime == "night")
					marker.setOpacity(nightOpacity);
				marker.addTo(map);
			}
			if (label.link)
				switch (label.link.type) {
					case "link_box_point":
					case "link_box_area":
						label.marker._icon.onmousedown = function() {
							if (label.link.toSurface != currentSurface)
								Array.from(surfaceSlider._container.children[0].children).find(e => e.innerText == label.link.toSurface).click();

							switch (label.link.type) {
								case "link_box_point":
									if (label.link.toSurface != currentSurface)
										map.panTo(convertCoordinates(label.link.to));
									else
										map.setView(convertCoordinates(label.link.to), map.getZoom());
									break;
								case "link_box_area":
									if (label.link.toSurface != currentSurface)
										map.flyToBounds([convertCoordinates(label.link.to[0]), convertCoordinates(label.link.to[1])]);
									else
										map.fitBounds([convertCoordinates(label.link.to[0]), convertCoordinates(label.link.to[1])], map.getZoom());
									break;
							}
						}
						break;

				}
		} else if (!shouldBeVisible && label.visible)
			for (const marker of [label.marker, ...label.subMarkers || []])
				map.removeLayer(marker);
		else
			continue;
		label.visible = shouldBeVisible;
	}
	updateRenderboxUrls();
	updateRenderboxOpacities(true);
}

function updateRenderboxUrls() {
	for (const label of labels)
		if (label.visible && label.link && label.link.type == "link_renderbox_area")
			for (const marker of [label.marker, ...label.subMarkers || []]) {
				const z = Math.min(marker.link.zoom.max, Math.max(marker.link.zoom.min, map.getZoom() - marker.zOffset));
				if (marker._lastZ != z) {
					marker._lastZ = z;
					marker.setUrl("Images/" + marker.link.path + "/" + marker.link.toSurface + "/" + (marker.link.daynight ? label.daytime : "day") + "/renderboxes/" + z + "/" + marker.link.filename + ".jpg");
				}
			}
}


function convertCoordinates(pos, recursion) {
	recursion = recursion || [];
	for (const [offset, scaleLevel, origin] of recursion) {
		pos = {
			x: (pos.x - origin.x) / Math.pow(2, scaleLevel) + offset.x,
			y: (pos.y - origin.y) / Math.pow(2, scaleLevel) + offset.y,
		}
	}
	return [-pos.y / COORDSCALE, pos.x / COORDSCALE]
}
function convertCoordinateSet(set, recursion) {
	return set.map(p => convertCoordinates(p, recursion));
}





if (countAvailableSaves > 0 || mapInfo.links && mapInfo.links.save) {
	let btn = document.createElement("a"), modal = document.getElementById("modal"), ulContainer = document.getElementById("save-download-container"), modalClose = modal.getElementsByClassName("close")[0], opened = false, built = false;
	btn.id = 'downBtn';
	btn.appendChild(document.createTextNode("Download Save"))
	if (saves.length <= 1) {
		//Act like a download link
		btn.href = saves.length === 1 ? saves[0].url : m.links.save;
		btn.target = '_blank';
	} else {
		btn.addEventListener('click', function () {
			if (!opened) {
				if (!built) {
					//Empty the modal, re-create modal content and display it
					while (ulContainer.lastChild) {
						ulContainer.removeChild(ulContainer.lastChild);
					}
					for (const i in saves) {
						if (saves.hasOwnProperty(i)) {
							let saveObj = saves[i];
							let li = document.createElement("li"), a = document.createElement("a"), span = document.createElement("span"), hr = document.createElement("hr");
							hr.classList.add("clear");
							a.classList.add("mapLayerLink");
							li.classList.add("mapLayer");
							a.appendChild(document.createTextNode("Download"));

							a.target = "_blank";
							if (!saveObj.url) {
								a.setAttribute("disabled", "disabled");
								a.classList.add("disabled");
							} else {
								a.href = saveObj.url;
							}
							span.classList.add("mapLayerName")
							span.appendChild(document.createTextNode(saveObj.layer));
							li.appendChild(span);
							li.appendChild(a);
							li.appendChild(hr);
							ulContainer.appendChild(li);
						}
					}
					modal.classList.add("open");
					opened = true;
				}
			}
		});
		modalClose.addEventListener("click", function () {
			if (opened) {
				modal.classList.remove("open");
				opened = false;
			}
		});
	}
	document.getElementById("buttonAnchor").appendChild(btn);
}

const defaultSurface = mapInfo.defaultSurface || "nauvis";
let nightOpacity = 0;
const defaultMapPath = (mapInfo.options.defaultTimestamp < 0 ? mapInfo.maps.length : 0) + mapInfo.options.defaultTimestamp;
console.assert(0 <= defaultMapPath && defaultMapPath < mapInfo.maps.length, "Default map path is out of bounds.");
const someSurfaces = mapInfo.maps[defaultMapPath].surfaces;
let currentSurface = defaultSurface in someSurfaces ? defaultSurface : Object.keys(someSurfaces).sort()[0]
let loadLayer = someSurfaces[currentSurface].layers;
let timestamp = (loadLayer.day || loadLayer.night).path;

let startZ = 16, startX = NaN, startY = NaN;
try {
	let split = window.location.hash.substr(1).split('/').map(decodeURIComponent);
	if (window.location.hash[0] == '#' && split[0] == "1") {
		currentSurface = split[1];
		loadLayer = someSurfaces[currentSurface].layers;
		if (!isNaN(parseInt(split[2]))) startZ = parseInt(split[2]);
		startX = parseInt(split[3]) / COORDSCALE || startX;
		startY = parseInt(split[4]) / COORDSCALE || startY;
		nightOpacity = parseFloat(split[5]) || nightOpacity;
		if (!isNaN(parseInt(split[6]))) {
			timestamp = split[6];
			if (!isNaN(parseInt(split[7])))
				timestamp += "-" + split[7];
		}
	}
} catch (_) {
		window.location.href = "#";
		window.location.reload();
}
if (isNaN(startX) || isNaN(startY)) {
	let spawn = mapInfo.maps.find(m => m.path == timestamp).surfaces[currentSurface].spawn;
	startX = -spawn.y / 2**(startZ-1);
	startY = spawn.x / 2**(startZ-1);
}


let lastHash = "";
function updateHash() {
	const zoom = map.getZoom();
	function condRound(x) {
		return zoom > globalMaxZoom ? Math.round(x * 2**(zoom-globalMaxZoom)) / 2**(zoom-globalMaxZoom) : Math.round(x);
	}
	const path = [1, currentSurface, zoom, condRound(map.getCenter().lat * COORDSCALE), condRound(map.getCenter().lng * COORDSCALE), nightOpacity, timestamp.replace('-', '/')];
	let hash = "#" + path.map(encodeURIComponent).join("/");
	if (hash != lastHash) {
		lastHash = hash;
		window.location.replace(hash);
	}
}
window.onhashchange = function() {
	if (lastHash != window.location.hash)
		window.location.reload();
}


let leafletLayers = [];
let map = L.map('map', {
	center: [startX, startY],
	zoom: startZ,
	layers: [],
	fadeAnimation: false,
	zoomAnimation: true,
	crs: L.CRS.Simple, // the map is 2D by nature
});
let nightOverlayPane = map.createPane("overlayPaneNight");
nightOverlayPane.style.zIndex = 450;
map.on("zoomanim", updateLabelScaling);
map.on("zoomend moveend", updateHash);
map.on("zoomend moveend", updateRenderboxUrls);


let lastRenderboxNightOpacity = nightOpacity;
function updateRenderboxOpacities(noUpdateLabels) {
	nightOverlayPane.style.opacity = nightOpacity;

	if (((nightOpacity == 1 || nightOpacity == 0) != (lastRenderboxNightOpacity == 1 || lastRenderboxNightOpacity == 0)) && !noUpdateLabels)
		updateLabels();
	lastRenderboxNightOpacity = nightOpacity;
}


let daylightSlider, timeSlider, surfaceSlider;
let mapLoadedBySlider = false;
if (Object.values(layers).some(s => Object.values(s).some(l => l.day)) && Object.values(layers).some(s => Object.values(s).some(l => l.night))) {
	daylightSlider = new L.Control.opacitySlider({
		position: "bottomright",
		orientation: "horizontal",
		initial: nightOpacity,
		length: 135,
		gravitate: 7,
		labels: [
			{
				name: "Day",
				position: 0,
				layers: Object.values(layers).map(s => Object.values(s).map(l => l.day)).flat()
			},
			{
				name: "Nightvision",
				position: .42,
				gravitate: 5
			},
			{
				name: "Night",
				position: 1,
				layers: Object.values(layers).map(s => Object.values(s).map(l => l.night)).flat()
			}
		],
		onChange: function(value) {
			nightOpacity = Math.round(value * 100) / 100;
			updateRenderboxOpacities();
			updateHash();
		}
	});
	map.addControl(daylightSlider);
	mapLoadedBySlider = true;
}








if (layersByTimestamp.length > 1 && true) {
	// min/max hours; "1" and "1-1" both become 1
	let minHours = Math.min.apply(undefined, mapInfo.maps.map(l => parseInt(l.path)));
	let maxHours = Math.max.apply(undefined, mapInfo.maps.map(l => parseInt(l.path)));
	// the tick times of each save
	let allTicksSorted = mapInfo.maps.map(l => l.tick).sort((a, b) => a - b);
	let minTicks = allTicksSorted[0];
	let maxTicks = allTicksSorted[allTicksSorted.length - 1];
	// number of handles on slider, and number of gaps in-between handles
	let numHandles = layersByTimestamp.length;
	let numGaps = numHandles - 1;
	// sliderHeight in px
	let sliderHeight = Math.min(window.innerHeight * .8, Math.max(95, 45 * numGaps));
	// labels for slider
	let timeLabels = layersByTimestamp.map(function(layer, i) {
		let position;
		let tick = mapInfo.maps[i].tick;
		// if both saves are in the same hour, or height per handle is less than 30 pixels, evenly space sliders
		if ((maxHours == minHours) || (sliderHeight / numHandles < 30)) {
			position = allTicksSorted.indexOf(tick) / numGaps;
		} else { // otherwise, space them based on how many ticks have passed
			position = (tick - minTicks) / (maxTicks - minTicks)
		}
		return {
			name: mapInfo.maps[i].path + "h",
			position: position,
			layers: Object.values(layer).map(s => ["day", "night"].map(n => s[n]).filter(l => l)).flat()
		}
	});



	let initialTime;
	for (let i = 0; i < timeLabels.length; i++) {
		if (parseFloat(timestamp) < parseInt(timeLabels[i].name)) {
			if (!i)
				initialTime = timeLabels[i].position;
			else
				initialTime = timeLabels[i].position - (timeLabels[i].position - timeLabels[i-1].position) * (parseInt(timeLabels[i].name) - parseFloat(timestamp)) / (parseInt(timeLabels[i].name) - parseInt(timeLabels[i-1].name));
			break;
		} else if (parseFloat(timestamp) == parseInt(timeLabels[i].name)) {
			let diff = parseInt(timeLabels[i].name.split("-")[1] || 0) - parseFloat(timestamp.split("-")[1] || 0);
			if (diff == 0) {
				initialTime = timeLabels[i].position;
				break;
			} else if (diff > 0) {
				initialTime = timeLabels[i].position - (timeLabels[i].position - timeLabels[i-1].position) * diff / (parseInt(timeLabels[i].name.split("-")[1] || 0) - parseInt(timeLabels[i-1].name.split("-")[1] || 0));
				break;
			}
		}
	}

	timeSlider = new L.Control.opacitySlider({
		position: "bottomright",
		orientation: "vertical",
		initial: initialTime,
		length: sliderHeight,
		evenSpacing: true,
		gravitate: 5,
		backdrop: false,
		labels: timeLabels,
		onChange: function(value, localValue, below, above) {
			if (!above)
				timestamp = below.name.slice(0, -1);
			else {
				let one = below.name.slice(0, -1).split("-");
				let two = above.name.slice(0, -1).split("-");
				if (one[0] == two[0])
					timestamp = one[0] + "-" + Math.round(((parseInt(one[1]) || 0) + localValue * ((parseInt(two[1]) || 0) - (parseInt(one[1]) || 0))) * 100) / 100;
				else
					timestamp = "" + Math.round((parseInt(one[0]) + localValue * (parseInt(two[0]) - parseInt(one[0]))) * 100) / 100;
			}
			updateHash();
			updateLabels();
		}
	});
	map.addControl(timeSlider);
	mapLoadedBySlider = true;
}


// default surface ontop, other than that natural sort.
let surfaceKeys = Object.keys(layers).filter(s => s != defaultSurface).sort(naturalSort);
if (Object.keys(layers).some(s => s == defaultSurface))
	surfaceKeys.unshift(defaultSurface)

if (surfaceKeys.length > 1) {
	surfaceSlider = new L.Control.layerRadioSelector({
		position: "bottomright",
		orientation: "vertical",
		initial: Math.max(0, surfaceKeys.indexOf(currentSurface)),
		length: (surfaceKeys.length-1)*30,
		evenSpacing: true,
		backdrop: false,
		labels: surfaceKeys.map((s, i) => { return {
			name: s, layers:
			Object.values(layers[s]).map(l => ["day", "night"].map(d => l[d]).filter(d => d)).flat()
		} }),
		onChange: function(index) {
			currentSurface = surfaceKeys[index];
			updateHash();
			updateLabels();
		}
	});
	map.addControl(surfaceSlider);
	if (!timeSlider)
		$(surfaceSlider._container).attr("style", "float: right !important");

	mapLoadedBySlider = true;
} else if (timeSlider)
	$(timeSlider._container).attr("style", "float: right !important");



if (!mapLoadedBySlider)
	map.addLayer(loadLayer.day || loadLayer.night);
map.addControl(new L.Control.FullScreen().setPosition('bottomright'));
map.zoomControl.setPosition('bottomleft')


updateLabels();
updateLabelScaling({ zoom: startZ });


if (daylightSlider)
	setTimeout(_ => {
		daylightSlider.setLength(135 + Math.round(($(".leaflet-control-container > .leaflet-bottom.leaflet-right").width() - 10 - $(daylightSlider._container).outerWidth())*10)/10);
	});