-- Tests for the OMP session picker preview.

local session_picker = require('omp.ui.session_picker')
local state = require('omp.state')
local store = require('omp.state.store')
local Promise = require('omp.promise')
local stub = require('luassert.stub')
local assert = require('luassert')
local support = require('tests.unit.services_spec_support')

describe('omp.ui.session_picker', function()
  describe('preview_fn contract', function()
    local original_api_client
    local original_pick

    before_each(function()
      original_api_client = state.api_client
      local base_picker = require('omp.ui.base_picker')
      original_pick = base_picker.pick
    end)

    after_each(function()
      state.jobs.set_api_client(original_api_client)
      require('omp.ui.base_picker').pick = original_pick
    end)

    it('writes through the backend-neutral preview target', function()
      local base_picker = require('omp.ui.base_picker')
      local captured_opts
      base_picker.pick = function(opts)
        captured_opts = opts
        return true
      end

      state.jobs.set_api_client({
        list_messages = function()
          return Promise.new():resolve({})
        end,
      })

      session_picker.pick({ { id = 's1', title = 'Session', time = { updated = 'now' } } }, function() end)
      assert.is_table(captured_opts)

      local writes = {}
      local target = {
        get_bufnr = function()
          return nil
        end,
        is_valid = function()
          return true
        end,
        set_lines = function(_, lines)
          writes[#writes + 1] = lines
        end,
        with_window = function() end,
      }

      captured_opts.preview_fn({ id = 's1' }, target)
      vim.wait(100, function()
        return #writes >= 2
      end)

      assert.are.same({ 'Loading...' }, writes[1])
      assert.are.same({ 'No messages or failed to load' }, writes[2])
    end)

    it('formats preview parts with non-interactive formatter context', function()
      local base_picker = require('omp.ui.base_picker')
      local formatter = require('omp.ui.formatter')
      local Output = require('omp.ui.output')
      local captured_opts
      local contexts = {}
      local format_stub = stub(formatter, 'format_part').invokes(function(_, _, _, context)
        contexts[#contexts + 1] = context
        local output = Output.new()
        output:add_line('preview part')
        return output
      end)

      base_picker.pick = function(opts)
        captured_opts = opts
        return true
      end

      state.jobs.set_api_client({
        list_messages = function()
          return Promise.new():resolve({
            {
              info = { id = 'msg_1', role = 'assistant', sessionID = 'ses_1' },
              parts = {
                { id = 'part_1', type = 'text', text = 'See `src/main.lua`.' },
              },
            },
          })
        end,
      })

      session_picker.pick({ { id = 's1', title = 'Session', time = { updated = 'now' } } }, function() end)

      local target = {
        get_bufnr = function()
          return nil
        end,
        is_valid = function()
          return true
        end,
        set_lines = function() end,
        with_window = function() end,
      }

      captured_opts.preview_fn({ id = 's1' }, target)
      vim.wait(100, function()
        return #contexts == 1
      end)

      format_stub:revert()

      assert.equal(1, #contexts)
      assert.is_false(contexts[1].interactive)
      assert.is_nil(contexts[1].get_child_parts)
      assert.is_nil(contexts[1].symbol_cycle)
    end)

    it('does not resolve rendered targets while formatting preview parts', function()
      local base_picker = require('omp.ui.base_picker')
      local original_symbol_snapshot = package.loaded['omp.ui.symbol_snapshot']
      local captured_opts
      local writes = {}
      local bufnr = vim.api.nvim_create_buf(false, true)

      package.loaded['omp.ui.symbol_snapshot'] = {
        new_cycle = function()
          error('preview formatting must not create a symbol cycle')
        end,
        targets_for_token = function()
          error('preview formatting must not resolve symbol targets')
        end,
      }

      base_picker.pick = function(opts)
        captured_opts = opts
        return true
      end

      state.jobs.set_api_client({
        list_messages = function()
          return Promise.new():resolve({
            {
              info = { id = 'msg_1', role = 'assistant', sessionID = 'ses_1' },
              parts = {
                { id = 'part_1', type = 'text', text = 'See `src/main.lua` then call foo.' },
              },
            },
          })
        end,
      })

      session_picker.pick({ { id = 's1', title = 'Session', time = { updated = 'now' } } }, function() end)

      local target = {
        get_bufnr = function()
          return bufnr
        end,
        is_valid = function()
          return true
        end,
        set_lines = function(_, lines)
          writes[#writes + 1] = lines
        end,
        with_window = function(_, fn)
          fn()
        end,
      }

      captured_opts.preview_fn({ id = 's1' }, target)
      vim.wait(100, function()
        return #writes >= 2
      end)

      package.loaded['omp.ui.symbol_snapshot'] = original_symbol_snapshot
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })

      assert.is_truthy(table.concat(writes[#writes], '\n'):find('src/main.lua', 1, true))
      assert.is_nil(table.concat(writes[#writes], '\n'):find('%[render error%]'))
    end)
  end)
end)
