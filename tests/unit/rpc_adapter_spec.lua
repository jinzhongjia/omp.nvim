local Adapter = require('omp.rpc.adapter')

describe('omp RPC adapter', function()
  it('maps streaming assistant text to renderer events', function()
    local adapter = Adapter.new({ session_id = 'session-1' })
    local started = adapter:handle({
      type = 'message_start',
      message = { id = 'message-1', role = 'assistant', content = {} },
    })
    assert.equals('message.updated', started[1].type)
    assert.equals('message-1', started[1].properties.info.id)

    local delta = adapter:handle({
      type = 'message_update',
      assistantMessageEvent = { type = 'text_delta', contentIndex = 1, delta = 'hello' },
    })
    assert.same({
      type = 'message.part.delta',
      properties = {
        sessionID = 'session-1',
        messageID = 'message-1',
        partID = 'message-1-text-1',
        field = 'text',
        delta = 'hello',
      },
    }, delta[1])
  end)

  it('uses distinct part ids across assistant messages', function()
    local adapter = Adapter.new({ session_id = 'session-1' })
    for index = 1, 2 do
      adapter:handle({
        type = 'message_start',
        message = { id = 'message-' .. index, role = 'assistant', content = {} },
      })
      local events = adapter:handle({
        type = 'message_update',
        assistantMessageEvent = { type = 'text_delta', contentIndex = 1, delta = 'x' },
      })
      assert.equals('message-' .. index .. '-text-1', events[1].properties.partID)
    end
  end)

  it('maps tool lifecycle and normalizes file paths', function()
    local adapter = Adapter.new({ session_id = 'session-1' })
    adapter:handle({ type = 'message_start', message = { id = 'message-1', role = 'assistant', content = {} } })
    local started = adapter:handle({
      type = 'tool_execution_start',
      toolCallId = 'call-1',
      toolName = 'read',
      args = { path = 'lua/omp/init.lua' },
    })
    local part = started[1].properties.part
    assert.equals('tool', part.type)
    assert.equals('running', part.state.status)
    assert.equals('lua/omp/init.lua', part.state.input.filePath)

    local ended = adapter:handle({
      type = 'tool_execution_end',
      toolCallId = 'call-1',
      isError = false,
      result = { content = { { type = 'text', text = 'file content' } } },
    })
    assert.equals('completed', ended[1].properties.part.state.status)
    assert.equals('file content', ended[1].properties.part.state.output)
  end)

  it('separates tool approvals from ordinary select questions', function()
    local adapter = Adapter.new({ session_id = 'session-1' })
    local permission = adapter:handle({
      type = 'extension_ui_request',
      id = 'permission-1',
      method = 'select',
      title = 'Allow tool: write',
      options = { 'Approve', 'Deny' },
    })
    assert.equals('permission.asked', permission[1].type)
    assert.is_not_nil(adapter.permissions['permission-1'])

    local question = adapter:handle({
      type = 'extension_ui_request',
      id = 'question-1',
      method = 'select',
      title = 'Choose target',
      options = { 'A', 'B' },
      optionDetails = { { description = 'first' }, { description = 'second' } },
    })
    assert.equals('question.asked', question[1].type)
    assert.equals('first', question[1].properties.questions[1].options[1].description)
    assert.is_not_nil(adapter.questions['question-1'])
  end)

  it('converts persisted tool results into completed tool parts', function()
    local messages = Adapter.convert_messages({
      {
        role = 'assistant',
        content = {
          { type = 'text', text = 'Reading' },
          { type = 'toolCall', id = 'call-1', name = 'read', arguments = { path = 'README.md' } },
        },
      },
      {
        role = 'toolResult',
        toolCallId = 'call-1',
        content = { { type = 'text', text = 'content' } },
        isError = false,
      },
    }, 'session-1')

    assert.equals(1, #messages)
    assert.equals('completed', messages[1].parts[2].state.status)
    assert.equals('content', messages[1].parts[2].state.output)
  end)

  it('ignores tool-result message boundaries', function()
    local adapter = Adapter.new({ session_id = 'session-1' })
    adapter:handle({ type = 'message_start', message = { id = 'message-1', role = 'assistant', content = {} } })
    assert.same(
      {},
      adapter:handle({
        type = 'message_end',
        message = { role = 'toolResult', toolCallId = 'call-1', content = {} },
      })
    )
  end)
end)
