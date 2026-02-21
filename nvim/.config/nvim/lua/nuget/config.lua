local M = {}

---@class NugetIcons
---@field installed string
---@field not_installed string
---@field outdated string
---@field loading string
---@field separator string
---@field add string
---@field remove string
---@field update string

---@class NugetConfig
---@field prerelease boolean Default prerelease toggle state
---@field split_ratio number Left panel width ratio (0-1)
---@field icons NugetIcons

M.defaults = {
  prerelease = false,
  split_ratio = 0.4,
  icons = {
    installed = "●",
    not_installed = "○",
    outdated = "↑",
    loading = "⟳",
    separator = "•",
    add = "+",
    remove = "✕",
    update = "↑",
  },
}

---@type NugetConfig
M.options = {}

---@param opts? NugetConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
