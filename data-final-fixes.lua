require("json")

-- consider adding symbols to beginning of mod name to ensure latest load?










local function typeCheck(item, itemType, field, expectedType, fieldName)
	if type(field) ~= expectedType then
		error("\n\n\n\n\n\nItem malformed: '" .. tostring(item.name) .. "' (item type: " .. itemType .. ")\n\nentity." .. fieldName .. " = " .. tostring(field) .. " (" .. type(field) .. " != " .. expectedType .. ")\n\n\nPlease report this error with the mod the item originates from.\n\n\n\n\n")
	end
end


local function index(entity, type)
	type = type or entity.type

	-- icon = {
	-- 	name = entity.name,
	-- 	type = type,
	-- 	path = entity.icon
	-- }


	typeCheck(entity, type, entity.name, "string", "name")
	local path = ""
	if entity.icon ~= nil then
		typeCheck(entity, type, entity.icon, "string", "icon")
		path = entity.icon:sub(1, -5)
	else
		for i, icon in pairs(entity.icons) do
			typeCheck(entity, type, icon.icon, "string", "icons[" .. i .. "].icon")
			if icon.tint ~= nil then
				typeCheck(entity, type, icon.tint, "table", "icons[" .. i .. "].tint")
				if icon.tint["r"] ~= nil then typeCheck(entity, type, icon.tint["r"], "number", "icons[" .. i .. "].tint.r") end
				if icon.tint["g"] ~= nil then typeCheck(entity, type, icon.tint["g"], "number", "icons[" .. i .. "].tint.g") end
				if icon.tint["b"] ~= nil then typeCheck(entity, type, icon.tint["b"], "number", "icons[" .. i .. "].tint.b") end
				if icon.tint["a"] ~= nil then typeCheck(entity, type, icon.tint["a"], "number", "icons[" .. i .. "].tint.a") end
				path = path .. "|" .. icon.icon:sub(1, -5) .. "?" ..
					math.floor((icon.tint["r"] or 0)*255+0.5) .. "%" ..
					math.floor((icon.tint["g"] or 0)*255+0.5) .. "%" ..
					math.floor((icon.tint["b"] or 0)*255+0.5) .. "%" ..
					math.floor((icon.tint["a"] or 1)*255+0.5)
			else
				path = path .. "|" .. icon.icon:sub(1, -5)
			end
		end
		path = path:sub(2)
	end

	log("FactorioMaps_Output_RawTagPaths:".. type .. entity.name:sub(1,1):upper() .. entity.name:sub(2) .. ":" .. path)

	-- in 0.17, we will hopefully be able to use writefile in the data stage instead..
end


for _, signal in pairs(data.raw["virtual-signal"]) do
	index(signal, "virtual")
end

-- 2.0 update: defines.prototypes finally lets us enumerate all item subtypes
for type in pairs(defines.prototypes["item"]) do
	for _, item in pairs(data.raw[type] or {}) do
		index(item, "item")
	end
end

for _, fluid in pairs(data.raw["fluid"]) do
	index(fluid)
end

-- planet icons, used by the surface list in the web ui
for _, planet in pairs(data.raw["planet"] or {}) do
	index(planet, "planet")
end





-- user_tiles = []
-- for key, item in pairs(data.raw["item"]) do
-- 	if item.place_as_tile then

-- 	end
-- end


-- for key, tile in pairs(data.raw["tile"]) do
-- 	no = "NO"
-- 	if tile.items_to_place_this then
-- 		no = "YES"
-- 	end
-- 	log(key .. " " .. no)
-- end


-- blank out alert icons so they dont show up on screenshots
for _, name in pairs({
	"ammo_icon", "danger_icon", "destroyed_icon", "electricity_icon", "electricity_icon_unplugged",
	"fluid_icon", "fuel_icon", "no_building_material_icon", "no_storage_space_icon",
	"not_enough_construction_robots_icon", "not_enough_repair_packs_icon", "recharge_icon",
	"too_far_from_roboport_icon", "warning_icon"
}) do
	local sprite = data.raw["utility-sprites"].default[name]
	if sprite ~= nil then
		sprite.filename = "__L0laapk3_FactorioMaps__/graphics/empty64.png"
	end
end
local itemRequestProxy = data.raw["item-request-proxy"]["item-request-proxy"]
if itemRequestProxy and itemRequestProxy.picture then -- removed in 2.0, uses an alert icon now
	itemRequestProxy.picture.filename = "__L0laapk3_FactorioMaps__/graphics/empty64.png"
end












