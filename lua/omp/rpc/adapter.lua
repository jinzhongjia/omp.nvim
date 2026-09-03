local Adapter = {}
Adapter.__index = Adapter

local function now_ms()
  return os.time() * 1000
end

local function event(type_, properties)
  return { type = type_, properties = properties or {} }
end

local function text_content(content)
  if type(content) == 'string' then
    return content
  end
  if type(content) ~= 'table' then
    return content == nil and '' or vim.inspect(content)
  end
  if content.content ~= nil then
    return text_content(content.content)
  end
  local chunks = {}
  for _, block in ipairs(content) do
    if type(block) == 'string' then
      table.insert(chunks, block)
    elseif type(block) == 'table' then
      local value = block.text or block.thinking or block.content
      if type(value) == 'string' then
        table.insert(chunks, value)
      end
    end
  end
  if #chunks > 0 then
    return table.concat(chunks, '\n')
  end
  return vim.json.encode(content)
end

local function normalize_tool_input(tool, args)
  local input = vim.deepcopy(type(args) == 'table' and args or {})
  if input.path and not input.filePath and vim.tbl_contains({ 'read', 'write', 'edit' }, tool) then
    input.filePath = input.path
  end
  return input
end

local function message_info(message, session_id, message_id)
  local usage = message and message.usage or {}
  local model = message and message.model or {}
  return {
    id = message_id,
    sessionID = session_id,
    role = message and message.role or 'assistant',
    time = {
      created = message and message.timestamp or now_ms(),
      completed = now_ms(),
    },
    tokens = {
      input = usage.input or usage.inputTokens or 0,
      output = usage.output or usage.outputTokens or 0,
      reasoning = usage.reasoning or usage.reasoningTokens or 0,
      cache = {
        read = usage.cacheRead or usage.cacheReadTokens or 0,
        write = usage.cacheWrite or usage.cacheWriteTokens or 0,
      },
    },
    cost = usage.cost or 0,
    modelID = model.id or message and message.modelId,
    providerID = model.provider or message and message.provider,
  }
end

local function tool_part(session_id, message_id, tool_call_id, tool, args, status)
  return {
    id = 'tool-' .. tostring(tool_call_id),
    callID = tool_call_id,
    messageID = message_id,
    sessionID = session_id,
    type = 'tool',
    tool = tool,
    state = {
      status = status or 'running',
      input = normalize_tool_input(tool, args),
      metadata = {},
      time = { start = now_ms() },
    },
  }
end

---@param value string
---@param prefix string
---@return boolean
local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

---@param text string
---@param session_id string
---@param message_id string
---@param block_index integer
---@return table[]|nil
local function restored_user_parts(text, session_id, message_id, block_index)
  if not text:find('<context', 1, true) and not text:find('<system>', 1, true) then
    return nil
  end

  local parts = {}
  local restored = false
  local sequence = 0

  ---@param part table
  local function add_part(part)
    sequence = sequence + 1
    part.id = string.format('%s-restored-%d-%d', message_id, block_index, sequence)
    part.messageID = message_id
    part.sessionID = session_id
    table.insert(parts, part)
  end

  ---@param remaining string
  ---@param last integer
  ---@return string
  local function after_chunk(remaining, last)
    local next_index = last + 1
    if remaining:sub(next_index, next_index + 1) == '\n\n' then
      next_index = next_index + 2
    end
    return remaining:sub(next_index)
  end

  local remaining = text
  while remaining ~= '' do
    local _, file_end, path = remaining:find('^<context file="([^"]*)">Referenced file</context>')
    if file_end then
      add_part({
        type = 'file',
        filename = path,
        url = 'file://' .. path,
        source = { path = path },
      })
      restored = true
      remaining = after_chunk(remaining, file_end)
    else
      local _, agent_end, name = remaining:find('^<context agent="([^"]*)">Referenced subagent</context>')
      if agent_end then
        add_part({
          type = 'agent',
          name = name,
          source = { path = name },
        })
        restored = true
        remaining = after_chunk(remaining, agent_end)
      elseif starts_with(remaining, '<system>\n') then
        local close_start, close_end = remaining:find('\n</system>', #'<system>\n' + 1, true)
        if not close_start then
          break
        end
        restored = true
        remaining = after_chunk(remaining, close_end)
      elseif starts_with(remaining, '<context') then
        local opening_end = remaining:find('>\n', 1, true)
        local close_start, close_end
        if opening_end then
          close_start, close_end = remaining:find('\n</context>', opening_end + 2, true)
        end
        if not opening_end or not close_start then
          break
        end
        local opening = remaining:sub(1, opening_end)
        local context_type = opening:match('^<context type="([^"]+)">$')
        if opening ~= '<context>' and not context_type then
          break
        end
        add_part({
          type = 'text',
          text = remaining:sub(opening_end + 2, close_start - 1),
          synthetic = true,
          metadata = context_type and { context_type = context_type } or nil,
        })
        restored = true
        remaining = after_chunk(remaining, close_end)
      else
        local context_start = remaining:find('\n\n<context', 1, true)
        local system_start = remaining:find('\n\n<system>\n', 1, true)
        local boundary
        if context_start and system_start then
          boundary = math.min(context_start, system_start)
        else
          boundary = context_start or system_start
        end
        local plain = boundary and remaining:sub(1, boundary - 1) or remaining
        if plain ~= '' then
          add_part({ type = 'text', text = plain })
        end
        remaining = boundary and remaining:sub(boundary + 2) or ''
      end
    end
  end

  if remaining ~= '' then
    add_part({ type = 'text', text = remaining })
  end
  return restored and parts or nil
end

local function content_parts(message, session_id, message_id)
  local result = {}
  local content = message and message.content
  if type(content) == 'string' then
    content = { { type = 'text', text = content } }
  end
  for index, block in ipairs(type(content) == 'table' and content or {}) do
    if type(block) == 'string' then
      block = { type = 'text', text = block }
    end
    if type(block) == 'table' then
      if block.type == 'text' then
        local restored = message.role == 'user' and restored_user_parts(block.text or '', session_id, message_id, index)
          or nil
        if restored then
          vim.list_extend(result, restored)
        else
          table.insert(result, {
            id = string.format('%s-text-%d', message_id, index),
            messageID = message_id,
            sessionID = session_id,
            type = 'text',
            text = block.text or '',
          })
        end
      elseif block.type == 'thinking' then
        table.insert(result, {
          id = string.format('%s-reasoning-%d', message_id, index),
          messageID = message_id,
          sessionID = session_id,
          type = 'reasoning',
          text = block.thinking or block.text or '',
        })
      elseif block.type == 'toolCall' then
        table.insert(
          result,
          tool_part(
            session_id,
            message_id,
            block.id or (message_id .. '-' .. index),
            block.name,
            block.arguments,
            'running'
          )
        )
      end
    end
  end
  return result
end

---@param messages table[]
---@param session_id string
---@return table[]
function Adapter.convert_messages(messages, session_id)
  local converted = {}
  local tools = {}
  for index, message in ipairs(messages or {}) do
    local role = message.role
    if role == 'user' or role == 'assistant' then
      local message_id = message.id or string.format('omp-%s-%d', session_id, index)
      local converted_message = {
        info = message_info(message, session_id, message_id),
        parts = content_parts(message, session_id, message_id),
      }
      table.insert(converted, converted_message)
      for _, part in ipairs(converted_message.parts) do
        if part.type == 'tool' and part.callID then
          tools[part.callID] = part
        end
      end
    elseif role == 'toolResult' and message.toolCallId then
      local part = tools[message.toolCallId]
      if part then
        part.state.status = message.isError and 'error' or 'completed'
        part.state.output = text_content(message.content)
        part.state.error = message.isError and part.state.output or nil
        part.state.metadata = vim.tbl_extend('force', part.state.metadata or {}, message.details or {})
        part.state.time['end'] = message.timestamp or now_ms()
      end
    end
  end
  return converted
end

---@param opts? {session_id?: string}
function Adapter.new(opts)
  opts = opts or {}
  return setmetatable({
    session_id = opts.session_id or '',
    sequence = 0,
    current_message_id = nil,
    current_message = nil,
    part_ids = {},
    tool_parts = {},
    permissions = {},
    questions = {},
  }, Adapter)
end

function Adapter:set_session_id(session_id)
  self.session_id = session_id or ''
end

function Adapter:_next_message_id(message)
  self.sequence = self.sequence + 1
  return message and message.id or string.format('omp-%s-live-%d', self.session_id, self.sequence)
end

---@param frame table
---@return table[]
function Adapter:handle(frame)
  local events = {}
  local frame_type = frame and frame.type
  if frame_type == 'agent_start' then
    return { event('session.status', { sessionID = self.session_id, status = { type = 'busy' } }) }
  end
  if frame_type == 'agent_end' and frame.isTerminal ~= false then
    return {
      event('session.status', { sessionID = self.session_id, status = { type = 'idle' } }),
      event('session.idle', { sessionID = self.session_id }),
    }
  end

  if frame_type == 'message_start' then
    self.part_ids = {}
    local message = frame.message or {}
    if message.role ~= 'user' and message.role ~= 'assistant' then
      return events
    end
    local message_id = self:_next_message_id(message)
    self.current_message_id = message_id
    self.current_message = message
    table.insert(events, event('message.updated', { info = message_info(message, self.session_id, message_id) }))
    for _, part in ipairs(content_parts(message, self.session_id, message_id)) do
      self.part_ids[part.type] = part.id
      if part.callID then
        self.tool_parts[part.callID] = part
      end
      table.insert(events, event('message.part.updated', { part = part }))
    end
    return events
  end

  if frame_type == 'message_update' then
    local update = frame.assistantMessageEvent or {}
    local message_id = self.current_message_id
    if not message_id then
      return events
    end
    local part_type, field
    if update.type == 'text_delta' then
      part_type, field = 'text', 'text'
    elseif update.type == 'thinking_delta' then
      part_type, field = 'reasoning', 'text'
    else
      return events
    end
    local content_index = (tonumber(update.contentIndex) or 0) + 1
    local key = part_type .. ':' .. tostring(content_index)
    local part_id = self.part_ids[key]
    if not part_id then
      part_id = string.format('%s-%s-%s', message_id, part_type, content_index)
      self.part_ids[key] = part_id
    end
    return {
      event('message.part.delta', {
        sessionID = self.session_id,
        messageID = message_id,
        partID = part_id,
        field = field,
        delta = update.delta or '',
      }),
    }
  end

  if frame_type == 'message_end' then
    local message = frame.message or self.current_message or {}
    if message.role ~= 'user' and message.role ~= 'assistant' then
      return events
    end
    local message_id = self.current_message_id or self:_next_message_id(message)
    table.insert(events, event('message.updated', { info = message_info(message, self.session_id, message_id) }))
    for _, part in ipairs(content_parts(message, self.session_id, message_id)) do
      if part.callID then
        self.tool_parts[part.callID] = self.tool_parts[part.callID] or part
      else
        table.insert(events, event('message.part.updated', { part = part }))
      end
    end
    self.current_message = nil
    return events
  end

  if frame_type == 'tool_execution_start' then
    local message_id = self.current_message_id or self:_next_message_id({ role = 'assistant' })
    if not self.current_message_id then
      self.current_message_id = message_id
      table.insert(
        events,
        event('message.updated', { info = message_info({ role = 'assistant' }, self.session_id, message_id) })
      )
    end
    local part =
      tool_part(self.session_id, message_id, frame.toolCallId, frame.toolName, frame.args or frame.arguments, 'running')
    part.state.time.start = frame.startedAt or now_ms()
    self.tool_parts[frame.toolCallId] = part
    table.insert(events, event('message.part.updated', { part = part }))
    return events
  end

  if frame_type == 'tool_execution_update' then
    local part = self.tool_parts[frame.toolCallId]
    if part then
      part.state.output = text_content(frame.partialResult or frame.result)
      return { event('message.part.updated', { part = vim.deepcopy(part) }) }
    end
    return events
  end

  if frame_type == 'tool_execution_end' then
    local part = self.tool_parts[frame.toolCallId]
    if not part then
      return events
    end
    local output = text_content(frame.result)
    part.state.status = frame.isError and 'error' or 'completed'
    part.state.output = output
    part.state.error = frame.isError and output or nil
    part.state.time['end'] = frame.endedAt or now_ms()
    if part.tool == 'bash' then
      part.state.metadata.output = output
      part.state.metadata.command = part.state.input.command
    elseif type(frame.result) == 'table' and type(frame.result.details) == 'table' then
      part.state.metadata = vim.tbl_extend('force', part.state.metadata, frame.result.details)
    end
    return { event('message.part.updated', { part = vim.deepcopy(part) }) }
  end

  if frame_type == 'extension_ui_request' and (frame.method == 'select' or frame.method == 'confirm') then
    local options = frame.options or { 'Yes', 'No' }
    local is_permission = (frame.title or ''):find('Allow tool:', 1, true) ~= nil
      or (vim.tbl_contains(options, 'Approve') and vim.tbl_contains(options, 'Deny'))
    if is_permission then
      local permission = {
        id = frame.id,
        sessionID = self.session_id,
        type = 'tool',
        title = frame.title or frame.message or 'OMP permission request',
        pattern = options,
        metadata = {
          method = frame.method,
          message = frame.message,
          options = options,
          optionDetails = frame.optionDetails,
        },
        time = { created = now_ms() },
      }
      self.permissions[frame.id] = permission
      return { event('permission.asked', permission) }
    end
    local question_options = {}
    for index, label in ipairs(options) do
      local detail = frame.optionDetails and frame.optionDetails[index] or {}
      table.insert(question_options, { label = label, description = detail.description or '' })
    end
    local request = {
      id = frame.id,
      sessionID = self.session_id,
      metadata = { method = frame.method, options = options },
      questions = {
        {
          header = frame.title or 'OMP',
          question = frame.message or frame.title or 'Select an option',
          options = question_options,
          multiple = false,
        },
      },
    }
    self.questions[frame.id] = request
    return { event('question.asked', request) }
  end

  if frame_type == 'auto_compaction_start' then
    return {
      event('session.status', { sessionID = self.session_id, status = { type = 'busy', message = 'Compacting' } }),
    }
  end
  if frame_type == 'auto_compaction_end' then
    return { event('session.compacted', { sessionID = self.session_id }) }
  end
  if frame_type == 'notice' and frame.level == 'error' then
    return { event('session.error', { sessionID = self.session_id, error = { message = frame.message } }) }
  end
  return events
end

return Adapter
