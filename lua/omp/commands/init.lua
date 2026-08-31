local command_parse = require('omp.commands.parse')
local command_dispatch = require('omp.commands.dispatch')
local command_complete = require('omp.commands.complete')

local M = {}

-- Aggregate command_defs from all handler modules.
---@type table<string, OmpUICommand>
local command_definitions = (function()
  local handler_modules = {
    'omp.commands.handlers.window',
    'omp.commands.handlers.workflow',
    'omp.commands.handlers.session',
    'omp.commands.handlers.diff',
    'omp.commands.handlers.surface',
    'omp.commands.handlers.agent',
    'omp.commands.handlers.permission',
  }

  local defs = {}
  for _, mod_name in ipairs(handler_modules) do
    local mod = require(mod_name)
    for name, def in pairs(mod.command_defs or {}) do
      if defs[name] then
        error(string.format("Duplicate command definition '%s' in module '%s'", name, mod_name))
      end
      defs[name] = def
    end
  end
  return defs
end)()

---@return table<string, OmpUICommand>
function M.get_commands()
  return command_definitions
end

---@param opts? OmpCommandRouteOpts
---@return any
function M.execute_command_opts(opts)
  local command_opts = opts or { args = '', range = 0 }
  local parsed = command_parse.command(command_opts, command_definitions)
  return M.execute_parsed_intent(parsed)
end

---@param name string
---@param args any[]|nil
---@param range? OmpSelectionRange
---@return OmpCommandParseResult
function M.build_parsed_intent(name, args, range)
  local intent_args = args or {}
  local source_argv = { name }
  for _, value in ipairs(intent_args) do
    table.insert(source_argv, tostring(value))
  end

  return {
    ok = true,
    intent = {
      name = name,
      args = intent_args,
      range = range,
      source = {
        raw_args = table.concat(source_argv, ' '),
        argv = source_argv,
      },
    },
  }
end

---@param parsed OmpCommandParseResult
---@param execute_override? fun(args: string[], range: OmpSelectionRange|nil): any
---@return any
function M.execute_parsed_intent(parsed, execute_override)
  local ctx = M.bind_action_context(parsed, execute_override)
  local dispatched = command_dispatch.execute(ctx)

  if not dispatched.ok then
    vim.notify(dispatched.error.message, vim.log.levels.ERROR)
    return nil
  end

  return dispatched.result
end

---@param parsed OmpCommandParseResult
---@param execute_override? fun(args: string[], range: OmpSelectionRange|nil): any
---@return OmpCommandActionContext
function M.bind_action_context(parsed, execute_override)
  local ctx = { parsed = parsed }

  if not (parsed and parsed.ok and parsed.intent and parsed.intent.name) then
    ctx.execute = execute_override
    return ctx
  end

  local intent = parsed.intent
  local command_def = command_definitions[intent.name]

  ctx.intent = intent
  ctx.args = intent.args
  ctx.range = intent.range
  ctx.execute = execute_override or (command_def and command_def.execute or nil)

  return ctx
end

function M.complete_command(arg_lead, cmd_line, _)
  return command_complete.complete_command(M.get_commands(), arg_lead, cmd_line)
end

function M.setup()
  vim.api.nvim_create_user_command('Omp', M.execute_command_opts, {
    desc = 'Omp.nvim main command with nested subcommands',
    nargs = '*',
    range = true,
    complete = M.complete_command,
  })
end

return M
