local state = require('omp.state')
local context = require('omp.context')
local util = require('omp.util')
local config = require('omp.config')
local Promise = require('omp.promise')
local log = require('omp.log')
local agent_model = require('omp.services.agent_model')
local session_runtime = require('omp.services.session_runtime')

local M = {}

--- Sends a message to the active session.
--- @param prompt string The message prompt to send.
--- @param opts? SendMessageOpts
M.send_message = Promise.async(function(prompt, opts)
  if not state.active_session or not state.active_session.id then
    return false
  end

  local mentioned_files = context.get_context().mentioned_files or {}
  local allowed, err_msg = util.check_prompt_allowed(config.prompt_guard, mentioned_files)

  if not allowed then
    log.notify(err_msg or 'Prompt denied by prompt_guard', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}

  opts.context = vim.tbl_deep_extend('force', state.current_context_config or {}, opts.context or {})
  state.context.set_current_context_config(opts.context)
  context.load()
  opts.model = opts.model or agent_model.initialize_current_model():await()
  opts.thinking_level = opts.thinking_level or state.current_thinking_level
  local params = {}

  if opts.model then
    local provider, model = opts.model:match('^(.-)/(.+)$')
    params.model = { providerID = provider, modelID = model }
    state.model.set_model(opts.model)

    if opts.thinking_level then
      params.thinking_level = opts.thinking_level
      state.model.set_thinking_level(opts.thinking_level)
    end
  end

  params.parts = context.format_message(prompt, opts.context):await()
  params.system = opts.system or config.default_system_prompt or nil

  local session_id = state.active_session.id
  local sent_context = vim.deepcopy(context.get_context())
  context.unload_attachments()

  local function update_sent_message_count(num)
    local sent_message_count = vim.deepcopy(state.user_message_count)
    local new_value = (sent_message_count[session_id] or 0) + num
    sent_message_count[session_id] = new_value >= 0 and new_value or 0
    state.session.set_user_message_count(sent_message_count)
  end

  update_sent_message_count(1)

  state.api_client
    :create_message(session_id, params)
    :and_then(function()
      update_sent_message_count(-1)
      M.after_run(prompt, sent_context)
    end)
    :catch(function(err)
      log.notify('Error sending message to session: ' .. vim.inspect(err), vim.log.levels.ERROR)
      update_sent_message_count(-1)
      session_runtime.cancel():await()
    end)
    :await()
end)

---@param prompt string
---@param sent_context? OmpContext
function M.after_run(prompt, sent_context)
  local context_sent = vim.deepcopy(sent_context or context.get_context())
  if not sent_context then
    context.unload_attachments()
  end
  state.session.set_last_sent_context(context_sent)
  context.delta_context()
  require('omp.history').write(prompt)
  vim.g.omp_abort_count = 0
end

return M
