-- Plugin-free Neovim configuration based on dot_vimrc.

local opt = vim.opt
local map = vim.keymap.set

vim.g.mapleader = ","

-- Monokai palette, defined here so no colorscheme plugin is needed.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai"

local palette = {
  bg = "#272822", fg = "#f8f8f2", comment = "#75715e",
  pink = "#f92672", green = "#a6e22e", yellow = "#e6db74",
  orange = "#fd971f", purple = "#ae81ff", cyan = "#66d9ef",
}
local function hi(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

hi("Normal", { fg = palette.fg, bg = palette.bg })
hi("NormalFloat", { fg = palette.fg, bg = "#1e1f1c" })
hi("Comment", { fg = palette.comment, italic = true })
hi("Constant", { fg = palette.purple })
hi("String", { fg = palette.yellow })
hi("Character", { fg = palette.yellow })
hi("Number", { fg = palette.purple })
hi("Boolean", { fg = palette.purple })
hi("Identifier", { fg = palette.fg })
hi("Function", { fg = palette.green })
hi("Statement", { fg = palette.pink })
hi("Conditional", { fg = palette.pink })
hi("Repeat", { fg = palette.pink })
hi("Operator", { fg = palette.pink })
hi("Keyword", { fg = palette.pink })
hi("PreProc", { fg = palette.green })
hi("Type", { fg = palette.cyan })
hi("Special", { fg = palette.orange })
hi("Underlined", { fg = palette.cyan, underline = true })
hi("Error", { fg = palette.bg, bg = palette.pink })
hi("Todo", { fg = palette.orange, bold = true })
hi("Visual", { bg = "#49483e" })
hi("Search", { fg = palette.bg, bg = palette.yellow })
hi("IncSearch", { fg = palette.bg, bg = palette.orange })
hi("StatusLine", { fg = palette.fg, bg = "#414339" })
hi("StatusLineNC", { fg = palette.comment, bg = "#34352f" })
hi("LineNr", { fg = palette.comment })
hi("CursorLineNr", { fg = palette.yellow, bold = true })
hi("CursorLine", { bg = "#34352f" })
hi("VertSplit", { fg = "#49483e" })
hi("Pmenu", { fg = palette.fg, bg = "#414339" })
hi("PmenuSel", { fg = palette.bg, bg = palette.green })

-- General editing and display
opt.mouse = "a"
opt.scrolloff = 4
opt.autoread = true
opt.textwidth = 0
opt.number = true
opt.relativenumber = true
opt.showcmd = true
opt.cursorline = true
opt.showmatch = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.expandtab = true
opt.smarttab = true
opt.termguicolors = true
opt.clipboard = "unnamedplus"
opt.foldlevel = 3

-- Searching and command completion
opt.incsearch = true
opt.hlsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.path:append("**")
opt.wildmenu = true
opt.wildmode = { "longest", "list", "full" }

vim.api.nvim_create_autocmd("FileChangedShell", {
  desc = "Warn when the current file changes outside Neovim",
  callback = function()
    vim.notify("File changed on disk", vim.log.levels.WARN)
  end,
})

-- Clipboard mappings from the Vim configuration.
map({ "n", "v" }, "<Leader>y", '"*y', { desc = "Yank to primary clipboard" })
map({ "n", "v" }, "<Leader>p", '"*p', { desc = "Paste from primary clipboard" })
map({ "n", "v" }, "<Leader>Y", '"+y', { desc = "Yank to system clipboard" })
map({ "n", "v" }, "<Leader>P", '"+p', { desc = "Paste from system clipboard" })

-- Quick insert-mode motions.
map("i", "II", "<Esc>I")
map("i", "AA", "<Esc>A")
map("i", "OO", "<Esc>O")
map("i", "CC", "<Esc>C")
map("i", "SS", "<Esc>S")
map("i", "DD", "<Esc>dd")
map("i", "UU", "<Esc>u")

-- Markdown heading helpers (F1-F4).
local function markdown_heading(level)
  local line = vim.api.nvim_get_current_line()
  local hashes = string.rep("#", level)
  local content = line:gsub("^#+%s*", "")
  if content == line then
    content = line:gsub("^%s*", "")
  end
  local heading = hashes .. " " .. content
  if level <= 2 then
    heading = heading:upper()
  else
    heading = heading:lower()
  end
  vim.api.nvim_set_current_line(heading)
end

for level = 1, 4 do
  map("n", "<F" .. level .. ">", function()
    markdown_heading(level)
  end, { desc = "Make Markdown heading level " .. level })
end

map("n", "<Leader>1", "/^# <CR>", { desc = "Next level-one heading" })
map("n", "<Leader>2", "/^## <CR>", { desc = "Next level-two heading" })
map("n", "<Leader>sop", "<Cmd>write<Bar>source %<CR>", { desc = "Save and source current file" })

-- Add Markdown code fences around the current line or visual selection.
local function fence_selection(language)
  local first = vim.fn.line("'[")
  local last = vim.fn.line("']")
  if first == 0 or last == 0 then
    first = vim.api.nvim_win_get_cursor(0)[1]
    last = first
  end
  if first > last then
    first, last = last, first
  end
  vim.api.nvim_buf_set_lines(0, last, last, false, { "```" })
  vim.api.nvim_buf_set_lines(0, first - 1, first - 1, false, { "```" .. language })
end

vim.api.nvim_create_user_command("FTsurround", function(args)
  fence_selection(args.args)
end, { nargs = "*", range = true })

map("n", "ss.", ":FTsurround ")
map("n", "ssv", ":FTsurround vim<CR>")
map("n", "ssb", ":FTsurround bash<CR>")
map("n", "sst", ":FTsurround text<CR>")
map("n", "ssj", ":FTsurround js<CR>")
map("n", "ssp", ":FTsurround php<CR>")

map("x", "ss.", ":<C-U>FTsurround ")
map("x", "ssv", function() fence_selection("vim") end)
map("x", "ssb", function() fence_selection("bash") end)
map("x", "sst", function() fence_selection("text") end)
map("x", "ssj", function() fence_selection("js") end)
map("x", "ssp", function() fence_selection("php") end)

map("n", "<Leader>test1", ":!notify-send <C-R>%<CR>", { desc = "Send current filename notification" })

