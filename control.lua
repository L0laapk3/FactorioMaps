


fm = {}
require "autorun"

require "generateMap"
require "api"


function exit()
	function NOT_AN_ERROR() exit_game() end
	function PLEASE_DONT_REPORT_THIS_AS_AN_ERROR() NOT_AN_ERROR() end
	function SERIOUSLY_THIS_IS_NOT_AN_ERROR() PLEASE_DONT_REPORT_THIS_AS_AN_ERROR() end

	SERIOUSLY_THIS_IS_NOT_AN_ERROR()
end


script.on_event(defines.events.on_tick, function(event)

	local player = game.connected_players[1]
	event.player_index = player.index



	game.autosave_enabled = false

	-- doesnt work lol
	-- type = "EXPLOIT TO PREVENT THE USER FROM BEING ABLE TO SAVE AND FUCK UP THEIR SAVE."
	-- global.something = "https://forums.factorio.com/viewtopic.php?f=48&t=67884"


	if fm.autorun and not fm.done then


		if fm.waitOneTick == nil then
			fm.waitOneTick = true
			return
		end

		--game.tick_paused = true
		--game.ticks_to_run = 1

		if nil == fm.tmp then	-- non surface specific stuff.

			log("Start world capture")

			if fm.autorun.mapInfo.options == nil then
				fm.autorun.mapInfo.options = {
					ranges = {
						build = fm.autorun.around_build_range,
						connect = fm.autorun.around_connect_range,
						tag = fm.autorun.around_tag_range
					},
					HD = fm.autorun.HD,
					day = fm.autorun.day,
					night = fm.autorun.night,
				}
				fm.autorun.mapInfo.seed = game.default_map_gen_settings.seed
				fm.autorun.mapInfo.mapExchangeString = game.get_map_exchange_string()
				fm.autorun.mapInfo.maps = {}
			end
		
			fm.savename = fm.autorun.name or ""
			fm.topfolder = fm.savename
			fm.autorun.tick = game.tick

			hour = math.ceil(fm.autorun.tick / 60 / 60 / 60)
			exists = true
			fm.autorun.filePath = tostring(hour)
			local i = 1
			while exists do
				exists = false
				if fm.autorun.mapInfo.maps ~= nil then
					for _, map in pairs(fm.autorun.mapInfo.maps) do
						if map.path == fm.autorun.filePath and map.tick ~= fm.autorun.tick then
							exists = true
							break
						end
					end
				end
				if exists then
					fm.autorun.filePath = tostring(hour) .. "-" .. tostring(i)
					i = i + 1
				end
			end
			
			fm.API.pull()

			
			if fm.autorun.surfaces == "all" then
				-- discover every surface charted by a player force, including space platforms
				fm.autorun.surfaces = {}
				for _, surface in pairs(game.surfaces) do
					local include = false
					if surface.platform ~= nil then
						-- space platforms are always visible to their force, include them if any chunk exists
						for chunk in surface.get_chunks() do
							if surface.is_chunk_generated(chunk) then
								include = true
								break
							end
						end
					else
						for chunk in surface.get_chunks() do
							for _, force in pairs(game.forces) do
								if #force.players > 0 and force.is_chunk_charted(surface, chunk) then
									include = true
									break
								end
							end
							if include then
								break
							end
						end
					end
					if include then
						fm.autorun.surfaces[#fm.autorun.surfaces+1] = surface.name
						log("Discovered charted surface: " .. surface.name)
					end
				end
			end

			if fm.autorun.surfaces == nil then
				if fm.autorun.mapInfo.defaultSurface == nil then
					if game.surfaces["battle_surface_1"] then	-- detect pvp scenario
						fm.autorun.mapInfo.defaultSurface = "battle_surface_1"
					else
						fm.autorun.mapInfo.defaultSurface = "nauvis"
					end
				end
				fm.autorun.surfaces = { fm.autorun.mapInfo.defaultSurface }
			else
				for index, surfaceName in pairs(fm.autorun.surfaces) do
					if player.surface.name == surfaceName then	-- move surface the player is on to first

						table.remove(fm.autorun.surfaces, index)
						fm.autorun.surfaces[#fm.autorun.surfaces+1] = surfaceName

						break
					end
				end
			end
			for _, surfaceName in pairs(fm.autorun.surfaces) do
				if game.surfaces[surfaceName] == nil then
					log("ERROR: surface \"" .. surfaceName .. "\" not found.")
					error("surface \"" .. surfaceName .. "\" not found.")
				end
			end
			
			fm.API.activeLinks = {}
			local newSurfaces = {true} -- discover all surfaces linked to from the original surface list or any new surfaces found by this process.
			while #newSurfaces > 0 do
				newSurfaces = {}
				for _, surfaceName in pairs(fm.autorun.surfaces) do

					if fm.API.linkData[surfaceName] then
						for _, link in pairs(fm.API.linkData[surfaceName]) do

							if link.type == "link_box_point" or link.type == "link_box_area" then
								local otherSurfaceAlreadyInList = false
								for _, otherSurfaceName in pairs(newSurfaces) do
									if link.toSurface == otherSurfaceName then
										otherSurfaceAlreadyInList = true
										break
									end
								end
								if not otherSurfaceAlreadyInList then
									for _, otherSurfaceName in pairs(fm.autorun.surfaces) do
										if link.toSurface == otherSurfaceName then
											otherSurfaceAlreadyInList = true
											break
										end
									end
								end
								if not otherSurfaceAlreadyInList then
									newSurfaces[#newSurfaces+1] = link.toSurface
									log("Discovered surface: " .. link.toSurface)
								end
							end
						end
					end
				end

				for _, surfaceName in pairs(newSurfaces) do
					fm.autorun.surfaces[#fm.autorun.surfaces+1] = surfaceName
				end
			end

			latest = ""
			for _, surfaceName in pairs(fm.autorun.surfaces) do
				local surface = game.surfaces[surfaceName]
				latest = fm.autorun.name:sub(1, -2):gsub(" ", "/") .. " " .. fm.autorun.filePath .. " " .. surfaceName:gsub(" ", "|") .. " " .. fm.autorun.daytime .. "\n" .. latest
			end
			helpers.write_file(fm.topfolder .. "latest.txt", latest, false, event.player_index)
			



			fm.tmp = true

		end
	




		if fm.ticks == nil then

			fm.currentSurface = game.surfaces[table.remove(fm.autorun.surfaces, #fm.autorun.surfaces)]
			-- if currentSurface ~= player.surface.name then
			-- 	player.teleport({0, 0}, currentSurface)
			-- 	fm.teleportedPlayer = true
			-- end
			
			-- remove ghost entities. no path signs are not entities anymore since 2.0
			for key, entity in pairs(fm.currentSurface.find_entities_filtered({type={"entity-ghost","tile-ghost"}})) do
				entity.destroy()
			end

			--spawn a bunch of hidden energy sources on lamps
			for _, t in pairs(fm.currentSurface.find_entities_filtered{type="lamp"}) do
				local control = t.get_control_behavior()
				if t.energy > 1 and (control and not control.disabled) or (not control) then
					fm.currentSurface.create_entity{name="hidden-electric-energy-interface", position=t.position}
				end
			end

			-- freeze all entities. Eventually, stuff will run out of power, but for just 2 ticks, it should be fine.
			-- some entity types have a read only active flag in 2.x, skip those.
			local function deactivate(entity)
				entity.active = false
			end
			for key, entity in pairs(fm.currentSurface.find_entities_filtered({invert=true, name="hidden-electric-energy-interface"})) do
				pcall(deactivate, entity)
			end



			-- some surfaces (e.g. space platforms) may not allow changing daytime
			if fm.autorun.daytime == "day" then
				pcall(function() fm.currentSurface.daytime = 0 end)
				fm.generateMap(event)
			else
				pcall(function() fm.currentSurface.daytime = 0.5 end)
				fm.generateMap(event)
			end
			
			fm.ticks = 1

		elseif fm.ticks < 2 then
			
			helpers.write_file(fm.topfolder .. "Images/" .. fm.autorun.filePath .. "/" .. fm.currentSurface.name .. "/" .. fm.autorun.daytime .. "/done.txt", "", false, event.player_index)

			fm.ticks = 2

		elseif #fm.autorun.surfaces > 0 then

			fm.ticks = nil	-- more surfaces to capture in this launch

		else
			fm.topfolder = nil

			fm.done = true
		end

	
	elseif fm.shownWarn == nil then
		-- give instructions on how to use mod and a warning to disable it.


		local text
		if fm.done then
			text = {
				"Factoriomaps automatic world capture",
				"Factoriomaps is now finished capturing your game and will close soon.",
				"If you believe the script is stuck or you see this screen in error,\nconsider making an issue on the github page: https://git.io/factoriomaps",
				"Do not save! This will result in a bricked gamestate."
			}
		else
			text = {
				"Welcome to FactorioMaps!",
				"For instructions, check out",
				"You can leave the mod disabled while you play.\nThe scripts will automagically enable it when it needs it!",
				"Do not save! This will result in a bricked gamestate."
			}
		end
	
		fm.shownWarn = true

		game.tick_paused = true
		game.ticks_to_run = 0
		if player.character then
			pcall(function() player.character.active = false end) -- read only for some character states in 2.x
		end
		
		local main = player.gui.center.add{type = "frame", caption = text[1], direction = "vertical"}
		local topLine = main.add{type = "flow", direction = "horizontal"}
		topLine.add{type = "label", caption = text[2]}
		if not fm.done then
			topLine.add{type = "label", caption = "https://git.io/factoriomaps."}.style.font = "default-bold"
		end
		--topLine.add{type = "label", name = "main-end", caption = "."}.style
		main.add{type = "label", caption = text[3]}.style.single_line = false
		main.add{type = "label", caption = text[4]}.style.font = "default-bold"
		main.style.horizontal_align = "right"
	
		
		if not fm.done then
			local buttonContainer = main.add{type = "flow", direction = "horizontal"}
			local button = buttonContainer.add{type = "button", caption = "Back to main menu"}
			buttonContainer.style.horizontally_stretchable = true
			buttonContainer.style.horizontal_align = "right"
			script.on_event(defines.events.on_gui_click, function(event)
	
				if event.element == button then
					main.destroy()
					exit()
				end
	
			end)
		end
		
	end
end)

function unpause()
	game.tick_paused = false
end
script.on_init(unpause)
