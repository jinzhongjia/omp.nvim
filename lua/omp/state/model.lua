local store = require('omp.state.store')

---@class OmpModelStateMutations
local M = {}

---@param model string|nil
function M.set_model(model)
  return store.set('current_model', model)
end

function M.clear_model()
  return store.set('current_model', nil)
end

function M.clear()
  return store.batch(function()
    store.set('current_model', nil)
    store.set('current_thinking_level', nil)
  end)
end

---@param info table|nil
function M.set_model_info(info)
  return store.set('current_model_info', info)
end

---@param level string|nil
function M.set_thinking_level(level)
  return store.set('current_thinking_level', level)
end

function M.clear_thinking_level()
  return store.set('current_thinking_level', nil)
end

return M
