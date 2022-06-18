return {
	postgres = {
		host = "localhost",
		port = 5432,
		database = "powdertoy_scripts",
		user = "powdertoy_scripts",
		password = "bagels",
	},
	powder = {
		scheme = "https",
		host = "powdertoy.co.uk",
		external_auth = {
			path = "/ExternalAuth.api",
			audience = "Script Manager Sample",
		},
	},
	secret = "the quick brown fox jumps over the lazy dog",
}
