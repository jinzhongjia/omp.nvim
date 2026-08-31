local store = require('omp.state.store')

---@class OmpJobStateMutations
local M = {}

---@param delta integer|nil
function M.increment_count(delta)
  return store.update('job_count', function(current)
    return (current or 0) + (delta or 1)
  end)
end

---@param delta integer|nil
function M.decrement_count(delta)
  return store.update('job_count', function(current)
    return math.max(0, (current or 0) - (delta or 1))
  end)
end

---@param count integer
function M.set_count(count)
  return store.set('job_count', count)
end

---@param manager OmpApiClient|nil
function M.set_rpc_manager(manager)
  return store.set('rpc_manager', manager)
end

---@param client OmpApiClient|nil
function M.set_api_client(client)
  return store.set('api_client', client)
end

---@param manager EventManager|nil
function M.set_event_manager(manager)
  return store.set('event_manager', manager)
end

---@param version Promise<string>|nil
function M.set_omp_cli_version(version)
  return store.set('omp_cli_version', version)
end

function M.is_running()
  return (store.get('job_count') or 0) > 0
end

return M
