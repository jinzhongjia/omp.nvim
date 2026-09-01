local agent_model = require('omp.services.agent_model')
local config_file = require('omp.config_file')
local model_state = require('omp.model_state')
local state = require('omp.state')
local Promise = require('omp.promise')
local stub = require('luassert.stub')

local function resolved(value)
  return Promise.new():resolve(value)
end

describe('omp.services.agent_model', function()
  before_each(function()
    state.model.clear()
    state.renderer.set_messages({})
  end)

  after_each(function()
    pcall(function()
      config_file.get_omp_config:revert()
    end)
    pcall(function()
      config_file.get_model_info:revert()
    end)
    pcall(function()
      model_state.set_thinking_level:revert()
    end)
  end)

  it('keeps the current user-selected model', function()
    state.model.set_model('openai/current')
    stub(config_file, 'get_omp_config').returns(resolved({ model = 'openai/configured' }))

    assert.equals('openai/current', agent_model.initialize_current_model():wait(1000))
  end)

  it('loads the configured model when none is selected', function()
    stub(config_file, 'get_omp_config').returns(resolved({ model = 'anthropic/claude-test' }))

    assert.equals('anthropic/claude-test', agent_model.initialize_current_model():wait(1000))
    assert.equals('anthropic/claude-test', state.current_model)
  end)

  it('restores the latest model from session messages', function()
    state.renderer.set_messages({
      { info = { role = 'assistant', providerID = 'openai', modelID = 'older' }, parts = {} },
      { info = { role = 'assistant', providerID = 'anthropic', modelID = 'latest' }, parts = {} },
    })

    local model = agent_model.initialize_current_model({ restore_from_messages = true }):wait(1000)
    assert.equals('anthropic/latest', model)
    assert.equals('anthropic/latest', state.current_model)
  end)

  it('cycles through OMP thinking levels', function()
    state.model.set_model('openai/reasoning-model')
    stub(config_file, 'get_model_info').returns({ reasoning = true })
    local save = stub(model_state, 'set_thinking_level')

    agent_model.cycle_thinking_level():wait(1000)
    assert.equals('off', state.current_thinking_level)
    assert.stub(save).was_called_with('openai', 'reasoning-model', 'off')

    agent_model.cycle_thinking_level():wait(1000)
    assert.equals('minimal', state.current_thinking_level)
  end)

  it('does not set a thinking level for non-reasoning models', function()
    state.model.set_model('openai/plain-model')
    stub(config_file, 'get_model_info').returns({ reasoning = false })

    agent_model.cycle_thinking_level():wait(1000)
    assert.is_nil(state.current_thinking_level)
  end)
end)
