local no_yield_from = setmetatable({}, { __mode = "k" })

local function create(func)
	local coro = coroutine.create(func)
	no_yield_from[coro] = true
	return coro
end

local function yield(...)
	if no_yield_from[coroutine.running()] then
		error("cannot yield from this coroutine", 2)
	end
	return coroutine.yield(...)
end

local function isyieldable()
	if no_yield_from[coroutine.running()] then
		return false
	end
	return coroutine.isyieldable()
end

return {
	yield       = yield,
	isyieldable = isyieldable,
	create      = create,
}
