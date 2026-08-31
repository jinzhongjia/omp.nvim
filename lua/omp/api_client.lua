local Promise = require('omp.promise')
local Process = require('omp.rpc.process')
local Adapter = require('omp.rpc.adapter')
local config = require('omp.config')
local log = require('omp.log')

---@class OmpApiClient
---@field cwd string
---@field control? OmpRpcProcess
---@field processes table<string, OmpRpcProcess>
---@field adapters table<OmpRpcProcess, table>
---@field sessions table<string, Session>
---@field listeners fun(event: table)[]
---@field available_commands table[]
---@field busy table<string, boolean>
---@field spawn_promise Promise<OmpApiClient>
---@field shutdown_promise Promise<boolean>
---@field url string
local OmpApiClient = {}
OmpApiClient.__index = OmpApiClient

local function reject(message)
  return Promise.new():reject(message)
end

local function session_root()
  return vim.fs.joinpath(vim.uv.os_homedir(), '.omp', 'agent', 'sessions')
end

local function canonical(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function encoded_workspace(cwd)
  cwd = canonical(cwd)
  local home = canonical(vim.uv.os_homedir())
  if cwd == home then
    return '-'
  end
  if vim.startswith(cwd, home .. '/') then
    return '-' .. cwd:sub(#home + 2):gsub('[/\\:]', '-')
  end
  return '--' .. cwd:gsub('^[/\\]', ''):gsub('[/\\:]', '-') .. '--'
end

local function workspace_session_dir(cwd)
  return vim.fs.joinpath(session_root(), encoded_workspace(cwd))
end

local function read_session(path)
  local ok, lines = pcall(vim.fn.readfile, path, '', 32)
  if not ok then
    return nil
  end
  local header, title
  for _, line in ipairs(lines) do
    local decoded_ok, entry = pcall(vim.json.decode, line)
    if decoded_ok and type(entry) == 'table' then
      if (entry.type == 'title' or entry.type == 'title_change') and entry.title then
        title = entry.title
      elseif entry.type == 'session' then
        header = entry
      end
    end
    if header and title then
      break
    end
  end
  if not header or not header.id then
    return nil
  end
  local stat = vim.uv.fs_stat(path)
  local updated = stat and stat.mtime and stat.mtime.sec * 1000 or 0
  local created = header.timestamp and (vim.fn.strptime('%Y-%m-%dT%H:%M:%S', header.timestamp:sub(1, 19)) * 1000)
    or updated
  return {
    id = header.id,
    title = title or header.title or vim.fs.basename(path),
    directory = header.cwd,
    workspace = header.cwd,
    parentID = nil,
    time = { created = created, updated = updated },
    sessionPath = path,
  }
end

local function scan_dir(path)
  local sessions = {}
  local handle = vim.uv.fs_scandir(path)
  if not handle then
    return sessions
  end
  while true do
    local name, type_ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if type_ == 'file' and vim.endswith(name, '.jsonl') then
      local session = read_session(vim.fs.joinpath(path, name))
      if session then
        table.insert(sessions, session)
      end
    end
  end
  return sessions
end

local function scan_all_sessions()
  local sessions = {}
  local handle = vim.uv.fs_scandir(session_root())
  if not handle then
    return sessions
  end
  while true do
    local name, type_ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if type_ == 'directory' then
      vim.list_extend(sessions, scan_dir(vim.fs.joinpath(session_root(), name)))
    end
  end
  return sessions
end

local function find_session(id, cwd)
  for _, session in ipairs(scan_dir(workspace_session_dir(cwd))) do
    if session.id == id then
      return session
    end
  end
  for _, session in ipairs(scan_all_sessions()) do
    if session.id == id then
      return session
    end
  end
  return nil
end

local function model_id(model)
  if not model then
    return nil
  end
  return string.format('%s/%s', model.provider, model.id)
end

local function read_binary(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)
  return data
end

local function serialize_prompt(params)
  local chunks, images = {}, {}
  if params.system and params.system ~= '' then
    table.insert(chunks, '<system>\n' .. params.system .. '\n</system>')
  end
  for _, part in ipairs(params.parts or {}) do
    if part.type == 'text' and part.text and part.text ~= '' then
      local context_type = part.metadata and part.metadata.context_type
      if part.synthetic or context_type then
        local attrs = context_type and string.format(' type="%s"', context_type) or ''
        table.insert(chunks, string.format('<context%s>\n%s\n</context>', attrs, part.text))
      else
        table.insert(chunks, part.text)
      end
    elseif part.type == 'file' then
      local path = part.url and part.url:gsub('^file://', '') or part.filename
      if part.mime and vim.startswith(part.mime, 'image/') and path then
        local data = read_binary(path)
        if data then
          table.insert(images, { type = 'image', data = vim.base64.encode(data), mimeType = part.mime })
        end
      elseif path then
        table.insert(chunks, string.format('<context file="%s">Referenced file</context>', path))
      end
    elseif part.type == 'agent' and part.name then
      table.insert(chunks, string.format('<context agent="%s">Referenced subagent</context>', part.name))
    end
  end
  return table.concat(chunks, '\n\n'), images
end

---@param cwd? string
---@return OmpApiClient
function OmpApiClient.new(cwd)
  return setmetatable({
    cwd = cwd or vim.fn.getcwd(),
    control = nil,
    processes = {},
    adapters = {},
    sessions = {},
    listeners = {},
    available_commands = {},
    busy = {},
    spawn_promise = Promise.new(),
    shutdown_promise = Promise.new(),
    url = 'stdio://omp',
    mode = 'rpc',
  }, OmpApiClient)
end
function OmpApiClient:set_cwd(cwd)
  self.cwd = canonical(cwd)
end

function OmpApiClient:_emit(event)
  local status = event.type == 'session.status' and event.properties and event.properties.status
  local session_id = event.properties and event.properties.sessionID
  if status and session_id then
    self.busy[session_id] = status.type == 'busy'
  end
  for _, listener in ipairs(vim.deepcopy(self.listeners)) do
    local ok, err = pcall(listener, event)
    if not ok then
      log.error('omp event listener failed: ' .. tostring(err))
    end
  end
end

function OmpApiClient:_attach(process, adapter)
  self.adapters[process] = adapter
  process:subscribe(function(frame)
    if frame.type == 'available_commands_update' then
      self.available_commands = frame.commands or {}
      return
    end
    for _, adapted in ipairs(adapter:handle(frame)) do
      self:_emit(adapted)
    end
  end)
end

---@return Promise<OmpApiClient>
function OmpApiClient:start()
  if self.control then
    return self.spawn_promise
  end
  self.control = Process.new({ cwd = self.cwd, no_session = true })
  self:_attach(self.control, Adapter.new())
  self.control
    :start()
    :and_then(function()
      self.spawn_promise:resolve(self)
    end)
    :catch(function(err)
      self.spawn_promise:reject(err)
    end)
  return self.spawn_promise
end

function OmpApiClient:is_running()
  return self.control ~= nil and self.control:is_running()
end

function OmpApiClient:get_spawn_promise()
  return self.spawn_promise
end

function OmpApiClient:get_shutdown_promise()
  return self.shutdown_promise
end

function OmpApiClient:shutdown()
  if self.shutdown_promise:is_resolved() then
    return self.shutdown_promise
  end
  local remaining = 0
  local function stopped()
    remaining = remaining - 1
    if remaining == 0 then
      self.shutdown_promise:resolve(true)
    end
  end
  local seen = {}
  local processes = {}
  if self.control then
    table.insert(processes, self.control)
  end
  for _, process in pairs(self.processes) do
    if not seen[process] then
      table.insert(processes, process)
      seen[process] = true
    end
  end
  remaining = #processes
  if remaining == 0 then
    return self.shutdown_promise:resolve(true)
  end
  for _, process in ipairs(processes) do
    process:shutdown():finally(stopped)
  end
  return self.shutdown_promise
end

function OmpApiClient:_control_request(command)
  return self:start():and_then(function()
    return self.control:request(command)
  end)
end

function OmpApiClient:_session_from_state(data, fallback)
  local id = data.sessionId or (fallback and fallback.id)
  local session = fallback or {}
  local timestamp = os.time() * 1000
  session.id = id
  session.title = data.sessionName or session.title or 'New session'
  session.directory = session.directory or self.cwd
  session.workspace = session.workspace or session.directory
  session.sessionPath = data.sessionFile or session.sessionPath
  session.time = session.time or { created = timestamp, updated = timestamp }
  session.model = data.model and { id = data.model.id, providerID = data.model.provider } or session.model
  self.sessions[id] = session
  return session
end

function OmpApiClient:_spawn_session(existing)
  return Promise.async(function()
    local process = Process.new({
      cwd = (existing and existing.directory) or self.cwd,
      resume = existing and existing.sessionPath or nil,
    })
    local adapter = Adapter.new({ session_id = existing and existing.id or '' })
    self:_attach(process, adapter)
    process:start():await()
    local data = process:request({ type = 'get_state' }):await()
    local session = self:_session_from_state(data, existing)
    adapter:set_session_id(session.id)
    self.processes[session.id] = process
    return process, session
  end)()
end

function OmpApiClient:_ensure_session_process(session_id)
  local process = self.processes[session_id]
  if process and process:is_running() then
    return Promise.new():resolve(process)
  end
  local existing = self.sessions[session_id] or find_session(session_id, self.cwd)
  if not existing then
    return reject('OMP session not found: ' .. tostring(session_id))
  end
  return self:_spawn_session(existing):and_then(function(spawned)
    return spawned
  end)
end

function OmpApiClient:get_current_project()
  local name = vim.fs.basename(self.cwd)
  return Promise.new():resolve({ id = encoded_workspace(self.cwd), name = name, worktree = self.cwd })
end

function OmpApiClient:get_config()
  return Promise.async(function()
    local state = self:_control_request({ type = 'get_state' }):await()
    local commands = self:_control_request({ type = 'get_available_commands' }):await()
    self.available_commands = commands.commands or self.available_commands
    local command_config = {}
    for _, command in ipairs(self.available_commands) do
      command_config[command.name] = { description = command.description }
    end
    return {
      model = model_id(state.model),
      agent = { default = { mode = 'primary' } },
      command = command_config,
    }
  end)()
end

function OmpApiClient:list_providers()
  return self:_control_request({ type = 'get_available_models' }):and_then(function(data)
    local grouped = {}
    for _, model in ipairs(data.models or {}) do
      local provider_id = model.provider
      grouped[provider_id] = grouped[provider_id] or { id = provider_id, name = provider_id, models = {} }
      grouped[provider_id].models[model.id] = {
        id = model.id,
        name = model.name or model.id,
        limit = { context = model.contextWindow, output = model.maxTokens },
        modalities = model.modalities,
        variants = model.reasoning and { low = {}, medium = {}, high = {} } or nil,
      }
    end
    local providers = {}
    for _, provider in pairs(grouped) do
      table.insert(providers, provider)
    end
    table.sort(providers, function(a, b)
      return a.id < b.id
    end)
    return { providers = providers, default = {} }
  end)
end

function OmpApiClient:list_sessions()
  local sessions = scan_dir(workspace_session_dir(self.cwd))
  for id, live in pairs(self.sessions) do
    if canonical(live.directory or '') == canonical(self.cwd) then
      local found = false
      for index, session in ipairs(sessions) do
        if session.id == id then
          sessions[index] = vim.tbl_extend('force', session, live)
          found = true
          break
        end
      end
      if not found then
        table.insert(sessions, live)
      end
    end
  end
  return Promise.new():resolve(sessions)
end

function OmpApiClient:list_sessions_global()
  return Promise.new():resolve(scan_all_sessions())
end

function OmpApiClient:list_session_status()
  local result = {}
  for id, busy in pairs(self.busy) do
    result[id] = { type = busy and 'busy' or 'idle' }
  end
  return Promise.new():resolve(result)
end

function OmpApiClient:create_session(session_data)
  return Promise.async(function()
    local process = self:_spawn_session(nil):await()
    local state = process:request({ type = 'get_state' }):await()
    local session = self.sessions[state.sessionId]
    if session_data and type(session_data) == 'table' and session_data.title then
      process:request({ type = 'set_session_name', name = session_data.title }):await()
      session.title = session_data.title
    end
    return session
  end)()
end

function OmpApiClient:get_session(id)
  local session = self.sessions[id] or find_session(id, self.cwd)
  if session then
    self.sessions[id] = session
  end
  return Promise.new():resolve(session)
end

function OmpApiClient:delete_session()
  return reject('OMP RPC does not support deleting sessions')
end

function OmpApiClient:update_session(id, update)
  return Promise.async(function()
    local process = self:_ensure_session_process(id):await()
    if update.title then
      process:request({ type = 'set_session_name', name = update.title }):await()
      self.sessions[id].title = update.title
    end
    return self.sessions[id]
  end)()
end

function OmpApiClient:list_messages(id, _, opts)
  return Promise.async(function()
    local process = self:_ensure_session_process(id):await()
    local data = process:request({ type = 'get_messages' }):await()
    local messages = Adapter.convert_messages(data.messages or {}, id)
    if opts and opts.limit and #messages > opts.limit then
      local limited = {}
      for index = #messages - opts.limit + 1, #messages do
        table.insert(limited, messages[index])
      end
      messages = limited
    end
    return messages
  end)()
end

function OmpApiClient:create_message(id, params)
  return Promise.async(function()
    local process = self:_ensure_session_process(id):await()
    if params.model then
      process
        :request({ type = 'set_model', provider = params.model.providerID, modelId = params.model.modelID })
        :await()
    end
    if params.variant then
      process:request({ type = 'set_thinking_level', level = params.variant }):await()
    end
    local message, images = serialize_prompt(params)
    local behavior = self.busy[id] and 'followUp' or nil
    process
      :request({
        type = 'prompt',
        message = message,
        images = #images > 0 and images or nil,
        streamingBehavior = behavior,
      })
      :await()
    return {
      info = { id = 'prompt-' .. tostring(os.time()), sessionID = id, role = 'user' },
      parts = {},
    }
  end)()
end

function OmpApiClient:abort_session(id)
  return self:_ensure_session_process(id):and_then(function(process)
    return process:request({ type = 'abort' })
  end)
end

function OmpApiClient:summarize_session(id)
  return self:_ensure_session_process(id):and_then(function(process)
    return process:request({ type = 'compact' })
  end)
end

function OmpApiClient:send_command(id, data)
  local arguments = data.arguments and data.arguments ~= '' and (' ' .. data.arguments) or ''
  return self:create_message(id, { parts = { { type = 'text', text = '/' .. data.command .. arguments } } })
end

function OmpApiClient:run_shell(id, data)
  return self:_ensure_session_process(id):and_then(function(process)
    return process:request({ type = 'bash', command = data.command })
  end)
end

function OmpApiClient:list_commands()
  if #self.available_commands > 0 then
    return Promise.new():resolve(self.available_commands)
  end
  return self:_control_request({ type = 'get_available_commands' }):and_then(function(data)
    self.available_commands = data.commands or {}
    return self.available_commands
  end)
end

function OmpApiClient:list_skills()
  return self:list_commands():and_then(function(commands)
    local skills = {}
    for _, command in ipairs(commands) do
      if command.source == 'skill' then
        table.insert(skills, { name = command.name, description = command.description })
      end
    end
    return skills
  end)
end

function OmpApiClient:list_permissions()
  local permissions = {}
  for _, adapter in pairs(self.adapters) do
    for _, permission in pairs(adapter.permissions) do
      table.insert(permissions, permission)
    end
  end
  return Promise.new():resolve(permissions)
end

function OmpApiClient:reply_to_permission(request_id, response)
  for process, adapter in pairs(self.adapters) do
    local permission = adapter.permissions[request_id]
    if permission then
      local rejected = response.reply == 'reject'
      local frame = { type = 'extension_ui_response', id = request_id }
      if permission.metadata.method == 'confirm' then
        frame.confirmed = not rejected
      elseif rejected then
        frame.cancelled = true
      else
        local options = permission.metadata.options or {}
        frame.value = options[1] or 'Approve'
      end
      local ok, err = process:send(frame)
      if not ok then
        return reject(err)
      end
      adapter.permissions[request_id] = nil
      self:_emit({
        type = 'permission.replied',
        properties = { sessionID = permission.sessionID, requestID = request_id, response = response.reply },
      })
      return Promise.new():resolve(true)
    end
  end
  return reject('OMP permission request not found: ' .. request_id)
end

function OmpApiClient:respond_to_permission(_, request_id, response)
  return self:reply_to_permission(request_id, { reply = response.response })
end
function OmpApiClient:list_questions()
  local questions = {}
  for _, adapter in pairs(self.adapters) do
    for _, request in pairs(adapter.questions) do
      table.insert(questions, request)
    end
  end
  return Promise.new():resolve(questions)
end

local function answer_question(client, request_id, answers, cancelled)
  for process, adapter in pairs(client.adapters) do
    local request = adapter.questions[request_id]
    if request then
      local frame = { type = 'extension_ui_response', id = request_id }
      if cancelled then
        frame.cancelled = true
      elseif request.metadata.method == 'confirm' then
        local answer = answers and answers[1] and answers[1][1]
        frame.confirmed = answer == 'Yes' or answer == 'Confirm' or answer == 'Approve'
      else
        frame.value = answers and answers[1] and answers[1][1] or request.metadata.options[1]
      end
      local ok, err = process:send(frame)
      if not ok then
        return reject(err)
      end
      adapter.questions[request_id] = nil
      client:_emit({
        type = cancelled and 'question.rejected' or 'question.replied',
        properties = { sessionID = request.sessionID, requestID = request_id, answers = answers },
      })
      return Promise.new():resolve(true)
    end
  end
  return reject('OMP question request not found: ' .. request_id)
end

function OmpApiClient:reply_question(request_id, answers)
  return answer_question(self, request_id, answers, false)
end

function OmpApiClient:reject_question(request_id)
  return answer_question(self, request_id, nil, true)
end

function OmpApiClient:find_files(pattern)
  local lowered = pattern:lower()
  local files = vim.fs.find(function(name, path)
    local relative = vim.fs.relpath(self.cwd, vim.fs.joinpath(path, name)) or name
    return relative:lower():find(lowered, 1, true) ~= nil
  end, { path = self.cwd, type = 'file', limit = 100 })
  return Promise.new():resolve(vim.tbl_map(function(path)
    return vim.fs.relpath(self.cwd, path) or path
  end, files))
end

function OmpApiClient:get_file_status()
  return Promise.new():resolve({})
end

function OmpApiClient:subscribe_to_events(_, callback)
  table.insert(self.listeners, callback)
  local client = self
  return {
    shutdown = function()
      for index = #client.listeners, 1, -1 do
        if client.listeners[index] == callback then
          table.remove(client.listeners, index)
        end
      end
    end,
  }
end

local function create_client(cwd)
  return OmpApiClient.new(cwd)
end

return {
  new = OmpApiClient.new,
  create = create_client,
  OmpApiClient = OmpApiClient,
}
