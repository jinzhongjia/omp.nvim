local Promise = require('omp.promise')
local log = require('omp.log')

local title_extension = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)), 'title.ts')

---@class OmpRpcProcessOpts
---@field cwd string
---@field executable? string
---@field extra_args? string[]
---@field resume? string
---@field no_session? boolean
---@field on_stderr? fun(data: string)

---@class OmpRpcProcess
---@field cwd string
---@field executable string
---@field extra_args string[]
---@field resume? string
---@field no_session boolean
---@field job? vim.SystemObj
---@field pid? integer
---@field url string
---@field mode string
---@field protocol_version integer
---@field max_reassembled_frame_bytes integer
---@field spawn_promise Promise<OmpRpcProcess>
---@field shutdown_promise Promise<boolean>
---@field pending table<string, Promise<any>>
---@field listeners fun(frame: table)[]
---@field stderr string[]
---@field private _next_id integer
---@field private _stdout_buffer string
---@field private _chunk? {id: string, count: integer, byte_length: integer, parts: string[]}
---@field private _stopping boolean
local Process = {}
Process.__index = Process

---@param opts OmpRpcProcessOpts
---@return OmpRpcProcess
function Process.new(opts)
  vim.validate('opts.cwd', opts.cwd, 'string')
  local config = require('omp.config')
  local rpc = config.rpc or {}
  return setmetatable({
    cwd = opts.cwd,
    executable = opts.executable or config.omp_executable or 'omp',
    extra_args = vim.deepcopy(opts.extra_args or rpc.extra_args or {}),
    resume = opts.resume,
    no_session = opts.no_session == true,
    job = nil,
    pid = nil,
    url = 'stdio://omp',
    mode = 'rpc',
    protocol_version = 1,
    max_reassembled_frame_bytes = 64 * 1024 * 1024,
    spawn_promise = Promise.new(),
    shutdown_promise = Promise.new(),
    pending = {},
    listeners = {},
    stderr = {},
    _next_id = 0,
    _stdout_buffer = '',
    _chunk = nil,
    _stopping = false,
    _on_stderr = opts.on_stderr,
  }, Process)
end

---@return string[]
function Process:_command()
  local command = { self.executable, '--mode', 'rpc', '--cwd', self.cwd }
  if self.resume then
    vim.list_extend(command, { '--resume', self.resume })
  elseif self.no_session then
    table.insert(command, '--no-session')
  end
  if not self.no_session then
    vim.list_extend(command, { '--extension', title_extension })
  end
  vim.list_extend(command, self.extra_args)
  return command
end

---@param reason any
function Process:_reject_pending(reason)
  for id, promise in pairs(self.pending) do
    self.pending[id] = nil
    promise:reject(reason)
  end
end

---@param frame table
function Process:_dispatch(frame)
  if frame.type == 'ready' then
    self.max_reassembled_frame_bytes = frame.maxReassembledFrameBytes or self.max_reassembled_frame_bytes
    if vim.tbl_contains(frame.supportedProtocolVersions or {}, 2) then
      self
        :_request_now({ type = 'negotiate_protocol', protocolVersion = 2 })
        :and_then(function(data)
          self.protocol_version = data and data.protocolVersion or 2
          self.spawn_promise:resolve(self)
        end)
        :catch(function(err)
          self.spawn_promise:reject('omp RPC v2 negotiation failed: ' .. tostring(err))
          self:shutdown()
        end)
    else
      self.spawn_promise:resolve(self)
    end
    return
  end

  if frame.type == 'response' and frame.id then
    local pending = self.pending[frame.id]
    if not pending then
      return
    end
    self.pending[frame.id] = nil
    if frame.success then
      pending:resolve(frame.data)
    else
      pending:reject(frame.error or ('omp RPC command failed: ' .. tostring(frame.command)))
    end
    return
  end

  for _, listener in ipairs(vim.deepcopy(self.listeners)) do
    local ok, err = pcall(listener, frame)
    if not ok then
      log.error('omp RPC listener failed: ' .. tostring(err))
    end
  end
end

---@param message string
function Process:_protocol_error(message)
  self._chunk = nil
  log.error('omp RPC protocol error: ' .. message)
end

---@param frame table
function Process:_handle_chunk(frame)
  if type(frame.chunkId) ~= 'string' or type(frame.index) ~= 'number' or type(frame.count) ~= 'number' then
    self:_protocol_error('invalid rpc_chunk metadata')
    return
  end
  if frame.index < 0 or frame.count < 1 or frame.index >= frame.count or type(frame.data) ~= 'string' then
    self:_protocol_error('invalid rpc_chunk bounds')
    return
  end

  if frame.index == 0 then
    if self._chunk then
      self:_protocol_error('interleaved rpc_chunk sequence')
      return
    end
    local byte_length = tonumber(frame.byteLength)
    if not byte_length or byte_length < 0 or byte_length > self.max_reassembled_frame_bytes then
      self:_protocol_error('rpc_chunk exceeds reassembly limit')
      return
    end
    self._chunk = { id = frame.chunkId, count = frame.count, byte_length = byte_length, parts = {} }
  end

  local chunk = self._chunk
  if not chunk or chunk.id ~= frame.chunkId or chunk.count ~= frame.count or frame.index ~= #chunk.parts then
    self:_protocol_error('interrupted rpc_chunk sequence')
    return
  end

  local ok, decoded = pcall(vim.base64.decode, frame.data)
  if not ok then
    self:_protocol_error('invalid rpc_chunk base64 data')
    return
  end
  table.insert(chunk.parts, decoded)
  if #chunk.parts ~= chunk.count then
    return
  end

  self._chunk = nil
  local payload = table.concat(chunk.parts)
  if #payload ~= chunk.byte_length then
    self:_protocol_error('rpc_chunk byte length mismatch')
    return
  end
  local decoded_ok, logical_frame = pcall(vim.json.decode, payload)
  if not decoded_ok or type(logical_frame) ~= 'table' then
    self:_protocol_error('invalid reassembled JSON frame')
    return
  end
  self:_dispatch(logical_frame)
end

---@param line string
function Process:_handle_line(line)
  if line == '' then
    return
  end
  local ok, frame = pcall(vim.json.decode, line)
  if not ok or type(frame) ~= 'table' then
    log.error('Ignoring malformed omp RPC frame: ' .. line)
    return
  end
  if frame.type == 'rpc_chunk' then
    self:_handle_chunk(frame)
  else
    if self._chunk then
      self:_protocol_error('rpc_chunk sequence interrupted by another frame')
    end
    self:_dispatch(frame)
  end
end

---@param data? string
function Process:_on_stdout(data)
  if not data or data == '' then
    return
  end
  self._stdout_buffer = self._stdout_buffer .. data
  while true do
    local newline = self._stdout_buffer:find('\n', 1, true)
    if not newline then
      break
    end
    local line = self._stdout_buffer:sub(1, newline - 1):gsub('\r$', '')
    self._stdout_buffer = self._stdout_buffer:sub(newline + 1)
    self:_handle_line(line)
  end
end

---@return Promise<OmpRpcProcess>
function Process:start()
  if self.job then
    return self.spawn_promise
  end

  local ok, job_or_error = pcall(vim.system, self:_command(), {
    cwd = self.cwd,
    text = true,
    stdin = true,
    stdout = function(err, data)
      if err then
        log.error('omp RPC stdout error: ' .. tostring(err))
        return
      end
      self:_on_stdout(data)
    end,
    stderr = function(_, data)
      if not data or data == '' then
        return
      end
      table.insert(self.stderr, data)
      if self._on_stderr then
        self._on_stderr(data)
      end
    end,
  }, function(result)
    self.pid = nil
    self.job = nil
    local reason = string.format('omp RPC process exited (code=%s, signal=%s)', result.code, result.signal)
    if not self.spawn_promise:is_resolved() then
      self.spawn_promise:reject(reason)
    end
    self:_reject_pending(reason)
    self.shutdown_promise:resolve(true)
  end)

  if not ok then
    self.spawn_promise:reject(job_or_error)
    return self.spawn_promise
  end

  self.job = job_or_error
  self.pid = job_or_error.pid
  return self.spawn_promise
end

---@param command table
---@return Promise<any>
function Process:_request_now(command)
  if not self.job then
    return Promise.new():reject('omp RPC process is not running')
  end
  self._next_id = self._next_id + 1
  local id = command.id or string.format('nvim-%d', self._next_id)
  command = vim.tbl_extend('force', command, { id = id })
  local promise = Promise.new()
  self.pending[id] = promise
  local ok, err = pcall(self.job.write, self.job, vim.json.encode(command) .. '\n')
  if not ok then
    self.pending[id] = nil
    promise:reject(err)
  end
  return promise
end

---@param command table
---@return Promise<any>
function Process:request(command)
  return self:start():and_then(function()
    return self:_request_now(command)
  end)
end
---@param frame table
---@return boolean, any
function Process:send(frame)
  if not self.job then
    return false, 'omp RPC process is not running'
  end
  return pcall(self.job.write, self.job, vim.json.encode(frame) .. '\n')
end

---@param listener fun(frame: table)
---@return fun()
function Process:subscribe(listener)
  table.insert(self.listeners, listener)
  return function()
    for i = #self.listeners, 1, -1 do
      if self.listeners[i] == listener then
        table.remove(self.listeners, i)
      end
    end
  end
end

---@return boolean
function Process:is_running()
  return self.job ~= nil and self.pid ~= nil
end

---@return Promise<boolean>
function Process:shutdown()
  if self.shutdown_promise:is_resolved() then
    return self.shutdown_promise
  end
  if not self.job then
    return self.shutdown_promise:resolve(true)
  end
  if not self._stopping then
    self._stopping = true
    local ok = pcall(self.job.write, self.job, nil)
    if not ok then
      pcall(self.job.kill, self.job, 15)
    end
  end
  return self.shutdown_promise
end

function Process:get_spawn_promise()
  return self.spawn_promise
end

function Process:get_shutdown_promise()
  return self.shutdown_promise
end

return Process
