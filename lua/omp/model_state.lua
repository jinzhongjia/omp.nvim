local M = {}

---Get the path to the model state file
---@return string
local function get_model_state_path()
  local home = vim.uv.os_homedir()
  return home .. '/.local/state/omp/model.json'
end

---Load model favorites, recent models, and per-model thinking levels.
---@return table
function M.load()
  local state_path = get_model_state_path()
  local file = io.open(state_path, 'r')
  if not file then
    return { recent = {}, favorite = {}, thinking_level = {} }
  end

  local content = file:read('*a')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    return { recent = {}, favorite = {}, thinking_level = {} }
  end

  data.recent = data.recent or {}
  data.favorite = data.favorite or {}
  data.thinking_level = data.thinking_level or {}
  return data
end

---Save model favorites, recent models, and thinking levels.
---@param state table
function M.save(state)
  local state_path = get_model_state_path()
  local state_dir = vim.fn.fnamemodify(state_path, ':h')

  if not vim.fn.isdirectory(state_dir) then
    vim.fn.mkdir(state_dir, 'p')
  end

  local file = io.open(state_path, 'w')
  if not file then
    vim.notify('Failed to save model state', vim.log.levels.WARN)
    return
  end

  local ok, json = pcall(vim.json.encode, state)
  if not ok then
    file:close()
    vim.notify('Failed to encode model state', vim.log.levels.WARN)
    return
  end

  file:write(json)
  file:close()
end

---Get the saved thinking level for a model.
---@param provider_id string
---@param model_id string
---@return string|nil
function M.get_thinking_level(provider_id, model_id)
  local state = M.load()
  return state.thinking_level[provider_id .. '/' .. model_id]
end

---Save the thinking level for a model.
---@param provider_id string
---@param model_id string
---@param level string|nil
function M.set_thinking_level(provider_id, model_id, level)
  local state = M.load()
  local key = provider_id .. '/' .. model_id
  state.thinking_level[key] = level
  M.save(state)
end

---Record that a model was accessed
---@param provider_id string
---@param model_id string
function M.record_model_access(provider_id, model_id)
  local state = M.load()

  state.recent = vim.tbl_filter(function(item)
    return not (item.providerID == provider_id and item.modelID == model_id)
  end, state.recent)

  table.insert(state.recent, 1, {
    providerID = provider_id,
    modelID = model_id,
  })

  if #state.recent > 10 then
    for i = #state.recent, 11, -1 do
      table.remove(state.recent, i)
    end
  end

  M.save(state)
end

---Toggle a model as favorite
---@param provider_id string
---@param model_id string
function M.toggle_favorite(provider_id, model_id)
  local state = M.load()

  -- Check if already in favorites
  local found_idx = nil
  for i, item in ipairs(state.favorite) do
    if item.providerID == provider_id and item.modelID == model_id then
      found_idx = i
      break
    end
  end

  if found_idx then
    table.remove(state.favorite, found_idx)
    vim.notify('Removed from favorites: ' .. provider_id .. '/' .. model_id, vim.log.levels.INFO)
  else
    table.insert(state.favorite, {
      providerID = provider_id,
      modelID = model_id,
    })
    vim.notify('Added to favorites: ' .. provider_id .. '/' .. model_id, vim.log.levels.INFO)
  end

  M.save(state)
end

---Get model index in a state list
---@param provider_id string
---@param model_id string
---@param list table Array of model entries with providerID and modelID
---@return number|nil Index in the list (1-based) or nil if not found
function M.get_model_index(provider_id, model_id, list)
  for i, item in ipairs(list) do
    if item.providerID == provider_id and item.modelID == model_id then
      return i
    end
  end
  return nil
end

return M
