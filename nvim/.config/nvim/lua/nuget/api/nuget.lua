local utils = require("nuget.utils")

local M = {}

local endpoint_cache = {}

--- Make an HTTP GET request via curl
---@param url string
---@param auth? {username: string, password: string}
---@param callback fun(data: table|nil, err: string|nil)
local function http_get(url, auth, callback)
  local cmd = { "curl", "-s", "-L", "--compressed" }
  if auth and auth.username and auth.password then
    table.insert(cmd, "-u")
    table.insert(cmd, auth.username .. ":" .. auth.password)
  end
  table.insert(cmd, url)

  vim.system(cmd, {
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "HTTP request failed: " .. (result.stderr or "unknown error"))
        return
      end

      local data, err = utils.json_decode(result.stdout)
      if not data then
        callback(nil, "Failed to parse response: " .. (err or "unknown error"))
        return
      end

      callback(data, nil)
    end)
  end)
end

--- URL encode a string
---@param str string
---@return string
local function url_encode(str)
  return str:gsub("([^%w%-%.~_])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

--- Resolve v3 endpoints for a source URL
---@param source_url string
---@param auth? {username: string, password: string}
---@param callback fun(endpoints: {search: string|nil, autocomplete: string|nil, registration: string|nil}|nil, err: string|nil)
function M.resolve_endpoints(source_url, auth, callback)
  if endpoint_cache[source_url] then
    callback(endpoint_cache[source_url], nil)
    return
  end

  http_get(source_url, auth, function(data, err)
    if err then
      callback(nil, err)
      return
    end

    if not data or not data.resources then
      callback(nil, "No service index resources")
      return
    end

    local endpoints = {
      search = nil,
      autocomplete = nil,
      registration = nil,
    }

    for _, resource in ipairs(data.resources) do
      local rtype = resource["@type"]
      local rid = resource["@id"]
      if rtype and rid then
        if type(rtype) == "table" then
          for _, t in ipairs(rtype) do
            if t:find("SearchQueryService", 1, true) then
              endpoints.search = endpoints.search or rid
            elseif t:find("SearchAutocompleteService", 1, true) then
              endpoints.autocomplete = endpoints.autocomplete or rid
            elseif t:find("RegistrationsBaseUrl", 1, true) then
              endpoints.registration = endpoints.registration or rid
            end
          end
        else
          if rtype:find("SearchQueryService", 1, true) then
            endpoints.search = endpoints.search or rid
          elseif rtype:find("SearchAutocompleteService", 1, true) then
            endpoints.autocomplete = endpoints.autocomplete or rid
          elseif rtype:find("RegistrationsBaseUrl", 1, true) then
            endpoints.registration = endpoints.registration or rid
          end
        end
      end
    end

    if not (endpoints.search or endpoints.autocomplete or endpoints.registration) then
      callback(nil, "No v3 endpoints found")
      return
    end

    endpoint_cache[source_url] = endpoints
    callback(endpoints, nil)
  end)
end

--- Get all versions of a package
---@param package_id string
---@param opts? { prerelease?: boolean, preferred_source?: string }
---@param sources {name: string, url: string}[]
---@param credentials table<string, {username: string, password: string}>
---@param callback fun(versions: string[]|nil, err: string|nil)
function M.get_versions(package_id, opts, sources, credentials, callback)
  opts = opts or {}
  sources = sources or {}
  credentials = credentials or {}

  local ordered_sources = sources
  if opts.preferred_source then
    ordered_sources = {}
    for _, src in ipairs(sources) do
      if src.name == opts.preferred_source then
        table.insert(ordered_sources, src)
      end
    end
    for _, src in ipairs(sources) do
      if src.name ~= opts.preferred_source then
        table.insert(ordered_sources, src)
      end
    end
  end

  if #ordered_sources == 0 then
    callback({}, "No sources configured")
    return
  end

  local done = false
  local pending = #ordered_sources
  local last_err = nil

  local function try_source(source)
    local auth = credentials[source.name:lower()]
    M.resolve_endpoints(source.url, auth, function(endpoints, err)
      if err or not endpoints or not endpoints.autocomplete then
        last_err = err or "Missing autocomplete endpoint"
        pending = pending - 1
        if pending == 0 and not done then
          done = true
          callback({}, last_err)
        end
        return
      end

      local params = {
        "id=" .. url_encode(package_id),
        "prerelease=" .. tostring(opts.prerelease or false),
        "semVerLevel=2.0.0",
      }
      local url = endpoints.autocomplete .. "?" .. table.concat(params, "&")

      http_get(url, auth, function(data, http_err)
        if done then
          return
        end
        if http_err then
          last_err = http_err
          pending = pending - 1
          if pending == 0 and not done then
            done = true
            callback({}, last_err)
          end
          return
        end

        if data and data.data then
          local versions = {}
          for i = #data.data, 1, -1 do
            table.insert(versions, data.data[i])
          end
          done = true
          callback(versions, nil)
        else
          last_err = "No versions found"
          pending = pending - 1
          if pending == 0 and not done then
            done = true
            callback({}, last_err)
          end
        end
      end)
    end)
  end

  for _, source in ipairs(ordered_sources) do
    try_source(source)
  end
end

--- Get package metadata (description, dependencies, etc.)
---@param package_id string
---@param version? string Specific version, or nil for latest
---@param opts? { preferred_source?: string }
---@param sources {name: string, url: string}[]
---@param credentials table<string, {username: string, password: string}>
---@param callback fun(metadata: NugetMetadata|nil, err: string|nil)
function M.get_metadata(package_id, version, opts, sources, credentials, callback)
  opts = opts or {}
  sources = sources or {}
  credentials = credentials or {}

  if #sources == 0 then
    callback(nil, "No sources configured")
    return
  end

  local ordered_sources = sources
  if opts.preferred_source then
    ordered_sources = {}
    for _, src in ipairs(sources) do
      if src.name == opts.preferred_source then
        table.insert(ordered_sources, src)
      end
    end
    for _, src in ipairs(sources) do
      if src.name ~= opts.preferred_source then
        table.insert(ordered_sources, src)
      end
    end
  end

  if #ordered_sources == 0 then
    callback(nil, "No sources configured")
    return
  end

  local lower_id = package_id:lower()
  local done = false
  local pending = #ordered_sources
  local last_err = nil

  local function try_source(source)
    local auth = credentials[source.name:lower()]
    M.resolve_endpoints(source.url, auth, function(endpoints, err)
      if err or not endpoints or not endpoints.registration then
        last_err = err or "Missing registration endpoint"
        pending = pending - 1
        if pending == 0 and not done then
          done = true
          callback(nil, last_err)
        end
        return
      end

      local url
      if version then
        url = endpoints.registration .. "/" .. lower_id .. "/" .. version:lower() .. ".json"
      else
        url = endpoints.registration .. "/" .. lower_id .. "/index.json"
      end

      http_get(url, auth, function(data, http_err)
        if done then
          return
        end
        if http_err then
          last_err = http_err
          pending = pending - 1
          if pending == 0 and not done then
            done = true
            callback(nil, last_err)
          end
          return
        end

        if not data then
          last_err = "No data returned"
          pending = pending - 1
          if pending == 0 and not done then
            done = true
            callback(nil, last_err)
          end
          return
        end

        if not version and data.items then
          local last_page = data.items[#data.items]

          if last_page.items then
            local last_entry = last_page.items[#last_page.items]
            if last_entry and last_entry.catalogEntry then
              done = true
              callback(M._parse_catalog_entry(last_entry.catalogEntry), nil)
              return
            end
          else
            http_get(last_page["@id"], auth, function(page_data, page_err)
              if done then
                return
              end
              if page_err or not page_data or not page_data.items then
                last_err = page_err or "Failed to fetch metadata page"
                pending = pending - 1
                if pending == 0 and not done then
                  done = true
                  callback(nil, last_err)
                end
                return
              end
              local last_entry = page_data.items[#page_data.items]
              if last_entry and last_entry.catalogEntry then
                done = true
                callback(M._parse_catalog_entry(last_entry.catalogEntry), nil)
              else
                last_err = "No catalog entry found"
                pending = pending - 1
                if pending == 0 and not done then
                  done = true
                  callback(nil, last_err)
                end
              end
            end)
            return
          end
        elseif data.catalogEntry then
          done = true
          callback(M._parse_catalog_entry(data.catalogEntry), nil)
          return
        end

        last_err = "Unexpected metadata format"
        pending = pending - 1
        if pending == 0 and not done then
          done = true
          callback(nil, last_err)
        end
      end)
    end)
  end

  for _, source in ipairs(ordered_sources) do
    try_source(source)
  end
end

--- Parse a NuGet catalog entry into a clean metadata table
---@param entry table Raw catalog entry from NuGet API
---@return NugetMetadata
function M._parse_catalog_entry(entry)
  local deps = {}
  if entry.dependencyGroups then
    for _, group in ipairs(entry.dependencyGroups) do
      local framework = group.targetFramework or "Any"
      local group_deps = {}
      if group.dependencies then
        for _, dep in ipairs(group.dependencies) do
          table.insert(group_deps, {
            id = dep.id,
            range = dep.range or "",
          })
        end
      end
      table.insert(deps, {
        framework = framework,
        dependencies = group_deps,
      })
    end
  end

  return {
    id = entry.id or "",
    version = entry.version or "",
    description = entry.description or "",
    authors = entry.authors or "",
    license = entry.licenseExpression or entry.licenseUrl or "",
    project_url = entry.projectUrl or "",
    listed = entry.listed ~= false,
    published = entry.published or "",
    dependency_groups = deps,
    deprecation = entry.deprecation,
    vulnerabilities = entry.vulnerabilities,
    tags = entry.tags or {},
  }
end

return M
