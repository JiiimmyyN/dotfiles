local M = {}

--- Find files by searching upward from a starting directory
---@param pattern string Glob pattern (e.g. "*.sln")
---@param start_dir? string Starting directory (defaults to cwd)
---@return string|nil path Full path to the found file
function M.find_upward(pattern, start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  local dir = start_dir

  while dir do
    local matches = vim.fn.glob(dir .. "/" .. pattern, false, true)
    if #matches > 0 then
      return matches[1]
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  return nil
end

--- Find .sln file from current buffer or cwd
---@return string|nil
function M.find_solution()
  local buf_dir = vim.fn.expand("%:p:h")
  if buf_dir == "" or buf_dir == "." then
    buf_dir = vim.fn.getcwd()
  end
  return M.find_upward("*.sln", buf_dir)
end

--- Find relevant nuget.config files
---@param solution_dir string
---@return string[]
function M.find_nuget_configs(solution_dir)
  local configs = {
    solution_dir .. "/nuget.config",
    solution_dir .. "/NuGet.Config",
    vim.fn.expand("~/.nuget/NuGet/NuGet.Config"),
    vim.fn.expand("~/.nuget/NuGet/nuget.config"),
  }

  local results = {}
  for _, path in ipairs(configs) do
    if vim.fn.filereadable(path) == 1 then
      table.insert(results, path)
    end
  end

  return results
end

--- Get the short name of a project from its path
---@param project_path string
---@return string
function M.project_name(project_path)
  return vim.fn.fnamemodify(project_path, ":t:r")
end

--- Truncate a string to a max length with ellipsis
---@param str string
---@param max_len number
---@return string
function M.truncate(str, max_len)
  if not str then
    return ""
  end
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

--- Create a separator line of given width
---@param width number
---@return string
function M.separator(width)
  return string.rep("─", width)
end

--- Safely decode JSON
---@param str string
---@return table|nil data
---@return string|nil error
function M.json_decode(str)
  if not str or str == "" then
    return nil, "empty input"
  end
  local ok, result = pcall(vim.json.decode, str)
  if ok then
    return result, nil
  else
    return nil, tostring(result)
  end
end

--- Notify the user with [NuGet] prefix
---@param msg string
---@param level? integer vim.log.levels.*
function M.notify(msg, level)
  vim.notify("[NuGet] " .. msg, level or vim.log.levels.INFO)
end

--- Decode XML name encoding like _x002E_ into characters
---@param name string
---@return string
function M.decode_xml_name(name)
  return name:gsub("_x(%x%x%x%x)_", function(hex)
    local code = tonumber(hex, 16)
    if not code then
      return ""
    end
    return vim.fn.nr2char(code)
  end)
end

--- Parse package source credentials from nuget.config files
---@param config_paths string[]
---@return table<string, {username: string, password: string}>
function M.parse_nuget_credentials(config_paths)
  local credentials = {}

  for _, path in ipairs(config_paths or {}) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or not lines then
      goto continue
    end

    local content = table.concat(lines, "\n")
    local creds_block = content:match("<packageSourceCredentials>([%s%S]-)</packageSourceCredentials>")
    if not creds_block then
      goto continue
    end

    for source_name, source_block in creds_block:gmatch("<([%w%._x%-]+)>([%s%S]-)</%1>") do
      local username = nil
      local clear_password = nil
      local encrypted_password = nil

      for add_tag in source_block:gmatch("<add%s+.-/>" ) do
        local key = add_tag:match('key="([^"]+)"')
        local value = add_tag:match('value="([^"]*)"')
        if key and value then
          if key == "Username" then
            username = value
          elseif key == "CleartextPassword" then
            clear_password = value
          elseif key == "Password" then
            encrypted_password = value
          end
        end
      end

      local decoded_name = M.decode_xml_name(source_name):lower()
      if username and clear_password then
        credentials[decoded_name] = {
          username = username,
          password = clear_password,
        }
      elseif username and encrypted_password then
        M.notify("Credentials for source '" .. decoded_name .. "' are encrypted; metadata/version lookup may be limited.", vim.log.levels.WARN)
      end
    end

    ::continue::
  end

  return credentials
end

--- Normalize a file path to absolute
---@param path string
---@param base_dir? string Base directory for relative paths
---@return string
function M.normalize_path(path, base_dir)
  path = path:gsub("\\", "/")
  if not vim.startswith(path, "/") and base_dir then
    path = base_dir .. "/" .. path
  end
  return vim.fn.fnamemodify(path, ":p")
end

--- Format a large number with commas (e.g., 1234567 -> "1,234,567")
---@param n number
---@return string
function M.format_number(n)
  if not n then
    return "0"
  end
  local formatted = tostring(math.floor(n))
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

return M
