local Promise = require('omp.promise')
local state = require('omp.state')

local M = {}

function M.unregister_port_usage() end

---@return Promise<OmpApiClient>
function M.ensure_started()
  if state.rpc_manager and state.rpc_manager:is_running() then
    return Promise.new():resolve(state.rpc_manager)
  end
  if not state.api_client then
    return Promise.new():reject('OMP API client is not initialized')
  end
  state.jobs.set_rpc_manager(state.api_client)
  return state.api_client:start()
end

return M
