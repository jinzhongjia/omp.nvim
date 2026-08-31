local util = require('omp.util')
local state = require('omp.state')
local config_file = require('omp.config_file')
local Promise = require('omp.promise')
local M = {}

---Get the current OMP project ID
---@return string|nil
M.project_id = Promise.async(function()
  local project = config_file.get_omp_project():await()
  if not project then
    vim.notify('No OMP project found in the current directory', vim.log.levels.ERROR)
    return nil
  end
  return project.id
end)

---Get the base storage path for OMP
---@return string
function M.get_storage_path()
  local home = vim.uv.os_homedir()
  return home .. '/.local/share/omp/storage'
end

---Get the session storage path for the current workspace
---@return string
M.get_workspace_session_path = Promise.async(function(project_id)
  project_id = project_id or M.project_id():await() or ''
  local home = vim.uv.os_homedir()
  return home .. '/.local/share/omp/storage/session/' .. project_id
end)

function M.get_cache_path(session_id)
  local cache_base = vim.fn.stdpath('cache') .. '/omp/session/'
  return cache_base .. session_id
end

---Get all workspace sessions, sorted and filtered
---@return Session[]|nil
M.get_all_workspace_sessions = Promise.async(function()
  local sessions = state.api_client:list_sessions():await()
  if not sessions then
    return nil
  end

  -- Validate that sessions is actually a table/array, not an error string
  if type(sessions) ~= 'table' then
    vim.notify('Error: list_sessions returned invalid data: ' .. tostring(sessions), vim.log.levels.ERROR)
    return nil
  end

  table.sort(sessions, function(a, b)
    return a.time.updated > b.time.updated
  end)

  if not util.is_git_project() then
    -- we only want sessions that are in the current workspace_folder
    sessions = vim.tbl_filter(function(session)
      if session.directory and vim.startswith(vim.fn.getcwd(), session.directory) then
        return true
      end
      return false
    end, sessions)
  end

  return sessions
end)

---Get all sessions across every project (no workspace filter)
---@return GlobalSession[]|nil
M.get_all_global_sessions = Promise.async(function()
  local sessions = state.api_client:list_sessions_global():await()
  if not sessions or type(sessions) ~= 'table' then
    return nil
  end

  table.sort(sessions, function(a, b)
    return a.time.updated > b.time.updated
  end)

  return sessions
end)

---Get the most recent main workspace session
---@return Session|nil
M.get_last_workspace_session = Promise.async(function()
  local sessions = M.get_all_workspace_sessions():await()
  ---@cast sessions Session[]|nil
  if not sessions then
    return nil
  end

  local main_sessions = vim.tbl_filter(function(session)
    return session.parentID == nil --- we don't want child sessions
  end, sessions)

  return main_sessions[1]
end)

---Get a session by its id
---@param id string
---@return Promise<Session|nil>
M.get_by_id = Promise.async(function(id)
  if not id or id == '' then
    return nil
  end
  return state.api_client:get_session(id):await()
end)

---Get messages for a session
---@param session Session
---@param opts? { limit?: number } Optional query parameters (e.g. limit)
---@return Promise<OmpMessage[]>
function M.get_messages(session, opts)
  if not session then
    return Promise.new():resolve(nil)
  end

  return state.api_client:list_messages(session.id, nil, opts)
end

return M
