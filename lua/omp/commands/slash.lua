local Promise = require('omp.promise')
local config_file = require('omp.config_file')
local commands = require('omp.commands')
local log = require('omp.log')

local M = {}

---@class OmpSlashPreset
---@field name string
---@field preset_args? string[]

---@type table<string, OmpSlashPreset>
local slash_command_presets = {
  ['/help'] = { name = 'help' },
  ['/command-list'] = { name = 'commands_list' },
  ['/compact'] = { name = 'session', preset_args = { 'compact' } },
  ['/history'] = { name = 'history' },
  ['/models'] = { name = 'models' },
  ['/variant'] = { name = 'variant' },
  ['/new'] = { name = 'session', preset_args = { 'new' } },
  ['/sessions'] = { name = 'session', preset_args = { 'select' } },
  ['/skills'] = { name = 'skills' },
  ['/clear_selections'] = { name = 'clear_selections' },
  ['/clear_files'] = { name = 'clear_files' },
  ['/rename'] = { name = 'session', preset_args = { 'rename' } },
  ['/thinking'] = { name = 'toggle_reasoning_output' },
  ['/reasoning'] = { name = 'toggle_reasoning_output' },
  ['/review'] = { name = 'review' },
}

---@param preset OmpSlashPreset
---@return string
local function preset_to_command_string(preset)
  local parts = { preset.name }
  for _, arg in ipairs(preset.preset_args or {}) do
    table.insert(parts, arg)
  end
  return table.concat(parts, ' ')
end

---@return table<string, OmpSlashCommandSpec>
local function build_builtin_slash_command_definitions()
  local command_defs = commands.get_commands()
  local slash_defs = {}

  for slash_cmd, preset in pairs(slash_command_presets) do
    local cmd_str = preset_to_command_string(preset)
    local command_def = command_defs[preset.name]
    local desc = 'Run :Omp ' .. cmd_str
    if command_def and command_def.desc then
      desc = command_def.desc
    end

    slash_defs[slash_cmd] = {
      command_name = preset.name,
      preset_args = vim.deepcopy(preset.preset_args or {}),
      -- Keep cmd_str for help/introspection and parseability checks, but execute via structured fields.
      cmd_str = cmd_str,
      desc = desc,
      args = command_def and command_def.nargs ~= nil or false,
    }
  end

  return slash_defs
end

local builtin_slash_command_definitions = build_builtin_slash_command_definitions()

---@return table<string, OmpSlashCommandSpec>
function M.get_builtin_command_definitions()
  return builtin_slash_command_definitions
end

---@param command_name string
---@param args string[]|nil
---@return any
local function dispatch_parsed(command_name, args)
  local parsed = commands.build_parsed_intent(command_name, args or {})
  return commands.execute_parsed_intent(parsed)
end

---@param slash_cmd string
---@param def OmpSlashCommandSpec
---@return OmpSlashCommand|nil
local function to_runtime_slash_command(slash_cmd, def)
  local fn = def.fn
  if not fn and type(def.command_name) == 'string' then
    local command_name = def.command_name
    local preset_args = vim.deepcopy(def.preset_args or {})
    fn = function(args)
      local merged_args = vim.list_extend(vim.deepcopy(preset_args), args or {})
      return dispatch_parsed(command_name, merged_args)
    end
  end

  if type(fn) ~= 'function' then
    log.notify(string.format("Slash command '%s' has no executable handler", slash_cmd), vim.log.levels.WARN)
    return nil
  end

  return {
    slash_cmd = slash_cmd,
    desc = def.desc,
    fn = fn,
    args = def.args or false,
  }
end

M.get_commands = Promise.async(function()
  ---@type OmpSlashCommand[]
  local result = {}

  for slash_cmd, def in pairs(M.get_builtin_command_definitions()) do
    local runtime_def = to_runtime_slash_command(slash_cmd, def)
    if runtime_def then
      table.insert(result, runtime_def)
    end
  end

  local user_commands = config_file.get_user_commands():await()
  if user_commands then
    for name, def in pairs(user_commands) do
      table.insert(result, {
        slash_cmd = '/' .. name,
        desc = def.description or 'User command',
        fn = function(args)
          local cmd_args = vim.list_extend({ name }, args or {})
          return dispatch_parsed('command', cmd_args)
        end,
        args = true,
      })
    end
  end

  local state = require('omp.state')
  local ok, skills = pcall(function()
    return state.api_client:list_skills():await()
  end)
  if ok and skills then
    for _, skill in ipairs(skills) do
      local skill_content = skill.content
      table.insert(result, {
        slash_cmd = '/' .. skill.name,
        desc = skill.description or 'Skill',
        fn = function(args)
          local message = skill_content
          if args and #args > 0 then
            message = skill_content .. '\n\n' .. table.concat(args, ' ')
          end
          require('omp.services.session_runtime').open({ new_session = false, focus = 'output' }):and_then(function()
            return require('omp.services.messaging').send_message(message, {})
          end)
        end,
        args = true,
      })
    end
  end

  return result
end)

return M
