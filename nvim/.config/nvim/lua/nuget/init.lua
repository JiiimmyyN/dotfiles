local config = require("nuget.config")
local state = require("nuget.state")
local utils = require("nuget.utils")

local M = {}

--- Setup the NuGet plugin
---@param opts? NugetConfig
function M.setup(opts)
  config.setup(opts)

  -- Register :Nuget command
  vim.api.nvim_create_user_command("Nuget", function(cmd_opts)
    local sub = cmd_opts.args
    if sub == "close" then
      M.close()
    elseif sub == "refresh" then
      M.refresh()
    else
      M.open()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "open", "close", "refresh" }
    end,
    desc = "NuGet Package Manager",
  })
end

--- Open the NuGet package manager
function M.open()
  local dotnet = require("nuget.api.dotnet")

  -- Prerequisite checks
  if not dotnet.is_available() then
    utils.notify("dotnet CLI not found. Install the .NET SDK first.", vim.log.levels.ERROR)
    return
  end

  -- Find solution
  local sln = utils.find_solution()
  if not sln then
    utils.notify("No .sln file found. Open a file inside a .NET solution first.", vim.log.levels.ERROR)
    return
  end

  -- Initialize state
  local s = state.current
  s.solution_path = sln
  s.solution_dir = vim.fn.fnamemodify(sln, ":h")
  s.prerelease = config.options.prerelease

  -- Open the UI layout
  local layout = require("nuget.ui.layout")
  if not layout.open() then
    utils.notify("Failed to open NuGet manager", vim.log.levels.ERROR)
    return
  end

  -- Set up buffer keymaps
  require("nuget.ui.packages").setup_keymaps()
  require("nuget.ui.details").setup_keymaps()

  -- Show help in the details panel
  require("nuget.ui.details").render_empty()

  -- Load data
  M.load_data()
end

--- Close the NuGet package manager
function M.close()
  require("nuget.ui.layout").close()
end

--- Load solution data: projects list + installed packages + outdated info
---@param on_complete? fun() Called after all data is loaded and rendered
function M.load_data(on_complete)
  local s = state.current
  local dotnet = require("nuget.api.dotnet")
  local packages_ui = require("nuget.ui.packages")

  s.loading_packages = true
  packages_ui.render()

  -- Step 0: Discover sources and credentials
  dotnet.list_sources(s.solution_dir, function(sources, src_err)
    if src_err or not sources or #sources == 0 then
      utils.notify(src_err or "No NuGet sources found; falling back to nuget.org", vim.log.levels.WARN)
      s.sources = {
        { name = "nuget.org", url = "https://api.nuget.org/v3/index.json" },
      }
    else
      s.sources = sources
    end

    local config_paths = utils.find_nuget_configs(s.solution_dir)
    s.source_credentials = utils.parse_nuget_credentials(config_paths)

    -- Step 1: Discover projects in the solution
    dotnet.list_projects(s.solution_path, function(projects, err)
      if err then
        utils.notify(err, vim.log.levels.ERROR)
        s.loading_packages = false
        packages_ui.render()
        return
      end

      s.projects = projects or {}

      -- Step 2: Fetch installed + outdated package data in parallel
      local pending = 2
      local installed_data = nil
      local outdated_data = nil

      local function on_both_done()
        pending = pending - 1
        if pending > 0 then
          return
        end

        M._merge_package_data(installed_data, outdated_data)
        s.loading_packages = false
        packages_ui.filter_packages()
        packages_ui.render()

        if on_complete then
          on_complete()
        end
      end

      -- Installed packages
      dotnet.list_packages(s.solution_path, {
        prerelease = s.prerelease,
      }, function(data, err)
        if err then
          utils.notify(err, vim.log.levels.WARN)
        end
        installed_data = data
        on_both_done()
      end)

      -- Outdated packages (for latest version info)
      dotnet.list_packages(s.solution_path, {
        outdated = true,
        prerelease = s.prerelease,
      }, function(data, err)
        if err then
          utils.notify(err, vim.log.levels.WARN)
        end
        outdated_data = data
        on_both_done()
      end)
    end)
  end)
end

--- Merge installed and outdated package data into state
---@param installed table|nil JSON from `dotnet list package --format json`
---@param outdated table|nil JSON from `dotnet list package --format json --outdated`
function M._merge_package_data(installed, outdated)
  local s = state.current
  s.packages = {}
  s.package_list = {}

  -- Process installed packages
  if installed and installed.projects then
    for _, proj in ipairs(installed.projects) do
      local proj_path = utils.normalize_path(proj.path, s.solution_dir)

      if proj.frameworks then
        for _, fw in ipairs(proj.frameworks) do
          if fw.topLevelPackages then
            for _, pkg in ipairs(fw.topLevelPackages) do
              local id_lower = pkg.id:lower()

              if not s.packages[id_lower] then
                s.packages[id_lower] = {
                  id = pkg.id,
                  installed_version = pkg.resolvedVersion,
                  requested_version = pkg.requestedVersion,
                  latest_version = nil,
                  source = nil,
                  is_outdated = false,
                  projects = {},
                }
              end

              s.packages[id_lower].projects[proj_path] = {
                resolved = pkg.resolvedVersion,
                requested = pkg.requestedVersion,
              }
            end
          end
        end
      end
    end
  end

  -- Merge outdated info (adds latest_version to packages that have updates)
  if outdated and outdated.projects then
    for _, proj in ipairs(outdated.projects) do
      if proj.frameworks then
        for _, fw in ipairs(proj.frameworks) do
          if fw.topLevelPackages then
            for _, pkg in ipairs(fw.topLevelPackages) do
              local id_lower = pkg.id:lower()
              if s.packages[id_lower] and pkg.latestVersion then
                s.packages[id_lower].latest_version = pkg.latestVersion
                s.packages[id_lower].is_outdated = true
              end
            end
          end
        end
      end
    end
  end

  -- Build sorted display list
  for _, pkg in pairs(s.packages) do
    table.insert(s.package_list, pkg)
  end

  table.sort(s.package_list, function(a, b)
    return a.id:lower() < b.id:lower()
  end)

  s.package_count = #s.package_list
end

--- Refresh all package data (re-fetches from dotnet CLI)
function M.refresh()
  local s = state.current
  if not s.solution_path then
    return
  end

  -- Preserve current selection
  local selected_id = s.selected_package and s.selected_package.id or nil

  s.action_message = nil
  M.load_data(function()
    -- Restore selection from the newly-merged package data
    if selected_id then
      local pkg = s.packages[selected_id:lower()]
      if pkg then
        s.selected_package = pkg
        require("nuget.ui.details").load_and_render(pkg)
      else
        -- Package was removed, clear details
        s.selected_package = nil
        require("nuget.ui.details").render_empty()
      end
    end
  end)
end

return M
