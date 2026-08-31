local Process = require('omp.rpc.process')

local function fake_rpc()
  local original_system = vim.system
  local writes = {}
  local stdout
  local on_exit
  local exited = false

  vim.system = function(command, opts, exit_callback)
    stdout = opts.stdout
    on_exit = exit_callback
    local job = { pid = 4242 }
    function job:write(data)
      if data == nil then
        if not exited then
          exited = true
          vim.schedule(function()
            on_exit({ code = 0, signal = 0, stdout = '', stderr = '' })
          end)
        end
        return
      end
      local frame = vim.json.decode(data)
      table.insert(writes, frame)
      if frame.type == 'negotiate_protocol' then
        vim.schedule(function()
          stdout(nil, vim.json.encode({
            type = 'response',
            id = frame.id,
            command = frame.type,
            success = true,
            data = { protocolVersion = 2 },
          }) .. '\n')
        end)
      end
    end
    vim.schedule(function()
      stdout(nil, vim.json.encode({
        type = 'ready',
        protocolVersion = 1,
        supportedProtocolVersions = { 1, 2 },
        maxFrameBytes = 1048576,
        maxReassembledFrameBytes = 67108864,
      }) .. '\n')
    end)
    job.command = command
    return job
  end

  return {
    writes = writes,
    emit = function(frame)
      stdout(nil, vim.json.encode(frame) .. '\n')
    end,
    emit_line = function(line)
      stdout(nil, line .. '\n')
    end,
    restore = function()
      vim.system = original_system
    end,
  }
end

describe('omp RPC process', function()
  local rpc

  before_each(function()
    rpc = fake_rpc()
  end)

  after_each(function()
    rpc.restore()
  end)

  it('negotiates protocol v2 and correlates responses by id', function()
    local process = Process.new({ cwd = '/tmp/project', no_session = true })
    process:start():wait(1000)

    assert.equals(2, process.protocol_version)
    assert.same({ 'omp', '--mode', 'rpc', '--cwd', '/tmp/project', '--no-session' }, process.job.command)

    local request = process:request({ type = 'get_state' })
    vim.wait(1000, function()
      return #rpc.writes >= 2
    end)
    local sent = rpc.writes[#rpc.writes]
    rpc.emit({
      type = 'response',
      id = sent.id,
      command = 'get_state',
      success = true,
      data = { sessionId = 'session-1' },
    })

    assert.same({ sessionId = 'session-1' }, request:wait(1000))
    process:shutdown():wait(1000)
  end)

  it('reassembles v2 rpc_chunk frames before dispatch', function()
    local process = Process.new({ cwd = '/tmp/project', no_session = true })
    process:start():wait(1000)
    local received
    process:subscribe(function(frame)
      received = frame
    end)

    local logical = vim.json.encode({ type = 'notice', level = 'info', message = string.rep('x', 40) })
    local split = math.floor(#logical / 2)
    local chunks = { logical:sub(1, split), logical:sub(split + 1) }
    for index, chunk in ipairs(chunks) do
      rpc.emit_line(vim.json.encode({
        type = 'rpc_chunk',
        chunkId = 'chunk-1',
        index = index - 1,
        count = #chunks,
        byteLength = #logical,
        data = vim.base64.encode(chunk),
      }))
    end

    assert.same({ type = 'notice', level = 'info', message = string.rep('x', 40) }, received)
    process:shutdown():wait(1000)
  end)
end)
