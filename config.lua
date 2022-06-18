local config = require("lapis.config")
local secret_config = require("secret_config")

config({ "development", "production" }, {
	port = 33001,
	num_workers = 4,
	postgres = {
		host = secret_config.postgres.host,
		port = secret_config.postgres.port,
		database = secret_config.postgres.database,
		user = secret_config.postgres.user,
		password = secret_config.postgres.password,
	},
	powder = {
		scheme = secret_config.powder.scheme,
		host = secret_config.powder.host,
		external_auth = {
			path = secret_config.powder.external_auth.path,
			audience = secret_config.powder.external_auth.audience,
			token_max_age = 60,
		},
	},
	secret = secret_config.secret,
	url_prefix = "",
	ca_certs = "/etc/ssl/certs/ca-certificates.crt",
	resolver = "127.0.0.1",
})

config("production", {
	port = 3001,
	url_prefix = "/scripts",
	code_cache = "on",
	resolver = "8.8.8.8 8.8.4.4",
})
