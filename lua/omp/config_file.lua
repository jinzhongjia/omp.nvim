local Promise = require('omp.promise')
local M = {
  config_promise = nil,
  project_promise = nil,
  providers_promise = nil,
}

---@type fun(): Promise<OmpConfigFile|nil>
M.get_omp_config = Promise.async(function()
  if not M.config_promise then
    local state = require('omp.state')
    M.config_promise = Promise.retry(function()
      return state.api_client:get_config()
    end, 3, 500)
  end
  local ok, result = pcall(function()
    return M.config_promise:await()
  end)

  if not ok then
    M.config_promise = nil
    vim.notify('Error fetching Omp config: ' .. vim.inspect(result), vim.log.levels.ERROR)
    return nil
  end

  return result
end)

---@type fun(): Promise<OmpProject|nil>
M.get_omp_project = Promise.async(function()
  if not M.project_promise then
    local state = require('omp.state')
    M.project_promise = Promise.retry(function()
      return state.api_client:get_current_project()
    end, 3, 500)
  end
  local ok, result = pcall(function()
    return M.project_promise:await()
  end)
  if not ok then
    M.project_promise = nil
    vim.notify('Error fetching Omp project: ' .. vim.inspect(result), vim.log.levels.ERROR)
    return nil
  end

  return result --[[@as OmpProject|nil]]
end)

local _providers_render_callback = false

---@return Promise<OmpProvidersResponse|nil>
function M.get_omp_providers()
  if not M.providers_promise then
    local state = require('omp.state')
    M.providers_promise = state.api_client:list_providers()
  end
  local wrapped = M.providers_promise:catch(function(err)
    vim.notify('Error fetching Omp providers: ' .. vim.inspect(err), vim.log.levels.ERROR)
    M.providers_promise = nil
    return nil
  end)
  if not _providers_render_callback then
    _providers_render_callback = true
    wrapped:finally(function()
      local ok, _ = pcall(function()
        require('omp.ui.topbar').render()
      end)
    end)
  end
  return wrapped
end

--- Get model information for a specific provider and model
--- @param provider string Provider ID
--- @param model string Model ID
--- @return OmpModel|nil Model information with variants
M.get_model_info = function(provider, model)
  local providers_response = M.get_omp_providers():peek()

  local providers = providers_response and providers_response.providers or {}

  local filtered_providers = vim.tbl_filter(function(p)
    return p.id == provider
  end, providers)

  if #filtered_providers == 0 then
    return nil
  end

  return filtered_providers[1] and filtered_providers[1].models and filtered_providers[1].models[model] or nil
end

---@type fun(): Promise<string[]>
M.get_omp_agents = Promise.async(function()
  return { 'default' }
end)

---@type fun(): Promise<string[]>
M.get_subagents = Promise.async(function()
  return {}
end)

---@type fun(): Promise<table<string, table>|nil>
M.get_user_commands = Promise.async(function()
  local cfg = M.get_omp_config():await()
  return cfg and cfg.command or nil
end)

---@type fun(): Promise<table<string, table>|nil>
M.get_mcp_servers = Promise.async(function()
  local cfg = M.get_omp_config():await()
  return cfg and cfg.mcp or nil
end)

---Does this omp user command take arguments?
---@param command OmpCommand
---@return boolean
function M.command_takes_arguments(command)
  return command.template and command.template:find('$ARGUMENTS') ~= nil or false
end

return M
