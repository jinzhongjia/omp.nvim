local utils = require('omp.ui.formatter.utils')
local icons = require('omp.ui.icons')
local M = {}

---@param output Output
---@param part OmpMessagePart
function M.format(output, part)
  local icons = require('omp.ui.icons')
  utils.format_action(output, icons.get('tool'), 'tool', part.tool, utils.get_duration_text(part))
end

---@param _ OmpMessagePart
---@param input table
---@return string, string, string
function M.summary(_, input)
  return icons.get('tool'), 'tool', input.description or ''
end

return M
