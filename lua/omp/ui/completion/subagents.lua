local icons = require('omp.ui.icons')
local Promise = require('omp.promise')

local M = {}

local custom_kind = require('omp.ui.completion.kind')

---@type CompletionSource
local subagent_source = {
  name = 'subagents',
  priority = 1,
  custom_kind = custom_kind.register('subagents', icons.get('agent')),
  complete = Promise.async(function(context)
    local subagents = require('omp.config_file').get_subagents():await()
    local config = require('omp.config')
    local expected_trigger = config.get_key_for_function('input_window', 'mention') or '@'
    if context.trigger_char ~= expected_trigger then
      return {}
    end

    local items = {}
    local input_lower = context.input:lower()

    for _, subagent in ipairs(subagents) do
      local name_lower = subagent:lower()

      if context.input == '' or name_lower:find(input_lower, 1, true) then
        local item = {
          label = subagent .. ' (agent)',
          kind = 'subagent',
          kind_icon = icons.get('agent'),
          detail = 'Subagent',
          documentation = 'Use the "' .. subagent .. '" subagent for this task.',
          insert_text = subagent,
          source_name = 'subagents',
          data = {
            name = subagent,
          },
        }

        table.insert(items, item)
      end
    end

    local sort_util = require('omp.ui.completion.sort')
    sort_util.sort_by_relevance(items, context.input)

    return items
  end),
  on_complete = function(item)
    local state = require('omp.state')
    local context = require('omp.context')
    local mention = require('omp.ui.mention')
    mention.highlight_all_mentions(state.windows.input_buf)
    context.add_subagent(item.data.name)
  end,
  get_trigger_character = function()
    local config = require('omp.config')
    return config.get_key_for_function('input_window', 'mention')
  end,
}

---Get the subagent completion source
---@return CompletionSource
function M.get_source()
  return subagent_source
end

return M
