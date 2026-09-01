local assert = require('luassert')
local Promise = require('omp.promise')

describe('slash command mapping', function()
  local slash
  local original_notify
  local captured_parsed
  local captured_ctx
  local user_commands

  before_each(function()
    original_notify = vim.notify
    captured_parsed = {}
    captured_ctx = {}
    user_commands = nil

    package.loaded['omp.commands'] = {
      get_commands = function()
        return {
          agent = { desc = 'Agent', nargs = '*' },
          review = { desc = 'Review', nargs = '*' },
          command = { desc = 'Command', nargs = '*' },
        }
      end,
      build_parsed_intent = function(name, args)
        local argv = { name }
        for _, arg in ipairs(args or {}) do
          table.insert(argv, tostring(arg))
        end
        return {
          ok = true,
          intent = {
            name = name,
            args = args or {},
            range = nil,
            source = {
              raw_args = table.concat(argv, ' '),
              argv = argv,
            },
          },
        }
      end,
      execute_parsed_intent = function(parsed)
        table.insert(captured_parsed, vim.deepcopy(parsed))
        local ctx = {
          parsed = parsed,
          intent = parsed.intent,
          args = parsed.intent.args,
          range = parsed.intent.range,
          execute = function() end,
        }
        table.insert(captured_ctx, ctx)
        return 'ok'
      end,
    }

    package.loaded['omp.config_file'] = {
      get_user_commands = function()
        local p = Promise.new()
        p:resolve(user_commands)
        return p
      end,
    }

    package.loaded['omp.log'] = {
      notify = function() end,
    }

    vim.notify = function() end

    package.loaded['omp.commands.slash'] = nil
    slash = require('omp.commands.slash')
  end)

  after_each(function()
    vim.notify = original_notify

    package.loaded['omp.commands'] = nil
    package.loaded['omp.commands.slash'] = nil
    package.loaded['omp.config_file'] = nil
    package.loaded['omp.log'] = nil
  end)

  it('maps builtin /models to ParsedIntent and dispatches', function()
    local slash_commands = slash.get_commands():wait()
    local cmd
    for _, entry in ipairs(slash_commands) do
      if entry.slash_cmd == '/models' then
        cmd = entry
        break
      end
    end

    assert.truthy(cmd)
    cmd.fn({})

    assert.equal(1, #captured_parsed)
    assert.same('models', captured_parsed[1].intent.name)
    assert.same({}, captured_parsed[1].intent.args)
    assert.same({ 'models' }, captured_parsed[1].intent.source.argv)
    assert.equal('models', captured_parsed[1].intent.source.raw_args)
    assert.equal(1, #captured_ctx)
  end)

  it('maps user slash command to command intent and dispatches', function()
    user_commands = {
      build = { description = 'Build project' },
    }

    local slash_commands = slash.get_commands():wait()
    local cmd
    for _, entry in ipairs(slash_commands) do
      if entry.slash_cmd == '/build' then
        cmd = entry
        break
      end
    end

    assert.truthy(cmd)
    cmd.fn({ '--fast' })

    assert.equal(1, #captured_parsed)
    assert.same('command', captured_parsed[1].intent.name)
    assert.same({ 'build', '--fast' }, captured_parsed[1].intent.args)
    assert.same({ 'command', 'build', '--fast' }, captured_parsed[1].intent.source.argv)
    assert.equal('command build --fast', captured_parsed[1].intent.source.raw_args)
    assert.equal(1, #captured_ctx)
  end)

  it('deduplicates native OMP commands against plugin commands', function()
    user_commands = {
      compact = { description = 'Native compact' },
      review = { description = 'Native review' },
    }

    local counts = {}
    for _, entry in ipairs(slash.get_commands():wait()) do
      counts[entry.slash_cmd] = (counts[entry.slash_cmd] or 0) + 1
    end

    assert.equals(1, counts['/compact'])
    assert.equals(1, counts['/review'])
  end)
end)
