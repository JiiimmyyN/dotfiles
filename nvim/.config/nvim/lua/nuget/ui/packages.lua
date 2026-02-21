local state = require("nuget.state")
local config = require("nuget.config")
local layout = require("nuget.ui.layout")

local M = {}

--- Namespace for extmarks
M.ns = vim.api.nvim_create_namespace("nuget_packages")

--- Debounce cursor movement to avoid excessive detail loading
local _cursor_move_id = 0

--- Render the left panel (package list)
function M.render()
  local s = state.current
  if not s.left_buf or not vim.api.nvim_buf_is_valid(s.left_buf) then
    return
  end

  -- Save cursor position before re-render
  local cursor_pos = nil
  if s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
    cursor_pos = vim.api.nvim_win_get_cursor(s.left_win)
  end

  local lines = {}
  local highlights = {} -- { line_0idx, col_start, col_end, hl_group }
  s.line_to_package = {}

  local icons = config.options.icons
  local win_width = 60
  if s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
    win_width = vim.api.nvim_win_get_width(s.left_win)
  end

  -- ── Line 1: Mode tabs + prerelease toggle ──
  local installed_label = s.mode == "installed" and "[Installed]" or " Installed "
  local browse_label = s.mode == "browse" and "[Browse]" or " Browse "
  local pre_label = s.prerelease and "Prerelease ✓" or "Prerelease  "
  local mode_line = " NuGet   " .. installed_label .. "  " .. browse_label
  local pre_pad = math.max(1, win_width - #mode_line - #pre_label - 1)
  mode_line = mode_line .. string.rep(" ", pre_pad) .. pre_label

  table.insert(lines, mode_line)
  table.insert(highlights, { 0, 1, 6, "NugetHeader" })
  -- Installed tab highlight
  local inst_start = 9
  local inst_end = inst_start + #installed_label
  table.insert(highlights, { 0, inst_start, inst_end, s.mode == "installed" and "NugetModeActive" or "NugetModeInactive" })
  -- Browse tab highlight
  local browse_start = inst_end + 2
  local browse_end = browse_start + #browse_label
  table.insert(highlights, { 0, browse_start, browse_end, s.mode == "browse" and "NugetModeActive" or "NugetModeInactive" })
  -- Prerelease highlight
  local pre_start = #mode_line - #pre_label
  table.insert(highlights, { 0, pre_start, #mode_line, s.prerelease and "NugetPrerelease" or "NugetInfo" })

  -- ── Line 2: Search ──
  local search_line
  if s.search_query ~= "" then
    search_line = " Search: " .. s.search_query
  else
    local hint = s.mode == "installed" and "(press s to filter)" or "(press s to search NuGet)"
    search_line = " Search: " .. hint
  end
  table.insert(lines, search_line)
  table.insert(highlights, { 1, 0, 9, "NugetSearchPrompt" })
  if s.search_query ~= "" then
    table.insert(highlights, { 1, 9, #search_line, "NugetSearchText" })
  else
    table.insert(highlights, { 1, 9, #search_line, "NugetInfo" })
  end

  -- ── Line 3: Separator ──
  table.insert(lines, " " .. string.rep("─", math.max(1, win_width - 2)))
  table.insert(highlights, { 2, 0, win_width, "NugetSeparator" })

  -- ── Line 4: Status ──
  local status_line
  if s.mode == "installed" then
    if s.loading_packages then
      status_line = " " .. icons.loading .. " Loading packages..."
      table.insert(highlights, { 3, 0, #status_line, "NugetLoading" })
    else
      local count = #s.filtered_list
      local total = s.package_count
      if s.search_query ~= "" and count ~= total then
        status_line = " Showing " .. count .. " of " .. total .. " packages"
      else
        status_line = " Installed Packages in Solution: " .. total
      end
      table.insert(highlights, { 3, 0, #status_line, "NugetSubHeader" })
    end
  else
    if s.loading_search then
      status_line = " " .. icons.loading .. " Searching..."
      table.insert(highlights, { 3, 0, #status_line, "NugetLoading" })
    elseif s.search_query ~= "" then
      status_line = " Found " .. #s.search_results .. " packages"
      table.insert(highlights, { 3, 0, #status_line, "NugetSubHeader" })
    else
      status_line = " Type s to search NuGet packages"
      table.insert(highlights, { 3, 0, #status_line, "NugetInfo" })
    end
  end
  table.insert(lines, status_line)

  -- ── Line 5: Empty ──
  table.insert(lines, "")

  s.header_lines = #lines -- number of header lines (1-indexed)

  -- ── Package list ──
  local pkg_list
  if s.mode == "installed" then
    pkg_list = s.filtered_list
  else
    pkg_list = s.search_results
  end

  if #pkg_list == 0 and not s.loading_packages and not s.loading_search then
    local empty_msg
    if s.mode == "installed" then
      empty_msg = s.search_query ~= "" and "   No matching packages found" or "   No packages installed"
    else
      empty_msg = s.search_query == "" and "   Search for a package to get started" or "   No packages found"
    end
    table.insert(lines, empty_msg)
    table.insert(highlights, { #lines - 1, 0, #empty_msg, "NugetInfo" })
  end

  -- Reserve rightmost columns for the latest version
  local version_col = math.max(win_width - 14, 40)

  for _, pkg in ipairs(pkg_list) do
    local line_idx = #lines -- 0-indexed line number
    s.line_to_package[line_idx] = pkg

    local current_ver = pkg.installed_version or pkg.version or ""
    local source = pkg.source

    -- Build: "   PackageName • version" (+ optional " • source")
    local prefix = "   "
    local display = prefix .. pkg.id .. " " .. icons.separator .. " " .. current_ver
    if source and source ~= "" then
      display = display .. " " .. icons.separator .. " " .. source
    end

    -- Right-aligned latest version (only if outdated)
    local latest = ""
    if pkg.is_outdated and pkg.latest_version and pkg.latest_version ~= current_ver then
      latest = pkg.latest_version
    end

    if latest ~= "" then
      local pad = math.max(1, version_col - #display)
      display = display .. string.rep(" ", pad) .. latest
    end

    -- In browse mode, show download count instead
    if s.mode == "browse" and pkg.total_downloads and pkg.total_downloads > 0 then
      local dl = require("nuget.utils").format_number(pkg.total_downloads)
      local pad = math.max(1, version_col - #display)
      display = display .. string.rep(" ", pad) .. dl
    end

    table.insert(lines, display)

    -- ── Highlights for this line ──
    local col = #prefix

    -- Package name
    table.insert(highlights, { line_idx, col, col + #pkg.id, "NugetPackageName" })
    col = col + #pkg.id + 1 + #icons.separator + 1

    -- Current version
    local ver_hl = pkg.is_outdated and "NugetPackageVersionOutdated" or "NugetPackageVersion"
    table.insert(highlights, { line_idx, col, col + #current_ver, ver_hl })
    col = col + #current_ver

    if source and source ~= "" then
      col = col + 1 + #icons.separator + 1
      table.insert(highlights, { line_idx, col, col + #source, "NugetPackageSource" })
      col = col + #source
    end

    -- Latest version (right-aligned)
    if latest ~= "" then
      local latest_start = #display - #latest
      table.insert(highlights, { line_idx, latest_start, #display, "NugetPackageLatest" })
    end

    -- Download count in browse mode
    if s.mode == "browse" and pkg.total_downloads and pkg.total_downloads > 0 then
      local dl = require("nuget.utils").format_number(pkg.total_downloads)
      local dl_start = #display - #dl
      table.insert(highlights, { line_idx, dl_start, #display, "NugetDownloads" })
    end
  end

  -- ── Status message ──
  if s.action_message then
    table.insert(lines, "")
    table.insert(lines, " " .. s.action_message)
    table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetStatusMessage" })
  end

  -- Write lines to buffer
  layout.set_lines(s.left_buf, lines)

  -- Apply highlights
  layout.clear_extmarks(s.left_buf, M.ns)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, s.left_buf, M.ns, hl[4], hl[1], hl[2], hl[3])
  end

  -- Restore cursor position
  if cursor_pos and s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
    local max_line = vim.api.nvim_buf_line_count(s.left_buf)
    local target_line = math.min(cursor_pos[1], max_line)
    -- Ensure cursor is on a package line
    if target_line <= s.header_lines and #pkg_list > 0 then
      target_line = s.header_lines + 1
    end
    pcall(vim.api.nvim_win_set_cursor, s.left_win, { target_line, 0 })
  end
end

--- Get the package info at the current cursor line
---@return NugetPackageInfo|nil
function M.get_package_at_cursor()
  local s = state.current
  if not s.left_win or not vim.api.nvim_win_is_valid(s.left_win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(s.left_win)
  local line = cursor[1] - 1 -- convert to 0-indexed
  return s.line_to_package[line]
end

--- Handle cursor movement -- debounced detail loading
function M.on_cursor_moved()
  _cursor_move_id = _cursor_move_id + 1
  local my_id = _cursor_move_id

  vim.defer_fn(function()
    if my_id ~= _cursor_move_id then
      return -- superseded by a newer move
    end

    local pkg = M.get_package_at_cursor()
    if not pkg then
      return
    end

    local s = state.current
    if s.selected_package and s.selected_package.id == pkg.id then
      return -- same package, no change
    end

    s.selected_package = pkg
    require("nuget.ui.details").load_and_render(pkg)
  end, 100) -- 100ms debounce
end

--- Set up keymaps for the left panel
function M.setup_keymaps()
  local s = state.current
  if not s.left_buf or not vim.api.nvim_buf_is_valid(s.left_buf) then
    return
  end

  local buf = s.left_buf
  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  -- Close
  map("q", function()
    layout.close()
  end, "Close NuGet")

  -- Search / Filter
  map("s", function()
    M.start_search()
  end, "Search packages")

  map("/", function()
    M.start_search()
  end, "Search packages")

  -- Clear search
  map("<Esc>", function()
    if s.search_query ~= "" then
      s.search_query = ""
      if s.mode == "installed" then
        M.filter_packages()
      else
        s.search_results = {}
      end
      M.render()
    end
  end, "Clear search")

  -- Toggle prerelease
  map("p", function()
    s.prerelease = not s.prerelease
    require("nuget").refresh()
  end, "Toggle prerelease")

  -- Mode switching
  map("b", function()
    s.mode = "browse"
    s.search_query = ""
    s.search_results = {}
    s.selected_package = nil
    M.render()
    require("nuget.ui.details").render_empty()
  end, "Browse NuGet packages")

  map("i", function()
    s.mode = "installed"
    s.search_query = ""
    s.selected_package = nil
    M.filter_packages()
    M.render()
    require("nuget.ui.details").render_empty()
  end, "Installed packages")

  -- Refresh
  map("r", function()
    require("nuget").refresh()
  end, "Refresh packages")

  -- Select and focus details
  map("<CR>", function()
    local pkg = M.get_package_at_cursor()
    if pkg then
      s.selected_package = pkg
      require("nuget.ui.details").load_and_render(pkg)
      -- Focus right panel
      if s.right_win and vim.api.nvim_win_is_valid(s.right_win) then
        vim.api.nvim_set_current_win(s.right_win)
      end
    end
  end, "View package details")

  -- Switch to right panel
  map("<Tab>", function()
    if s.right_win and vim.api.nvim_win_is_valid(s.right_win) then
      vim.api.nvim_set_current_win(s.right_win)
    end
  end, "Focus details panel")

  -- CursorMoved autocmd for auto-preview
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      M.on_cursor_moved()
    end,
  })

  -- Help popup
  map("?", function()
    layout.show_help()
  end, "Show help")
end

--- Start search input
function M.start_search()
  local s = state.current
  local prompt = s.mode == "installed" and "Filter packages: " or "Search NuGet: "

  vim.ui.input({ prompt = prompt, default = s.search_query }, function(input)
    if input == nil then
      return -- cancelled
    end
    s.search_query = input

    if s.mode == "installed" then
      M.filter_packages()
      M.render()
    else
      if input ~= "" then
        M.search_nuget(input)
      else
        s.search_results = {}
        M.render()
      end
    end
  end)
end

--- Filter installed packages by search query
function M.filter_packages()
  local s = state.current
  if s.search_query == "" then
    s.filtered_list = vim.deepcopy(s.package_list)
    return
  end

  local query = s.search_query:lower()
  s.filtered_list = {}
  for _, pkg in ipairs(s.package_list) do
    if pkg.id:lower():find(query, 1, true) then
      table.insert(s.filtered_list, pkg)
    end
  end
end

--- Search NuGet API (browse mode)
---@param query string
function M.search_nuget(query)
  local s = state.current
  s.loading_search = true
  M.render()

  require("nuget.api.dotnet").search_packages(query, {
    prerelease = s.prerelease,
    take = 50,
  }, s.solution_dir or vim.fn.getcwd(), function(results, err)
    s.loading_search = false
    if err then
      require("nuget.utils").notify("Search failed: " .. err, vim.log.levels.ERROR)
      M.render()
      return
    end

    s.search_results = {}
    if results and results.searchResult then
      for _, group in ipairs(results.searchResult) do
        local source_name = group.sourceName or ""
        for _, pkg in ipairs(group.packages or {}) do
          local installed = s.packages[pkg.id:lower()]
          table.insert(s.search_results, {
            id = pkg.id,
            version = pkg.latestVersion,
            installed_version = installed and installed.installed_version or nil,
            latest_version = pkg.latestVersion,
            description = nil,
            total_downloads = pkg.totalDownloads,
            source = source_name,
            is_installed = installed ~= nil,
            is_outdated = false,
            projects = installed and installed.projects or {},
          })
        end
      end
    end

    M.render()
  end)
end

return M
