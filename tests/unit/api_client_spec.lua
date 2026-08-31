local api_client = require('omp.api_client')
local Promise = require('omp.promise')
local Process = require('omp.rpc.process')

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
    assert.same({ low = {}, medium = {}, high = {} }, result.providers[1].models['claude-test'].variants)
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
end)
