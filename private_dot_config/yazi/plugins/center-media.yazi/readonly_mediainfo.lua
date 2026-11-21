--- @since 26.9.1

local M = {}

local const = require(".const")
local utils = require(".utils")

local adobe = require(".adobe")
local audio = require(".audio")
local image = require(".image")
local video = require(".video")
local none_media_preview = require(".none-media-preview")

--- Apply what the keymaps switched on or off to the job's arguments, then pick
--- the module that previews it: nil when both the image and the metadata are off.
local function module_for(job)
	for _, key in ipairs({ "no_metadata", "no_preview" }) do
		local value = utils.get_state(const.STATE_KEY[key])
		if value ~= nil then
			job.args[key] = value
		end
	end

	if job.args.no_preview and job.args.no_metadata then
		return nil
	elseif job.args.no_preview then
		return none_media_preview
	elseif const.seekable_mimes[job.mime] then
		return adobe
	elseif job.mime:find("^image/") then
		return image
	elseif job.mime:find("^video/") then
		return video
	elseif job.mime:find("^audio/") then
		return audio
	end
	return none_media_preview
end

function M:peek(job)
	-- debounce peek
	local start = os.clock()
	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	-- The mime picks the module. Without Yazi's cache, which it keeps for no
	-- file in its own cache directory, there is nothing to draw with.
	if not job.mime or not utils.cache(job) then
		return
	end

	local module = module_for(job)
	utils.set_states(const.STATE_KEY.cached_job_args, tostring(job.file.url), job.args)
	if not module then
		ya.preview_widget(job, { ui.Clear(job.area) })
		return
	end
	return module:peek(job)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		utils.set_state(const.STATE_KEY.units, job.units)
		ya.emit("peek", {
			math.max(0, cx.active.preview.skip + job.units),
			only_if = job.file.url,
		})
	end
end

function M:preload(job)
	if not utils.cache(job) then
		ya.dbg("center-media", "Can't access yazi cache folder")
		return true
	end
	if not job.mime then
		return false
	end

	-- With the image and the metadata both hidden there is nothing to prepare,
	-- which is done; false would have Yazi preload the file again every time.
	local module = module_for(job)
	if not module then
		return true
	end
	return module:preload(job)
end

--- The list as a set, or nil for anything but a table.
local function set_of(list)
	if type(list) ~= "table" then
		return nil
	end
	local set = {}
	for _, v in ipairs(list) do
		set[v] = true
	end
	return set
end

function M:setup(opts)
	if type(opts) ~= "table" then
		return
	end

	utils.set_state(
		const.STATE_KEY.skip_labels,
		opts.skip_labels == false and {} or set_of(opts.skip_labels) or const.skip_labels
	)
	utils.set_state(const.STATE_KEY.skip_section_labels, set_of(opts.skip_section_labels) or {})

	-- { audio = { "General", "Audio" } } keeps only those sections for audio
	-- files; `false` keeps every section of every file.
	local sections = opts.sections == false and {} or const.sections
	if type(opts.sections) == "table" then
		sections = {}
		for kind, names in pairs(opts.sections) do
			sections[kind] = set_of(names)
		end
	end
	utils.set_state(const.STATE_KEY.sections, sections)
end

-- Keymap actions that switch the image or the metadata on or off, in the order
-- they apply, so that hiding wins over showing when both are asked for.
local SWITCHES = {
	{ "show-metadata", "no_metadata", false },
	{ "show-preview", "no_preview", false },
	{ "hide-metadata", "no_metadata", true },
	{ "hide-preview", "no_preview", true },
}

local TOGGLES = {
	{ "toggle-metadata", "no_metadata" },
	{ "toggle-preview", "no_preview" },
}

--- Whether the keymap asked for `action`, either as the action itself
--- ("-- toggle-preview") or as a flag ("-- --toggle-preview").
local function wants(job, action)
	return job.args[1] == action or job.args[(action:gsub("-", "_"))]
end

function M:entry(job)
	if wants(job, "reset") then
		utils.set_state(const.STATE_KEY.no_preview, nil)
		utils.set_state(const.STATE_KEY.no_metadata, nil)
		ya.emit("peek", { force = true })
		return
	end

	for _, s in ipairs(SWITCHES) do
		if wants(job, s[1]) then
			utils.set_state(const.STATE_KEY[s[2]], s[3])
			ya.emit("peek", { force = true })
		end
	end

	if not (wants(job, "toggle-metadata") or wants(job, "toggle-preview")) then
		return
	end

	-- A toggle flips what the current preview shows, which its peek recorded.
	-- Right after moving to another file that peek may still be running.
	local args
	for _ = 0, 5 do
		local file = utils.current_file()
		args = file and utils.get_states(const.STATE_KEY.cached_job_args, file)
		if args then
			break
		end
		ya.sleep(0.1)
	end
	-- A file this previewer does not show, as when mediainfo is missing and
	-- another previewer shows it, has no recorded preview. The toggle then flips
	-- the setting as it stands for every file.
	if not args then
		args = {
			no_metadata = utils.get_state(const.STATE_KEY.no_metadata),
			no_preview = utils.get_state(const.STATE_KEY.no_preview),
		}
	end

	for _, t in ipairs(TOGGLES) do
		if wants(job, t[1]) then
			utils.set_state(const.STATE_KEY[t[2]], not args[t[2]])
			ya.emit("peek", { force = true })
		end
	end
end

return M
