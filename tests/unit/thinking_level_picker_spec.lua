local picker = require('omp.thinking_level_picker')
local base_picker = require('omp.ui.base_picker')
local config_file = require('omp.config_file')
local model_state = require('omp.model_state')
local state = require('omp.state')
local stub = require('luassert.stub')

local function revert(target, name)
  pcall(function()
    target[name]:revert()
  end)
end

describe('OMP thinking level picker', function()
  before_each(function()
    state.model.clear()
    state.model.set_model('openai/reasoning-model')
  end)

  after_each(function()
    revert(config_file, 'get_model_info')
    revert(model_state, 'get_thinking_level')
    revert(model_state, 'set_thinking_level')
    revert(base_picker, 'pick')
  end)

  it('offers every RPC thinking level and persists the selection', function()
    stub(config_file, 'get_model_info').returns({ reasoning = true })
    stub(model_state, 'get_thinking_level').returns(nil)
    local save = stub(model_state, 'set_thinking_level')
    local captured
    stub(base_picker, 'pick').invokes(function(opts)
      captured = opts
      opts.callback({ name = 'xhigh', value = 'xhigh' })
    end)

    picker.select(function() end)

    assert.equals('Select thinking level', captured.title)
    assert.same(
      { 'default', 'off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max' },
      vim.tbl_map(function(item)
        return item.name
      end, captured.items)
    )
    assert.equals('xhigh', state.current_thinking_level)
    assert.stub(save).was_called_with('openai', 'reasoning-model', 'xhigh')
  end)

  it('does not open for a model without reasoning support', function()
    stub(config_file, 'get_model_info').returns({ reasoning = false })
    local open = stub(base_picker, 'pick')
    local selection = 'unset'

    picker.select(function(value)
      selection = value
    end)

    assert.is_nil(selection)
    assert.stub(open).was_not_called()
  end)
end)
