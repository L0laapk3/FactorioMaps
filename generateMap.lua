require("json")

math.log2 = function(x) return math.log(x) / math.log(2) end

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"



--[[
x+ = UP, y+ = RIGHT
corners:
2   1
  X
4   3 
]]--

function adjustBox(entity, box, initBox, corners)
	if entity.bounding_box.right_bottom.x < box[1] then
		box[1] = math.ceil(entity.bounding_box.right_bottom.x) - 8/32  --8 pixel remains of the lamp, 8 pixels because dont wanna mess with jpg
	elseif entity.bounding_box.left_top.x > box[3] then
		box[3] = math.floor(entity.bounding_box.left_top.x) + 8/32
	end
	if entity.bounding_box.right_bottom.y < box[2] then
		box[2] = math.ceil(entity.bounding_box.right_bottom.y) - 8/32
	elseif entity.bounding_box.left_top.y > box[4] then
		box[4] = math.floor(entity.bounding_box.left_top.y) + 8/32
	end

	if entity.bounding_box.left_top.x > initBox[3] then
		if not (entity.bounding_box.left_top.y < initBox[2]) then corners[1] = 1 end
		if not (entity.bounding_box.right_bottom.y > initBox[4]) then corners[2] = 1 end
	elseif entity.bounding_box.right_bottom.x < initBox[1] then
		if not (entity.bounding_box.left_top.y < initBox[2]) then corners[3] = 1 end
		if not (entity.bounding_box.right_bottom.y > initBox[4]) then corners[4] = 1 end
	end
end

function fm.generateMap(data)

	local player = game.players[data.player_index]

	local forces = {}
	local forceStats = {}
	for _, force in pairs(game.forces) do
		if #force.players > 0 then
			forces[#forces+1] = force.name
			forceStats[force.name] = 0
		end
	end

	game.set_wait_for_screenshots_to_finish()
	


	-- delete folder (if it already exists)
	local basePath = fm.topfolder
	local subPath = basePath .. "Images/" .. fm.autorun.filePath .. "/" .. fm.currentSurface.name .. "/" .. fm.autorun.daytime
	helpers.remove_path(subPath)
	subPath = subPath .. "/"


	
	-- Number of pixels in an image     -- CHANGE THIS AND REF.PY WILL NEED TO BE CHANGED
	local gridSizes = {256, 512, 1024} -- cant have 2048 anymore. code now relies on it being smaller than one game chunk (32 tiles * 32 pixels)
	local gridSize = gridSizes[2] --always 512x512 pixel images for now, its a good balance (check rest of code before changing this)

	local tilesPerChunk = 32    --hardcoded
	
	local pixelsPerTile = 32
	if fm.autorun.mapInfo.options.HD then
		pixelsPerTile = 64   -- HD textures have 64 pixels/tile
	end

	-- These are the number of tiles per image (gridSize = 512, 32 pixelspertile means 16 by 16 tiles in each image)
	local gridPixelSize = gridSize / pixelsPerTile



	
	if fm.tilenames == nil then
		local craftableItems = {}
		for _, recipe in pairs(prototypes.recipe) do
			for _, product in pairs(recipe.products) do
				if product.type == "item" then
					craftableItems[product.name] = true
				end
			end
		end

		local tilenamedict = {}
		for itemName, _ in pairs(craftableItems) do
			item = prototypes.item[itemName]
			if item.place_as_tile_result ~= nil and item.place_as_tile_result.result.autoplace_specification == nil then
				tilenamedict[item.place_as_tile_result.result.name] = true
			end
			::continue::
		end

		fm.tilenames = {}
		for tilename, _ in pairs(tilenamedict) do
			fm.tilenames[#fm.tilenames+1] = tilename
		end
	end

	

	local spawn = player.force.get_spawn_position(fm.currentSurface)


	local imageStats = {
		remembered = 0,
		charted = 0,
		not_cached = 0,
		tags = 0,
		build = 0,
		connect = 0,
		player = 0,
		smoothed = 0
	}


	

	local minX = spawn.x
	local minY = spawn.y
	local maxX = spawn.x
	local maxY = spawn.y

	local allGrid = {}
	local mapIndex = 0
	local surfaceWasScanned = false
	if fm.autorun.chunkCache then
		for mapTick, v in pairs(fm.autorun.chunkCache) do
			if tonumber(mapTick) <= fm.autorun.tick then
				if v[fm.currentSurface.name] ~= nil then
					for s in v[fm.currentSurface.name]:gmatch("%-?%d+ %-?%d+ ?%a?") do
						local gridX, gridY, prevScanResult = s:match("(%-?%d+) (%-?%d+) ?(%a?)")
						gridX = tonumber(gridX)
						gridY = tonumber(gridY)

						allGrid[gridX .. " " .. gridY] = {
							x = gridX,
							y = gridY,
							scan = BASE64:find(#prevScanResult > 0 and prevScanResult or "A") - 1,
							old = true
						}

						minX = math.min(minX, gridX)
						minY = math.min(minY, gridY)
						maxX = math.max(maxX, gridX)
						maxY = math.max(maxY, gridY)

						imageStats.remembered = imageStats.remembered + 1
					end
				end
				if tonumber(mapTick) == fm.autorun.tick then
					for i, map in pairs(fm.autorun.mapInfo.maps) do
						if map.tick == fm.autorun.tick then
							surfaceWasScanned = v[fm.currentSurface.name] ~= nil
							mapIndex = i
							break
						end
					end
				end
			end
		end
	end


	
	local ENUMSCAN = {
		RANGE = 1,
		BUILD = 2,
		CONNECT = 4,
		TAG = 8,
	}

	local allGridString = ""
	if not surfaceWasScanned then

		log("[info]Surface prescan " .. fm.savename .. fm.autorun.filePath .. "/" .. fm.currentSurface.name)



		-- tag range
		for _, force in pairs(game.forces) do
			if #force.players > 0 then
				for _, tag in pairs(force.find_chart_tags(fm.currentSurface)) do
					local tagX = math.floor(tag.position.x / gridPixelSize)
					local tagY = math.floor(tag.position.y / gridPixelSize)
					local oldScanResult = allGrid[tagX .. " " .. tagY] and allGrid[tagX .. " " .. tagY].scan or 0
					allGrid[tagX .. " " .. tagY] = {x = tagX, y = tagY, scan = bit32.bor(oldScanResult, bit32.bor(ENUMSCAN.RANGE, ENUMSCAN.TAG)) }

					imageStats.tags = imageStats.tags + 1

					for k = 0, fm.autorun.mapInfo.options.ranges.tag * pixelsPerTile / tilesPerChunk, 1 do
						for l = 0, fm.autorun.mapInfo.options.ranges.tag * pixelsPerTile / tilesPerChunk, 1 do
							for m = 1, k > 0 and -1 or 1, -2 do
								for n = 1, l > 0 and -1 or 1, -2 do
									local i = k * m
									local j = l * n
									local x = tagX + i
									local y = tagY + j
									if allGrid[x .. " " .. y] == nil or not bit32.band(allGrid[x .. " " .. y].scan, ENUMSCAN.RANGE) then
										local chunk = { x = math.floor(x * gridPixelSize / tilesPerChunk), y = math.floor(y * gridPixelSize / tilesPerChunk) }
										if fm.currentSurface.is_chunk_generated(chunk) then
											local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
											if dist <= math.pow(fm.autorun.mapInfo.options.ranges.tag + 0.5, 2) then

												allGrid[x .. " " .. y] = {x = x, y = y, scan = bit32.bor(allGrid[x .. " " .. y] and allGrid[x .. " " .. y].scan or 0, ENUMSCAN.RANGE) }

												minX = math.min(minX, x)
												minY = math.min(minY, y)
												maxX = math.max(maxX, x)
												maxY = math.max(maxY, y)
												
												imageStats.tags = imageStats.tags + 1
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end


		-- build range
		for chunk in fm.currentSurface.get_chunks() do
			if fm.currentSurface.is_chunk_generated(chunk) then
				-- log(chunk.x .. " " .. chunk.y)
				for _, force in pairs(game.forces) do
					if #force.players > 0 and force.is_chunk_charted(fm.currentSurface, chunk) then
						-- log("charted by " .. force.name)
						forceStats[force.name] = forceStats[force.name] + 1
						imageStats.charted = imageStats.charted + 1
						for gridX = chunk.x * tilesPerChunk / gridPixelSize, (chunk.x + 1) * tilesPerChunk / gridPixelSize - 1 do
							for gridY = chunk.y * tilesPerChunk / gridPixelSize, (chunk.y + 1) * tilesPerChunk / gridPixelSize - 1 do
								if allGrid[gridX .. " " .. gridY] == nil or bit32.band(allGrid[gridX .. " " .. gridY].scan, bit32.bnot(ENUMSCAN.RANGE)) then
									imageStats.not_cached = imageStats.not_cached + 1

									local scanRange = -1
									local previousScan = (allGrid[gridX .. " " .. gridY] and allGrid[gridX .. " " .. gridY].scan or 0)
									
									if bit32.band(previousScan, ENUMSCAN.TAG) > 0 then
										scanRange = fm.autorun.mapInfo.options.ranges.tag
									end
									if bit32.band(previousScan, ENUMSCAN.BUILD) > 0 then
										scanRange = math.max(scanRange, fm.autorun.mapInfo.options.ranges.build)
									end
									if bit32.band(previousScan, ENUMSCAN.CONNECT) > 0 then
										scanRange = math.max(scanRange, fm.autorun.mapInfo.options.ranges.connect)
									end
									
									local oldScanRange = scanRange
									local excludeCount = nil
									local area = nil
									local connectTypeCount = nil
									local byBigType = false
									if scanRange < fm.autorun.mapInfo.options.ranges.build then
										if area == nil then
											area = {{gridPixelSize * gridX, gridPixelSize * gridY}, {gridPixelSize * (gridX+1), gridPixelSize * (gridY+1)}}
											connectTypeCount = fm.currentSurface.count_entities_filtered({ force=forces, area=area, type=fm.autorun.connect_types })
											excludeCount = fm.currentSurface.count_entities_filtered({ force=forces, area=area, type={"character"} })
										end
										if  			  0 < fm.currentSurface.count_tiles_filtered({ force=forces, area=area, limit=1, name=fm.tilenames })
											or connectTypeCount + excludeCount < fm.currentSurface.count_entities_filtered({ force=forces, area=area, limit=connectTypeCount+excludeCount+1 }) then

											allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY, scan = bit32.bor(allGrid[gridX .. " " .. gridY] and allGrid[gridX .. " " .. gridY].scan or 0, bit32.bor(ENUMSCAN.RANGE, ENUMSCAN.BUILD)) }
											scanRange = fm.autorun.mapInfo.options.ranges.build

											imageStats.build = imageStats.build + 1

											byBigType = true
										end
									end
									if scanRange < fm.autorun.mapInfo.options.ranges.connect then
										if area == nil then
											area = {{gridPixelSize * gridX, gridPixelSize * gridY}, {gridPixelSize * (gridX+1), gridPixelSize * (gridY+1)}}
											excludeCount = fm.currentSurface.count_entities_filtered({ force=forces, area=area, type={"character"} })
										end
										if excludeCount < (connectTypeCount or fm.currentSurface.count_entities_filtered({ force=forces, area=area, limit=excludeCount+1, type=fm.autorun.connect_types })) then

											allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY, scan = bit32.bor(allGrid[gridX .. " " .. gridY] and allGrid[gridX .. " " .. gridY].scan or 0, bit32.bor(ENUMSCAN.RANGE, ENUMSCAN.CONNECT)) }
											scanRange = fm.autorun.mapInfo.options.ranges.connect

											imageStats.connect = imageStats.connect + 1
										end
									end

									if scanRange > oldScanRange then
										for k = 0, scanRange * pixelsPerTile / tilesPerChunk, 1 do
											for l = 0, scanRange* pixelsPerTile / tilesPerChunk, 1 do
												for m = 1, k > 0 and -1 or 1, -2 do
													for n = 1, l > 0 and -1 or 1, -2 do
														local i = k * m
														local j = l * n
														local x = gridX + i
														local y = gridY + j
														if allGrid[x .. " " .. y] == nil or not bit32.band(allGrid[x .. " " .. y].scan, ENUMSCAN.RANGE) then
															local chunk = { x = math.floor(x * gridPixelSize / tilesPerChunk), y = math.floor(y * gridPixelSize / tilesPerChunk) }
															if fm.currentSurface.is_chunk_generated(chunk) then
																local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
																if dist <= math.pow(scanRange + 0.5, 2) then
													
																	allGrid[x .. " " .. y] = {x = x, y = y, scan = bit32.bor(allGrid[x .. " " .. y] and allGrid[x .. " " .. y].scan or 0, ENUMSCAN.RANGE) }

																	minX = math.min(minX, x)
																	minY = math.min(minY, y)
																	maxX = math.max(maxX, x)
																	maxY = math.max(maxY, y)
																	
																	if byBigType then
																		imageStats.build = imageStats.build + 1
																	else
																		imageStats.connect = imageStats.connect + 1
																	end
																end
															end
														end
													end
												end
											end
										end
									end
								end
							end
						end
						break
					end
				end
			end
		end





		-- add around player on empty
		local allGridIsEmpty = true
		for _, _ in pairs(allGrid) do
			allGridIsEmpty = false
			break
		end
		if allGridIsEmpty then
			range = math.max(fm.autorun.around_tag_range, fm.autorun.around_build_range)
			for k = 0, range * pixelsPerTile / tilesPerChunk, 1 do
				for l = 0, range * pixelsPerTile / tilesPerChunk, 1 do
					for m = 1, k > 0 and -1 or 1, -2 do
						for n = 1, l > 0 and -1 or 1, -2 do
							local i = k * m
							local j = l * n
							local x = player.position.x / gridPixelSize + i
							local y = player.position.y / gridPixelSize + j
							local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
							local chunk = {x = math.floor(x * gridPixelSize / tilesPerChunk), y = math.floor(y * gridPixelSize / tilesPerChunk)}
							if dist <= math.pow(range + 0.5, 2) then
								local gridX = math.floor(x)
								local gridY = math.floor(y)
								allGrid[gridX .. " " .. gridY] = { x = gridX, y = gridY, scan = bit32.bor(allGrid[gridX .. " " .. gridY] and allGrid[gridX .. " " .. gridY].scan or 0, ENUMSCAN.RANGE) }

								minX = math.min(minX, gridX)
								minY = math.min(minY, gridY)
								maxX = math.max(maxX, gridX)
								maxY = math.max(maxY, gridY)

								imageStats.player = imageStats.player + 1
							end
						end
					end
				end
			end
		end



		
	
		-- smoothing
		local cont = true
		while cont do
			cont = false
			tmp = {}
			for _, p in pairs(allGrid) do
				for _, o in pairs({ {x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1} }) do
					local x = p.x + o.x
					local y = p.y + o.y
					if allGrid[x .. " " .. y] == nil then
						local count = 0
						for _, pos in pairs({ {x=p.x+2*o.x, y=p.y+2*o.y}, {x=p.x+o.x+o.y, y=p.y+o.y+o.x}, {x=p.x+o.x-o.y, y=p.y+o.y-o.x} }) do
							if allGrid[pos.x .. " " .. pos.y] ~= nil then
								count = count + 1
								if count == 3 then
									tmp[#tmp + 1] = { x = x, y = y, scan = bit32.bor(allGrid[x .. " " .. y] and allGrid[x .. " " .. y].scan or 0, ENUMSCAN.RANGE) }
									cont = true
								end
							end
						end
					end
				end
			end
			cont = #tmp > 0
			for _, v in pairs(tmp) do
				allGrid[v.x .. " " .. v.y] = v 

				minX = math.min(minX, v.x)
				minY = math.min(minY, v.y)
				maxX = math.max(maxX, v.x)
				maxY = math.max(maxY, v.y)
								
				imageStats.smoothed = imageStats.smoothed + 1
			end
		end



		-- build gridstring
		for gridKey, grid in pairs(allGrid) do
			if grid.old == nil then
				allGridString = allGridString .. gridKey .. " " .. BASE64:sub(grid.scan+1, grid.scan+1) .. "|"
			end
		end
	end



	local linkStats = {
		link_box_point = 0,
		link_box_area = 0,
		link_renderbox_area = 0,
	}
	for _, links in pairs(fm.API.linkData) do
		for _, link in pairs(links) do
			linkStats[link.type] = linkStats[link.type] + 1
		end
	end

	log("imageStats")
	log("        remembered:          " .. imageStats.remembered)
	log("        charted:             " .. imageStats.charted * math.pow(tilesPerChunk / gridPixelSize, 2))
	log("        not_cached:          " .. imageStats.not_cached)
	log("        tag:                 " .. imageStats.tags)
	log("        build:               " .. imageStats.build)
	log("        connect:             " .. imageStats.connect)
	log("        player:              " .. imageStats.player)
	log("        smoothed:            " .. imageStats.smoothed)
	log("linkStats")
	log("        link_box_point:      " .. linkStats.link_box_point)
	log("        link_box_area:       " .. linkStats.link_box_area)
	log("        link_renderbox_area: " .. linkStats.link_renderbox_area)
	log("forceStats")
	for force, count in pairs(forceStats) do
		log("        " .. force .. ": " .. count)
	end
	

	local maxZoom = 20
	if fm.autorun.mapInfo.options.HD then
		maxZoom = 21
	end

	if mapIndex == 0 then

		mapIndex = #fm.autorun.mapInfo.maps + 1
		fm.autorun.mapInfo.maps[mapIndex] = {
			tick = fm.autorun.tick,
			path = fm.autorun.filePath,
			date = fm.autorun.date,
			mods = script.active_mods,
			surfaces = {}
		}

		for surfaceName, links in pairs(fm.API.linkData) do
			fm.autorun.mapInfo.maps[mapIndex].surfaces[surfaceName] = {
				zoom = { max = maxZoom },
				links = links
			}
		end
	end
	

	local maxImagesNextToEachotherOnLargestZoom = 2
	local minZoom = (maxZoom - math.max(2, math.ceil(math.min(math.log2(maxX - minX), math.log2(maxY - minY)) + 0.01 - math.log2(maxImagesNextToEachotherOnLargestZoom))))

	if fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name] == nil or fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].captured ~= true then
		

		fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name] = {
			spawn = spawn, -- this only includes spawn point of the player taking the screenshots
			zoom = { min = minZoom, max = maxZoom },
			tags = {},
			hidden = false,
			captured = true,
			links = fm.API.linkData[fm.currentSurface.name] or {}
		}

		for _, s in pairs(fm.API.hiddenSurfaces) do
			if s.name == fm.currentSurface.name then
				fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].hidden = true
				break
			end
		end

		if fm.currentSurface == player.surface then
			fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].playerPosition = player.position
		end
		if fm.autorun.tags then
			for _, force in pairs(game.forces) do
				if #force.players > 0 then
					for i, tag in pairs(force.find_chart_tags(fm.currentSurface)) do
						if tag.icon == nil then
							fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].tags[i] = {
								position 	= tag.position,
								text 		= tag.text,
								last_user	= tag.last_user and tag.last_user.name,
								force	    = force.name
							}
						else
							local iconType = tag.icon.type or "item" -- SignalID type defaults to "item" since 2.0
							name = tag.icon["name"] or iconType
							fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].tags[i] = {
								iconType 	= iconType,
								iconName 	= name,
								iconPath    = "Images/labels/" .. iconType .. "/" .. name .. ".png",
								position 	= tag.position,
								text 		= tag.text,
								last_user	= tag.last_user and tag.last_user.name,
								force	    = force.name
							}
						end
					end
				end
			end
		end

		if fm.autorun.chunkCache[fm.autorun.tick] == nil then
			fm.autorun.chunkCache[fm.autorun.tick] = {}
		end
		fm.autorun.chunkCache[fm.autorun.tick][fm.currentSurface.name] = allGridString:sub(1, -2)
		helpers.write_file(basePath .. "chunkCache.json", prettyjson(fm.autorun.chunkCache), false, data.player_index)
	
	end
	fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name][fm.autorun.daytime] = true


	-- todo: if fm.autorun.mapInfo.maps[mapIndex].surfaces[fm.currentSurface.name].hidden is true, only care about the chunks linked to by renderboxes.

   
	local extension = ".png"


	
	log("[info]Surface capture " .. fm.savename .. fm.autorun.filePath .. "/" .. fm.currentSurface.name .. "/" .. fm.autorun.daytime)



	local cropText = ""
	local function capture(positionTable, surface, path)
		local box = { positionTable[1].x, positionTable[1].y, positionTable[2].x, positionTable[2].y } -- -X -Y X Y
		local initialBox = { box[1], box[2], box[3], box[4] }
		local area = {{box[1] - 16, box[2] - 16}, {box[3] + 16, box[4] + 16}}
		
		local corners = {0, 0, 0, 0} 

		for _, t in pairs(fm.currentSurface.find_entities_filtered{area=area, name="big-electric-pole"}) do 
			adjustBox(t, box, initialBox, corners)
		end
		for _, t in pairs(fm.currentSurface.find_entities_filtered{area=area, type="lamp"}) do 
			local control = t.get_control_behavior()
			if t.energy > 1 and (control and not control.disabled) or (not control and fm.currentSurface.darkness > 0.3) then
				adjustBox(t, box, initialBox, corners)
			end
		end
		if box[1] < positionTable[1].x or box[2] < positionTable[1].y or box[3] > positionTable[2].x or box[4] > positionTable[2].y then
			cropText = cropText .. "\n" .. (positionTable[1].x - box[1])*pixelsPerTile .. " " .. (positionTable[1].y - box[2])*pixelsPerTile .. " " .. (positionTable[2].x - positionTable[1].x)*pixelsPerTile .. " " .. (positionTable[2].y - positionTable[1].y)*pixelsPerTile .. " " .. string.format("%x", corners[1] + 2*corners[2] + 4*corners[3] + 8*corners[4]) .. " " .. path
		end

		game.take_screenshot({
			by_player = player,
			surface = surface,
			position = {(box[1] + box[3]) / 2, (box[2] + box[4]) / 2},
			resolution = {(box[3] - box[1])*pixelsPerTile, (box[4] - box[2])*pixelsPerTile},
			zoom = fm.autorun.mapInfo.options.HD and 2 or 1,
			path = basePath .. "Images/" .. path,
			show_entity_info = fm.autorun.alt_mode,
			hide_clouds = true,
			hide_fog = true
		})                        
	end



	for _, chunk in pairs(allGrid) do   
		local positionTable = {
			{ x =  chunk.x    * gridPixelSize, y =  chunk.y    * gridPixelSize  },
			{ x = (chunk.x+1) * gridPixelSize, y = (chunk.y+1) * gridPixelSize  }
		}

		capture(positionTable, fm.currentSurface, fm.autorun.filePath .. "/" .. fm.currentSurface.name .. "/" .. fm.autorun.daytime .. "/" .. maxZoom .. "/" .. chunk.x .. "/" .. chunk.y .. extension)
	end 


 
	local linkWorkList = {}
	for _, link in pairs(fm.API.linkData[fm.currentSurface.name] or {}) do
		if link.type == "link_renderbox_area" then
			linkWorkList[#linkWorkList+1] = link
		end
	end

	local doneLinkPaths = {}
	while #linkWorkList > 0 do
		local link = table.remove(linkWorkList)

		local folder = fm.autorun.filePath .. "/" .. link.toSurface .. "/" .. fm.autorun.daytime .. "/" .. "renderboxes" .. "/"
		local filename = link.to[1].x .. "_" .. link.to[1].y .. "_" .. link.to[2].x .. "_" .. link.to[2].y
		local path = folder .. maxZoom .. "/"  .. filename

		local surface = game.surfaces[link.toSurface]
		link.daynight = not surface.freeze_daytime
		if link.daynight then
			surface.daytime = fm.autorun.daytime == "day" and 0 or 0.5
		end
		
		
		if doneLinkPaths[path] == nil then
			if link.daynight or not link.filename then
				capture(link.to, link.toSurface, path .. extension)
				link.filename = filename
				link.zoom = { max = maxZoom }
		
			end
			doneLinkPaths[path] = true
		end

		for _, index in pairs(link.chain) do
			linkWorkList[#linkWorkList+1] = fm.API.linkData[link.toSurface][index+1]
		end
	end

	
	
	helpers.write_file(basePath .. "mapInfo.json", json(fm.autorun.mapInfo), false, data.player_index)
	helpers.write_file(subPath .. "crop.txt", "v2" .. cropText, false, data.player_index)
	
end