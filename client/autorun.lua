local this_env, load_with_env, unpack, ipairs
if rawget(_G, "loadstring") then
	this_env = getfenv(1)
	function load_with_env(str, src, env)
		local func, err = loadstring(str, src)
		if not func then
			return nil, err
		end
		return setfenv(func, env)
	end
	unpack = _G.unpack
	ipairs = _G.ipairs
else
	this_env = _ENV
	function load_with_env(str, src, env)
		return load(str, src, "t", env)
	end
	unpack = table.unpack
	function ipairs(tbl)
		local index = 0
		return function()
			index = index + 1
			if tbl[index] ~= nil then
				return index, tbl[index]
			end
		end
	end
end

local strict_env = setmetatable({}, { __index = function(_, key)
	local value = rawget(this_env, key)
	if value ~= nil then
		return value
	end
	error("__index on env: " .. tostring(key), 2)
end, __newindex = function(_, key)
	error("__newindex on env: " .. tostring(key), 2)
end })

os.setlocale("C") -- force printing of numbers to use '.' as the decimal point

local function make_require(readall, env)
	local mod_status = {}
	local mod_result = {}
	return function(modname)
		if mod_status[modname] ~= "loaded" then
			if mod_status[modname] == "loading" then
				error("recursive require", 2)
			end
			local components = {}
			local function push(component)
				if not component:find("^[a-zA-Z_][a-zA-Z_0-9]*$") then
					error("invalid module name", 2)
				end
				table.insert(components, component)
			end
			local modname_part = modname
			while true do
				local dot_at = modname_part:find("%.")
				if not dot_at then
					push(modname_part)
					break
				end
				push(modname_part:sub(1, dot_at - 1))
				modname_part = modname_part:sub(dot_at + 1)
			end
			local dir = table.concat(components, "/")
			local candidates = {
				dir .. "/init.lua",
				dir .. ".lua",
			}
			local chunk
			for _, candidate in ipairs(candidates) do
				chunk = readall(candidate)
				if chunk then
					break
				end
			end
			if not chunk then
				error("module not found", 2)
			end
			local func, err = load_with_env(chunk, "=[module " .. modname .. "]", env)
			if not func then
				error(err, 0)
			end
			mod_status[modname] = "loading"
			local ok, result = pcall(func)
			mod_status[modname] = nil
			if not ok then
				error(result, 0)
			end
			mod_status[modname] = "loaded"
			mod_result[modname] = result
		end
		return mod_result[modname]
	end
end

local manager_require
if true then -- if running from dev dir
	local source = debug.getinfo(1).source
	local path_to_self = source:match("^@(.*)$")
	if not path_to_self then
		error("source string does not seem like a path")
	end
	local module_root = path_to_self:gsub("\\", "/"):match("^(.*/)[^/]*$")
	if not module_root then
		error("cannot find module root in source string")
	end
	manager_require = make_require(function(path)
		path = module_root .. path
		if not fs.exists(path) then
			return
		end
		-- TODO: yield once reading files becomes a request
		local handle = assert(io.open(path, "rb"))
		local data = assert(handle:read("*a"))
		assert(handle:close())
		return data
	end, strict_env)
else
	-- TODO: make sure long strings begin with an extra \n so the initial-\n feature doesn't trigger
	-- bundled modules begin =
	-- bundled modules end =

	-- TODO
end

local function packn(...)
	return { select("#", ...), ... }
end

local function unpackn(tbl)
	return unpack(tbl, 2, tbl[1] + 1)
end

local function xpcall_wrap(func, handler)
	return function(...)
		local args_in = packn(...)
		local args_out
		xpcall(function()
			args_out = packn(func(unpackn(args_in)))
		end, function(err)
			if handler then
				handler()
			end
			print(err)
			print(debug.traceback())
		end)
		return unpackn(args_out)
	end
end

for key, value in pairs({
	ipairs       = ipairs,
	packn        = packn,
	unpack       = unpack,
	xpcall_wrap  = xpcall_wrap,
	strict_env   = strict_env,
	require      = manager_require,
	make_require = make_require,
	unpackn      = unpackn,
}) do
	rawset(strict_env, key, value)
end
xpcall_wrap(function()
	manager_require("manager", strict_env)
end)()
