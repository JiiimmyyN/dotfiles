local M = {}

local ok, builtin = pcall(require, "telescope.builtin")
if not ok then
  error("supersearch.nvim requires telescope.nvim (telescope.builtin not found)")
end

local function find_upward(names, startpath)
  return vim.fs.find(names, { upward = true, path = startpath })[1]
end

local function dirname(p)
  return p and vim.fs.dirname(p) or nil
end

local function normalize(p)
  return p and vim.fs.normalize(p) or nil
end

local function is_git_repo(startpath)
  return find_upward(".git", startpath) ~= nil
end

local function is_subpath(child, parent)
  child = normalize(child)
  parent = normalize(parent)
  if not child or not parent then
    return false
  end
  if child == parent then
    return false
  end
  return child:sub(1, #parent + 1) == parent .. "/"
end

-- Parse .sln and return absolute paths to referenced *.csproj
local function parse_sln_csprojs(sln_path)
  local sln_dir = dirname(sln_path)
  local lines = vim.fn.readfile(sln_path)

  local csprojs = {}
  for _, line in ipairs(lines) do
    -- Project("{GUID}") = "Name", "Relative\Path\Proj.csproj", "{GUID}"
    local rel = line:match('Project%("%b{}"%)%s*=%s*".-",%s*"(.-%.csproj)"%s*,%s*"%b{}"')
    if rel then
      rel = rel:gsub("\\", "/")
      local abs = normalize(sln_dir .. "/" .. rel)
      table.insert(csprojs, abs)
    end
  end

  return csprojs, sln_dir
end

local function csharp_roots(startpath)
  -- 1) Search upwards until you find a .sln
  local sln = find_upward(function(name)
    return name:match("%.sln$")
  end, startpath)

  if sln then
    local csprojs, sln_dir = parse_sln_csprojs(sln)

    -- Use all csproj dirs as separate roots IF they are not in a subfolder from the .sln
    local roots = {}
    for _, csproj in ipairs(csprojs) do
      local csproj_dir = dirname(csproj)
      if csproj_dir and not is_subpath(csproj_dir, sln_dir) then
        table.insert(roots, csproj_dir)
      end
    end

    if #roots > 0 then
      return roots
    end

    -- fallback: sln dir itself
    return { sln_dir }
  end

  -- 3) Search upwards until you find the first csproj
  local csproj = find_upward(function(name)
    return name:match("%.csproj$")
  end, startpath)

  if csproj then
    return { dirname(csproj) }
  end

  return nil
end

local function node_roots(startpath)
  -- Search upwards until you find a package.json file and use that as the root
  local pkg = find_upward("package.json", startpath)
  if pkg then
    return { dirname(pkg) }
  end
  return nil
end

local function buf_start_dir()
  local d = vim.fn.expand("%:p:h")
  if not d or d == "" then
    d = vim.fn.getcwd()
  end
  return d
end

local function uniq(list)
  local out, seen = {}, {}
  for _, v in ipairs(list or {}) do
    v = normalize(v)
    if v and not seen[v] then
      seen[v] = true
      table.insert(out, v)
    end
  end
  return out
end

---Open supersearch picker.
---Behavior:
---- If in git repo: telescope.git_files(show_untracked=true)
---- C#:
---  - prefer .sln upward -> roots from its csprojs (with your "not subfolder of sln" rule)
---  - else first csproj upward -> root = its dir
---- JS/TS:
---  - prefer package.json upward -> root = its dir
---- Fallback: telescope.find_files(hidden=true)
function M.open(opts)
  opts = opts or {}

  local startpath = opts.startpath or buf_start_dir()

  -- 2) Use default git_files, if we are in a git repo
  if is_git_repo(startpath) then
    return builtin.git_files({ show_untracked = true })
  end

  local ft = vim.bo.filetype
  local roots

  -- Category by filetype, otherwise probe by markers
  local is_csharp = ft == "cs" or ft == "csproj" or ft == "razor"
  local is_node = ft == "typescript"
    or ft == "typescriptreact"
    or ft == "javascript"
    or ft == "javascriptreact"
    or ft == "json"

  if is_csharp then
    roots = csharp_roots(startpath)
  elseif is_node then
    roots = node_roots(startpath)
  else
    roots = csharp_roots(startpath) or node_roots(startpath)
  end

  roots = uniq(roots)

  local ignore_patterns = {}

  if is_csharp then
    ignore_patterns = {
      "bin/", -- paths are typically relative to cwd in telescope
      "obj/",
      "%.vs/",
      "%.vscode/",
    }
  elseif is_node then
    ignore_patterns = {
      "^node_modules/",
      "^%.vscode/",
      "^dist/",
      "^build/",
      "^%.next/",
    }
  else
    ignore_patterns = {
      "bin/", -- paths are typically relative to cwd in telescope
      "obj/",
      "%.vs/",
      "%.vscode/",
      "^node_modules/",
      "^%.vscode/",
      "^dist/",
      "^build/",
      "^%.next/",
    }
  end

  if not roots or #roots == 0 then
    return builtin.find_files({ hidden = true, file_ignore_patterns = ignore_patterns })
  end

  if #roots == 1 then
    return builtin.find_files({ hidden = true, cwd = roots[1], file_ignore_patterns = ignore_patterns })
  end

  -- Multi-root: telescope supports this via `search_dirs`
  return builtin.find_files({ hidden = true, search_dirs = roots, file_ignore_patterns = ignore_patterns })
end

return M
