local no_yield    = require("manager.no_yield")
local environment = require("manager.environment")

local runner_i = {}
local runner_m = { __index = runner_i }

function runner_i:dispatch(...)
	assert(self.status_ == "ready")
	return select(2, assert(coroutine.resume(self.coro_, ...)))
end

function runner_i:status()
	return self.status_
end

local valid_contexts = setmetatable({}, { __mode = "k" })
local function make_runner()
	local runner
	runner = setmetatable({
		coro_ = no_yield.create(function(...)
			local args_in = environment.packn(...)
			while true do
				local func = environment.unpackn(args_in)
				runner.status_ = "dispatching"
				local args_out = environment.packn(func(environment.unpackn(args_in, 2)))
				runner.status_ = "ready"
				args_in = environment.packn(coroutine.yield(environment.unpackn(args_out)))
			end
		end),
		status_ = "ready",
	}, runner_m)
	valid_contexts[runner.coro_] = true
	return runner
end

local function message_box(title, message)
	local coro = coroutine.running()
	if not valid_contexts[coro] then
		error("blocking prompts are not available in this context", 2)
	end
	ui.beginMessageBox(title, message, function()
		coroutine.resume(coro)
	end)
	coroutine.yield()
end

local function input(title, message, text)
	local coro = coroutine.running()
	if not valid_contexts[coro] then
		error("blocking prompts are not available in this context", 2)
	end
	local result_outer
	ui.beginInput(title, message, text, function(result)
		result_outer = result or ""
		coroutine.resume(coro)
	end)
	coroutine.yield()
	return result_outer
end

local function throw_error(text)
	local coro = coroutine.running()
	if not valid_contexts[coro] then
		error("blocking prompts are not available in this context", 2)
	end
	ui.beginThrowError(text, function()
		coroutine.resume(coro)
	end)
	coroutine.yield()
end

local function confirm(title, message, button_name)
	local coro = coroutine.running()
	if not valid_contexts[coro] then
		error("blocking prompts are not available in this context", 2)
	end
	local result_outer
	ui.beginConfirm(title, message, button_name, function(result)
		result_outer = result
		coroutine.resume(coro)
	end)
	coroutine.yield()
	return result_outer
end

return {
	message_box = message_box,
	input       = input,
	throw_error = throw_error,
	confirm     = confirm,
	make_runner = make_runner,
}
