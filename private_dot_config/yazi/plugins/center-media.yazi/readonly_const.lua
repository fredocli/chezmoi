local M = {}

M.skip_labels = {
	["Complete name"] = true,
	["CompleteName_Last"] = true,
	["Unique ID"] = true,
	["File size"] = true,
	["Format/Info"] = true,
	["Codec ID/Info"] = true,
	["MD5 of the unencoded content"] = true,
}

-- The sections of the mediainfo output to keep, by the file's MIME top-level
-- type. A type that is not listed keeps every section. Audio drops the Image
-- section that describes its cover art, which is on screen right above it.
M.sections = {
	audio = { General = true, Audio = true },
}

M.STATE_KEY = {
	skip_labels = "skip_labels",
	skip_section_labels = "skip_section_labels",
	sections = "sections",
	units = "units",
	no_metadata = "no_metadata",
	no_preview = "no_preview",
	prev_metadata_area = "prev_metadata_area",
	prev_image_height = "prev_image_height",
	last_valid_mediainfo_skip = "last_valid_mediainfo_skip",
	cached_mediainfo = "cached_mediainfo",
	cached_job_args = "cached_job_args",
	-- Embedded pictures of an audio file, or layers of an Adobe file, by cache path
	layers = "layers",
}

M.magick_image_mimes = {
	avif = true,
	hei = true,
	heic = true,
	heif = true,
	["heif-sequence"] = true,
	["heic-sequence"] = true,
	jxl = true,
	tiff = true,
	xml = true,
	["canon-cr2"] = true,
}

M.seekable_mimes = {
	-- NOTE: Adobe illustrator photoshop mimetypes
	["application/postscript"] = true,
	["application/dvb.ait"] = true,
	["application/illustrator"] = true,
	["application/vnd.adobe.illustrator"] = true,
	["image/x-eps"] = true,
	["application/eps"] = true,
	["application/pdf"] = true,

	["image/adobe.photoshop"] = true,
}

M.suffix = "_mediainfo"

return M
