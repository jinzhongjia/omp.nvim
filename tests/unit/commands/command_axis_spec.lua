local assert = require('luassert')

local function clear_command_packages()
  package.loaded['omp.commands'] = nil
  package.loaded['omp.commands.parse'] = nil
  package.loaded['omp.commands.dispatch'] = nil
  package.loaded['omp.commands.complete'] = nil

  package.loaded['omp.commands.handlers.window'] = nil
  package.loaded['omp.commands.handlers.workflow'] = nil
  package.loaded['omp.commands.handlers.session'] = nil
  package.loaded['omp.commands.handlers.diff'] = nil
  package.loaded['omp.commands.handlers.surface'] = nil
  package.loaded['omp.commands.handlers.agent'] = nil
  package.loaded['omp.commands.handlers.permission'] = nil
end

describe('commands axis contract', function()
  local original_notify

  before_each(function()
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    clear_command_packages()
  end)

  it('parse returns ParsedIntent without execute injection', function()
    local parse = require('omp.commands.parse')

    local parsed = parse.command({ args = 'toggle foo bar', range = 0 }, {
      toggle = { desc = 'toggle' },
    })

    assert.is_true(parsed.ok)
    assert.same('toggle', parsed.intent.name)
    assert.same({ 'foo', 'bar' }, parsed.intent.args)
    assert.is_nil(parsed.intent.execute)
    assert.same('toggle foo bar', parsed.intent.source.raw_args)
    assert.same({ 'toggle', 'foo', 'bar' }, parsed.intent.source.argv)
  end)

  it('binds ActionContext only in init and dispatches via execute(ctx)', function()
    local captured_ctx

    package.loaded['omp.commands.parse'] = {
      command = function()
        return {
          ok = true,
          intent = {
            name = 'toggle',
            args = { 'a' },
            range = nil,
            source = { raw_args = 'toggle a', argv = { 'toggle', 'a' } },
          },
        }
      end,
    }

    package.loaded['omp.commands.dispatch'] = {
      execute = function(ctx)
        captured_ctx = ctx
        return { ok = true, result = 'done' }
      end,
    }

    package.loaded['omp.commands.complete'] = {
      complete_command = function() return {} end,
    }

    local toggle_execute = function(args)
      return args[1]
    end

    package.loaded['omp.commands.handlers.window'] = {
      command_defs = {
        toggle = {
          desc = 'toggle',
          execute = toggle_execute,
        },
      },
    }
    package.loaded['omp.commands.handlers.workflow'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.session'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.diff'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.surface'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.agent'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.permission'] = { command_defs = {} }

    local commands = require('omp.commands')
    local result = commands.execute_command_opts({ args = 'toggle a', range = 0 })

    assert.equal('done', result)
    assert.same('toggle', captured_ctx.intent.name)
    assert.same({ 'a' }, captured_ctx.args)
    assert.equal(toggle_execute, captured_ctx.execute)
  end)

  it('binds run/review/quick_chat intents through one axis', function()
    package.loaded['omp.commands.handlers.window'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.workflow'] = {
      command_defs = {
        run = {
          desc = 'run',
          execute = function(args)
            return 'run:' .. table.concat(args or {}, ',')
          end,
        },
        review = {
          desc = 'review',
          execute = function(args)
            return 'review:' .. table.concat(args or {}, ',')
          end,
        },
        quick_chat = {
          desc = 'quick',
          execute = function(args)
            return 'quick_chat:' .. table.concat(args or {}, ',')
          end,
        },
      },
    }
    package.loaded['omp.commands.handlers.session'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.diff'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.surface'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.agent'] = { command_defs = {} }
    package.loaded['omp.commands.handlers.permission'] = { command_defs = {} }

    local commands = require('omp.commands')
    local dispatch = require('omp.commands.dispatch')
    dispatch.reset_hooks_for_test()

    local matrix = {
      { name = 'run', args = { 'hello' }, expected = 'run:hello' },
      { name = 'review', args = { 'HEAD~1..HEAD' }, expected = 'review:HEAD~1..HEAD' },
      { name = 'quick_chat', args = { 'summarize' }, expected = 'quick_chat:summarize' },
    }

    for _, row in ipairs(matrix) do
      local argv = { row.name }
      for _, arg in ipairs(row.args) do
        table.insert(argv, arg)
      end

      local parsed = {
        ok = true,
        intent = {
          name = row.name,
          args = row.args,
          range = nil,
          source = {
            raw_args = table.concat(argv, ' '),
            argv = vim.deepcopy(argv),
          },
        },
      }

      local ctx = commands.bind_action_context(parsed)
      local result = dispatch.execute(ctx)

      assert.is_true(result.ok)
      assert.same(row.name, result.intent.name)
      assert.same(row.expected, result.result)
    end
  end)
end)
