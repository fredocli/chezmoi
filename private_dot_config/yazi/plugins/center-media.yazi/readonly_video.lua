--- @since 26.9.1

local M = {}
local utils = require(".utils")

--- The job for the video frame to show: the scroll position, as a percentage
--- of the video, picks the frame.
local function frame(job)
	return { skip = math.min(job.skip, 90), args = job.args, file = job.file, area = job.area }
end

function M:peek(job)
	-- Scrolling moves the frame through the video as well, up to 90% of it.
	return utils.peek(self, job, ya.file_cache(frame(job)), function()
		return job.skip <= 90
	end)
end

function M:preload(job)
	local err_msg = ""
	local ok, err = require("video"):preload(frame(job))
	if not ok and err then
		ya.dbg("center-media", err)
		err_msg = "Failed to start `ffmpeg`.\n Do you have `ffmpeg` installed?\n"
	end
	return utils.cache_mediainfo(job, err_msg)
end

return M
