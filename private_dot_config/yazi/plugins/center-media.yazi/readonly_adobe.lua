--- @since 26.9.1

local M = {}
local const = require(".const")
local utils = require(".utils")

local function image_layer_count(job)
	local cache = utils.cache(job)
	if not cache then
		return 0
	end
	local layer_count = utils.get_states(const.STATE_KEY.layers, tostring(cache))
	if layer_count then
		return layer_count
	end
	local output, err = Command("identify"):arg({ tostring(utils.path(job)) }):output()
	if err or not output then
		return 0
	end
	layer_count = 0
	for line in output.stdout:gmatch("[^\r\n]+") do
		if line:match("%S") then
			layer_count = layer_count + 1
		end
	end
	utils.set_states(const.STATE_KEY.layers, tostring(cache), layer_count)
	return layer_count
end

function M:peek(job)
	-- Scrolling steps through the layers, past the end of the metadata too
	-- while there are more.
	return utils.peek(self, job, ya.file_cache(job), function()
		return image_layer_count(job) >= 1 + utils.step(job)
	end)
end

function M:preload(job)
	local cache_img_url = ya.file_cache(job)
	local cache_img_url_cha = cache_img_url and fs.cha(cache_img_url)

	local err_msg = ""
	if not cache_img_url_cha or cache_img_url_cha.len <= 0 then
		-- The layer the scroll position is on, or the last one past them.
		local layer_index = utils.step(job)
		if layer_index > 0 then
			layer_index = math.min(layer_index, math.max(0, image_layer_count(job) - 1))
		end
		local ok, err = utils.magick(cache_img_url, {
			"-background",
			"none",
			tostring(utils.path(job)) .. "[" .. layer_index .. "]",
			"-auto-orient",
			"-strip",
			"-resize",
			string.format("%dx%d>", rt.preview.max_width, rt.preview.max_height),
			"-quality",
			rt.preview.image_quality,
		})
		if not ok and err then
			ya.dbg("center-media", err)
			err_msg = tostring(err)
		end
	end

	return utils.cache_mediainfo(job, err_msg)
end

return M
