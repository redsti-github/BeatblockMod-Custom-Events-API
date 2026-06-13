local info = {
	event = 'unknownCustomEvent',
	name = 'Unknown Custom Event',
	tooltip = '¯\\_(ツ)_/¯',
	mod = "Custom Events API",
	custom = true,
	storeInChart = false,
	hideOrder = true,
	hideVariant = true
}

local function editorProperties(v)
	imgui.Separator()
	imgui.Text("!! Custom event '" .. tostring(v.customEventData.type) .. "' was not found !!")
	imgui.Text("Missing mod '" .. tostring(v.info.modName) .. "'.")
	imgui.Text("(or one of your mods is broken and being silly)")
	imgui.Separator()
	imgui.Text("contains " .. tostring(#v.packedEvents) .. " events")
end

local function convertToVanilla(v)
	return v.packedEvents
end


return info, editorDraw, editorProperties, checkActiveRange, convertToVanilla
