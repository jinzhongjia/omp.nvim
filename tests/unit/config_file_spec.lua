local config_file = require('omp.config_file')
local Promise = require('omp.promise')
local state = require('omp.state')

describe('OMP config adapter', function()
  local original_api_client

  before_each(function()
    original_api_client = state.api_client
    config_file.config_promise = nil
    config_file.project_promise = nil
    config_file.providers_promise = nil
  end)

  after_each(function()
    state.jobs.set_api_client(original_api_client)
  end)

  it('loads RPC config and project lazily', function()
    local get_config_called, get_project_called = false, false
    local cfg = { model = 'openai/test', agent = { default = { mode = 'primary' } } }
    state.jobs.set_api_client({
      get_config = function()
        get_config_called = true
        return Promise.new():resolve(cfg)
      end,
      get_current_project = function()
        get_project_called = true
        return Promise.new():resolve({ id = 'project-1' })
      end,
    })

    assert.is_nil(config_file.config_promise)
    assert.same(cfg, config_file.get_omp_config():wait(1000))
    assert.is_true(get_config_called)
    assert.same({ id = 'project-1' }, config_file.get_omp_project():wait(1000))
    assert.is_true(get_project_called)
  end)

  it('does not synthesize opencode subagents', function()
    assert.same({}, config_file.get_subagents():wait(1000))
  end)
end)
