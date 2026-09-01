local M = {}
local base_picker = require('omp.ui.base_picker')
local state = require('omp.state')
local config = require('omp.config')
local config_file = require('omp.config_file')
local model_state = require('omp.model_state')

local levels = { 'off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max' }

local function get_current_model_levels()
  if not state.current_model then
    return {}
  end

  local provider, model = state.current_model:match('^(.-)/(.+)$')
  local model_info = provider and model and config_file.get_model_info(provider, model) or nil
  if not model_info or not model_info.reasoning then
    return {}
  end

  local items = { { name = 'default', value = nil } }
  for _, level in ipairs(levels) do
    table.insert(items, { name = level, value = level })
  end
  return items
end

---@param callback fun(selection: table?)
function M.select(callback)
  local items = get_current_model_levels()
  if #items == 0 then
    vim.notify('Current model does not support thinking levels', vim.log.levels.WARN)
    if callback then
      callback(nil)
    end
    return
  end

  if not state.current_thinking_level and state.current_model then
    local provider, model = state.current_model:match('^(.-)/(.+)$')
    local saved = provider and model and model_state.get_thinking_level(provider, model) or nil
    if saved then
      state.model.set_thinking_level(saved)
    end
  end

  base_picker.pick({
    title = 'Select thinking level',
    items = items,
    layout_opts = config.ui.picker,
    format_fn = function(item, width)
      local item_width = width or vim.api.nvim_win_get_width(0)
      local is_current = state.current_thinking_level == item.value
      local indicator = is_current and '*' or '  '
      return base_picker.create_picker_item({
        {
          text = indicator,
          highlight = is_current and 'OmpContextSwitchOn' or 'OmpHint',
        },
        {
          text = base_picker.align(item.name, item_width - vim.api.nvim_strwidth(indicator), { truncate = true }),
          highlight = is_current and 'OmpContextSwitchOn' or nil,
        },
      })
    end,
    actions = {},
    callback = function(selection)
      if selection and state.current_model then
        state.model.set_thinking_level(selection.value)
        local provider, model = state.current_model:match('^(.-)/(.+)$')
        if provider and model then
          model_state.set_thinking_level(provider, model, selection.value)
        end
      end
      if callback then
        callback(selection)
      end
    end,
  })
end

return M
