local date   = require("date")
local lapis  = require("lapis")
local auth   = require("auth")
local db     = require("lapis.db")
local config = require("lapis.config").get()
local util   = require("lapis.util")

local app = lapis.Application()

local function good_url_for(self, route)
	return config.url_prefix .. self:url_for(route)
end

function app:cookie_attributes(key, value)
	if key == "session_id" and value == "" then
		return "Expires=" .. date(0):adddays(365):fmt("${http}") .. "; Path=/; HttpOnly"
	end
end

app:before_filter(function(self)
	if self.cookies.session_id then
		local res = db.query("select * from get_session_user(?);", self.cookies.session_id)[1]
		if res.status == "found" then
			self.user_id = res.user_id
			self.user_name = res.user_name
			self.anti_csrf = res.anti_csrf
		else
			self.cookies.session_id = ""
		end
	end
end)

app:get("index", "/", function(self)
	if self.user_id then
		return [[hey, ]] .. self.user_name .. [[. you can <a href="]] .. good_url_for(self, "logout") .. [[">log out</a>.<br>anti-csrf: ]] .. self.anti_csrf
	else
		return [[hey. you can <a href="]] .. good_url_for(self, "login") .. [[">log in</a>.]]
	end
end)

app:get("logout", "/logout", function(self)
	if self.user_id then
		db.query("call destroy_session(?);", self.cookies.session_id)
	end
	return { redirect_to = self.req.headers["referer"] }
end)

app:get("login", "/login", function(self)
	return { redirect_to = auth.get(self.req.headers["referer"]) }
end)

app:get("/check", function(self)
	local uid, name, redirect = auth.check(self.req.params_get.PowderToken, self.req.params_get.AppToken)
	if not uid then
		return name
	end
	local res = db.query("select * from create_session(?, ?);", uid, name)[1]
	self.cookies.session_id = res.new_session
	return { redirect_to = redirect }
end)

return app
