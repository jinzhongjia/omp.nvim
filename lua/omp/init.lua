local M = {}

local setup_done = false
local state

local session_runtime = require('omp.services.session_runtime')

local function on_rpc_manager()
  require('omp.ui.permission_window').clear_all()
end

function M.setup(opts)
  if setup_done then
    return
  end
  setup_done = true

  -- Configuration must be initialized before state-backed modules.
  local config = require('omp.config')
  config.setup(opts)

  require('omp.ui.highlight').setup()

  state = require('omp.state')
  state.store.subscribe('rpc_manager', on_rpc_manager)
  state.store.subscribe('user_message_count', session_runtime._on_user_message_count_change)
  state.store.subscribe('pending_permissions', session_runtime._on_current_permission_change)

  vim.schedule(function()
    session_runtime.omp_ok()
  end)
  local OmpApiClient = require('omp.api_client')
  state.jobs.set_api_client(OmpApiClient.create())

  require('omp.commands').setup()
  require('omp.ui.completion').setup()
  require('omp.keymap').setup(config.keymap)
  require('omp.event_manager').setup()
  require('omp.context').setup()
  require('omp.ui.context_bar').setup()
end

return M
