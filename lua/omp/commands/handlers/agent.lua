local Promise = require('omp.promise')
local agent_model = require('omp.services.agent_model')

local M = {
  actions = {},
}

function M.actions.configure_provider()
  return agent_model.configure_provider()
end

function M.actions.configure_variant()
  return agent_model.configure_variant()
end

function M.actions.cycle_variant()
  return agent_model.cycle_variant()
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
  configure_variant = {
    desc = 'Configure model variant',
    execute = M.actions.configure_variant,
  },
  variant = {
    desc = 'Switch model variant',
    execute = M.actions.configure_variant,
  },
  cycle_variant = {
    desc = 'Cycle model variant',
    execute = M.actions.cycle_variant,
  },
}

return M
