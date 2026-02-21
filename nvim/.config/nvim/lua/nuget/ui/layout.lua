local state = require("nuget.state")
local config = require("nuget.config")

local M = {}

-- Highlight group definitions
local hl_groups = {
  NugetHeader = { link = "Title" },
  NugetSubHeader = { link = "Comment" },
  NugetSeparator = { link = "NonText" },
  NugetPackageName = { link = "Identifier" },
  NugetPackageVersion = { link = "Number" },
  NugetPackageVersionOutdated = { link = "DiagnosticWarn" },
  NugetPackageLatest = { link = "String" },
  NugetPackageSource = { link = "Comment" },
  NugetInstalled = { link = "DiagnosticOk" },
  NugetNotInstalled = { link = "NonText" },
  NugetAction = { link = "Special" },
  NugetLoading = { link = "Comment" },
  NugetError = { link = "DiagnosticError" },
  NugetProjectName = { link = "Normal" },
  NugetSearchPrompt = { link = "SpecialKey" },
  NugetSearchText = { link = "Normal" },
  NugetModeActive = { link = "TabLineSel" },
  NugetModeInactive = { link = "TabLine" },
  NugetPrerelease = { link = "WarningMsg" },
  NugetInfo = { link = "Comment" },
  NugetStatusMessage = { link = "MoreMsg" },
  NugetDownloads = { link = "Comment" },
}

--- Set up highlight groups
function M.setup_highlights()
  for name, hl in pairs(hl_groups) do
    vim.api.nvim_set_hl(0, name, hl)
  end
end

--- Create a scratch buffer with standard options
---@param name string Buffer name
---@return integer buf Buffer handle
local function create_buffer(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "nuget"
  return buf
end

--- Open the NuGet manager layout (new tab with vertical split)
---@return boolean success
function M.open()
  local s = state.current

  -- If already open, just focus the existing window
  if s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
    vim.api.nvim_set_current_win(s.left_win)
    return true
  end

  M.setup_highlights()

  -- Create a new tab
  vim.cmd("tabnew")
  s.tab = vim.api.nvim_get_current_tabpage()

  -- Left buffer (packages list) uses the initial window
  s.left_buf = create_buffer("nuget://packages")
  vim.api.nvim_win_set_buf(0, s.left_buf)
  s.left_win = vim.api.nvim_get_current_win()

  -- Create right split (details panel)
  local total_width = vim.api.nvim_win_get_width(s.left_win)
  local left_width = math.floor(total_width * config.options.split_ratio)

  vim.cmd("vsplit")
  s.right_buf = create_buffer("nuget://details")
  vim.api.nvim_win_set_buf(0, s.right_buf)
  s.right_win = vim.api.nvim_get_current_win()

  -- Set widths
  vim.api.nvim_win_set_width(s.left_win, left_width)

  -- Window options for both panels
  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].wrap = true
    vim.wo[win].spell = false
    vim.wo[win].cursorline = false
    vim.wo[win].winfixwidth = true
    vim.wo[win].statuscolumn = ""
  end

  -- Enable cursorline only on left panel for navigation
  vim.wo[s.left_win].cursorline = true

  -- Focus left panel
  vim.api.nvim_set_current_win(s.left_win)

  -- Autocommand to clean up when windows are closed
  local augroup = vim.api.nvim_create_augroup("NugetLayout", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(ev)
      local win_id = tonumber(ev.match)
      if win_id == s.left_win or win_id == s.right_win then
        -- Defer close to avoid issues during WinClosed event
        vim.schedule(function()
          M.close()
        end)
        return true -- remove autocmd
      end
    end,
  })

  return true
end

--- Close the NuGet manager and clean up
function M.close()
  local s = state.current

  -- Remove augroup first to prevent recursive close
  pcall(vim.api.nvim_del_augroup_by_name, "NugetLayout")

  -- Close windows
  for _, win in ipairs({ s.left_win, s.right_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  -- Delete buffers
  for _, buf in ipairs({ s.left_buf, s.right_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- Close the tab if it's empty and there are other tabs
  if s.tab and vim.api.nvim_tabpage_is_valid(s.tab) then
    local wins = vim.api.nvim_tabpage_list_wins(s.tab)
    local all_empty = true
    for _, w in ipairs(wins) do
      if vim.api.nvim_win_is_valid(w) then
        local b = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_buf_get_name(b) ~= "" or vim.bo[b].modified then
          all_empty = false
          break
        end
      end
    end
    if all_empty and #vim.api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, "tabclose")
    end
  end

  -- Reset state
  state.reset()
end

--- Check if the layout is currently open
---@return boolean
function M.is_open()
  local s = state.current
  return s.left_win ~= nil and vim.api.nvim_win_is_valid(s.left_win)
end

--- Set buffer content (toggles modifiable flag)
---@param buf integer Buffer handle
---@param lines string[] Lines to set
function M.set_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Clear all extmarks in a buffer for a given namespace
---@param buf integer Buffer handle
---@param ns integer Namespace ID
function M.clear_extmarks(buf, ns)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

--- Show a floating help popup with all keybinds
function M.show_help()
  local lines = {
    " NuGet Package Manager — Help",
    "",
    " Package List (left panel)",
    " ──────────────────────────────────",
    "   s / /    Search / filter",
    "   p        Toggle prerelease",
    "   b        Browse NuGet packages",
    "   i        View installed packages",
    "   r        Refresh",
    "   <CR>     Select & focus details",
    "   <Tab>    Switch panel focus",
    "   <Esc>    Clear search",
    "   q        Close NuGet",
    "",
    " Details panel (right panel)",
    " ──────────────────────────────────",
    "   v        Open version selector",
    "   a / +    Add to project at cursor",
    "   x / -    Remove from project",
    "   u        Update project at cursor",
    "   U        Update all projects",
    "   h / <Tab> Focus package list",
    "   q        Close NuGet",
    "",
    " Press ? / q / <Esc> to close this popup",
  }

  local width = 44
  local height = #lines

  -- Center the popup in the editor
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  })

  -- Write content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("nuget_help")
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "NugetHeader", 0, 0, -1)
  for _, i in ipairs({ 2, 13 }) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, "NugetSubHeader", i, 0, -1)
  end
  for _, i in ipairs({ 3, 15 }) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, "NugetSeparator", i, 0, -1)
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "NugetInfo", #lines - 1, 0, -1)

  -- Dismiss keymaps
  local function close_help()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  for _, key in ipairs({ "q", "?", "<Esc>" }) do
    vim.keymap.set("n", key, close_help, { buffer = buf, nowait = true, silent = true })
  end
end

return M
