local M = {}

local setup_done = false
local state

local session_runtime = require('omp.services.session_runtime')

local function on_rpc_manager()
  require('omp.ui.permission_window').clear_all()
end

local function on_current_model_change(_key, new_val, old_val)
  if new_val ~= old_val then
    state.model.clear_thinking_level()

    if new_val then
      local provider, model = new_val:match('^(.-)/(.+)$')
      if provider and model then
        local model_state = require('omp.model_state')
        local saved_variant = model_state.get_thinking_level(provider, model)
        if saved_variant then
          state.model.set_thinking_level(saved_variant)
        end
      end
    end
  end
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
  state.store.subscribe('current_model', on_current_model_change)

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
