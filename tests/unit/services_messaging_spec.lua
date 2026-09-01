local loaded = rawget(_G, '__omp_service_spec_loaded') or {}
_G.__omp_service_spec_loaded = loaded
if loaded.services_messaging_spec then
  return
end
loaded.services_messaging_spec = true

local messaging = require('omp.services.messaging')
local session_runtime = require('omp.services.session_runtime')
local context = require('omp.context')
local state = require('omp.state')
local Promise = require('omp.promise')
local stub = require('luassert.stub')
local assert = require('luassert')
local support = require('tests.unit.services_spec_support')

describe('omp.services.messaging', function()
  before_each(function()
    support.mock_api_client()
  end)

  it('sends a message via api_client', function()
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active({ id = 'sess1' })

    local create_called = false
    local orig = state.api_client.create_message
    state.api_client.create_message = function(_, sid, params)
      create_called = true
      assert.equal('sess1', sid)
      assert.truthy(params.parts)
      return Promise.new():resolve({ id = 'm1' })
    end

    messaging.send_message('hello world')
    vim.wait(50, function()
      return create_called
    end)
    assert.True(create_called)
    state.api_client.create_message = orig
  end)

  it('returns false when active session is missing', function()
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active(nil)

    local sent = messaging.send_message('hello world'):wait()
    assert.is_false(sent)
  end)

  it('persists context, model, and thinking level when sending', function()
    local original = state.api_client.create_message
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active({ id = 'sess1' })

    local captured
    state.api_client.create_message = function(_, session_id, params)
      assert.equal('sess1', session_id)
      captured = params
      return Promise.new():resolve({ id = 'm1' })
    end

    messaging
      .send_message('hello world', {
        context = { current_file = { enabled = false } },
        model = 'test/model',
        thinking_level = 'high',
      })
      :wait()

    assert.same({ current_file = { enabled = false } }, state.current_context_config)
    assert.equal('test/model', state.current_model)
    assert.equal('high', state.current_thinking_level)
    assert.same({ providerID = 'test', modelID = 'model' }, captured.model)
    assert.equal('high', captured.thinking_level)
    state.api_client.create_message = original
  end)

  it('increments and decrements user_message_count correctly', function()
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active({ id = 'sess1' })
    state.session.set_user_message_count({})

    local count_before = state.user_message_count['sess1'] or 0
    local count_during = nil

    local orig = state.api_client.create_message
    state.api_client.create_message = function(_, sid, params)
      count_during = state.user_message_count['sess1']
      return Promise.new():resolve({
        id = 'm1',
        info = { id = 'm1' },
        parts = {},
      })
    end

    messaging.send_message('hello world'):wait()

    local count_after = state.user_message_count['sess1'] or 0

    assert.equal(0, count_before)
    assert.equal(1, count_during)
    assert.equal(0, count_after)

    state.api_client.create_message = orig
  end)

  it('decrements user_message_count on error', function()
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active({ id = 'sess1' })
    state.session.set_user_message_count({})

    local original_context = vim.deepcopy(context.get_context())
    context.get_context().mentioned_files = { '/tmp/attached.lua' }
    context.get_context().selections = {
      {
        file = { path = '/tmp/attached.lua', name = 'attached.lua', extension = 'lua' },
        content = 'selected',
        lines = '1, 2',
      },
    }

    local count_before = state.user_message_count['sess1'] or 0
    local count_during = nil

    local orig = state.api_client.create_message
    state.api_client.create_message = function(_, sid, params)
      count_during = state.user_message_count['sess1']
      return Promise.new():reject('Test error')
    end

    local orig_cancel = session_runtime.cancel
    stub(session_runtime, 'cancel').returns(Promise.new():resolve(nil))

    messaging.send_message('hello world'):wait()

    local count_after = state.user_message_count['sess1'] or 0

    assert.equal(0, count_before)
    assert.equal(1, count_during)
    assert.equal(0, count_after)
    assert.same({}, context.get_context().mentioned_files)
    assert.same({}, context.get_context().selections)

    state.api_client.create_message = orig
    session_runtime.cancel = orig_cancel
    for key, value in pairs(original_context) do
      context.get_context()[key] = value
    end
  end)

  it('clears attachments before the request is sent', function()
    state.ui.set_windows({ mock = 'windows' })
    state.session.set_active({ id = 'sess1' })

    local original_context = vim.deepcopy(context.get_context())
    context.get_context().mentioned_files = { '/tmp/attached.lua' }
    context.get_context().selections = {
      {
        file = { path = '/tmp/attached.lua', name = 'attached.lua', extension = 'lua' },
        content = 'selected',
        lines = '1, 2',
      },
    }

    local observed_context
    local original_create_message = state.api_client.create_message
    state.api_client.create_message = function(_, _session_id, _params)
      observed_context = vim.deepcopy(context.get_context())
      return Promise.new():resolve({ info = { id = 'm1' }, parts = {} })
    end

    messaging.send_message('hello world'):wait()

    assert.same({}, observed_context.mentioned_files)
    assert.same({}, observed_context.selections)

    state.api_client.create_message = original_create_message
    for key, value in pairs(original_context) do
      context.get_context()[key] = value
    end
  end)

  it('clears sent attachments from the active context', function()
    state.session.set_active({ id = 'sess1' })

    local original_context = vim.deepcopy(context.get_context())
    local sent_context = {
      current_file = nil,
      cursor_data = nil,
      linter_errors = nil,
      mentioned_files = { '/tmp/attached.lua' },
      mentioned_subagents = {},
      selections = {
        {
          file = { path = '/tmp/attached.lua', name = 'attached.lua', extension = 'lua' },
          content = 'selected',
          lines = '1, 2',
        },
      },
    }
    for key, value in pairs(sent_context) do
      context.get_context()[key] = value
    end

    local delta_stub = stub(context, 'delta_context')
    messaging.after_run('hello')

    assert.same({}, context.get_context().mentioned_files)
    assert.same({}, context.get_context().selections)

    delta_stub:revert()
    for key, value in pairs(original_context) do
      context.get_context()[key] = value
    end
  end)
end)
