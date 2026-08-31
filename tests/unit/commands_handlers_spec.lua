local session_handler = require('omp.commands.handlers.session')
local diff_handler = require('omp.commands.handlers.diff')
local state = require('omp.state')

describe('omp command handlers', function()
  it('only exposes OMP-supported session subcommands', function()
    assert.same(
      { 'new', 'select', 'compact', 'rename', 'toggle_lock' },
      session_handler.command_defs.session.completions
    )
    assert.is_nil(session_handler.command_defs.undo)
    assert.is_nil(session_handler.command_defs.redo)
    assert.is_nil(session_handler.command_defs.timeline)
    assert.is_nil(session_handler.command_defs.navigate_session_tree)
  end)

  it('routes the compact session subcommand', function()
    local original = session_handler.actions.compact_session
    local called = false
    session_handler.actions.compact_session = function()
      called = true
    end
    session_handler.command_defs.session.execute({ 'compact' })
    session_handler.actions.compact_session = original
    assert.is_true(called)
  end)

  it('only exposes working-tree diff commands', function()
    assert.same({ 'open', 'next', 'prev', 'close' }, diff_handler.command_defs.diff.completions)
    assert.is_not_nil(diff_handler.command_defs.diff_open)
    assert.is_not_nil(diff_handler.command_defs.diff_close)
    assert.is_nil(diff_handler.command_defs.revert)
    assert.is_nil(diff_handler.command_defs.restore)
  end)

  it('copies original non-synthetic user text in order', function()
    local original_setreg = vim.fn.setreg
    local copied
    vim.fn.setreg = function(_, value)
      copied = value
    end
    state.session.set_active({ id = 'session-1' })
    state.renderer.set_messages({
      {
        info = { id = 'message-1', role = 'user', sessionID = 'session-1' },
        parts = {
          { type = 'text', text = 'first' },
          { type = 'text', text = 'hidden', synthetic = true },
          { type = 'text', text = 'second' },
        },
      },
    })

    session_handler.actions.copy_message('message-1')
    vim.fn.setreg = original_setreg
    assert.equals('first\n\nsecond', copied)
  end)
end)
