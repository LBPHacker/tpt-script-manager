local directory_view_i = {}
local directory_view_m = { __index = directory_view_i }

function directory_view_i:readall(...)
	return self:readall_func_(...)
end

function directory_view_i:writeall(...)
	return self:writeall_func_(...)
end

function directory_view_i:exists(...)
	return self:exists_func_(...)
end

local from_path
do
	local function readall(self, relative)
		local path = self.root_ .. "/" .. relative
		local handle, err = io.open(path, "rb")
		if not handle then
			return nil, err
		end
		local data, err = handle:read("*a")
		if not data then
			return nil, err
		end
		handle:close()
		return data
	end

	local function writeall(self, relative, data)
		local path = self.root_ .. "/" .. relative
		local handle, err = io.open(path, "wb")
		if not handle then
			return nil, err
		end
		local data, err = handle:write(data)
		if not data then
			return nil, err
		end
		handle:close()
		return true
	end

	local function exists(self, relative)
		local path = self.root_ .. "/" .. relative
		return fs.exists(path)
	end

	function from_path(root)
		return setmetatable({
			root_ = root,
			readall_func_ = readall,
			writeall_func_ = writeall,
			exists_func_ = exists,
		}, directory_view_m)
	end
end

return {
	from_path = from_path,
}
