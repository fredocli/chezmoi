--- @since 26.9.1

local M = {}
local const = require(".const")
local utils = require(".utils")

function M:peek(job)
	return utils.peek(self, job, utils.cache(job))
end

function M:preload(job)
	local subtype = job.mime:match(".*/(.*)$")
	local is_svg = subtype == "svg+xml"
	-- The job for Yazi's own previewers, which make the image: always at skip 0,
	-- since scrolling moves only the metadata.
	local no_skip_job = { skip = 0, file = job.file, args = job.args, area = job.area }
	local cache_img_url = ya.file_cache(no_skip_job)
	local cache_img_url_cha = cache_img_url and fs.cha(cache_img_url)

	local err_msg = ""
	if not cache_img_url_cha or cache_img_url_cha.len <= 0 then
		local ok, err
		if utils.is_valid_utf8(tostring(utils.path(job))) then
			local previewer = is_svg and "svg" or (const.magick_image_mimes[subtype] and "magick" or "image")
			ok, err = require(previewer):preload(no_skip_job)
		elseif is_svg then
			-- Of the paths that are not valid UTF-8, only an SVG's is handled,
			-- by running magick on it directly.
			ok, err = utils.magick(cache_img_url, {
				"-background",
				"none",
				tostring(utils.path(job)),
				"-auto-orient",
				"-strip",
				string.format("%dx%d>", rt.preview.max_width, rt.preview.max_height),
				"-quality",
				rt.preview.image_quality,
			})
		end
		if not ok and err then
			ya.dbg("center-media", err)
			err_msg = tostring(err)
		end
	end

	return utils.cache_mediainfo(job, err_msg)
end

return M
