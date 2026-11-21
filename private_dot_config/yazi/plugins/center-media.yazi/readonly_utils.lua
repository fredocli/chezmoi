local const = require(".const")

local M = {}
local MAX_ITEMS_IN_CACHE = 10

function M.is_valid_utf8(str)
	return utf8.len(str) ~= nil
end

--- The characters of `str` from the `start_char`th to the `end_char`th, or to
--- the end when `end_char` is nil.
local function utf8_sub(str, start_char, end_char)
	local start_byte = utf8.offset(str, start_char)
	local end_byte = end_char and (utf8.offset(str, end_char + 1) or (#str + 1)) - 1
	if not start_byte then
		return ""
	end
	return str:sub(start_byte, end_byte)
end

--- The file on disk, for the tools that are run on it.
function M.path(job)
	return job.file.path or job.file.cache or job.file.url.path or job.file.url
end

--- The cache Yazi keeps for the file itself, at skip 0, or nil for a file it
--- keeps none for. Its path is the key of the session caches and, with
--- const.suffix, the name of the metadata cache file.
function M.cache(job)
	return ya.file_cache({ file = job.file, skip = 0 })
end

local function path_quote(path)
	if not path or tostring(path) == "" then
		return path
	end
	return "'" .. string.gsub(tostring(path), "'", "'\\''") .. "'"
end

M.force_render = ya.sync(function(_, _)
	(ui.render or ya.render)()
end)

M.set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

M.get_state = ya.sync(function(state, key)
	return state[key]
end)

--- Keeps the last `limit_cached_items` keys of a namespace. The keys are strings,
--- so the order they were added in is tracked in a list next to the namespace.
M.set_states = ya.sync(function(state, namespace, key, value, limit_cached_items)
	if not limit_cached_items then
		limit_cached_items = MAX_ITEMS_IN_CACHE
	end
	local order_key = namespace .. ":order"
	state[namespace] = state[namespace] or {}
	state[order_key] = state[order_key] or {}
	local storage, order = state[namespace], state[order_key]
	if storage[key] == nil then
		order[#order + 1] = key
		while #order > limit_cached_items do
			storage[table.remove(order, 1)] = nil
		end
	end
	storage[key] = value
end)

M.get_states = ya.sync(function(state, namespace, key)
	local storage = state[namespace]
	return storage and storage[key]
end)
function M.read_mediainfo_cached_file(file_path)
	local cached = M.get_states(const.STATE_KEY.cached_mediainfo, file_path)
	if cached then
		return cached
	end
	local file = io.open(file_path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		-- An error is not kept, so the reload peek asks for after one reads
		-- what that reload wrote rather than the error again.
		if not content:match("^Error:") then
			M.set_states(const.STATE_KEY.cached_mediainfo, file_path, content)
		end
		return content
	end
end

--- Run mediainfo on the file and write its output to the metadata cache file,
--- after `err_msg`, the errors from making the preview image, if there were any.
--- An existing cache file is kept unless peek asked for a reload.
function M.cache_mediainfo(job, err_msg)
	local cache_mediainfo_url = Url(tostring(M.cache(job)) .. const.suffix)
	if fs.cha(cache_mediainfo_url) and not job.args.force_reload_mediainfo then
		return true, err_msg ~= "" and Err("Error: " .. err_msg) or nil
	end

	local path = M.path(job)
	local output, err
	if M.is_valid_utf8(tostring(path)) then
		output, err = Command("mediainfo"):arg({ tostring(path) }):output()
	else
		-- Reach a file whose path is not valid UTF-8 by name from its directory.
		-- The "./" keeps a name that starts with "-" from being read as an option.
		local script = "cd " .. path_quote(tostring(path.parent)) .. " && mediainfo " .. path_quote("./" .. tostring(path.name))
		output, err = Command("sh"):arg({ "-c", script }):output()
	end
	if err then
		ya.dbg("center-media", tostring(err))
		err_msg = err_msg .. "Failed to start `mediainfo`. \n Do you have `mediainfo` installed?\n"
	end

	return fs.write(
		cache_mediainfo_url,
		(err_msg ~= "" and ("Error: " .. err_msg) or "") .. (output and output.stdout or "")
	)
end

--- Run magick with `args` and put the PNG it draws at `cache`. It draws into a
--- file next to the cache first and renames it once it is done, so that a run
--- that fails leaves no half-written cache. Returns what magick's status does.
function M.magick(cache, args)
	local tmp = Url(cache .. ".tmp")
	if fs.cha(tmp) then
		fs.remove("file", tmp)
	end
	local file = type(fs.unique) == "function" and fs.unique("file", tmp) or fs.unique_name(tmp)
	args[#args + 1] = string.format("PNG32:%s", tostring(file))
	local ok, err = require("magick").with_limit():arg(args):status()
	if ok then
		os.rename(tostring(file), tostring(cache))
	end
	return ok, err
end

--- The stream a line of mediainfo output starts, if it starts one. mediainfo
--- puts each stream's kind on a line of its own ("General", "Audio",
--- "Audio #2") above that stream's "Label   : value" lines.
local function section_of(str)
	return str:match("^(%a+) #%d+$") or str:match("^%a+$")
end

--- Whether the preview wraps long lines, as Yazi's preview.wrap setting says.
local function wraps()
	return rt.preview.wrap == ui.Wrap.YES
end

--- The dim ellipsis that marks metadata cut short, down or to the right.
local function ellipsis()
	return ui.Span("…"):style(ui.Style():dim())
end

--- The characters of `s` from the `from`th on that fill at most `width`
--- columns, marks that take no column included, and where the row after them
--- starts. Wrapping breaks a row at a space and drops it, so that is skipped.
local function take(s, from, width)
	local start = utf8.offset(s, from)
	if not start or start > #s then
		return "", from
	end
	local out, used, after = {}, 0, from
	for _, code in utf8.codes(s:sub(start)) do
		local char = utf8.char(code)
		used = used + ui.width(char)
		if used > width then
			break
		end
		out[#out + 1] = char
		after = after + 1
	end
	local rest = utf8.offset(s, after)
	if rest and s:sub(rest, rest) == " " then
		after = after + 1
	end
	return table.concat(out), after
end

--- Turn cached mediainfo output into the lines of the metadata block, starting
--- `skip` lines in and stopping once the preview area is full.
--- Returns the lines, how many lines were walked through including skipped ones
--- (at most skip + area height), whether the output ended inside the area, and
--- how wide the block of all the lines is, the ones not shown included.
function M.metadata_lines(job, output, skip)
	local skip_labels = M.get_state(const.STATE_KEY.skip_labels) or const.skip_labels
	local skip_section_labels = M.get_state(const.STATE_KEY.skip_section_labels) or {}
	local sections = M.get_state(const.STATE_KEY.sections) or const.sections
	local kind = (job.mime or ""):match("^([^/]+)/") or ""
	local keep = sections[kind]
	-- Trimmed audio also loses the Cover lines under General: like the Image
	-- section, they describe the cover art the preview shows.
	local no_cover = keep and kind == "audio"

	-- Pick the lines to show first, so that dropped sections cost no height.
	local entries, current = {}, nil
	for raw in output:gsub("\n+$", ""):gmatch("[^\n]*") do
		-- Bytes that are not UTF-8, as in a file name, would stop the counting below.
		local str = utf8.len(raw) and raw or (raw:gsub("[\128-\255]", "?"))
		local label, value = str:match("(.*[^ ])  +: (.*)")
		current = not label and section_of(str) or current
		if not (keep and current and not keep[current]) then
			if label then
				if not skip_labels[label] and not (no_cover and label:find("^Cover")) then
					entries[#entries + 1] = { label = label, line = label .. ": " .. value }
				end
			elseif not skip_section_labels[str] then
				entries[#entries + 1] = { line = str, heading = section_of(str) ~= nil }
			end
		end
	end
	-- A dropped last section leaves the blank line that preceded it.
	while #entries > 0 and entries[#entries].line == "" do
		entries[#entries] = nil
	end

	-- A line wider than the pane would make the block as wide as the pane, which
	-- leaves it where it is instead of centering it. Such a line gets the width
	-- of the widest line that fits: it wraps there when the preview wraps, and
	-- is cut there and ended with an ellipsis when it does not. Section headings
	-- are left out, so that a pane too narrow for any other line cuts at its
	-- edge rather than at the width of "General".
	local width, headings, overflows = 0, 0, false
	for _, entry in ipairs(entries) do
		entry.width = ui.Line(entry.line):width()
		if entry.width > job.area.w then
			overflows = true
		elseif entry.heading then
			headings = math.max(headings, entry.width)
		else
			width = math.max(width, entry.width)
		end
	end
	-- A heading that fits is not cut or wrapped either, and metadata that is
	-- only headings, all of which fit, is as wide as they are.
	if width > 0 or (headings > 0 and not overflows) then
		width = math.max(width, headings)
	else
		width = math.max(1, job.area.w)
	end

	local lines = {}
	local limit = job.area.h
	local last_line = 0
	local EOF_mediainfo = true
	local opt = { ansi = true, tab_size = rt.preview.tab_size, wrap = rt.preview.wrap, width = width }
	local label_style = ui.Style():fg("reset"):bold()
	for i, entry in ipairs(entries) do
		local label, line = entry.label, entry.line
		local long = entry.width > width and not wraps()
		if long then
			line = take(line, 1, width - 1)
		end
		local rows = ui.lines(line, opt)
		-- The label and its ": " take the first characters of the line.
		local label_len = label and utf8.len(label .. ": ") or 0
		local pos = 1
		for j = 1, math.min(#rows, skip + limit - last_line) do
			local piece, after = take(line, pos, rows[j]:width() or 0)
			if last_line >= skip then
				local len = utf8.len(piece)
				local head = math.max(0, math.min(label_len - pos + 1, len))
				local spans = {}
				if head > 0 then
					spans[#spans + 1] = ui.Span(utf8_sub(piece, 1, head)):style(label_style)
				end
				if head < len or not label then
					spans[#spans + 1] = ui.Span(utf8_sub(piece, head + 1)):style(
						label and (th.spot.tbl_col or ui.Style():fg("blue")) or (th.spot.title or ui.Style():fg("green"))
					)
				end
				if long then
					spans[#spans + 1] = ellipsis()
				end
				lines[#lines + 1] = ui.Line(spans)
			end
			pos = after
			last_line = last_line + 1
			if last_line >= skip + limit then
				-- Full, and more follows unless this was the last row.
				EOF_mediainfo = i == #entries and not rows[j + 1]
				break
			end
		end
	end
	return lines, last_line, EOF_mediainfo, width
end

--- How many seek steps the preview has been scrolled by.
function M.step(job)
	local units = M.get_state(const.STATE_KEY.units)
	return units and math.floor(math.abs(job.skip / units)) or 0
end

--- The lines as a Text in `area`. `width` is how wide the whole metadata block
--- is, the lines not shown included: main.lua centers the block by it, so that
--- scrolling does not move the block sideways.
local function text(lines, area, width)
	lines.width = width
	return ui.Text(lines):area(area):wrap(wraps() and ui.Wrap.YES or ui.Wrap.NO)
end

local function error_line(err)
	return ui.Line(tostring(err)):style(th.spot.title or ui.Style():fg("red"))
end

--- Whether `image` is the blank 1x1 picture audio.lua caches in place of
--- missing cover art. It only keeps preload from looking for the cover again,
--- and drawing it would push the metadata down by the rows it takes.
local function blank(image)
	local info = ya.image_info(image)
	return info ~= nil and info.w == 1 and info.h == 1
end

--- What the next peek needs to clear the metadata this one drew: `rect`, and
--- the pane it was drawn in, since it is only cleared while the pane is the same.
local function drawn_area(rect, pane)
	return {
		x = rect.x, y = rect.y, w = rect.w, h = rect.h,
		win_x = pane.x, win_y = pane.y, win_w = pane.w, win_h = pane.h,
	}
end

--- The metadata rows to draw in `rows` rows, and how many rows that takes.
--- When not all fit, because some are below the area or past what
--- metadata_lines read (`eof` false), the last row becomes a centered
--- ellipsis, a hint that scrolling shows more, and `margin` rows stay free
--- under it: as many as the image has above it.
local function fit(lines, rows, eof, margin)
	if eof and #lines <= rows then
		return lines, rows
	end
	rows = math.max(0, rows - margin)
	local fitted = { table.unpack(lines, 1, rows - 1) }
	if rows > 0 then
		fitted[rows] = ui.Line({ ellipsis() }):align(ui.Align.CENTER)
	end
	return fitted, rows
end

--- The peek every media module shares: the preview image at the top, if the
--- module has one, and the metadata below it.
--- `image` is the cached preview image, nil for a module that only shows
--- metadata. `more(job)` tells whether scrolling past the end of the metadata
--- still has something to show, such as later video frames or further layers.
function M.peek(module, job, image, more)
	-- Without a cache there is nothing to show but why, as when it cannot be written.
	local function uncached(err)
		ya.preview_widget(job, { ui.Clear(job.area), text({ error_line(err or "Cannot write the cache") }, job.area) })
	end
	local ok, preload_err = module:preload(job)
	if not ok then
		return uncached(preload_err)
	end

	local key = tostring(M.cache(job))
	local lines, height, eof, width = {}, 0, true, nil
	if not job.args.no_metadata then
		local output = M.read_mediainfo_cached_file(key .. const.suffix)
		if output and output:match("^Error:") then
			job.args.force_reload_mediainfo = true
			ok, preload_err = module:preload(job)
			if not ok then
				return uncached(preload_err)
			end
			output = M.read_mediainfo_cached_file(key .. const.suffix)
		end
		if output then
			local skip = job.skip
			local last_line
			lines, last_line, eof, width = M.metadata_lines(job, output, skip)
			if eof and #lines == 0 and skip > 0 then
				local units = M.get_state(const.STATE_KEY.units) or 0
				if not (more and more(job)) then
					ya.emit("peek", { math.max(0, job.skip - units), only_if = job.file.url, upper_bound = true })
					return
				end
				-- Scrolling goes on through the frames or layers, and the metadata
				-- stays at the last position that showed any.
				local last = M.get_state(const.STATE_KEY.last_valid_mediainfo_skip)
				skip = last and last[key] or math.max(0, skip - units)
				lines, last_line, eof, width = M.metadata_lines(job, output, skip)
				while #lines == 0 and skip > 0 and units > 0 do
					skip = math.max(0, skip - units)
					lines, last_line, eof, width = M.metadata_lines(job, output, skip)
				end
			end
			if #lines > 0 then
				M.set_state(const.STATE_KEY.last_valid_mediainfo_skip, { [key] = skip })
			end
			height = math.min(job.area.h, last_line)
		end
	end
	-- An error goes first, where metadata too long for the pane cannot hide it.
	if preload_err then
		table.insert(lines, 1, error_line(preload_err))
	end

	local area = job.area
	if image and blank(image) then
		image = nil
	end
	if not image then
		M.force_render()
		ya.preview_widget(job, { ui.Clear(area), text(fit(lines, area.h, eof, 0), area, width) })
		M.set_state(const.STATE_KEY.prev_metadata_area, drawn_area(area, area))
		return
	end

	-- Clear the metadata the last peek drew in this pane: the image drawn over
	-- that area would otherwise mix with it.
	local old = M.get_state(const.STATE_KEY.prev_metadata_area)
	if old and old.win_x == area.x and old.win_y == area.y and old.win_w == area.w and old.win_h == area.h then
		ya.preview_widget(job, { ui.Clear(ui.Rect({ x = old.x, y = old.y, w = old.w, h = old.h })) })
	end
	M.force_render()

	-- The centering in main.lua returns the rows it moved the image down by as
	-- the third value.
	local drawn, image_err, margin
	if fs.cha(image) then
		drawn, image_err, margin = ya.image_show(image, ui.Rect({
			x = area.x,
			y = area.y,
			w = area.w,
			h = height > 0 and math.max(area.h - height, area.h / 2) or area.h,
		}))
	end
	-- No image is made for a skip past the end of a video. Keep the room the
	-- last one took, so the metadata does not jump up.
	if not drawn and image_err then
		table.insert(lines, 1, error_line(image_err))
	end
	local rooms = M.get_state(const.STATE_KEY.prev_image_height)
	local room = drawn and { h = drawn.h, margin = margin or 0 } or (rooms and rooms[key]) or { h = 0, margin = 0 }
	if drawn then
		M.set_state(const.STATE_KEY.prev_image_height, { [key] = room })
	end

	local below = ui.Rect({ x = area.x, y = area.y + room.h, w = area.w, h = area.h - room.h })
	local fitted, rows = fit(lines, below.h, eof, room.margin)
	ya.preview_widget(job, { text(fitted, ui.Rect({ x = below.x, y = below.y, w = below.w, h = rows }), width) })
	M.set_state(const.STATE_KEY.prev_metadata_area, not job.args.no_metadata and drawn_area(below, area) or nil)
end

M.current_file = ya.sync(function()
	local h = cx.active.current.hovered
	if not h then
		return
	end
	return tostring(h.url)
end)

return M
