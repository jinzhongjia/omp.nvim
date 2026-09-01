local state = require('omp.state')
local config_file = require('omp.config_file')
local util = require('omp.util')
local Promise = require('omp.promise')
local log = require('omp.log')
local ui = require('omp.ui.ui')

local M = {}

function M.configure_provider()
  require('omp.model_picker').select(function(selection)
    if not selection then
      if state.ui.is_visible() then
        ui.focus_input()
      end
      return
    end

    local model = string.format('%s/%s', selection.provider, selection.model)
    state.model.set_model(model)
    if state.ui.is_visible() then
      ui.focus_input()
    else
      log.notify('Changed model to ' .. model, vim.log.levels.INFO)
    end
  end)
end

function M.configure_thinking_level()
  require('omp.thinking_level_picker').select(function(selection)
    if not selection then
      if state.ui.is_visible() then
        ui.focus_input()
      end
      return
    end

    state.model.set_thinking_level(selection.value)
    if state.ui.is_visible() then
      ui.focus_input()
    else
      log.notify('Changed thinking level to ' .. selection.name, vim.log.levels.INFO)
    end
  end)
end

M.cycle_thinking_level = Promise.async(function()
  if not state.current_model then
    log.notify('No model selected', vim.log.levels.WARN)
    return
  end

  local provider, model = state.current_model:match('^(.-)/(.+)$')
  local model_info = provider and model and config_file.get_model_info(provider, model) or nil
  if not model_info or not model_info.reasoning then
    log.notify('Current model does not support thinking levels', vim.log.levels.WARN)
    return
  end

  local levels = { 'off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max' }
  local total_count = #levels + 1
  local current_index = state.current_thinking_level == nil and total_count
    or (util.index_of(levels, state.current_thinking_level) or 0)
  local next_index = (current_index % total_count) + 1
  local next_level = next_index > #levels and nil or levels[next_index]

  state.model.set_thinking_level(next_level)
  require('omp.model_state').set_thinking_level(provider, model, next_level)
end)

---@param opts? {restore_from_messages?: boolean}
---@return Promise<string|nil>
M.initialize_current_model = Promise.async(function(opts)
  opts = opts or {}

  if opts.restore_from_messages and state.messages then
    for index = #state.messages, 1, -1 do
      local info = state.messages[index] and state.messages[index].info
      if info and info.providerID and info.modelID then
        local model = info.providerID .. '/' .. info.modelID
        state.model.set_model(model)
        return model
      end
    end
  end

  if state.current_model then
    return state.current_model
  end

  local cfg = config_file.get_omp_config():await()
  if cfg and cfg.model and cfg.model ~= '' then
    state.model.set_model(cfg.model)
  end
  return state.current_model
end)

return M
