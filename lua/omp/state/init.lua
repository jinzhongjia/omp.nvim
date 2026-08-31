local store = require('omp.state.store')
local session = require('omp.state.session')
local jobs = require('omp.state.jobs')
local ui = require('omp.state.ui')
local model = require('omp.state.model')
local renderer = require('omp.state.renderer')
local context = require('omp.state.context')

---@class OmpState : OmpStateData
---@field store OmpStateStore
---@field session OmpSessionStateMutations
---@field jobs OmpJobStateMutations
---@field ui OmpUiStateMutations
---@field model OmpModelStateMutations
---@field renderer OmpRendererStateMutations
---@field context OmpContextStateMutations
---@field active_session Session|nil
---@field current_model string|nil
---@field api_client OmpApiClient|nil

---@type OmpState
local M = {
  store = store,
  session = session,
  jobs = jobs,
  ui = ui,
  model = model,
  renderer = renderer,
  context = context,
}

return setmetatable(M, {
  __index = function(_, key)
    return store.get(key)
  end,
  __newindex = function(_, key, _value)
    error(string.format('Direct write to state key `%s` is not allowed; use a state domain setter', key), 2)
  end,
  __pairs = function()
    return pairs(store.state())
  end,
  __ipairs = function()
    return ipairs(store.state())
  end,
}) --[[@as OmpState]]
