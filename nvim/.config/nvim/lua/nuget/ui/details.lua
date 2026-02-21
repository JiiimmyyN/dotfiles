local state = require("nuget.state")
local config = require("nuget.config")
local layout = require("nuget.ui.layout")
local nuget_api = require("nuget.api.nuget")
local dotnet_api = require("nuget.api.dotnet")
local utils = require("nuget.utils")

local M = {}

--- Namespace for extmarks
M.ns = vim.api.nvim_create_namespace("nuget_details")

--- Render the empty/help state for the details panel
function M.render_empty()
  local s = state.current
  if not s.right_buf or not vim.api.nvim_buf_is_valid(s.right_buf) then
    return
  end

  local lines = {
    "",
    "  Select a package to view details",
    "",
    "  Keymaps:",
    "  ──────────────────────────────────",
    "    s / /    Search / filter",
    "    p        Toggle prerelease",
    "    b        Browse NuGet packages",
    "    i        View installed packages",
    "    r        Refresh",
    "    <CR>     Select & focus details",
    "    <Tab>    Switch panel focus",
    "",
    "  Details panel:",
    "  ──────────────────────────────────",
    "    v        Open version selector",
    "    a / +    Add to project at cursor",
    "    x / -    Remove from project",
    "    u        Update project at cursor",
    "    U        Update all projects",
    "    q        Close NuGet",
  }

  layout.set_lines(s.right_buf, lines)
  layout.clear_extmarks(s.right_buf, M.ns)

  pcall(vim.api.nvim_buf_add_highlight, s.right_buf, M.ns, "NugetHeader", 1, 0, -1)
  for j = 4, #lines - 1 do
    pcall(vim.api.nvim_buf_add_highlight, s.right_buf, M.ns, "NugetInfo", j, 0, -1)
  end
end

--- Load metadata + versions and render details for a package
---@param pkg NugetPackageInfo
function M.load_and_render(pkg)
  local s = state.current
  if not pkg then
    M.render_empty()
    return
  end

  s.selected_version = pkg.latest_version or pkg.installed_version or pkg.version
  s.loading_details = true
  s.metadata = nil
  s.versions = nil
  M.render(pkg)

  local sources = s.sources or {}
  local credentials = s.source_credentials or {}
  local preferred_source = pkg.source

  -- Fetch metadata and versions in parallel
  local pending = 2
  local function check_done()
    pending = pending - 1
    if pending == 0 then
      s.loading_details = false
      M.render(pkg)
    end
  end

  nuget_api.get_metadata(pkg.id, nil, { preferred_source = preferred_source }, sources, credentials, function(metadata, _)
    s.metadata = metadata
    check_done()
  end)

  nuget_api.get_versions(pkg.id, { prerelease = s.prerelease, preferred_source = preferred_source }, sources, credentials, function(versions, _)
    s.versions = versions
    check_done()
  end)
end

--- Render the details panel
---@param pkg? NugetPackageInfo Package info (nil falls back to state.selected_package)
function M.render(pkg)
  local s = state.current
  pkg = pkg or s.selected_package
  if not pkg then
    M.render_empty()
    return
  end
  if not s.right_buf or not vim.api.nvim_buf_is_valid(s.right_buf) then
    return
  end

  local lines = {}
  local highlights = {} -- { line_0idx, col_start, col_end, hl_group }
  local icons = config.options.icons

  local win_width = 60
  if s.right_win and vim.api.nvim_win_is_valid(s.right_win) then
    win_width = vim.api.nvim_win_get_width(s.right_win)
  end

  s.line_to_project = {}

  -- ── Header: Package name ──
  local header = " " .. pkg.id
  local installed_in_any = false
  if pkg.is_installed ~= false then
    local pkg_data = s.packages[pkg.id:lower()]
    if pkg_data and pkg_data.projects and next(pkg_data.projects) then
      installed_in_any = true
    end
  end
  if installed_in_any then
    header = header .. " ✓"
  end
  table.insert(lines, header)
  table.insert(highlights, { 0, 0, #header, "NugetHeader" })

  -- ── Separator ──
  table.insert(lines, " " .. string.rep("─", math.max(1, win_width - 2)))
  table.insert(highlights, { 1, 0, win_width, "NugetSeparator" })

  -- ── Version + source ──
  local ver_display = s.selected_version or pkg.installed_version or pkg.version or "?"
  local source = pkg.source
  local ver_line = " Version  " .. ver_display
  if source and source ~= "" then
    local src_pad = math.max(1, win_width - #ver_line - #source - 2)
    ver_line = ver_line .. string.rep(" ", src_pad) .. source
  end
  table.insert(lines, ver_line)
  table.insert(highlights, { 2, 1, 9, "NugetSubHeader" })
  table.insert(highlights, { 2, 10, 10 + #ver_display, "NugetPackageVersion" })
  if source and source ~= "" then
    table.insert(highlights, { 2, #ver_line - #source, #ver_line, "NugetPackageSource" })
  end

  -- ── Empty ──
  table.insert(lines, "")

  -- ── Loading indicator ──
  if s.loading_details then
    table.insert(lines, " " .. icons.loading .. " Loading package details...")
    table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetLoading" })
    M._flush(lines, highlights)
    return
  end

  -- ── Info section ──
  local desc = ""
  if s.metadata and s.metadata.description then
    desc = s.metadata.description
  elseif pkg.description then
    desc = pkg.description
  end

  if desc ~= "" then
    table.insert(lines, " ▸ Info")
    table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetSubHeader" })

    local wrapped = M._wrap_text(desc, math.max(20, win_width - 6))
    for _, wline in ipairs(wrapped) do
      table.insert(lines, "   " .. wline)
      table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetInfo" })
    end
    table.insert(lines, "")
  end

  -- ── Frameworks and Dependencies ──
  if s.metadata and s.metadata.dependency_groups and #s.metadata.dependency_groups > 0 then
    table.insert(lines, " ▸ Frameworks and Dependencies")
    table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetSubHeader" })

    local frameworks = {}
    for _, group in ipairs(s.metadata.dependency_groups) do
      table.insert(frameworks, group.framework)
    end
    local fw_line = "   " .. table.concat(frameworks, ", ")
    table.insert(lines, fw_line)
    table.insert(highlights, { #lines - 1, 0, #fw_line, "NugetInfo" })

    -- Show dependencies for each framework (collapsed by default -- just framework names)
    for _, group in ipairs(s.metadata.dependency_groups) do
      if group.dependencies and #group.dependencies > 0 then
        local dep_names = {}
        for _, dep in ipairs(group.dependencies) do
          table.insert(dep_names, dep.id)
        end
        local dep_line = "     " .. group.framework .. ": " .. table.concat(dep_names, ", ")
        dep_line = utils.truncate(dep_line, win_width - 2)
        table.insert(lines, dep_line)
        table.insert(highlights, { #lines - 1, 0, #dep_line, "NugetInfo" })
      end
    end
    table.insert(lines, "")
  end

  -- ── Projects section ──
  if s.projects and #s.projects > 0 then
    local proj_header = " Projects"
    local ver_label = "Version"
    local proj_pad = math.max(1, win_width - #proj_header - #ver_label - 8)
    local header_line = proj_header .. string.rep(" ", proj_pad) .. ver_label
    table.insert(lines, header_line)
    table.insert(highlights, { #lines - 1, 0, #proj_header, "NugetSubHeader" })
    table.insert(highlights, { #lines - 1, #proj_header + proj_pad, #header_line, "NugetSubHeader" })

    -- Separator
    table.insert(lines, " " .. string.rep("─", math.max(1, win_width - 2)))
    table.insert(highlights, { #lines - 1, 0, win_width, "NugetSeparator" })

    -- Project list
    local pkg_lower = pkg.id:lower()
    local pkg_data = s.packages[pkg_lower]

    for _, proj in ipairs(s.projects) do
      local line_idx = #lines

      -- Check if this package is installed in this project
      local proj_ver = nil
      if pkg_data and pkg_data.projects then
        if pkg_data.projects[proj.full_path] then
          proj_ver = pkg_data.projects[proj.full_path].resolved
        end
      end

      local icon = proj_ver and icons.installed or icons.not_installed
      local icon_hl = proj_ver and "NugetInstalled" or "NugetNotInstalled"

      local max_name_len = math.max(10, win_width - 30)
      local proj_name = utils.truncate(proj.name, max_name_len)
      local ver_text = proj_ver or "-"

      -- Action hints
      local action
      if proj_ver then
        action = icons.update .. " " .. icons.remove
      else
        action = icons.add
      end

      -- Build line
      local proj_line = "   " .. icon .. " " .. proj_name
      local right_part = ver_text .. "    " .. action
      local line_pad = math.max(1, win_width - #proj_line - #right_part - 1)
      proj_line = proj_line .. string.rep(" ", line_pad) .. right_part

      table.insert(lines, proj_line)
      s.line_to_project[line_idx] = proj

      -- Highlights
      table.insert(highlights, { line_idx, 3, 3 + #icon, icon_hl })
      table.insert(highlights, { line_idx, 5, 5 + #proj_name, "NugetProjectName" })

      local ver_start = #proj_line - #right_part
      if proj_ver then
        table.insert(highlights, { line_idx, ver_start, ver_start + #ver_text, "NugetPackageVersion" })
      else
        table.insert(highlights, { line_idx, ver_start, ver_start + #ver_text, "NugetNotInstalled" })
      end

      local action_start = #proj_line - #action
      table.insert(highlights, { line_idx, action_start, #proj_line, "NugetAction" })
    end
  end

  -- ── Action status message ──
  if s.action_message then
    table.insert(lines, "")
    table.insert(lines, " " .. s.action_message)
    table.insert(highlights, { #lines - 1, 0, #lines[#lines], "NugetStatusMessage" })
  end

  M._flush(lines, highlights)
end

--- Write lines and highlights to the right buffer
---@param lines string[]
---@param highlights table[]
function M._flush(lines, highlights)
  local s = state.current
  layout.set_lines(s.right_buf, lines)
  layout.clear_extmarks(s.right_buf, M.ns)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, s.right_buf, M.ns, hl[4], hl[1], hl[2], hl[3])
  end
end

--- Set up keymaps for the right panel
function M.setup_keymaps()
  local s = state.current
  if not s.right_buf or not vim.api.nvim_buf_is_valid(s.right_buf) then
    return
  end

  local buf = s.right_buf
  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  -- Close
  map("q", function()
    layout.close()
  end, "Close NuGet")

  -- Version selector
  map("v", function()
    M.open_version_selector()
  end, "Select version")

  -- Add to project
  map("a", function()
    M.add_to_project()
  end, "Add package to project")
  map("+", function()
    M.add_to_project()
  end, "Add package to project")

  -- Remove from project
  map("x", function()
    M.remove_from_project()
  end, "Remove package from project")
  map("-", function()
    M.remove_from_project()
  end, "Remove package from project")

  -- Update single project
  map("u", function()
    M.update_project()
  end, "Update project to selected version")

  -- Update all projects
  map("U", function()
    M.update_all_projects()
  end, "Update all projects")

  -- Switch to left panel
  map("h", function()
    if s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
      vim.api.nvim_set_current_win(s.left_win)
    end
  end, "Focus package list")

  map("<Tab>", function()
    if s.left_win and vim.api.nvim_win_is_valid(s.left_win) then
      vim.api.nvim_set_current_win(s.left_win)
    end
  end, "Focus package list")

  -- Help popup
  map("?", function()
    layout.show_help()
  end, "Show help")
end

--- Get the project at the current cursor position in the right panel
---@return NugetProject|nil
function M.get_project_at_cursor()
  local s = state.current
  if not s.right_win or not vim.api.nvim_win_is_valid(s.right_win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(s.right_win)
  local line = cursor[1] - 1 -- 0-indexed
  return s.line_to_project[line]
end

--- Open version selector using vim.ui.select
function M.open_version_selector()
  local s = state.current
  local pkg = s.selected_package
  if not pkg then
    return
  end

  if not s.versions or #s.versions == 0 then
    utils.notify("Loading versions...", vim.log.levels.INFO)
    -- Try fetching versions
    local sources = s.sources or {}
    local credentials = s.source_credentials or {}
    nuget_api.get_versions(pkg.id, { prerelease = s.prerelease, preferred_source = pkg.source }, sources, credentials, function(versions, err)
      if err or not versions or #versions == 0 then
        vim.ui.input({ prompt = "Enter version for " .. pkg.id .. ": " }, function(input)
          if input and input ~= "" then
            s.selected_version = input
            M.render(pkg)
          else
            utils.notify("No versions available", vim.log.levels.WARN)
          end
        end)
        return
      end
      s.versions = versions
      M.open_version_selector() -- retry
    end)
    return
  end

  vim.ui.select(s.versions, {
    prompt = "Select version for " .. pkg.id .. ":",
    format_item = function(version)
      local suffix = ""
      if version == (pkg.installed_version or "") then
        suffix = " (installed)"
      elseif s.versions and version == s.versions[1] then
        suffix = " (latest)"
      end
      return version .. suffix
    end,
  }, function(choice)
    if choice then
      s.selected_version = choice
      M.render(pkg)
    end
  end)
end

--- Add the selected package to the project under cursor
function M.add_to_project()
  local s = state.current
  local pkg = s.selected_package
  if not pkg then
    utils.notify("No package selected", vim.log.levels.WARN)
    return
  end

  local proj = M.get_project_at_cursor()
  if not proj then
    utils.notify("Move cursor to a project line", vim.log.levels.WARN)
    return
  end

  local version = s.selected_version or pkg.latest_version or pkg.version
  s.loading_action = true
  s.action_message = "Adding " .. pkg.id .. "@" .. (version or "latest") .. " to " .. proj.name .. "..."
  M.render(pkg)

  dotnet_api.add_package(proj.full_path, pkg.id, version, function(success, message)
    s.loading_action = false
    s.action_message = message
    M.render(pkg)

    if success then
      vim.defer_fn(function()
        s.action_message = nil
        require("nuget").refresh()
      end, 1500)
    else
      vim.defer_fn(function()
        s.action_message = nil
        M.render(pkg)
      end, 3000)
    end
  end)
end

--- Remove the selected package from the project under cursor
function M.remove_from_project()
  local s = state.current
  local pkg = s.selected_package
  if not pkg then
    utils.notify("No package selected", vim.log.levels.WARN)
    return
  end

  local proj = M.get_project_at_cursor()
  if not proj then
    utils.notify("Move cursor to a project line", vim.log.levels.WARN)
    return
  end

  -- Verify the package is actually installed in this project
  local pkg_data = s.packages[pkg.id:lower()]
  if not pkg_data or not pkg_data.projects or not pkg_data.projects[proj.full_path] then
    utils.notify(pkg.id .. " is not installed in " .. proj.name, vim.log.levels.WARN)
    return
  end

  s.loading_action = true
  s.action_message = "Removing " .. pkg.id .. " from " .. proj.name .. "..."
  M.render(pkg)

  dotnet_api.remove_package(proj.full_path, pkg.id, function(success, message)
    s.loading_action = false
    s.action_message = message
    M.render(pkg)

    if success then
      vim.defer_fn(function()
        s.action_message = nil
        require("nuget").refresh()
      end, 1500)
    else
      vim.defer_fn(function()
        s.action_message = nil
        M.render(pkg)
      end, 3000)
    end
  end)
end

--- Update the project under cursor to the selected version
function M.update_project()
  local s = state.current
  local pkg = s.selected_package
  if not pkg then
    utils.notify("No package selected", vim.log.levels.WARN)
    return
  end

  local proj = M.get_project_at_cursor()
  if not proj then
    utils.notify("Move cursor to a project line", vim.log.levels.WARN)
    return
  end

  local version = s.selected_version or pkg.latest_version or pkg.version
  s.loading_action = true
  s.action_message = "Updating " .. pkg.id .. " to " .. version .. " in " .. proj.name .. "..."
  M.render(pkg)

  dotnet_api.add_package(proj.full_path, pkg.id, version, function(success, message)
    s.loading_action = false
    s.action_message = message
    M.render(pkg)

    if success then
      vim.defer_fn(function()
        s.action_message = nil
        require("nuget").refresh()
      end, 1500)
    else
      vim.defer_fn(function()
        s.action_message = nil
        M.render(pkg)
      end, 3000)
    end
  end)
end

--- Update ALL projects that have this package to the selected version
function M.update_all_projects()
  local s = state.current
  local pkg = s.selected_package
  if not pkg then
    utils.notify("No package selected", vim.log.levels.WARN)
    return
  end

  local pkg_data = s.packages[pkg.id:lower()]
  if not pkg_data or not pkg_data.projects then
    utils.notify("Package not installed in any project", vim.log.levels.WARN)
    return
  end

  local version = s.selected_version or pkg.latest_version or pkg.version
  local project_paths = {}
  for path, _ in pairs(pkg_data.projects) do
    table.insert(project_paths, path)
  end

  if #project_paths == 0 then
    utils.notify("Package not installed in any project", vim.log.levels.WARN)
    return
  end

  s.loading_action = true
  s.action_message = "Updating " .. pkg.id .. " to " .. version .. " in " .. #project_paths .. " projects..."
  M.render(pkg)

  local completed = 0
  local errors = {}

  for _, path in ipairs(project_paths) do
    dotnet_api.add_package(path, pkg.id, version, function(success, message)
      completed = completed + 1
      if not success then
        table.insert(errors, message)
      end

      if completed == #project_paths then
        s.loading_action = false
        if #errors > 0 then
          s.action_message = "Updated with " .. #errors .. " error(s)"
        else
          s.action_message = "Updated " .. pkg.id .. " to " .. version .. " in all projects"
        end
        M.render(pkg)

        vim.defer_fn(function()
          s.action_message = nil
          require("nuget").refresh()
        end, 1500)
      end
    end)
  end
end

--- Wrap text to a given width, breaking on word boundaries
---@param text string
---@param width number
---@return string[]
function M._wrap_text(text, width)
  local result = {}
  local line = ""

  for word in text:gmatch("%S+") do
    if #line + #word + 1 > width then
      if #line > 0 then
        table.insert(result, line)
        line = word
      else
        table.insert(result, word)
      end
    else
      if #line > 0 then
        line = line .. " " .. word
      else
        line = word
      end
    end
  end

  if #line > 0 then
    table.insert(result, line)
  end

  return result
end

return M
