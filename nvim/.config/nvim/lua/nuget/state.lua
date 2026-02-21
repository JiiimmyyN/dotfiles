local M = {}

---@class NugetProjectVersion
---@field resolved string
---@field requested string

---@class NugetPackageInfo
---@field id string Package ID (original casing)
---@field installed_version string|nil Most common installed version across projects
---@field requested_version string|nil Requested version spec
---@field latest_version string|nil Latest available version (from --outdated)
---@field source string Package source
---@field is_outdated boolean Whether a newer version is available
---@field is_installed boolean|nil Whether it's installed (used in browse mode)
---@field description string|nil Package description (from search results)
---@field total_downloads number|nil Download count (from search results)
---@field version string|nil Latest version (used in browse mode)
---@field projects table<string, NugetProjectVersion> Map of project_full_path -> version info

---@class NugetProject
---@field path string Relative path from solution
---@field name string Short display name
---@field full_path string Absolute path to .csproj

---@class NugetMetadata
---@field id string
---@field version string
---@field description string
---@field authors string
---@field license string
---@field project_url string
---@field listed boolean
---@field published string
---@field dependency_groups table[]
---@field deprecation table|nil
---@field vulnerabilities table|nil
---@field tags string[]

---@class NugetState
local state_defaults = {
  -- Solution info
  solution_path = nil, ---@type string|nil
  solution_dir = nil, ---@type string|nil
  projects = {}, ---@type NugetProject[]

  -- Installed packages (aggregated across all projects)
  packages = {}, ---@type table<string, NugetPackageInfo> keyed by lowercase ID
  package_list = {}, ---@type NugetPackageInfo[] sorted list for display
  package_count = 0, ---@type number

  -- NuGet sources + credentials
  sources = {}, ---@type {name: string, url: string}[]
  source_credentials = {}, ---@type table<string, {username: string, password: string}>

  -- UI state
  selected_package = nil, ---@type NugetPackageInfo|nil
  mode = "installed", ---@type "installed"|"browse"
  search_query = "", ---@type string
  prerelease = false, ---@type boolean
  filtered_list = {}, ---@type NugetPackageInfo[]

  -- Browse mode search results
  search_results = {}, ---@type NugetPackageInfo[]

  -- Detail panel state
  metadata = nil, ---@type NugetMetadata|nil
  versions = nil, ---@type string[]|nil
  selected_version = nil, ---@type string|nil

  -- Loading states
  loading_packages = false,
  loading_details = false,
  loading_versions = false,
  loading_search = false,
  loading_action = false,
  action_message = nil, ---@type string|nil

  -- Buffer/window handles
  left_buf = nil, ---@type integer|nil
  right_buf = nil, ---@type integer|nil
  left_win = nil, ---@type integer|nil
  right_win = nil, ---@type integer|nil
  tab = nil, ---@type integer|nil

  -- Line mappings for mouse/cursor interaction
  line_to_package = {}, ---@type table<integer, NugetPackageInfo>
  line_to_project = {}, ---@type table<integer, NugetProject>
  header_lines = 0, ---@type integer
}

---@type NugetState
M.current = vim.deepcopy(state_defaults)

function M.reset()
  M.current = vim.deepcopy(state_defaults)
end

return M
