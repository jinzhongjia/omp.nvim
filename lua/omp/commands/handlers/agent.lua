local Promise = require('omp.promise')
local agent_model = require('omp.services.agent_model')

local M = {
  actions = {},
}

function M.actions.configure_provider()
  return agent_model.configure_provider()
end

function M.actions.configure_thinking_level()
  return agent_model.configure_thinking_level()
end

function M.actions.cycle_thinking_level()
  return agent_model.cycle_thinking_level()
end

M.actions.current_model = Promise.async(function()
  return agent_model.initialize_current_model()
end)

M.command_defs = {
  models = {
    desc = 'Switch provider/model',
    execute = M.actions.configure_provider,
  },
  configure_provider = {
    desc = 'Configure provider',
    execute = M.actions.configure_provider,
  },
  configure_thinking_level = {
    desc = 'Configure thinking level',
    execute = M.actions.configure_thinking_level,
  },
  thinking_level = {
    desc = 'Switch thinking level',
    execute = M.actions.configure_thinking_level,
  },
  cycle_thinking_level = {
    desc = 'Cycle thinking level',
    execute = M.actions.cycle_thinking_level,
  },
}

return M
