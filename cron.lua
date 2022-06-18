require("environment")
local db = require("lapis.db")

local function defer(func)
	ngx.timer.at(0, func)
end

local function periodic(interval, func)
	local function wrapper()
		func()
		ngx.timer.at(interval, wrapper)
	end
	defer(wrapper)
end

defer(function()
	local prune_interval = db.query("select * from extract(epoch from session_max_age()) as seconds;")[1].seconds
	periodic(prune_interval, function()
		db.query("call prune_sessions();")
	end)
end)
