-- ==============================================================================
-- swayimg -> nsxiv-style config
-- Put in ~/.config/swayimg/init.lua
-- API reference for your installed version: /usr/share/swayimg/swayimg.lua
-- ==============================================================================

-- ---------- look & feel ----------
swayimg.decoration = false
swayimg.text.visible = false                      -- toggled with "b"/"i" below
swayimg.viewer.set_window_background(0xff111111)
swayimg.gallery.window_color = 0xff111111
swayimg.viewer.default_scale = "optimal"          -- nsxiv default: shrink to fit, never upscale
swayimg.viewer.loop = true                        -- wrap around at list ends
swayimg.imagelist.order = "alpha"
swayimg.viewer.mark_color = 0xffff5555

-- ---------- helpers ----------
local function shq(s)                              -- POSIX single-quote escape
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function notify(title, msg)
    os.execute(string.format("notify-send %s %s &", shq(title), shq(msg)))
end

-- bind several key-name candidates to one handler; invalid names are skipped
-- (swayimg wants xkb keysym names: plus, minus, equal, less, greater, bar...)
local bad = {}
local bound = {}
-- leader-key state (nsxiv key-handler style: "," then a key). While active, the
-- next key press runs leader.handlers[key] instead of its normal binding.
local leader = { active = false, at = 0, handlers = {} }
local function bind(mode, keys, fn)
    for _, k in ipairs(keys) do
        local function wrapped()
            if leader.active then
                leader.active = false
                local h = (os.time() - leader.at <= 5) and leader.handlers[k]
                if h then h() end
                return
            end
            fn()
        end
        local ok = pcall(swayimg[mode].on_key, k, wrapped)
        if ok then bound[mode .. ":" .. k] = true
        else bad[#bad + 1] = mode .. ":" .. k end
    end
end

local function key(mode, k, fn) bind(mode, { k }, fn) end

-- nsxiv-style numeric prefix: "10n" = 10 images forward, "5k" = pan 5 steps
local count = 0
local function take_count()
    local n = (count > 0) and count or 1
    count = 0
    return n
end
for d = 0, 9 do
    local f = function() count = count * 10 + d end
    key("viewer", tostring(d), f)
    key("gallery", tostring(d), f)
end

-- images to act on: marked ones if any, else the current one (like nsxiv's key-handler)
local function targets(current)
    local list = {}
    local ok, entries = pcall(swayimg.imagelist.get)
    if ok and entries then
        for _, e in ipairs(entries) do
            if e.mark then list[#list + 1] = e.path end
        end
    end
    if #list == 0 and current and current.path then list[1] = current.path end
    return list
end

-- run a shell command, true on exit status 0 (works on LuaJIT and Lua 5.2+)
local function run(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end
local function have(cmd) return run("command -v " .. cmd .. " >/dev/null 2>&1") end

-- yes/no prompt: fuzzel > wofi > bemenu > zenity > press-twice fallback
local pending = 0
local function confirm(msg)
    local yn = "printf 'No\\nYes\\n' | "
    if have("fuzzel") then
        return run(yn .. "fuzzel --dmenu -p " .. shq(msg .. " ") .. " | grep -qx Yes")
    elseif have("wofi") then
        return run(yn .. "wofi --dmenu -p " .. shq(msg) .. " | grep -qx Yes")
    elseif have("bemenu") then
        return run(yn .. "bemenu -p " .. shq(msg) .. " | grep -qx Yes")
    elseif have("zenity") then
        return run("zenity --question --text=" .. shq(msg))
    end
    -- no dialog tool: second press within 3s confirms
    if os.time() - pending <= 3 then pending = 0; return true end
    pending = os.time()
    notify("swayimg", msg .. " (press again to confirm)")
    return false
end

local function delete_files(paths)
    if #paths == 0 then return end
    local what = (#paths == 1) and (paths[1]:match("[^/]+$") or paths[1])
                               or (#paths .. " marked files")
    if not confirm("Delete " .. what .. "?") then return end
    local n = 0
    for _, p in ipairs(paths) do
        local ok, err = os.remove(p)
        if ok then
            swayimg.imagelist.remove(p)            -- drop from list, viewer jumps to next
            n = n + 1
        else
            notify("swayimg", "delete failed: " .. (err or p))
        end
    end
    if n > 0 then notify("swayimg", "deleted " .. n .. " file(s)") end
end

local function set_wallpaper(path)
    if not path then return end
    if os.getenv("SWAYSOCK") then
        os.execute(string.format("swaymsg %s >/dev/null",
            shq('output * bg "' .. path:gsub('"', '\\"') .. '" fill')))
    elseif os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
        os.execute(string.format("hyprctl hyprpaper wallpaper %s >/dev/null",
            shq("," .. path)))
    else
        notify("swayimg", "no sway/hyprland socket found")
        return
    end
    notify("swayimg", "wallpaper set")
end

local function toggle_info()
    swayimg.text.visible = not swayimg.text.visible
end

local PAN = 60  -- px per pan step
local function pan(dx, dy)
    local n = take_count()
    local ok, x, y = pcall(swayimg.viewer.get_position)
    if not ok or x == nil then return end
    if type(x) == "table" then                     -- get_position returns {x=, y=}
        x, y = x.x or x[1], x.y or x[2]
    end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local nx, ny = x + dx * n * PAN, y + dy * n * PAN
    -- set_abs_position may take (x, y) or a table, depending on version
    if not pcall(swayimg.viewer.set_abs_position, nx, ny) then
        pcall(swayimg.viewer.set_abs_position, { x = nx, y = ny })
    end
end

local function zoom(factor)
    swayimg.viewer.scale = swayimg.viewer.scale * factor
end

-- ==============================================================================
-- VIEWER MODE
-- ==============================================================================

-- navigation: n/Space next, p/Backspace prev, [ ] = +-10 (nsxiv), g/G first/last
bind("viewer", { "n", "space", "Space" }, function()
    for _ = 1, take_count() do swayimg.viewer.open("next") end
end)
bind("viewer", { "p", "BackSpace", "Backspace" }, function()
    for _ = 1, take_count() do swayimg.viewer.open("prev") end
end)
bind("viewer", { "bracketright", "]" }, function()
    take_count()
    for _ = 1, 10 do swayimg.viewer.open("next") end
end)
bind("viewer", { "bracketleft", "[" }, function()
    take_count()
    for _ = 1, 10 do swayimg.viewer.open("prev") end
end)
key("viewer", "g", function() count = 0; swayimg.viewer.open("first") end)
key("viewer", "G", function() count = 0; swayimg.viewer.open("last") end)

-- panning: hjkl
key("viewer", "h", function() pan( 1,  0) end)
key("viewer", "l", function() pan(-1,  0) end)
key("viewer", "k", function() pan( 0,  1) end)
key("viewer", "j", function() pan( 0, -1) end)

-- zoom: + - = w e E
bind("viewer", { "plus", "+" }, function() zoom(1.2) end)
bind("viewer", { "minus", "-" }, function() zoom(1 / 1.2) end)
bind("viewer", { "equal", "=" }, function() swayimg.viewer.scale = 1.0 end)  -- 100%
key("viewer", "w", function() swayimg.viewer.reset() end)       -- fit/optimal
key("viewer", "e", function() pcall(swayimg.viewer.set_fix_scale, "width")  end)
key("viewer", "E", function() pcall(swayimg.viewer.set_fix_scale, "height") end)

-- transforms: < > rotate, | _ flip
bind("viewer", { "less", "<" }, function() swayimg.viewer.rotate(270) end)
bind("viewer", { "greater", ">" }, function() swayimg.viewer.rotate(90) end)
bind("viewer", { "bar", "|" }, function() swayimg.viewer.flip_horizontal() end)
bind("viewer", { "underscore", "_" }, function() swayimg.viewer.flip_vertical() end)

-- marks, ui, misc
key("viewer", "m", function() swayimg.viewer.mark_image() end)
key("viewer", "b", toggle_info)
key("viewer", "i", toggle_info)
key("viewer", "q", function() swayimg.exit(0) end)
key("viewer", "Return", function() swayimg.mode = "gallery" end)

-- actions (operate on marked images, else current)
key("viewer", "Ctrl-d", function()
    delete_files(targets(swayimg.viewer.get_image()))
end)
key("viewer", "Ctrl-w", function()
    local img = swayimg.viewer.get_image()
    if img then set_wallpaper(img.path) end
end)

-- ==============================================================================
-- GALLERY (thumbnail) MODE
-- ==============================================================================

local function gsel(dir)
    return function()
        for _ = 1, take_count() do swayimg.gallery.select(dir) end
    end
end
key("gallery", "h", gsel("left"))
key("gallery", "j", gsel("down"))
key("gallery", "k", gsel("up"))
key("gallery", "l", gsel("right"))
key("gallery", "g", function() count = 0; swayimg.gallery.select("first") end)
key("gallery", "G", function() count = 0; swayimg.gallery.select("last") end)

key("gallery", "m", function() swayimg.gallery.mark_image() end)
key("gallery", "b", toggle_info)
key("gallery", "q", function() swayimg.exit(0) end)
key("gallery", "Return", function() swayimg.mode = "viewer" end)

key("gallery", "Ctrl-d", function()
    delete_files(targets(swayimg.gallery.get_image()))
end)
key("gallery", "Ctrl-w", function()
    local img = swayimg.gallery.get_image()
    if img then set_wallpaper(img.path) end
end)

-- ==============================================================================
-- HELP: Ctrl-h shows keybindings (desktop notification)
-- ==============================================================================

local HELP = table.concat({
    "VIEWER",
    "n/Space  p/BkSp   next / prev   (10n = 10 images)",
    "[ ]  ±10 images    g G  first / last",
    "h j k l  pan       + - zoom   = 100%   w fit",
    "e / E  fit width / height",
    "< >  rotate        | _  flip",
    "m  mark   b/i  info   Return  gallery   q  quit",
    "",
    "GALLERY",
    "h j k l  move   g G  first / last   m  mark",
    "Return  open   q  quit",
    "",
    "BOTH",
    "Ctrl-d  delete marked (or current)",
    "Ctrl-w  set wallpaper",
    "Ctrl-h  this help",
}, "\n")

-- ==============================================================================
-- LEADER KEY HANDLER  ("," then key) -- port of the sxiv key-handler script
-- ==============================================================================

local TERMINAL = "alacritty --class modal -e"   -- sway: for_window [app_id="modal"] floating enable

local function show_modal(text)
    local script = 'printf "%s\\n" "$1"; printf "\\nPress Enter to close"; read -r'
    os.execute(string.format("setsid -f %s sh -c %s sh %s >/dev/null 2>&1",
        TERMINAL, shq(script), shq(text)))
end

local function capture(cmd)
    local f = io.popen(cmd .. " 2>&1")
    if not f then return "" end
    local out = f:read("*a") or ""
    f:close()
    return (out:gsub("%s+$", ""))
end

local function current()
    local ok, m = pcall(function() return swayimg.mode end)
    local api = (ok and m == "gallery") and swayimg.gallery or swayimg.viewer
    return api.get_image()
end

local LEADER_HELP = table.concat({
    "LEADER  ,  then:",
    "h  show hotkeys",
    "i  show file information",
    "r  rotate file 90 degrees",
    "c  copy image to clipboard",
    "w  set wallpaper",
    "y  copy file path",
    "Y  copy absolute file path",
    "d  delete file(s) (asks first)",
    "g  open in GIMP",
}, "\n")

local function show_help() show_modal(HELP .. "\n\n" .. LEADER_HELP) end
key("viewer", "Ctrl-h", show_help)
key("gallery", "Ctrl-h", show_help)

-- all handlers act on marked images, else the current one
local H = leader.handlers
H.h = show_help
H.i = function()
    local img = current()
    if img then show_modal("File information\n" .. capture("mediainfo " .. shq(img.path))) end
end
H.r = function()
    local paths = targets(current())
    for _, p in ipairs(paths) do os.execute("magick " .. shq(p) .. " -rotate 90 " .. shq(p)) end
    if paths[1] then pcall(swayimg.viewer.open_path, paths[1]) end  -- reload from disk
end
H.c = function()
    local p = targets(current())[1]
    if p then
        os.execute("magick " .. shq(p) .. " png:- | wl-copy -t image/png &")
        notify("swayimg", "image copied to clipboard")
    end
end
H.w = function()
    local p = targets(current())[1]
    if p then set_wallpaper(p) end
end
H.y = function()
    local paths = targets(current())
    if #paths == 0 then return end
    os.execute("printf %s " .. shq(table.concat(paths, "\n")) .. " | wl-copy")
    notify("swayimg", "path copied: " .. paths[1])
end
H.Y = function()
    local abs = {}
    for _, p in ipairs(targets(current())) do abs[#abs + 1] = capture("readlink -f " .. shq(p)) end
    if #abs == 0 then return end
    os.execute("printf %s " .. shq(table.concat(abs, "\n")) .. " | wl-copy")
    notify("swayimg", "path copied: " .. abs[1])
end
H.d = function() delete_files(targets(current())) end
H.g = function()
    local q = {}
    for _, p in ipairs(targets(current())) do q[#q + 1] = shq(p) end
    if #q > 0 then os.execute("setsid -f gimp " .. table.concat(q, " ") .. " >/dev/null 2>&1") end
end

-- leader key itself, plus no-op binds so handler keys with no normal binding are caught
for _, mode in ipairs({ "viewer", "gallery" }) do
    for _, k in ipairs({ "comma", "," }) do
        pcall(swayimg[mode].on_key, k, function()
            leader.active, leader.at = true, os.time()
        end)
    end
    for k in pairs(H) do
        if not bound[mode .. ":" .. k] then bind(mode, { k }, function() end) end
    end
end

-- report any key names this build rejected (fix names in the bind()/key() calls)
if #bad > 0 then notify("swayimg config", "skipped keys: " .. table.concat(bad, " ")) end