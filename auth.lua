local config   = require("lapis.config").get()
local lunajson = require("lunajson")
local util     = require("lapis.util")
local encoding = require("lapis.util.encoding")
local basexx   = require("basexx")
local http     = require("lapis.nginx.http")

local function token_payload(token)
	local payload = token:match("^[^%.]+%.([^%.]+)%.[^%.]+$")
	if not payload then
		return nil, "no payload"
	end
	local unb64 = basexx.from_url64(payload)
	if not unb64 then
		return nil, "bad base64"
	end
	local ok, json = pcall(lunajson.decode, unb64)
	if not ok then
		return nil, "bad json: " .. json
	end
	if type(json) ~= "table" then
		return nil, "bad payload"
	end
	if type(json.sub) ~= "string" or json.sub:find("[^0-9]") then
		return nil, "bad subject"
	end
	if json.aud ~= config.powder.external_auth.audience then
		return nil, "bad audience"
	end
	return json
end

local function get(redirect)
	return util.build_url({
		scheme = config.powder.scheme,
		host = config.powder.host,
		path = config.powder.external_auth.path,
		query = util.encode_query_string({
			Action = "Get",
			Audience = config.powder.external_auth.audience,
			AppToken = encoding.encode_with_secret({
				iat = os.time(),
				redirect = redirect,
			}),
		}),
	})
end

local function check(powder_token, app_token)
	local powder_data, err = token_payload(powder_token)
	if not powder_data then
		return nil, { status = 401, json = { status = "malformed powder token: " .. err } }
	end
	do
		local body, code, headers = http.simple({
			url = util.build_url({
				scheme = config.powder.scheme,
				host = config.powder.host,
				path = config.powder.external_auth.path,
				query = util.encode_query_string({
					Action = "Check",
					MaxAge = config.powder.external_auth.token_max_age,
					Token = powder_token,
				}),
			}),
		})
		if code ~= 200 then
			return nil, { status = 502, json = { status = "authentication backend failed with code " .. code } }
		end
		local ok, json = pcall(lunajson.decode, body)
		if not ok or type(json) ~= "table" then
			return nil, { status = 502, json = { status = "authentication backend returned a malformed response" } }
		end
		if json.Status ~= "OK" then
			return nil, { status = 401, json = { status = "bad token: " .. json.Status } }
		end
	end
	local app_data = encoding.decode_with_secret(app_token)
	if not app_data then
		return nil, { status = 401, json = { status = "malformed app token" } }
	end
	if app_data.iat + config.powder.external_auth.token_max_age < os.time() then
		return nil, { status = 401, json = { status = "app token expired" } }
	end
	return tonumber(powder_data.sub), powder_data.name, app_data.redirect
end

return {
	get = get,
	check = check,
}
