local utils = require("nuget.utils")

local M = {}

--- Check if dotnet CLI is available
---@return boolean
function M.is_available()
  return vim.fn.executable("dotnet") == 1
end

--- Run a dotnet command asynchronously
---@param args string[] Command arguments
---@param cwd string Working directory
---@param callback fun(success: boolean, stdout: string, stderr: string)
function M.run(args, cwd, callback)
  local cmd = vim.list_extend({ "dotnet" }, args)

  vim.system(cmd, {
    cwd = cwd,
    text = true,
  }, function(result)
    vim.schedule(function()
      callback(result.code == 0, result.stdout or "", result.stderr or "")
    end)
  end)
end

--- List projects in a solution
---@param solution_path string Path to .sln file
---@param callback fun(projects: NugetProject[]|nil, err: string|nil)
function M.list_projects(solution_path, callback)
  local sln_dir = vim.fn.fnamemodify(solution_path, ":h")

  M.run({ "sln", solution_path, "list" }, sln_dir, function(success, stdout, stderr)
    if not success then
      callback(nil, "Failed to list projects: " .. stderr)
      return
    end

    local projects = {}
    local in_projects = false

    for line in stdout:gmatch("[^\r\n]+") do
      if line:match("^%-%-") then
        in_projects = true
      elseif in_projects and line:match("%.%w+proj$") then
        local rel_path = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        local full_path = utils.normalize_path(rel_path, sln_dir)
        table.insert(projects, {
          path = rel_path,
          name = utils.project_name(rel_path),
          full_path = full_path,
        })
      end
    end

    table.sort(projects, function(a, b)
      return a.name:lower() < b.name:lower()
    end)

    callback(projects, nil)
  end)
end

--- List installed packages with optional outdated info
---@param target string Path to .sln or .csproj
---@param opts? { outdated?: boolean, prerelease?: boolean }
---@param callback fun(data: table|nil, err: string|nil)
function M.list_packages(target, opts, callback)
  opts = opts or {}
  local dir = vim.fn.fnamemodify(target, ":h")

  local args = { "list", target, "package", "--format", "json" }
  if opts.outdated then
    table.insert(args, "--outdated")
  end
  if opts.prerelease then
    table.insert(args, "--include-prerelease")
  end

  M.run(args, dir, function(success, stdout, stderr)
    if not success then
      callback(nil, "Failed to list packages: " .. stderr)
      return
    end

    local data, err = utils.json_decode(stdout)
    if not data then
      callback(nil, "Failed to parse package list: " .. (err or "unknown error"))
      return
    end

    callback(data, nil)
  end)
end

--- List NuGet sources
---@param cwd string Working directory (solution dir)
---@param callback fun(sources: {name: string, url: string}[]|nil, err: string|nil)
function M.list_sources(cwd, callback)
  M.run({ "nuget", "list", "source" }, cwd, function(success, stdout, stderr)
    if not success then
      callback(nil, "Failed to list sources: " .. stderr)
      return
    end

    local sources = {}
    local current_name = nil
    local current_enabled = false
    local current_url = nil

    for line in stdout:gmatch("[^\r\n]+") do
      local name, status = line:match("^%s*%d+%.%s*(.+)%s*%[(%w+)%]%s*$")
      if name then
        current_name = name
        current_enabled = status == "Enabled"
        current_url = nil
      else
        local url = line:match("^%s*(https?://%S+)%s*$")
        if url and current_name then
          current_url = url
        end

        if current_name and current_enabled and current_url then
          table.insert(sources, { name = current_name, url = current_url })
          current_name = nil
          current_enabled = false
          current_url = nil
        end
      end
    end

    if current_name and current_enabled and current_url then
      table.insert(sources, { name = current_name, url = current_url })
    end

    callback(sources, nil)
  end)
end

--- Search for packages via dotnet CLI
---@param query string Search term
---@param opts? { prerelease?: boolean, take?: number }
---@param cwd string Working directory
---@param callback fun(data: table|nil, err: string|nil)
function M.search_packages(query, opts, cwd, callback)
  opts = opts or {}
  local args = { "package", "search", query, "--format", "json" }

  if opts.prerelease then
    table.insert(args, "--prerelease")
  end
  if opts.take then
    table.insert(args, "--take")
    table.insert(args, tostring(opts.take))
  end

  M.run(args, cwd, function(success, stdout, stderr)
    if not success then
      callback(nil, "Failed to search packages: " .. stderr)
      return
    end

    local data, err = utils.json_decode(stdout)
    if not data then
      callback(nil, "Failed to parse search results: " .. (err or "unknown error"))
      return
    end

    callback(data, nil)
  end)
end

--- Add a package to a project
---@param project_path string Path to .csproj file
---@param package_name string Package ID
---@param version? string Version (nil for latest)
---@param callback fun(success: boolean, message: string)
function M.add_package(project_path, package_name, version, callback)
  local dir = vim.fn.fnamemodify(project_path, ":h")
  local args = { "add", project_path, "package", package_name }

  if version then
    table.insert(args, "-v")
    table.insert(args, version)
  end

  M.run(args, dir, function(success, _, stderr)
    if success then
      callback(true, "Added " .. package_name .. " to " .. utils.project_name(project_path))
    else
      callback(false, "Failed to add package: " .. stderr)
    end
  end)
end

--- Remove a package from a project
---@param project_path string Path to .csproj file
---@param package_name string Package ID
---@param callback fun(success: boolean, message: string)
function M.remove_package(project_path, package_name, callback)
  local dir = vim.fn.fnamemodify(project_path, ":h")
  local args = { "remove", project_path, "package", package_name }

  M.run(args, dir, function(success, _, stderr)
    if success then
      callback(true, "Removed " .. package_name .. " from " .. utils.project_name(project_path))
    else
      callback(false, "Failed to remove package: " .. stderr)
    end
  end)
end

--- Restore packages
---@param target string Path to .sln or .csproj
---@param callback fun(success: boolean, message: string)
function M.restore(target, callback)
  local dir = vim.fn.fnamemodify(target, ":h")

  M.run({ "restore", target }, dir, function(success, _, stderr)
    if success then
      callback(true, "Restore completed")
    else
      callback(false, "Restore failed: " .. stderr)
    end
  end)
end

return M
