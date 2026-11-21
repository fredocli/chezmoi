local function cached_cover(path)
	local cache_dir = os.getenv("HOME") .. "/.cache/yazi/audio-cover"
	fs.create("dir_all", Url(cache_dir))

	local cover = cache_dir .. "/" .. ya.hash(path) .. ".jpg"
	if fs.cha(Url(cover)) then
		return cover
	end

	local status = Command("ffmpeg")
		:arg({ "-v", "error", "-i", path, "-map", "0:v:0", "-frames:v", "1", "-y", cover })
		:status()
	return status and status.success and cover or nil
end

local function metadata(path)
	local output = Command("preview"):arg(path):output()
	local text = output and output.stdout or ""
	return text ~= "" and ui.Text.parse(text) or ui.Text("No audio metadata available.")
end

local function peek(_, job)
	local path = tostring(job.file.url)
	local cover = cached_cover(path)
	local area = job.area
	local cover_area, text_area

	if not cover then
		text_area = area
	elseif area.w >= 44 then
		local width = math.min(20, math.floor((area.w - 1) / 2))
		cover_area = ui.Rect { x = area.x, y = area.y, w = width, h = math.min(20, area.h) }
		text_area = ui.Rect { x = area.x + width + 1, y = area.y, w = area.w - width - 1, h = area.h }
	elseif area.h >= 24 then
		local height = math.min(20, math.floor((area.h - 1) / 2))
		cover_area = ui.Rect { x = area.x, y = area.y, w = math.min(20, area.w), h = height }
		text_area = ui.Rect { x = area.x, y = area.y + height + 1, w = area.w, h = area.h - height - 1 }
	else
		text_area = area
	end

	if cover_area then
		ya.image_show(Url(cover), cover_area)
	end
	ya.preview_widget({ area = text_area, file = job.file, mime = "text/plain", skip = job.skip }, metadata(path):area(text_area))
end

return { peek = peek, seek = function() end }