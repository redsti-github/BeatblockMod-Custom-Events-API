
-- if custom.storeInChart == false, then we place everything into 'level', new.forceStoreInLevel = true, new.variant = custom.variant

-- else, if configs.storeInChart == true, we have more of a dilema
--		generated events that have new.storeInChart == true, can simply go into the chart (IF that is the variant we're editing!!)
--		other events (including the driver comment) must go into the level, but can be tagged with new.variant = custom.variant

local customEvents = {
	configs = {
		modded = {},
		vanilla = {} -- (vanilla compatible)
	}
}

function customEvents:init()
	-- partially stolen from BeatblockPlus
	local modsPath = "Mods"
	if not love.filesystem.getInfo(modsPath, 'directory') then
		log("[CustomEvents] Failed to find Mods directory. Custom events won't be loaded.", "error")
		return
	end

	for _, modId in ipairs(love.filesystem.getDirectoryItems(modsPath)) do
		local modPath = modsPath .. "/" .. modId
		if not love.filesystem.getInfo(modPath, 'directory') then goto nextMod end
		if not love.filesystem.getInfo(modPath .. "/custom-events.json", 'file') then goto nextMod end
		if not love.filesystem.getInfo(modPath .. "/mod.json", 'file') then goto nextMod end

		local configList = dpf.loadJson(modPath .. "/custom-events.json")
		local modInfo = dpf.loadJson(modPath .. "/mod.json")
		if #configList == 0 then
			log("[CustomEvents] file '" .. modPath .. "/custom-events.json' does not contain any events.", "error")
			goto nextMod
		end

		for i,config in ipairs(configList) do
			if config.source == nil then
				log("[CustomEvents] '" .. modPath .. "/custom-events.json': missing 'source' field", "error")
				goto nextConfig
			end
			if type(config.source) ~= "string" then
				log("[CustomEvents] '" .. modPath .. "/custom-events.json': 'source' field must be a string", "error")
				goto nextConfig
			end
			local evFile = modPath.."/"..config.source
			if not love.filesystem.getInfo(evFile, 'file') then
				log("[CustomEvents] Failed to open file '" .. evFile .. "', skipping.", "error")
				goto nextConfig
			end
			config.source = evFile

			if config.type == nil then
				log("[CustomEvents] '" .. modPath .. "/custom-events.json': missing 'type' field", "error")
				goto nextConfig
			end
			if type(config.type) ~= "string" then
				log("[CustomEvents] '" .. modPath .. "/custom-events.json': 'type' field must be a string", "error")
				goto nextConfig
			end

			config.modId = modInfo.id
			config.modName = modInfo.name
			if config.type == "modded" then
				table.insert(self.configs.modded, config)
			elseif config.type == "vanilla-compatible" then
				table.insert(self.configs.vanilla, config)
			else
				log("[CustomEvents] '" .. modPath .. "/custom-events.json': 'type' field has invalid value '" .. config.type .. "'", "error")
				goto nextConfig
			end

			if config.icon then
				local iconPath = modPath .. "/" .. config.icon
				if love.filesystem.getInfo(iconPath, 'file') then
					config.icon = love.graphics.newImage(iconPath)
				else
					log("[CustomEvents] image '" .. iconPath "' not found.", "error")
					config.icon = nil
				end
			end

			::nextConfig::
		end
		::nextMod::
	end
end

function customEvents:loadEvents(eList)
	for i,conf in ipairs(self.configs.modded) do
		table.insert(eList, conf) -- note: this gets marked as modded in another patch
	end
	for i,conf in ipairs(self.configs.vanilla) do
		local info, editorDraw, editorProperties, checkActiveRange, convertToVanilla = dofile(conf.source)
		info.modId = conf.modId
		info.modName = conf.modName
		info.custom = true

		Event.editorDraw[info.event] = editorDraw or conf.icon
		Event.editorProperties[info.event] = editorProperties

		checkActiveRange = checkActiveRange or function(event, beat, lastBeat)
			return event.time >= beat and event.time <= lastBeat
		end
		Event.checkActiveRange[info.event] = function(v, beat, lastBeat) -- hide events that are "stored in other charts"
			local storeInChart = Event.info[v.type].storeInChart and not v.forceStoreInLevel
			if v.type == "unknownCustomEvent" then storeInChart = v.info.storeInChart end
			if storeInChart and v.variant and v.variant ~= cs.variant.name then
				return false
			else
				return checkActiveRange(v, beat, lastBeat)
			end
		end

		Event.convertToVanilla[info.event] = convertToVanilla

		Event.info[info.event] = info
		log('loaded event "'..info.name..'" ('..info.event..')')
	end
end

local function randomID()
	local id = ""
	for i=1,16 do -- there are ~10^22 possible IDs, so we shouldn't get collisions
		id = id .. string.char(math.random(97,122))
	end
	return id
end
function customEvents.unpack(events, levelVariant) -- unpack custom events into vanilla ones (returns a new array)
	local newEvents = {}
	for i,v in ipairs(events) do
		if not Event.info[v.type] then
			cs:playbackError("Event '" .. v.type .. "' not found!\n\nMissing mod: '" .. tostring(v.info and v.info.modName or nil) .. "'")
			if cs.name == "Editor" then
				cs.errorExit = true
			end
			return {}
		end

		if not Event.info[v.type].custom then
			if Event.info[v.type].modded then
				v.info = {
					modName = Event.info[v.type].modName,
					modId = Event.info[v.type].modId
				}
			end
			table.insert(newEvents, v)
			goto nextEvent
		end

		local generatedEvents = Event.convertToVanilla[v.type](v, newEvents)
		local storeInChart = Event.info[v.type].storeInChart and not v.forceStoreInLevel
		local modName = Event.info[v.type].modName

		if v.type == "unknownCustomEvent" then
			storeInChart = v.info.storeInChart
			modName = v.info.modName
			v = v.customEventData
		end

		local id = v.customEventId or randomID()
		if storeInChart and not v.variant then v.variant = levelVariant.name end
		local variant = v.variant

		local dataComment = {
			type = "comment",
			text = "!! THIS IS A CUSTOM EVENT !!\n mod: '" .. tostring(modName) .. "'\n event: '" .. v.type .. "'.\nYou probably want to install the required mod if you want to edit this chart properly.",
			time = v.time,
			angle = v.angle,
			customEventId = id,
			customEventData = v,
			variant = variant,
			info = {
				storeInChart = storeInChart,
				modName = modName,
			},
		}
		table.insert(newEvents, dataComment)

		for i,new in ipairs(generatedEvents) do
			new.customEventId = id
			new.variant = variant
			new.customEventData = nil -- just in case
			if Event.info[new.type].storeInChart then
				if storeInChart then
					new.variant = nil
					if variant == levelVariant.name then
						table.insert(newEvents, new)
					end
				else
					new.forceStoreInLevel = true
					table.insert(newEvents, new)
				end
			else
				table.insert(newEvents, new)
			end
		end
		::nextEvent::
	end

	return newEvents
end

function customEvents.pack(events, variant) -- pack vanilla events into custom ones (returns a new array)
	local unrecognisedEvents = {} -- id -> list of events
	for i,v in ipairs(events) do
		if v.customEventData and not Event.info[v.customEventData.type] then
			unrecognisedEvents[v.customEventId] = {}
		end
	end

	-- gather unrecognised events
	for i,v in ipairs(events) do
		if v.customEventId and unrecognisedEvents[v.customEventId] and not v.customEventData then
			table.insert(unrecognisedEvents[v.customEventId], v)
		end
	end

	local newEvents = {}
	for i,v in ipairs(events) do
		if not v.customEventId then -- normal events
			table.insert(newEvents, v)
			goto nextEvent
		end
		if not v.customEventData then -- these events get packed up
			goto nextEvent
		end

		if unrecognisedEvents[v.customEventId] then
			local new = {
				type = "unknownCustomEvent",
				time = v.time,
				angle = v.angle,
				customEventData = v.customEventData,
				customEventId = v.customEventId,
				variant = v.variant,
				packedEvents = unrecognisedEvents[v.customEventId],
				info = v.info,
			}
			table.insert(newEvents, new)
		else
			local new = v.customEventData -- normal custom event
			new.customEventId = v.customEventId
			table.insert(newEvents, new)
		end
		::nextEvent::
	end

	return newEvents
end

function customEvents:updateEventPalette(palette)
	for _,conf in ipairs(self.configs.vanilla) do
		if conf.palette then
			local p = palette
			for _,folder in ipairs(conf.palette) do
				if not p[folder] then p[folder] = {} end
				p = p[folder]
			end
			local info = dofile(conf.source)
			table.insert(p, info.event)
		end
	end
	for _,conf in ipairs(self.configs.modded) do
		if conf.palette then
			local p = palette
			for _,folder in ipairs(conf.palette) do
				if not p[folder] then p[folder] = {} end
				p = p[folder]
			end
			local info = dofile(conf.source)
			table.insert(p, info.event)
		end
	end
end

return customEvents
