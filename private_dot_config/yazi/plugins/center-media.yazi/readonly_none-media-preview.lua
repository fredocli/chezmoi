--- @since 26.9.1

local M = {}
local utils = require(".utils")

function M:peek(job)
	return utils.peek(self, job)
end

function M:preload(job)
	return utils.cache_mediainfo(job, "")
end

return M
