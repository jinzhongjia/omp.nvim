local commands = require('omp.commands')
local window = require('omp.commands.handlers.window').actions
local session = require('omp.commands.handlers.session').actions
local diff = require('omp.commands.handlers.diff').actions
local surface = require('omp.commands.handlers.surface').actions
local workflow = require('omp.commands.handlers.workflow').actions
local permission = require('omp.commands.handlers.permission').actions
local agent = require('omp.commands.handlers.agent').actions

-- Route API actions through the same command execution axis.
---@param hook_key? string
local function dispatch_action(name, action_fn, hook_key, ...)
  local parsed = commands.build_parsed_intent(name, vim.deepcopy({ ... }))
  if hook_key and parsed and parsed.ok and parsed.intent then
    parsed.intent.hook_key = hook_key
  end

  return commands.execute_parsed_intent(parsed, function(resolved_args)
    return action_fn(unpack(resolved_args or {}))
  end)
end

---@type OmpCommandApi
local M = {}

local action_groups = {
  window = {
    swap_position = window.swap_position,
    toggle_zoom = window.toggle_zoom,
    toggle_input = window.toggle_input,
    open_input = window.open_input,
    open_output = window.open_output,
    close = window.close,
    hide = window.hide,
    toggle_pane = window.toggle_pane,
    focus_input = window.focus_input,
    cancel = window.cancel,
    toggle_focus = window.toggle_focus,
    toggle = window.toggle,
  },

  session = {
    open_input_new_session = session.open_input_new_session,
    select_session = session.select_session,
    compact_session = session.compact_session,
    open_input_new_session_with_title = session.open_input_new_session_with_title,
    rename_session = session.rename_session,
    copy_message = session.copy_message,
    toggle_session_lock = session.toggle_session_lock,
  },

  diff = {
    diff_next = diff.diff_next,
    diff_prev = diff.diff_prev,
    diff_close = diff.diff_close,
    diff_open = diff.diff_open,
  },

  workflow = {
    paste_image = workflow.paste_image,
    select_history = workflow.select_history,
    prev_history = workflow.prev_history,
    next_history = workflow.next_history,
    prev_prompt_history = workflow.prev_prompt_history,
    next_prompt_history = workflow.next_prompt_history,
    next_message = workflow.next_message,
    prev_message = workflow.prev_message,
    next_user_message = workflow.next_user_message,
    prev_user_message = workflow.prev_user_message,
    mention_file = workflow.mention_file,
    mention = workflow.mention,
    context_items = workflow.context_items,
    slash_commands = workflow.slash_commands,
    references = workflow.references,
    jump_to_file = workflow.jump_to_file,
    jump_to_target_at_cursor = workflow.jump_to_target_at_cursor,
    debug_output = workflow.debug_output,
    debug_message = workflow.debug_message,
    debug_session = workflow.debug_session,
    toggle_tool_output = workflow.toggle_tool_output,
    toggle_reasoning_output = workflow.toggle_reasoning_output,
    toggle_max_messages = workflow.toggle_max_messages,
    navigate_to_location = workflow.navigate_to_location,
    submit_input_prompt = workflow.submit_input_prompt,
    run = workflow.run,
    run_new_session = workflow.run_new_session,
    quick_chat = workflow.quick_chat,
    run_user_command = workflow.run_user_command,
    review = workflow.review,
    add_visual_selection = workflow.add_visual_selection,
    add_visual_selection_inline = workflow.add_visual_selection_inline,
  },

  surface = {
    help = surface.help,
    commands_list = surface.commands_list,
  },

  permission = {
    question_answer = permission.question_answer,
    question_other = permission.question_other,
    respond_to_permission = permission.respond_to_permission,
    permission_accept = permission.permission_accept,
    permission_accept_all = permission.permission_accept_all,
    permission_deny = permission.permission_deny,
  },

  agent = {
    configure_provider = agent.configure_provider,
    configure_thinking_level = agent.configure_thinking_level,
    cycle_thinking_level = agent.cycle_thinking_level,
  },

  query = {
    get_window_state = window.get_window_state,
    current_model = agent.current_model,
    with_header = surface.with_header,
  },
}

---@param group_name string
---@param exports table<string, function>
local function register_exports(group_name, exports)
  for name, fn in pairs(exports) do
    M[name] = function(...)
      return dispatch_action(name, fn, group_name, ...)
    end
  end
end

for group_name, exports in pairs(action_groups) do
  register_exports(group_name, exports)
end

return M
