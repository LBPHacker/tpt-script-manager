local ignore_g_write = {
	socket = true,
	lpeg = true,
}
setmetatable(_G, { __newindex = function(tbl, key, value)
	if not ignore_g_write[key] then
		error("attempt to set _G." .. key)
	end
	rawset(tbl, key, value)
end })

local encoding = require("lapis.util.encoding")
local config = require("lapis.config").get()
local jwt = require("resty.jwt")

local jwt_alg = "HS256"

function encoding.encode_with_secret(thing)
	return jwt:sign(config.secret, {
		header = { typ = "JWT", alg = jwt_alg },
		payload = thing,
	})
end

function encoding.decode_with_secret(token)
	local obj = jwt:verify(config.secret, token)
	if obj and obj.valid and obj.header.alg == jwt_alg then
		return obj.payload
	end
end
