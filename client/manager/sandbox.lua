local util            = require("manager.util")
local logger          = require("manager.logger")
local environment     = require("manager.environment")
local check           = require("manager.check")
local atexit          = require("manager.atexit")
local no_yield        = require("manager.no_yield")
local blocking_prompt = require("manager.blocking_prompt")

local shared_runner = blocking_prompt.make_runner()

local CALLBACK_PROPERTY = {
	[ "Update"        ] = true,
	[ "Graphics"      ] = true,
	[ "Create"        ] = true,
	[ "CreateAllowed" ] = true,
	[ "ChangeType"    ] = true,
	[ "CtypeDraw"     ] = true,
}
local ELTRANSITION_TO_PROPERTY = {
	[ "presLowValue"  ] = "LowPressure",
	[ "presLowType"   ] = "LowPressureTransition",
	[ "presHighValue" ] = "HighPressure",
	[ "presHighType"  ] = "HighPressureTransition",
	[ "tempLowValue"  ] = "LowTemperature",
	[ "tempLowType"   ] = "LowTemperatureTransition",
	[ "tempHighValue" ] = "HighTemperature",
	[ "tempHighType"  ] = "HighTemperatureTransition",
}
local EL_TO_PROPERTY = {
	[ "menu"     ] = "MenuVisible",
	[ "heat"     ] = "Temperature",
	[ "hconduct" ] = "HeatConduct",
}
local BLOCKING_PROMPT_AVAILABLE = {
	[ event.textinput                   ] = true,
	[ event.textediting                 ] = true,
	[ event.keypress                    ] = true,
	[ event.keyrelease                  ] = true,
	[ event.mousedown                   ] = true,
	[ event.mouseup                     ] = true,
	[ event.mousemove                   ] = true,
	[ event.mousewheel                  ] = true,
	[ event.tick                        ] = true, -- actually ignores the "stop" return value but it's fine
	[ "register_once_compat_mouseclick" ] = true,
	[ "register_once_compat_keypress"   ] = true,
}

local sandboxes = {}
local function broadcast_element_id(identifier, id)
	for _, sandbox in pairs(sandboxes) do
		sandbox.elements[identifier] = id
	end
end

local function make_element_resource(identifier)
	return {
		identifier = identifier,
		properties = {},
	}
end
local element_resources = {}
for i = 1, sim.PT_NUM - 1 do
	if elem.exists(i) then
		element_resources[i] = make_element_resource(elem.property(i, "Identifier"))
		element_resources[i].default = true
		element_resources[i].el_name = elem.property(i, "Name"):lower()
	end
end

local event_handler_wrappers = {}
local native_event_types = {}

local function factory(script_name)
	return function(chunks_with_deps, flags)
		-- TODO: use flags
		local sandbox_atexit = atexit.make_atexit()
		assert(not sandboxes[script_name])
		local sandbox_info = {}
		sandboxes[script_name] = sandbox_info
		sandbox_atexit:atexit(function()
			sandboxes[script_name] = nil
		end)
		local script_log = logger.make_logger(script_name)

		local script_runner
		local function make_blocking_wrapper_factory(...)
			local default_args = environment.packn(...)
			return function(func)
				return function(...)
					local runner = script_runner or shared_runner
					local args_out = environment.packn(runner:dispatch(func, ...))
					if runner:status() == "dispatching" then
						if runner == shared_runner then
							shared_runner = blocking_prompt.make_runner()
							script_runner = runner
						end
						return environment.unpackn(default_args)
					end
					return environment.unpackn(args_out)
				end
			end
		end

		local function copy_simple_values(dest, src)
			for key, value in pairs(src) do
				if type(key) == "boolean" or
				   type(key) == "number" or
				   type(key) == "string" then
					dest[key] = value
				end
			end
		end

		local function allow_query_only(func, max_arg_count)
			return function(...)
				if select("#", ...) > max_arg_count then
					error("cannot set query-only property", 2)
				end
				return func(...)
			end
		end

		local script_env = {}
		sandbox_info.script_env = script_env

		for _, name in ipairs({
			"assert",
			"tostring",
			"tonumber",
			"rawget",
			"ipairs",
			"pcall",
			"rawset",
			"rawequal",
			"_VERSION",
			"next",
			"xpcall",
			"setmetatable",
			"pairs",
			"getmetatable",
			"type",
			"error",
			"newproxy",
			"select",
			"unpack",
			"string",
			"bz2",
			"graphics",
			"table",
			"math",
			"bit",
		}) do
			script_env[name] = util.deep_clone(environment.top_level[name])
		end

		script_env._G = script_env
		local mod_require, mod_package = environment.make_require(function(path)
			return chunks_with_deps[path]
		end, script_env)
		script_env.require = mod_require
		script_env.package = mod_package

		script_env.tpt = {
			set_pause          = tpt.set_pause,
			toggle_pause       = tpt.toggle_pause,
			menu_enabled       = allow_query_only(tpt.menu_enabled, 1),
			active_menu        = allow_query_only(tpt.active_menu, 0),
			setfpscap          = allow_query_only(tpt.setfpscap, 0),
			setdrawcap         = allow_query_only(tpt.setdrawcap, 0),
			setwindowsize      = allow_query_only(tpt.setwindowsize, 0),
			set_console        = allow_query_only(tpt.set_console, 0),
			perfectCircleBrush = allow_query_only(tpt.perfectCircleBrush, 0),
			decorations_enable = allow_query_only(tpt.decorations_enable, 0),
			hud                = allow_query_only(tpt.hud, 0),
		}
		for _, name in ipairs({
			"get_elecmap",
			"set_elecmap",
			"log",
			"getPartIndex",
			"create",
			"delete",
			"setfire",
			"set_gravity",
			"get_numOfParts",
			"version",
			"next_getPartIndex",
			"get_wallmap",
			"newtonian_gravity",
			"start_getPartIndex",
			"ambient_heat",
			"heat",
			"num_menus",
		}) do
			script_env.tpt[name] = util.deep_clone(tpt[name])
		end
		if flags["deprecated_20230918"] then
			for _, name in ipairs({
				"drawrect",
				"drawtext",
				"drawline",
				"fillrect",
				"textwidth",
				"drawpixel",
				"get_property",
				"set_property",
				"element",
				"set_pressure",
				"watertest",
			}) do
				script_env.tpt[name] = util.deep_clone(tpt[name])
			end
			if environment.can_yield_xpcall then
				script_env.tpt.message_box = blocking_prompt.message_box
				script_env.tpt.input       = blocking_prompt.input
				script_env.tpt.throw_error = blocking_prompt.throw_error
				script_env.tpt.confirm     = blocking_prompt.confirm
			end
		end

		if flags["priv_tpt"] then
			for _, name in ipairs({
				"menu_enabled",
				"set_clipboard",
				"setwindowsize",
				"active_menu",
				"get_clipboard",
				"record",
				"screenshot",
				"beginGetScript",
				"setfpscap",
				"get_name",
				"perfectCircleBrush",
				"set_wallmap",
				"decorations_enable",
				"set_console",
				"setdebug",
				"reset_spark",
				"reset_gravity_field",
				"setdrawcap",
				"hud",
				"display_mode",
				"reset_velocity",
			}) do
				script_env.tpt[name] = tpt[name]
			end
		end

		local parts_mt = { __index = function(tbl, key)
			return script_env.sim.partProperty(tbl[1], key)
		end, __newindex = function(tbl, key, value)
			script_env.sim.partProperty(tbl[1], key, value)
		end }
		script_env.tpt.parts = setmetatable({}, { __index = function(_, key)
			return setmetatable({ key }, parts_mt)
		end })

		local el_mt = { __index = function(tbl, key)
			return script_env.elem.property(tbl.id, EL_TO_PROPERTY[key] or key:lower())
		end, __newindex = function(tbl, key, value)
			script_env.elem.property(tbl.id, EL_TO_PROPERTY[key] or key:lower(), value)
		end }
		script_env.tpt.el = {}

		local eltransition_mt = { __index = function(tbl, key)
			return script_env.elem.property(tbl.id, ELTRANSITION_TO_PROPERTY[key] or "invalid")
		end, __newindex = function(tbl, key, value)
			script_env.elem.property(tbl.id, ELTRANSITION_TO_PROPERTY[key] or "invalid", value)
		end }
		script_env.tpt.eltransition = {}

		for i, resource in pairs(element_resources) do
			if resource.default then
				script_env.tpt.el[resource.el_name] = setmetatable({ id = i }, el_mt)
				script_env.tpt.eltransition[resource.el_name] = setmetatable({ id = i }, eltransition_mt)
			end
		end

		-- TODO: troll scripts into using non-blocking http request status loops
		script_env.http = {
			getAuthToken = http.getAuthToken,
		}

		if flags["priv_http"] then
			for _, name in ipairs({
				"post",
				"get",
			}) do
				script_env.http[name] = http[name]
			end
		end

		if flags["priv_fs"] then
			script_env.fileSystem = {
				exists          = fs.exists,
				list            = fs.list,
				removeDirectory = fs.removeDirectory,
				isFile          = fs.isFile,
				removeFile      = fs.removeFile,
				move            = fs.move,
				copy            = fs.copy,
				makeDirectory   = fs.makeDirectory,
				isDirectory     = fs.isDirectory,
				isLink          = fs.isLink,
			}
			script_env.io = {
				input   = io.input,
				stdin   = io.stdin,
				read    = io.read,
				output  = io.output,
				open    = io.open,
				close   = io.close,
				write   = io.write,
				flush   = io.flush,
				type    = io.type,
				lines   = io.lines,
				stdout  = io.stdout,
				stderr  = io.stderr,
			}
		end

		script_env.platform = {
			ident       = plat.ident,
			releaseType = plat.releaseType,
			platform    = plat.platform,
		}

		if flags["priv_plat"] then
			for _, name in ipairs({
				"exeName",
				"clipboardPaste",
				"clipboardCopy",
				"openLink",
				"restart",
			}) do
				script_env.platform[name] = plat[name]
			end
		end

		script_env.socket = {
			gettime = socket.gettime,
		}

		if flags["priv_socket"] then
			for _, name in ipairs({
				"tcp",
			}) do
				script_env.socket[name] = socket[name]
			end
		end

		script_env.coroutine = {
			wrap        = coroutine.wrap,
			yield       = no_yield.yield,
			resume      = coroutine.resume,
			status      = coroutine.status,
			isyieldable = no_yield.isyieldable,
			running     = coroutine.running,
			create      = coroutine.create,
		}

		script_env.os = {
			difftime = os.difftime,
			date     = os.date,
			time     = os.time,
			clock    = os.clock,
		}

		script_env.elements = {}
		copy_simple_values(script_env.elements, elem)
		sandbox_info.elements = script_env.elements

		function script_env.elements.allocate(group, name)
			check.is_string(group, "group", 2)
			check.is_string(name , "name" , 2)
			name = name:upper()
			group = group:upper()
			if name:find("_") then
				error("name may not contain _", 2)
			end
			if group:find("_") then
				error("group may not contain _", 2)
			end
			if group == "DEFAULT" then
				error("cannot allocate elements in group DEFAULT", 2)
			end
			local identifier = ("%s_PT_%s"):format(group, name)
			if elem[identifier] then
				error("identifier already in use", 2)
			end
			local id = elem.allocate(group, name)
			if id ~= -1 then
				broadcast_element_id(identifier, id)
				element_resources[id] = make_element_resource(identifier)
				element_resources[id].atexit_entry = sandbox_atexit:atexit(function(log, requester_name)
					if requester_name ~= script_name then
						sandboxes[requester_name].script_log:wrn("freeing %s of %s; this may cause issues later", identifier, script_name)
					end
					elem.free(id)
					element_resources[id] = nil
					broadcast_element_id(identifier, nil)
				end)
				element_resources[id].script_name = script_name
			end
			return id
		end

		function script_env.elements.free(id)
			if not element_resources[id] then
				error("invalid element", 2)
			end
			if element_resources[id].default then
				error("cannot free elements in group DEFAULT", 2)
			end
			element_resources[id].atexit_entry:exit_now(script_log, script_name)
		end

		function script_env.elements.loadDefault(id)
			local function reset(id)
				if element_resources[id].default then
					util.foreach_clean(element_resources[id].properties, function(_, resource)
						resource.atexit_entry:exit_now()
					end)
				else
					script_env.elements.free(id)
				end
			end
			if id then
				if not element_resources[id] then
					error("invalid element", 2)
				end
				reset(id)
			else
				for i = 0, sim.PT_NUM - 1 do
					reset(i)
				end
			end
		end

		function script_env.elements.element(id, tbl)
			if not element_resources[id] then
				error("invalid element", 2)
			end
			if tbl then
				for property, value in pairs(tbl) do
					if property ~= "Identifier" then
						script_env.elements.property(id, property, value)
					end
				end
				return
			end
			return elem.element(id)
		end

		local function property_mux(id, property, ...)
			local can_move_into_id = property ~= "Properties" and type(property) == "string" and property:match("^_CanMove_(%d+)$")
			if can_move_into_id then
				return sim.can_move(id, tonumber(can_move_into_id), ...)
			end
			return elem.property(id, property, ...)
		end

		local function property_common(id, property, value, mode)
			local function register_property(reset_to)
				if element_resources[id].properties[property] then
					local other_script_name = element_resources[id].properties[property].script_name
					if script_name ~= other_script_name then
						script_log:wrn("overwriting %s of %s set by %s; this may cause issues later", property, element_resources[id].identifier, other_script_name)
					end
				else
					local resource = {
						script_name = script_name,
					}
					element_resources[id].properties[property] = resource
					if element_resources[id].default then
						resource.atexit_entry = sandbox_atexit:atexit(function()
							property_mux(id, property, reset_to)
							element_resources[id].properties[property] = nil
						end)
					end
				end
			end
			if CALLBACK_PROPERTY[property] then
				property_mux(id, property, value, mode)
				register_property(false)
				return
			end
			local initial_value = property_mux(id, property)
			if value == nil then
				return initial_value
			end
			property_mux(id, property, value)
			register_property(initial_value)
		end

		function script_env.elements.property(id, property, ...)
			if select("#", ...) == 0 then
				return elem.property(id, property)
			end
			if type(property) == "string" and property:sub(1, 1) == "_" then
				error("invalid element property", 2)
			end
			return property_common(id, property, ...)
		end

		function script_env.elements.exists(id)
			return element_resources[id] and true or false
		end

		for id, info in pairs(element_resources) do
			script_env.elements[info.identifier] = id
		end

		script_env.interface = {
			beginInput      = ui.beginInput,
			beginThrowError = ui.beginThrowError,
			beginMessageBox = ui.beginMessageBox,
			beginConfirm    = ui.beginConfirm,
			textInputRect   = ui.textInputRect,
			showWindow      = ui.showWindow,
			closeWindow     = ui.closeWindow,
		}
		copy_simple_values(script_env.interface, ui)

		local components_added = {}

		function script_env.interface.addComponent(component)
			if components_added[component] then
				return
			end
			ui.addComponent(component)
			components_added[component] = sandbox_atexit:atexit(function()
				ui.removeComponent(component)
			end)
		end

		function script_env.interface.removeComponent(component)
			local atexit_entry = components_added[component]
			if not atexit_entry then
				return
			end
			atexit_entry:exit_now()
		end

		local textinput_grabs = {}
		local textinput_drops = {}

		function script_env.interface.grabTextInput()
			local atexit_entry = next(textinput_drops)
			if atexit_entry then
				atexit_entry:exit_now()
				return
			end
			ui.grabTextInput()
			textinput_grabs[sandbox_atexit:atexit(function()
				ui.dropTextInput()
			end)] = true
		end

		function script_env.interface.dropTextInput()
			local atexit_entry = next(textinput_grabs)
			if atexit_entry then
				atexit_entry:exit_now()
				return
			end
			ui.dropTextInput()
			textinput_drops[sandbox_atexit:atexit(function()
				ui.grabTextInput()
			end)] = true
		end

		local windows_should_close = false
		sandbox_atexit:atexit(function()
			windows_should_close = true
		end)

		local function divert_closeWindow_shim(name, func)
			return function(window, ...)
				if windows_should_close then
					func = nil
					if name == "onTick" then
						ui.closeWindow(window)
					end
					return
				end
				return func(window, ...)
			end
		end

		for _, name in ipairs({
			"Slider",
			"Textbox",
			"ProgressBar",
			"Checkbox",
			"Window",
			"Button",
			"Label",
		}) do
			local real_new = _G[name].new
			local proxy_to_component = setmetatable({}, { __mode = "k" })
			local value_override = {}
			local blocking_wrapper_factory = make_blocking_wrapper_factory()
			local mt = { __index = function(proxy, key)
				local component = assert(proxy_to_component[proxy], "invalid proxy")
				local value = assert(component[key], "invalid key")
				if not value_override[value] then
					if type(value) == "function" and key:find("^on[A-Z]") then
						value = blocking_wrapper_factory(value)
					end
					if name == "Window" then
						value = divert_closeWindow_shim(key, value)
					end
					value_override[value] = value
				end
				return value_override[value]
			end }
			local function new(...)
				local component = real_new(...)
				local proxy = setmetatable({}, mt)
				proxy_to_component[proxy] = component
				return proxy
			end
			script_env[name] = {
				new = new,
			}
		end

		script_env.event = {
			getmodifiers = evt.getmodifiers,
		}
		copy_simple_values(script_env.event, evt)


		local register_common
		do
			local blocking_wrapper_factory = make_blocking_wrapper_factory(false)

			function register_common(etype, func, register_once, reg_func, unreg_func)
				if type(func) ~= "function" then
					error("invalid event handler", 3)
				end
				local registry = event_handler_wrappers[etype]
				if not registry[func] then
					local wrapper = environment.xpcall_wrap(func, function(_, full)
						script_log:err("error in %s event handler: %s", etype, full)
					end)
					if BLOCKING_PROMPT_AVAILABLE[etype] then
						wrapper = blocking_wrapper_factory(wrapper)
					end
					registry[func] = {
						wrapper        = wrapper,
						atexit_entries = {},
					}
				end
				if not (register_once and next(registry[func].atexit_entries)) then
					reg_func(registry[func].wrapper)
					local atexit_entry
					atexit_entry = sandbox_atexit:atexit(function()
						unreg_func(registry[func].wrapper)
						registry[func].atexit_entries[atexit_entry] = nil
						if not next(registry[func].atexit_entries) then
							registry[func] = nil
						end
					end)
					registry[func].atexit_entries[atexit_entry] = true
				end
				return func
			end
		end

		local function unregister_common(etype, func)
			if type(func) ~= "function" then
				error("invalid event handler", 3)
			end
			local registry = event_handler_wrappers[etype]
			if registry[func] then
				local atexit_entry = next(registry[func].atexit_entries)
				if atexit_entry then
					atexit_entry:exit_now()
				end
			end
		end

		function script_env.event.register(etype, func)
			if not native_event_types[etype] then
				error("invalid event type", 2)
			end
			return register_common(etype, func, false, function(wrapper)
				evt.register(etype, wrapper)
			end, function(wrapper)
				evt.unregister(etype, wrapper)
			end)
		end

		function script_env.event.unregister(etype, func)
			if not native_event_types[etype] then
				error("invalid event type", 2)
			end
			unregister_common(etype, func)
		end

		if flags["deprecated_20230918"] then
			local function register_once_compat_event(name)
				local etype = "register_once_compat_" .. name
				event_handler_wrappers[etype] = {}
				script_env.tpt["register_" .. name] = function(func)
					register_common(etype, func, true, tpt["register_" .. name], tpt["unregister_" .. name])
				end
				script_env.tpt["unregister_" .. name] = function(func)
					unregister_common(etype, func)
				end
			end
			register_once_compat_event("mouseclick")
			register_once_compat_event("keypress")
		end

		for key, value in pairs(evt) do
			if type(value) == "number" then -- TODO: not ideal, event constants should be possible to discern by key
				event_handler_wrappers[value] = {}
				native_event_types[value] = true
			end
		end

		if flags["deprecated_20230918"] then
			function script_env.tpt.register_step(func)
				script_env.evt.register(script_env.evt.tick, func)
			end

			function script_env.tpt.unregister_step(func)
				script_env.evt.unregister(script_env.evt.tick, func)
			end

			script_env.tpt.register_keyevent     = script_env.tpt.register_keypress
			script_env.tpt.unregister_keyevent   = script_env.tpt.unregister_keypress
			script_env.tpt.register_mouseevent   = script_env.tpt.register_mouseclick
			script_env.tpt.unregister_mouseevent = script_env.tpt.unregister_mouseclick

			function script_env.tpt.element_func(func, id, mode)
				script_env.elem.property(id, "Update", func or false, mode)
			end

			function script_env.tpt.graphics_func(func, id)
				script_env.elem.property(id, "Graphics", func or false)
			end
		end

		script_env.simulation = {
			gspeed            = allow_query_only(sim.gspeed, 0),
			temperatureScale  = allow_query_only(sim.temperatureScale, 0),
			replaceModeFlags  = allow_query_only(sim.replaceModeFlags, 0),
			framerender       = allow_query_only(sim.framerender, 0),
			waterEqualisation = allow_query_only(sim.waterEqualisation, 0),
			waterEqualization = allow_query_only(sim.waterEqualization, 0),
			airMode           = allow_query_only(sim.airMode, 0),
			ensureDeterminism = allow_query_only(sim.ensureDeterminism, 0),
			prettyPowders     = allow_query_only(sim.prettyPowders, 0),
			ambientHeat       = allow_query_only(sim.ambientHeat, 0),
			ambientAirTemp    = allow_query_only(sim.ambientAirTemp, 0),
			customGravity     = allow_query_only(sim.customGravity, 0),
			randomseed        = allow_query_only(sim.randomseed, 0),
			edgeMode          = allow_query_only(sim.edgeMode, 0),
			gravityMode       = allow_query_only(sim.gravityMode, 0),
			gravityGrid       = allow_query_only(sim.gravityGrid, 0),
		}
		for _, name in ipairs({
			"decoBrush",
			"neighbors",
			"toolBox",
			"partExists",
			"decoColor",
			"toolLine",
			"adjustCoords",
			"partChangeType",
			"partKill",
			"photons",
			"decoLine",
			"decoBox",
			"partProperty",
			"createBox",
			"createParts",
			"partID",
			"createWalls",
			"partPosition",
			"pmap",
			"gravMap",
			"elementCount",
			"createLine",
			"partNeighbours",
			"floodDeco",
			"createWallBox",
			"floodParts",
			"decoColour",
			"velocityX",
			"floodWalls",
			"toolBrush",
			"clearRect",
			"hash",
			"neighbours",
			"pressure",
			"partNeighbors",
			"lastUpdatedID",
			"createWallLine",
			"brush",
			"partCreate",
			"velocityY",
			"parts",
		}) do
			script_env.simulation[name] = sim[name]
		end
		copy_simple_values(script_env.simulation, sim)

		if flags["priv_sim"] then
			for _, name in ipairs({
				"gravityGrid",
				"gravityMode",
				"edgeMode",
				"randomseed",
				"resetTemp",
				"clearSim",
				"customGravity",
				"ambientAirTemp",
				"ambientHeat",
				"prettyPowders",
				"ensureDeterminism",
				"resetPressure",
				"airMode",
				"waterEqualisation",
				"waterEqualization",
				"gspeed",
				"updateUpTo",
				"temperatureScale",
				"deleteStamp",
				"listCustomGol",
				"saveStamp",
				"reloadSave",
				"loadSave",
				"removeCustomGol",
				"replaceModeFlags",
				"addCustomGol",
				"framerender",
				"getSaveID",
				"loadStamp",
				"takeSnapshot",
				"historyRestore",
				"historyForward",
				"signs",
			}) do
				script_env.simulation[name] = sim[name]
			end
		end

		function script_env.simulation.can_move(moving_id, into_id, value)
			return property_common(moving_id, "_CanMove_" .. into_id, value)
		end

		script_env.debug = {
			traceback = debug.traceback,
		}

		script_env.renderer = {
			depth3d      = ren.depth3d,
			zoomScope    = allow_query_only(ren.zoomScope, 0),
			renderModes  = allow_query_only(ren.renderModes, 0),
			zoomEnabled  = allow_query_only(ren.zoomEnabled, 0),
			zoomWindow   = allow_query_only(ren.zoomWindow, 0),
			colourMode   = allow_query_only(ren.colourMode, 0),
			colorMode    = allow_query_only(ren.colorMode, 0),
			decorations  = allow_query_only(ren.decorations, 0),
			displayModes = allow_query_only(ren.displayModes, 0),
			showBrush    = allow_query_only(ren.showBrush, 0),
			debugHUD     = allow_query_only(ren.debugHUD, 0),
			grid         = allow_query_only(ren.grid, 0),
		}
		copy_simple_values(script_env.renderer, ren)

		if flags["priv_ren"] then
			for _, name in ipairs({
				"zoomScope",
				"renderModes",
				"zoomEnabled",
				"zoomWindow",
				"depth3d",
				"colourMode",
				"colorMode",
				"decorations",
				"displayModes",
				"showBrush",
				"debugHUD",
				"grid",
			}) do
				script_env.renderer[name] = ren[name]
			end
		end

		for short, name in pairs({
			gfx  = "graphics",
			elem = "elements",
			evt  = "event",
			plat = "platform",
			fs   = "fileSystem",
			ren  = "renderer",
			sim  = "simulation",
			ui   = "interface",
		}) do
			script_env[short] = script_env[name]
		end

		sandbox_info.script_log = script_log
		function script_env.print(...)
			local strs = {}
			local args = util.packn(...)
			for i = 1, args[0] do
				table.insert(strs, tostring(args[i]))
			end
			script_log:inf(table.concat(strs, "\t"))
		end

		function script_env.load(str, src, mode, env)
			return load(str, src, mode, env or script_env)
		end

		return {
			entrypoint = function()
				mod_require(script_name)
			end,
			exit = function(log)
				sandbox_atexit:exit(log, script_name)
			end,
		}
	end
end

return {
	factory = factory,
}
