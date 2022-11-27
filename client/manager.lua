local imgui          = require("imgui")
local atexit         = require("atexit")
local directory_view = require("directory_view")

local SCRIPTS_DIR = "scripts"
local DOWNLOADED_DIR = "downloaded"
local CONFIG_FILE = "scriptinfo"

local manager = {
	how_are_you_holding_up = "because I'm a potato",
}

local function log(str)
	print(str) -- TODO: something better
end

local atexit_manager = atexit.make_atexit()
function manager.unload()
	atexit_manager:exit()
end

local function add_permanent_global(key, value)
	_G[key] = value
	atexit_manager:atexit(function()
		_G[key] = nil
	end)
end

local function add_permanent_event(name, func)
	event.register(name, func)
	atexit_manager:atexit(function()
		event.unregister(name, func)
	end)
end

local myimgui = imgui.make_imgui()

local x, y, w, h = 250, 50, 300, 300
local ox, oy, ow, oh
local mw, mh = 300, 200
local showing = "scripts"
local function tick_handler()
	myimgui:begin_frame(x, y)
	myimgui:min_size(w, h)
	myimgui:primary_dimension(imgui.VERTICAL)
	myimgui:border(true)
	myimgui:background(true)
	do
		myimgui:begin_horiz_panel("nav")
		myimgui:size(15)
		do
			myimgui:begin_dragger("resize")
			myimgui:size(15)
			myimgui:grooves(true)
			local resize_result = myimgui:end_dragger("resize")
			if resize_result then
				if resize_result.last then
					ox, oy, ow, oh = nil, nil, nil, nil
				else
					if resize_result.first then
						ox, oy, ow, oh = x, y, w, h
					end
					w, h = ow - resize_result.diff_x, oh - resize_result.diff_y
					w = math.max(mw, w)
					h = math.max(mh, h)
					local diff_x, diff_y = ow - w, oh - h
					x, y = ox + diff_x, oy + diff_y
				end
			end
		end
		myimgui:begin_style("nav_buttons")
		do
			myimgui:space_before(-1)
			myimgui:size(50)
			if myimgui:button("scripts", "Scripts", showing == "scripts") then
				showing = "scripts"
			end
			if myimgui:button("settings", "Settings", showing == "settings") then
				showing = "settings"
			end
		end
		myimgui:end_style("nav_buttons")
		do
			myimgui:begin_dragger("move")
			myimgui:space_before(-1)
			myimgui:text("TPT Script Manager v4.dev")
			myimgui:text_alignment(imgui.RIGHT)
			myimgui:padding(3)
			local move_result = myimgui:end_dragger("move")
			if move_result then
				if move_result.last then
					ox, oy = nil, nil
				else
					if move_result.first then
						ox, oy = x, y
					end
					x, y = ox + move_result.diff_x, oy + move_result.diff_y
					x = math.max(0, math.min(gfx.WIDTH - w, x))
					y = math.max(0, math.min(gfx.HEIGHT - h, y))
				end
			end
		end
		myimgui:begin_button("close", "\238\128\170")
		myimgui:text_nudge(0, -1)
		myimgui:size(15)
		myimgui:space_before(-1)
		if myimgui:end_button("close") then
			print("bye")
		end
		myimgui:end_horiz_panel("nav")
	end
	do
		myimgui:begin_vert_panel("content_outer")
		myimgui:space_before(-1)
		myimgui:padding(1)
		do
			myimgui:begin_vert_panel("content")
			myimgui:padding(1)
			myimgui:fill_parent(1)
			for i = 1, 15 do
				myimgui:begin_button(i, "Marco " .. i)
				myimgui:size(15)
				if i == 3 then
					myimgui:space_before(-1)
				end
				if i == 4 then
					myimgui:disabled(true)
				end
				do
					myimgui:padding(5)
					myimgui:begin_button("bruh", "End my " .. (i - 3))
					myimgui:max_size(70)
					if i == 4 then
						myimgui:disabled(true)
					end
					if myimgui:end_button("bruh") then
						print("Suffering " .. (i - 3))
					end
				end
				if myimgui:end_button(i) then
					print("Polo " .. i)
				end
			end
			myimgui:end_vert_panel("content")
		end
		myimgui:end_vert_panel("content_outer")
	end
	myimgui:end_frame()
end

local function mousedown_handler(x, y, button)
	return myimgui:mousedown_handler(button)
end

local function mouseup_handler(x, y, button, reason)
	return myimgui:mouseup_handler(button, reason)
end

local function mousewheel_handler(x, y, offset)
	return myimgui:mousewheel_handler(offset)
end

local function mousemove_handler(x, y)
	return myimgui:mousemove_handler(x, y)
end

local function blur_handler()
	return myimgui:blur_handler()
end

local function ends_with(str, with)
	return str:sub(-#with, -1) == with
end

local manager_dv = directory_view.from_path(".")

-- local function register_from_path(path)
-- 	if fs.isFile(path) and ends_with(path:lower(), ".lua") then
-- 		-- TODO
-- 		return
-- 	end
-- 	local dv
-- 	if fs.isDirectory(path) then
-- 		dv = directory_view_from_path(path)
-- 	elseif fs.isFile(path) and ends_with(path:lower(), ".tar.bz2") then
-- 		dv = directory_view_from_tarball(path)
-- 	end
-- 	if dv and dv:isFile(path .. "/init.lua") then
-- 		-- TODO
-- 		return

-- 	end
-- end

-- for _, item in ipairs(fs.list("scripts")) do
-- 	register_from_path("scripts/" .. item)
-- end

if type(_G.manager) == "table" and _G.manager.how_are_you_holding_up == "because I'm a potato" then
	local failed
	xpcall_wrap(_G.manager.unload, function()
		failed = true
	end)
	if failed then
		error("failed to unload active script manager instance, try restarting TPT")
	end
end
add_permanent_global("manager", manager)
add_permanent_event(event.tick, xpcall_wrap(tick_handler))
add_permanent_event(event.mousedown, xpcall_wrap(mousedown_handler))
add_permanent_event(event.mouseup, xpcall_wrap(mouseup_handler))
add_permanent_event(event.mousewheel, xpcall_wrap(mousewheel_handler))
add_permanent_event(event.mousemove, xpcall_wrap(mousemove_handler))
add_permanent_event(event.blur, xpcall_wrap(blur_handler))

local function validate_manifest(manifest)
	return false -- TODO
end

local config, save_config
do
	local config_file_path = SCRIPTS_DIR .. "/" .. DOWNLOADED_DIR .. "/" .. CONFIG_FILE

	function save_config()
		local data = serde.serialize(config)
		local ok, err = manager_dv:writeall(config_file_path, data)
		if not ok then
			log("cannot save config: " .. err)
		end
	end

	local config
	if manager_dv:exists(config_file_path) then
		local data, err = manager_dv:readall(config_file_path)
		if data then
			local ok
			ok, err = pcall(serde.unserialize, data)
			if ok then
				config = err
			end
		end
		if not config then
			log("cannot load config: " .. err)
		end
	end

	local good = true
	local function sanitize_node(cond, node, default)
		if not cond then
			good = false
			return default
		end
		return node
	end
	config = sanitize_node(type(config) == "table", config, {})
	config.manifest = sanitize_node(validate_manifest(config.manifest), config.manifest, nil)
	if not good then
		log("detected inconsistencies in config")
	end
end

return manager
