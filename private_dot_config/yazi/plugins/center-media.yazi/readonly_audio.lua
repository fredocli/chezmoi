--- @since 26.9.1

local M = {}
local const = require(".const")
local utils = require(".utils")

local function get_cover_layers(job)
	local cache = utils.cache(job)
	if not cache then
		return {}
	end
	local covers = utils.get_states(const.STATE_KEY.layers, tostring(cache))
	if type(covers) == "table" then
		return covers
	end
	local output, err = Command("ffprobe"):arg({
		"-v",
		"error",
		"-select_streams",
		"v",
		"-show_entries",
		"stream=index:stream_disposition=attached_pic",
		"-of",
		"json",
		tostring(utils.path(job)),
	}):output()
	if err or not output then
		return {}
	end
	covers = {}
	local data = ya.json_decode(output.stdout)
	if type(data) == "table" and type(data.streams) == "table" then
		for _, stream in ipairs(data.streams) do
			if stream.disposition and stream.disposition.attached_pic == 1 then
				covers[#covers + 1] = stream.index
			end
		end
	end
	utils.set_states(const.STATE_KEY.layers, tostring(cache), covers)
	return covers
end

--- Which embedded picture the scroll position is on, counted from 1: one
--- further with every seek step, like the layers of an Adobe file.
local function cover_index(job)
	return utils.step(job) + 1
end

--- The line shown for `tool` failing to start, or complaining on stderr.
local function failed(tool, output, err)
	return string.format(
		"Failed to start `%s`.\n Error: %s\n",
		tool,
		tostring(err or (output and output.stderr or ""))
	)
end

function M:peek(job)
	-- Scrolling steps through the embedded pictures, past the end of the
	-- metadata too while there are more.
	return utils.peek(self, job, ya.file_cache(job), function()
		return get_cover_layers(job)[cover_index(job)] ~= nil
	end)
end

function M:preload(job)
	local cache_img_url = ya.file_cache(job)
	local cache_img_url_cha = cache_img_url and fs.cha(cache_img_url)

	local err_msg = ""
	if cache_img_url and (not cache_img_url_cha or cache_img_url_cha.len <= 0) then
		-- The cover the scroll position is on, or the last one past them. ffprobe
		-- reports streams by their index in the file, which "0:N" picks; without
		-- a cover, "0:v:0?" takes the first video stream if there is one.
		local covers = get_cover_layers(job)
		local position = utils.get_state(const.STATE_KEY.units) and cover_index(job) or 1
		local stream = covers[math.min(position, #covers)]
		local qv = 31 - math.floor(rt.preview.image_quality * 0.3)
		local output, err = Command("ffmpeg"):arg({
			"-v",
			"error",
			"-threads",
			1,
			"-i",
			tostring(utils.path(job)),
			"-map",
			stream and string.format("0:%d", stream) or "0:v:0?",
			"-an",
			"-sn",
			"-dn",
			"-vframes",
			1,
			"-q:v",
			qv,
			"-vf",
			string.format("scale=-1:'min(%d,ih)':flags=fast_bilinear", rt.preview.max_height / 2),
			"-f",
			"image2",
			"-y",
			tostring(cache_img_url),
		}):output()
		if err then
			ya.dbg("center-media", err)
			err_msg = err_msg .. failed("ffmpeg", output, err)
		elseif output and type(output.stderr) == "string" and output.stderr:find("does not contain any stream") then
			-- Audio without cover art. A blank image is cached in its place, so
			-- that the cover is not looked for again; utils.peek skips drawing it.
			ya.dbg("center-media", output.stderr)
			if fs.cha(cache_img_url) then
				fs.remove("file", Url(cache_img_url))
			end
			output, err = require("magick")
				.with_limit()
				:arg({
					"-size",
					"1x1",
					"canvas:none",
					string.format("PNG32:%s", cache_img_url),
				})
				:output()
			if (output and output.stderr ~= nil and output.stderr ~= "") or err then
				ya.dbg("center-media", err or (output and output.stderr))
				err_msg = err_msg .. failed("magick", output, err)
			end
		end
	end

	return utils.cache_mediainfo(job, err_msg)
end

return M
