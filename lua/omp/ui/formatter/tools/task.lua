local M = {}
local icons = require('omp.ui.icons')

---@param output Output
---@param part OmpMessagePart
---@param _context? FormatterContext
function M.format(output, part, _context)
  if part.tool ~= 'task' then
    return
  end

  local input = part.state and part.state.input or {}
  local tool_output = part.state and part.state.output or ''

  local description = input.description or ''
  local agent_type = input.subagent_type
  if agent_type then
    description = string.format('%s (@%s)', description, agent_type)
  end

  local utils = require('omp.ui.formatter.utils')
  local config = require('omp.config')

  utils.format_action(output, icons.get('task'), 'task', description, utils.get_duration_text(part))

  local output_start_line = output:get_line_count() + 1
  if config.ui.output.tools.show_output or config.ui.output.tools.use_folds then
    if tool_output ~= '' then
      local clean_output = tool_output:gsub('<task_result>', ''):gsub('</task_result>', '')
      if clean_output ~= '' then
        output:add_empty_line()
        output:add_lines(vim.split(clean_output, '\n'))
        output:add_empty_line()
      end
    end

    output:add_fold_with_threshold(
      output_start_line,
      config.ui.output.tools.show_output,
      config.ui.output.tools.use_folds
    )
  end
end

---@param _ OmpMessagePart
---@param input TaskToolInput
---@return string, string, string
function M.summary(_, input)
  return icons.get('task'), 'task', input.description or ''
end

return M
