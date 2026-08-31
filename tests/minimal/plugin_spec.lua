describe('omp.nvim plugin', function()
  local original_system
  local original_executable

  before_each(function()
    original_system = vim.system
    original_executable = vim.fn.executable
    vim.fn.executable = function()
      return 1
    end
    vim.system = function(_, _, callback)
      local result = { code = 0, signal = 0, stdout = 'omp/18.0.11\n', stderr = '' }
      if callback then
        vim.schedule(function()
          callback(result)
        end)
      end
      return {
        wait = function()
          return result
        end,
      }
    end
  end)

  after_each(function()
    vim.system = original_system
    vim.fn.executable = original_executable
  end)

  it('loads the plugin without errors', function()
    local omp = require('omp')
    assert.truthy(omp)
    assert.is_function(omp.setup)
  end)

  it('registers the Omp command with custom config', function()
    require('omp').setup({
      default_global_keymaps = false,
      keymap = { editor = { ['<leader>test'] = { 'toggle' } } },
    })

    assert.same({ 'toggle' }, require('omp.config').keymap.editor['<leader>test'])
    assert.equals(2, vim.fn.exists(':Omp'))
  end)
end)
