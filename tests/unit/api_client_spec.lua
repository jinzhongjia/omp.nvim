local api_client = require('omp.api_client')
local Promise = require('omp.promise')
local Process = require('omp.rpc.process')
local state = require('omp.state')

local function fake_process_factory(states)
  local created = {}
  local original_new = Process.new
  Process.new = function(opts)
    local process = {
      opts = opts,
      requests = {},
      running = false,
      shutdown_count = 0,
    }
    local state = states[#created + 1]
    function process:subscribe(listener)
      self.listener = listener
      return function() end
    end
    function process:start()
      self.running = true
      return Promise.new():resolve(self)
    end
    function process:is_running()
      return self.running
    end
    function process:request(command)
      table.insert(self.requests, command)
      if command.type == 'get_state' then
        return Promise.new():resolve(state)
      end
      return Promise.new():resolve({})
    end
    function process:send()
      return true
    end
    function process:shutdown()
      self.running = false
      self.shutdown_count = self.shutdown_count + 1
      return Promise.new():resolve(true)
    end
    table.insert(created, process)
    return process
  end
  return created, function()
    Process.new = original_new
  end
end

describe('OMP API client', function()
  it('creates a stdio RPC manager for the current workspace', function()
    local client = api_client.new('/tmp/project')
    assert.equals('/tmp/project', client.cwd)
    assert.equals('stdio://omp', client.url)
    assert.same({}, client.processes)
  end)

  it('groups omp models into the provider shape consumed by the picker', function()
    local client = api_client.new('/tmp/project')
    client._control_request = function(_, command)
      assert.equals('get_available_models', command.type)
      return Promise.new():resolve({
        models = {
          { provider = 'openai', id = 'gpt-test', name = 'GPT Test', contextWindow = 1000, maxTokens = 100 },
          { provider = 'anthropic', id = 'claude-test', name = 'Claude Test', reasoning = true },
        },
      })
    end

    local result = client:list_providers():wait(1000)
    assert.equals(2, #result.providers)
    assert.equals('anthropic', result.providers[1].id)
    assert.equals('Claude Test', result.providers[1].models['claude-test'].name)
    assert.is_true(result.providers[1].models['claude-test'].reasoning)
  end)

  it('routes extension UI question answers back to the owning process', function()
    local client = api_client.new('/tmp/project')
    local sent
    local process = {
      send = function(_, frame)
        sent = frame
        return true
      end,
    }
    local adapter = {
      permissions = {},
      questions = {
        ['question-1'] = {
          id = 'question-1',
          sessionID = 'session-1',
          metadata = { method = 'select', options = { 'A', 'B' } },
        },
      },
    }
    client.adapters[process] = adapter

    client:reply_question('question-1', { { 'B' } }):wait(1000)
    assert.same({ type = 'extension_ui_response', id = 'question-1', value = 'B' }, sent)
    assert.is_nil(adapter.questions['question-1'])
  end)

  it('starts one distinct omp process for each opened session', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
      {
        sessionId = 'session-2',
        sessionFile = '/tmp/project/session-2.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')

    local first = client:create_session(false):wait(1000)
    local second = client:create_session(false):wait(1000)

    assert.equals(2, #created)
    assert.is_not_equal(created[1], created[2])
    assert.equals(created[1], client.processes[first.id])
    assert.equals(created[2], client.processes[second.id])
    assert.equals('/tmp/project', created[1].opts.cwd)
    assert.is_nil(created[1].opts.resume)
    restore()
  end)

  it('resumes a historical session once and reuses its running process', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/original/session-1.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/current')
    client.sessions['session-1'] = {
      id = 'session-1',
      title = 'Existing',
      directory = '/tmp/original',
      workspace = '/tmp/original',
      sessionPath = '/tmp/original/session-1.jsonl',
      time = { created = 1, updated = 1 },
    }

    local first = client:_ensure_session_process('session-1'):wait(1000)
    local second = client:_ensure_session_process('session-1'):wait(1000)

    assert.equals(1, #created)
    assert.equals(first, second)
    assert.equals('/tmp/original', created[1].opts.cwd)
    assert.equals('/tmp/original/session-1.jsonl', created[1].opts.resume)
    restore()
  end)

  it('recreates the control process after an unexpected exit', function()
    local created, restore = fake_process_factory({ {}, {} })
    local client = api_client.new('/tmp/project')
    client:start():wait(1000)
    local first = client.control
    first.running = false

    client:list_providers():wait(1000)

    assert.equals(2, #created)
    assert.is_not_equal(first, client.control)
    assert.is_nil(client.adapters[first])
    client:shutdown():wait(1000)
    restore()
  end)

  it('uses the state returned during session spawn without a duplicate request', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
      },
    })
    local client = api_client.new('/tmp/project')

    client:create_session(false):wait(1000)

    local get_state_count = 0
    for _, request in ipairs(created[1].requests) do
      if request.type == 'get_state' then
        get_state_count = get_state_count + 1
      end
    end
    assert.equals(1, get_state_count)
    client:shutdown():wait(1000)
    restore()
  end)

  it('shuts down the control process and every opened session process', function()
    local created, restore = fake_process_factory({
      {},
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
      {
        sessionId = 'session-2',
        sessionFile = '/tmp/project/session-2.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')

    client:start():wait(1000)
    client:create_session(false):wait(1000)
    client:create_session(false):wait(1000)
    client:shutdown():wait(1000)

    assert.equals(3, #created)
    for _, process in ipairs(created) do
      assert.equals(1, process.shutdown_count)
      assert.is_false(process.running)
    end
    restore()
  end)

  it('uses a no-session process for ephemeral sessions and releases it', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'quick-1',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')

    local session = client:create_ephemeral_session('Quick chat'):wait(1000)
    assert.is_true(session.ephemeral)
    assert.is_true(created[1].opts.no_session)
    assert.is_nil(created[1].opts.resume)

    client:release_session(session.id):wait(1000)
    assert.is_nil(client.processes[session.id])
    assert.equals(1, created[1].shutdown_count)
    restore()
  end)

  it('resolves a run waiter only when that session becomes idle', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')
    local session = client:create_session(false):wait(1000)

    client:create_message(session.id, { parts = { { type = 'text', text = 'hello' } } }):wait(1000)
    local waiter = client:wait_for_idle(session.id)
    assert.is_false(waiter:is_resolved())

    client:_emit({ type = 'session.idle', properties = { sessionID = session.id } })
    assert.is_true(waiter:wait(1000))
    client:release_session(session.id):wait(1000)
    restore()
  end)

  it('resolves local-only prompts from prompt_result frames', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'quick-1',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')
    local session = client:create_ephemeral_session('Quick chat'):wait(1000)
    client:create_message(session.id, { parts = { { type = 'text', text = '/help' } } }):wait(1000)

    local prompt = created[1].requests[#created[1].requests]
    local waiter = client:wait_for_idle(session.id)
    assert.is_false(waiter:is_resolved())
    created[1].listener({ type = 'prompt_result', id = prompt.id, agentInvoked = false })

    assert.is_true(waiter:wait(1000))
    assert.is_nil(client.prompt_sessions[prompt.id])
    client:release_session(session.id):wait(1000)
    restore()
  end)

  it('syncs the RPC thinking level into the active session UI state', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
        thinkingLevel = 'high',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')
    local session = client:create_session(false):wait(1000)
    assert.equals('high', session.thinkingLevel)

    state.session.set_active(session)
    state.model.set_thinking_level(session.thinkingLevel)
    created[1].listener({ type = 'thinking_level_changed', thinkingLevel = 'xhigh' })

    assert.equals('xhigh', client.sessions[session.id].thinkingLevel)
    assert.equals('xhigh', state.current_thinking_level)
    state.session.clear_active()
    client:release_session(session.id):wait(1000)
    restore()
  end)

  it('leaves first-prompt title generation to OMP', function()
    local created, restore = fake_process_factory({
      {
        sessionId = 'session-1',
        sessionFile = '/tmp/project/session-1.jsonl',
        model = { provider = 'openai', id = 'gpt-test' },
      },
    })
    local client = api_client.new('/tmp/project')
    local session = client:create_session(false):wait(1000)

    client
      :create_message(session.id, {
        parts = {
          { type = 'text', text = 'context', synthetic = true },
          { type = 'text', text = 'Fix this' .. string.char(10) .. 'now' },
        },
      })
      :wait(1000)

    local prompt_requests = {}
    for _, request in ipairs(created[1].requests) do
      if request.type == 'prompt' then
        table.insert(prompt_requests, request)
      end
      assert.is_not_equal('set_session_name', request.type)
    end
    assert.equals(1, #prompt_requests)
    local expected = '<context>'
      .. string.char(10)
      .. 'context'
      .. string.char(10)
      .. '</context>'
      .. string.char(10, 10)
      .. 'Fix this'
      .. string.char(10)
      .. 'now'
    assert.equals(expected, prompt_requests[1].message)
    assert.equals('New session', client.sessions[session.id].title)
    client:release_session(session.id):wait(1000)
    restore()
  end)

  it('keeps persisted sessions with an empty OMP title visible', function()
    local original_home = vim.uv.os_homedir
    local home = vim.fn.tempname()
    local cwd = home .. '/project'
    local session_dir = home .. '/.omp/agent/sessions/-project'
    vim.fn.mkdir(cwd, 'p')
    vim.fn.mkdir(session_dir, 'p')
    vim.fn.writefile({
      vim.json.encode({ type = 'title', title = '' }),
      vim.json.encode({
        type = 'session',
        id = 'empty-title-session',
        timestamp = '2026-09-01T12:00:00.000Z',
        cwd = cwd,
      }),
    }, session_dir .. '/session.jsonl')
    vim.uv.os_homedir = function()
      return home
    end

    local sessions = api_client.new(cwd):list_sessions():wait(1000)

    vim.uv.os_homedir = original_home
    vim.fn.delete(home, 'rf')
    assert.equals(1, #sessions)
    assert.equals('empty-title-session', sessions[1].id)
    assert.equals('New session', sessions[1].title)
  end)

  it('refreshes a cached New session title from OMP persistence', function()
    local original_home = vim.uv.os_homedir
    local home = vim.fn.tempname()
    local cwd = home .. '/project'
    local session_dir = home .. '/.omp/agent/sessions/-project'
    vim.fn.mkdir(cwd, 'p')
    vim.fn.mkdir(session_dir, 'p')
    vim.fn.writefile({
      vim.json.encode({ type = 'title', title = 'Generated title' }),
      vim.json.encode({
        type = 'session',
        id = 'generated-title-session',
        timestamp = '2026-09-01T12:00:00.000Z',
        cwd = cwd,
      }),
    }, session_dir .. '/session.jsonl')
    vim.uv.os_homedir = function()
      return home
    end
    local client = api_client.new(cwd)
    local live = {
      id = 'generated-title-session',
      title = 'New session',
      directory = cwd,
      workspace = cwd,
      time = { created = 0, updated = 0 },
    }
    client.sessions[live.id] = live

    local sessions = client:list_sessions():wait(1000)

    vim.uv.os_homedir = original_home
    vim.fn.delete(home, 'rf')
    assert.equals(1, #sessions)
    assert.equals('Generated title', sessions[1].title)
    assert.equals('Generated title', live.title)
  end)

  it('publishes an asynchronous native title update into the live session', function()
    local original_defer = vim.defer_fn
    local home = vim.fn.tempname()
    local cwd = home .. '/project'
    local session_path = home .. '/session.jsonl'
    vim.fn.mkdir(cwd, 'p')
    vim.fn.writefile({
      vim.json.encode({ type = 'title', title = '' }),
      vim.json.encode({
        type = 'session',
        id = 'async-title-session',
        timestamp = '2026-09-01T12:00:00.000Z',
        cwd = cwd,
      }),
    }, session_path)
    local deferred
    vim.defer_fn = function(callback, timeout)
      assert.equals(250, timeout)
      deferred = callback
    end
    local client = api_client.new(cwd)
    local live = {
      id = 'async-title-session',
      title = 'New session',
      directory = cwd,
      workspace = cwd,
      sessionPath = session_path,
      time = { created = 0, updated = 0 },
    }
    client.sessions[live.id] = live
    client.processes[live.id] = {}
    local updated
    table.insert(client.listeners, function(event)
      if event.type == 'session.updated' then
        updated = event.properties.info
      end
    end)

    client:_poll_session_title(live.id)
    vim.fn.writefile({
      vim.json.encode({ type = 'title', title = 'Generated asynchronously' }),
      vim.json.encode({
        type = 'session',
        id = live.id,
        timestamp = '2026-09-01T12:00:00.000Z',
        cwd = cwd,
      }),
    }, session_path)
    deferred()

    vim.defer_fn = original_defer
    vim.fn.delete(home, 'rf')
    assert.equals('Generated asynchronously', live.title)
    assert.equals(live, updated)
    assert.is_nil(client.title_poll_tokens[live.id])
  end)
end)
