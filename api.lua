
fm.API = {}
fm.API.startEvent = script.generate_event_name()

fm.API.linkData = {}
fm.API.hiddenSurfaces = {}


local ERRORPRETEXT = "\n\nFACTORIOMAPS HAS DETECTED AN INVALID USAGE OF THE FACTORIOMAPS API BY ANOTHER MOD.\nTHIS IS LIKELY NOT A PROBLEM WITH FACTORIOMAPS, BUT WITH THE OTHER MOD.\n\n"


local function NYI()
	error("This API call is not yet implemented due to lack of demand. If you are looking at using this function, contact me! I will gladly implement it.")
end




-- resolve surface to surface object
local function resolveSurface(surface, default, errorText)
	errorText = errorText or ""
	if surface ~= nil then
		if type(surface) == "string" or type(surface) == "number" then
			surface = game.surfaces[surface]
			if not surface then
				error(ERRORPRETEXT .. errorText .. "surface does not exist\n")
			elseif not surface.valid then
				error(ERRORPRETEXT .. errorText .. "surface.valid is false\n")
			end
			return surface
		else
			error(ERRORPRETEXT .. errorText .. "surface is not a string or number\n")
		end
	else
		if not default then
			error(ERRORPRETEXT .. errorText .. "no surface specified\n")
		else
			return default
		end
	end
end

local roundMultiplier = 32
if fm.autorun and fm.autorun.HD then
	roundMultiplier = 64
end

local function parseLocation(options, optionName, isArea, canHaveSurface, defaultSurface)

	assert(options, "no options specified")
	local obj = options[optionName]
	assert(obj, "no '" .. optionName .. "' option specified")
	assert(type(obj) == "table", "option '" .. optionName .. "' must be a table with coordinates")

	local surface = nil
	if canHaveSurface then
		surface = resolveSurface(obj["surface"], defaultSurface, "option '" .. optionName .. "': ")
		if obj["surface"] then
			obj.surface = nil
		end
	end
	
	for k, v in pairs(obj) do
		if k ~= 1 and k ~= 2 then
			error(ERRORPRETEXT .. "option '" .. optionName .. "': invalid key '" .. k .. "'\n")
		end
	end
	if obj[1] and obj[2] then
		if isArea then
			return { parseLocation(obj, 1), parseLocation(obj, 2) }, surface
		else
			return { x = math.floor(obj[1] * roundMultiplier + 0.5) / roundMultiplier, y = math.floor(obj[2] * roundMultiplier + 0.5) / roundMultiplier }, surface
		end
	else
		error(ERRORPRETEXT .. "option '" .. optionName .. "': invalid " .. (isArea and "area" or "point") .. " '" .. serpent.block(obj) .. "'\n")
	end

end


-- because of unknown scaling (powers of 2 only allowed, this could change in the future), do not test which parts
-- of the renderbox are a problem, only test if any part of the renderbox can form a chain back to the origin.
local function hasPartialOverlap(a, b)
	return b[2].x > a[1].x and b[1].x < a[2].x
	   and b[2].y > a[1].y and b[1].y < a[2].y
end
local function testChainCausality(link, sourceSurface, sourceIndex)
	for _, nextLinkIndex in pairs(link.chain or {}) do
		local nextLink = fm.API.linkData[link.toSurface][nextLinkIndex+1]
		if (nextLinkIndex == sourceIndex and sourceSurface == link.toSurface) or not testChainCausality(nextLink, sourceSurface, sourceIndex) then
			return false
		end
	end
	return true
end
local function updateMaxZoomDifference(link, prevZoomFromSurfaces)
	local newSurfaceZooms = {}
	for surfaceName, prevZoom in pairs(prevZoomFromSurfaces) do
		local newZoomDifference = prevZoom + link.zoomDifference
			
		if link.maxZoomFromSurfaces[surfaceName] == nil or link.maxZoomFromSurfaces[surfaceName] < newZoomDifference then
			newSurfaceZooms[surfaceName] = newZoomDifference
		end
	end

	for surfaceName, newZoomDifference in pairs(newSurfaceZooms) do
		link.maxZoomFromSurfaces[surfaceName] = newZoomDifference
	end

	for _, _ in pairs(newSurfaceZooms) do	-- break right after, its like length > 0 but for objects
		for _, nextLinkIndex in pairs(link.chain or {}) do
			updateMaxZoomDifference(fm.API.linkData[link.toSurface][nextLinkIndex+1], newSurfaceZooms)
		end
		break
	end
end
local function populateRenderChain(newLink, newLinkIndex, fromSurface)

	-- scan if other links contain this link in their destination and update them (for max zoom scale)
	newLink.maxZoomFromSurfaces = {}
	newLink.maxZoomFromSurfaces[fromSurface] = 0
	for _, linkList in pairs(fm.API.linkData or {}) do
		for i, link in pairs(linkList) do
			if link.chain and link.toSurface == fromSurface and hasPartialOverlap(link.to, newLink.from) then

				-- update that link chain to contain this link
				link.chain[#link.chain+1] = newLinkIndex
				
				-- update max zoom levels from each surface
				for surfaceName, zoomDifference in pairs(link.maxZoomFromSurfaces) do
					newLink.maxZoomFromSurfaces[surfaceName] = math.max(zoomDifference, newLink.maxZoomFromSurfaces[surfaceName] or 0)
				end
			end
		end
	end

	-- increment all by this zoom step
	for surfaceName, zoomDifference in pairs(newLink.maxZoomFromSurfaces) do
		newLink.maxZoomFromSurfaces[surfaceName] = zoomDifference + newLink.zoomDifference
	end

	-- find other links that are in the destination of this link
	newLink.chain = {}
	for i, link in pairs(fm.API.linkData[newLink.toSurface] or {}) do
		if hasPartialOverlap(newLink.to, link.from) then
			newLink.chain[#newLink.chain+1] = i-1
			if not testChainCausality(link, fromSurface, newLinkIndex) then
				error(ERRORPRETEXT .. "Renderbox bad causality: can cause an infinite rendering loop\n")
			end
			updateMaxZoomDifference(link, newLink.maxZoomFromSurfaces)
		end
	end
end


local function addLink(type, from, fromSurface, to, toSurface)
	if fm.API.linkData[fromSurface.name] == nil then
		fm.API.linkData[fromSurface.name] = {}
	end
	local newLink = {
		type = type,
		from = from,
		to = to,
		toSurface = toSurface.name
	}

	if type == "link_renderbox_area" then
		local centerX = (from[1].x + from[2].x) / 2
		local centerY = (from[1].y + from[2].y) / 2
		local fromSizeX = from[2].x-from[1].x
		local fromSizeY = from[2].y-from[1].y
		local toSizeX = to[2].x-to[1].x
		local toSizeY = to[2].y-to[1].y
		newLink.zoomDifference = math.ceil(math.log(math.max(toSizeX/fromSizeX, toSizeY/fromSizeY)) / math.log(2))
		local sizeMul = math.pow(2, -newLink.zoomDifference-1) -- -1 for additional division by 2
		newLink.renderFrom = {
			{ x = centerX - toSizeX * sizeMul, y = centerY - toSizeY * sizeMul },
			{ x = centerX + toSizeX * sizeMul, y = centerY + toSizeY * sizeMul }
		}
		newLink.daynight = true
	end

	log("adding link type " .. type .. " from " .. fromSurface.name .. " to " .. toSurface.name)
	local linkIndex = #fm.API.linkData[fromSurface.name]
	fm.API.linkData[fromSurface.name][linkIndex+1] = newLink

	if type == "link_renderbox_area" then
		populateRenderChain(newLink, linkIndex, fromSurface.name)
	end
end




remote.add_interface("factoriomaps", {
	get_start_capture_event_id = function()
		return fm.API.startEvent
	end,



	link_box_point = function(options)
		local from, fromSurface = parseLocation(options, "from", true, true)
		local to, toSurface =     parseLocation(options, "to", false, true, fromSurface)

		addLink("link_box_point", from, fromSurface, to, toSurface)
	end,
	link_box_area = function(options)
		local from, fromSurface = parseLocation(options, "from", true, true)
		local to, toSurface =     parseLocation(options, "to", true, true, fromSurface)

		addLink("link_box_area", from, fromSurface, to, toSurface)
	end,
	link_renderbox_area = function(options)
		local from, fromSurface = parseLocation(options, "from", true, true)
		local to, toSurface =     parseLocation(options, "to", true, true, fromSurface)

		addLink("link_renderbox_area", from, fromSurface, to, toSurface)
	end,



	surface_set_hidden = function(surface, isHidden)
		surface = resolveSurface(surface)
		if isHidden == true or isHidden == nil then
			for _, s in pairs(fm.API.hiddenSurfaces) do
				if s == surface then
					return
				end
			end
			fm.API.hiddenSurfaces[#fm.API.hiddenSurfaces+1] = surface
		elseif isHidden == false then
			for i, s in pairs(fm.API.hiddenSurfaces) do
				if s == surface then
					table.remove(fm.API.hiddenSurfaces, i)
					return
				end
			end
		else
			error(ERRORPRETEXT .. "invalid isHidden parameter\n")
		end
	end,
	surface_set_default = function(surface)
		surface = resolveSurface(surface)
		if fm.autorun.mapInfo.defaultSurface ~= nil and fm.autorun.mapInfo.defaultSurface ~= surface.name then
			error(ERRORPRETEXT .. "The default surface was set multiple times: '" .. fm.autorun.mapInfo.defaultSurface .. "', '" .. surface.name .. "'.\n")
		end
		fm.autorun.mapInfo.defaultSurface = surface.name
	end,
	surface_set_startpoint = function(options)
		NYI();
	end,



	legend_link_point = function(directory, subdirectory, text)
		NYI();
	end,
	legend_link_area = function(directory, subdirectory, text)
		NYI();
	end
})



function fm.API.pull()
	script.raise_event(fm.API.startEvent, {})

	--remote.remove_interface("factoriomaps")
end

