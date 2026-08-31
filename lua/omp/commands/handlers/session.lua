---@type OmpState
local state = require('omp.state')
local session_store = require('omp.session')
local Promise = require('omp.promise')
local window_actions = require('omp.commands.handlers.window').actions
local session_runtime = require('omp.services.session_runtime')

local M = {
  actions = {},
}

local session_subcommands = { 'new', 'select', 'compact', 'rename', 'toggle_lock' }

---@param message string
local function invalid_arguments(message)
  error({
    code = 'invalid_arguments',
    message = message,
  }, 0)
end

---@param warning string
---@param callback fun(state_obj: OmpState): any
---@return any
local function with_active_session(warning, callback)
  local state_obj = state
  if not state_obj.active_session then
    vim.notify(warning, vim.log.levels.WARN)
    return
  end
  return callback(state_obj)
end

---@param promise Promise<any>
---@param success_cb fun(response: any)|nil
---@param error_prefix string
local function notify_promise(promise, success_cb, error_prefix)
  promise
    :and_then(function(response)
      if not success_cb then
        return
      end

      vim.schedule(function()
        success_cb(response)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        vim.notify(error_prefix .. vim.inspect(err), vim.log.levels.ERROR)
      end)
    end)
end

function M.actions.open_input_new_session()
  return session_runtime.open({ new_session = true, focus = 'input', start_insert = true })
end

---@param title string
function M.actions.open_input_new_session_with_title(title)
  return Promise.async(function(session_title)
    local new_session = session_runtime.create_new_session(session_title):await()
    if not new_session then
      vim.notify('Failed to create new session', vim.log.levels.ERROR)
      return
    end

    state.session.set_active(new_session)
    return window_actions.open_input()
  end)(title)
end

---@param parent_id? string
---@param scope? 'project' | 'global' defaults to global when session is locked, project otherwise
function M.actions.select_session(parent_id, scope)
  if scope == nil then
    scope = session_runtime.is_session_locked() and 'global' or 'project'
  end
  session_runtime.select_session(parent_id, scope)
end

---@param value? boolean if nil toggle, otherwise set to value
function M.actions.toggle_session_lock(value)
  local new_value
  if value == nil then
    new_value = session_runtime.toggle_session_lock()
  else
    new_value = session_runtime.set_session_lock(value and true or false)
  end
  vim.notify(
    'Session lock ' .. (new_value and 'enabled (session preserved across cwd changes)' or 'disabled'),
    vim.log.levels.INFO
  )
  return new_value
end

---@param current_session? Session
function M.actions.compact_session(current_session)
  local state_obj = state
  current_session = current_session or state_obj.active_session
  if not current_session then
    vim.notify('No active session to compact', vim.log.levels.WARN)
    return
  end

  local current_model = state_obj.current_model
  if not current_model then
    vim.notify('No model selected', vim.log.levels.ERROR)
    return
  end

  local providerId, modelId = current_model:match('^(.-)/(.+)$')
  if not providerId or not modelId then
    vim.notify('Invalid model format: ' .. tostring(current_model), vim.log.levels.ERROR)
    return
  end

  notify_promise(
    state_obj.api_client:summarize_session(current_session.id, {
      providerID = providerId,
      modelID = modelId,
    }),
    function()
      vim.notify('Session compacted successfully', vim.log.levels.INFO)
    end,
    'Failed to compact session: '
  )
end

---@param current_session? Session
---@param new_title? string
function M.actions.rename_session(current_session, new_title)
  return Promise.async(function(session_obj, requested_title)
    local promise = Promise.new()
    local state_obj = state
    session_obj = session_obj or (state_obj.active_session and vim.deepcopy(state_obj.active_session) or nil) --[[@as Session]]
    if not session_obj then
      vim.notify('No active session to rename', vim.log.levels.WARN)
      promise:resolve(nil)
      return promise
    end

    local function rename_session_with_title(title)
      state_obj.api_client
        :update_session(session_obj.id, { title = title })
        :catch(function(err)
          vim.schedule(function()
            vim.notify('Failed to rename session: ' .. vim.inspect(err), vim.log.levels.ERROR)
          end)
        end)
        :and_then(Promise.async(function()
          session_obj.title = title
          if state_obj.active_session and state_obj.active_session.id == session_obj.id then
            local persisted_session = session_store.get_by_id(session_obj.id):await()
            if persisted_session then
              persisted_session.title = title
              state_obj.session.set_active(vim.deepcopy(persisted_session))
            end
          end
          promise:resolve(session_obj)
        end))
    end

    if requested_title and requested_title ~= '' then
      rename_session_with_title(requested_title)
      return promise
    end

    vim.schedule(function()
      vim.ui.input({ prompt = 'New session name: ', default = session_obj.title or '' }, function(input)
        if input and input ~= '' then
          rename_session_with_title(input)
        else
          promise:resolve(nil)
        end
      end)
    end)

    return promise
  end)(current_session, new_title)
end

---@param state_obj OmpState
---@param target_id string
---@return OmpMessage|nil
local function find_message_in_state(state_obj, target_id)
  for _, m in ipairs(state_obj.messages or {}) do
    if m.info and m.info.id == target_id then
      return m
    end
  end
  return nil
end

---@param message_id string
function M.actions.copy_message(message_id)
  return with_active_session('No active session to copy', function(state_obj)
    local target = find_message_in_state(state_obj, message_id)
    if not target or not target.info or target.info.role ~= 'user' then
      vim.notify('No user message to copy', vim.log.levels.WARN)
      return
    end

    local text_parts = {}
    for _, part in ipairs(target.parts or {}) do
      if
        part.type == 'text'
        and part.synthetic ~= true
        and type(part.text) == 'string'
        and vim.trim(part.text) ~= ''
      then
        text_parts[#text_parts + 1] = part.text
      end
    end

    if #text_parts == 0 then
      vim.notify('No message text to copy', vim.log.levels.WARN)
      return
    end

    vim.fn.setreg('+', table.concat(text_parts, '\n\n'))
  end)
end

---@param args string[]
---@param start_idx integer
---@return string|nil
local function parse_title(args, start_idx)
  local title = table.concat(vim.list_slice(args, start_idx), ' ')
  if title == '' then
    return nil
  end

  return title
end

---@type table<string, fun(args: string[]): any>
local session_subcommand_actions = {
  new = function(args)
    local title = parse_title(args, 2)
    if title then
      return M.actions.open_input_new_session_with_title(title)
    end
    return M.actions.open_input_new_session()
  end,
  rename = function(args)
    return M.actions.rename_session(nil, parse_title(args, 2))
  end,
  select = function()
    return M.actions.select_session()
  end,
  compact = function()
    return M.actions.compact_session()
  end,
  toggle_lock = function(args)
    local raw = args[2]
    local value
    if raw == nil or raw == '' then
      value = nil
    elseif raw == 'true' or raw == 'on' or raw == '1' then
      value = true
    elseif raw == 'false' or raw == 'off' or raw == '0' then
      value = false
    else
      invalid_arguments('Invalid toggle_lock argument: ' .. tostring(raw))
    end
    return M.actions.toggle_session_lock(value)
  end,
}

M.command_defs = {
  session = {
    desc = 'Manage sessions (new/select/compact/rename/toggle_lock)',
    completions = session_subcommands,
    nested_subcommand = { allow_empty = false },
    execute = function(args)
      local subcommand = args[1]
      local action = session_subcommand_actions[subcommand]
      if not action then
        invalid_arguments('Invalid session subcommand. Use: ' .. table.concat(session_subcommands, ', '))
      end
      return action(args)
    end,
  },
  -- action name aliases for keymap compatibility
  open_input_new_session = { desc = 'Open input (new session)', execute = M.actions.open_input_new_session },
  toggle_session_lock = {
    desc = 'Toggle session lock (preserve active session across cwd changes)',
    execute = function(args)
      return M.actions.toggle_session_lock(args[1])
    end,
  },
  select_session = {
    desc = 'Select session',
    execute = function()
      return M.actions.select_session()
    end,
  },
  rename_session = {
    desc = 'Rename session',
    execute = function(args)
      return M.actions.rename_session(nil, args[1])
    end,
  },
}

return M
