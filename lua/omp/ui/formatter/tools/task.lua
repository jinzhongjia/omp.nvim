local M = {}
local icons = require('omp.ui.icons')

---@param part OmpMessagePart
---@param status string
---@param utils table
---@return string
function M.tool_action_line(part, status, utils)
  local tool_formatters = require('omp.ui.formatter.tools')
  local tool = part.tool
  local input = part.state and part.state.input or {}
  local metadata = part.state and part.state.metadata or {}
  local formatter = tool_formatters[tool] or tool_formatters.tool
  local summary = formatter.summary or tool_formatters.tool.summary
  local icon, tool_label, tool_value = summary(part, input, metadata)

  if status ~= 'completed' then
    icon = icons.get(status)
  end

  return utils.build_action_line(icon, tool_label or tool or 'tool', tool_value)
end

---@param output Output
---@param part OmpMessagePart
---@param context? FormatterContext
function M.format(output, part, _context)
  if part.tool ~= 'task' then
    return
  end

  local input = part.state and part.state.input or {}
  local metadata = part.state and part.state.metadata or {}
  local tool_output = part.state and part.state.output or ''

  local start_line = output:get_line_count() + 1

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
