local git_review = require('omp.git_review')
local session_runtime = require('omp.services.session_runtime')

local M = {
  actions = {},
}

local diff_subcommands = { 'open', 'next', 'prev', 'close' }

local function with_output_open(callback, open_if_closed)
  local open_fn = open_if_closed and session_runtime.open_if_closed or session_runtime.open
  return function(...)
    local args = { ... }
    open_fn({ new_session = false, focus = 'output' }):and_then(function()
      callback(unpack(args))
    end)
  end
end

---@param message string
local function invalid_arguments(message)
  error({
    code = 'invalid_arguments',
    message = message,
  }, 0)
end

local function extract_hash_arg(value)
  if type(value) == 'table' then
    value = value[1]
  end

  if type(value) == 'string' and value ~= '' then
    return value
  end

  return nil
end

---@param from_snapshot_id? string
---@param _to_snapshot_id? string|number
M.actions.diff_open = with_output_open(function(from_snapshot_id, _to_snapshot_id)
  git_review.review(extract_hash_arg(from_snapshot_id))
end, true)

M.actions.diff_next = with_output_open(function()
  git_review.next_diff()
end, false)

M.actions.diff_prev = with_output_open(function()
  git_review.prev_diff()
end, false)

M.actions.diff_close = with_output_open(function()
  git_review.close_diff()
end, false)

---@type table<string, fun(): any>
local diff_subcommand_actions = {
  open = M.actions.diff_open,
  next = M.actions.diff_next,
  prev = M.actions.diff_prev,
  close = M.actions.diff_close,
}

M.command_defs = {
  diff = {
    desc = 'View file diffs (open/next/prev/close)',
    completions = diff_subcommands,
    nested_subcommand = { allow_empty = true },
    execute = function(args)
      local subcommand = args[1] or 'open'
      local target = args[2]
      local action = diff_subcommand_actions[subcommand]
      if not action then
        invalid_arguments('Invalid diff subcommand. Use: ' .. table.concat(diff_subcommands, ', '))
      end
      return action(target)
    end,
  },
  diff_open = { desc = 'Open diff view', execute = M.actions.diff_open },
  diff_next = { desc = 'Next diff', execute = M.actions.diff_next },
  diff_prev = { desc = 'Previous diff', execute = M.actions.diff_prev },
  diff_close = { desc = 'Close diff view', execute = M.actions.diff_close },
}

return M
