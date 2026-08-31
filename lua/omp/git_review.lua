local diff_tab = require('omp.ui.diff_tab')
local picker = require('omp.ui.picker')

local M = {
  __changed_files = {},
  __current_file_index = nil,
  __temporary_files = {},
}

local function git(args)
  local command = { 'git', '-C', vim.fn.getcwd() }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr
  end
  return result.stdout or ''
end

local function cleanup_temporary_files()
  for _, path in ipairs(M.__temporary_files) do
    pcall(vim.uv.fs_unlink, path)
  end
  M.__temporary_files = {}
end

local function temporary_file(content, extension)
  local path = vim.fn.tempname() .. (extension ~= '' and ('.' .. extension) or '')
  local fd = assert(vim.uv.fs_open(path, 'w', 384))
  vim.uv.fs_write(fd, content or '', 0)
  vim.uv.fs_close(fd)
  table.insert(M.__temporary_files, path)
  return path
end

local function changed_paths()
  local tracked, err = git({ 'diff', '--name-only', 'HEAD' })
  if not tracked then
    tracked = git({ 'diff', '--name-only' }) or ''
    if tracked == '' and err then
      return nil, err
    end
  end
  local untracked = git({ 'ls-files', '--others', '--exclude-standard' }) or ''
  local paths, seen = {}, {}
  for _, output in ipairs({ tracked, untracked }) do
    for _, path in ipairs(vim.split(output, '\n', { trimempty = true })) do
      if not seen[path] then
        seen[path] = true
        table.insert(paths, path)
      end
    end
  end
  table.sort(paths)
  return paths
end

local function build_changed_files()
  cleanup_temporary_files()
  local root = (git({ 'rev-parse', '--show-toplevel' }) or vim.fn.getcwd()):gsub('%s+$', '')
  local paths, err = changed_paths()
  if not paths then
    return nil, err
  end
  local files = {}
  for _, relative in ipairs(paths) do
    local actual = vim.fs.joinpath(root, relative)
    local extension = vim.fn.fnamemodify(relative, ':e')
    local base = git({ 'show', 'HEAD:' .. relative }) or ''
    local right = vim.uv.fs_stat(actual) and actual or temporary_file('', extension)
    table.insert(files, {
      path = relative,
      current = right,
      base = temporary_file(base, extension),
      file_type = extension,
    })
  end
  M.__changed_files = files
  return files
end

local function display(index)
  local file = M.__changed_files[index]
  if not file then
    return
  end
  M.__current_file_index = index
  vim.notify(string.format('Showing file %d of %d: %s', index, #M.__changed_files, file.path))
  diff_tab.open_diff_tab(file.current, file.base, file.file_type)
end

function M.review()
  local files, err = build_changed_files()
  if not files then
    vim.notify('Git diff failed: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if #files == 0 then
    vim.notify('No working tree changes to review.')
    return
  end
  if #files == 1 then
    display(1)
    return
  end
  picker.select(
    vim.tbl_map(function(file)
      return file.path
    end, files),
    { prompt = 'Select a file to review:' },
    function(choice, index)
      if choice then
        display(index)
      end
    end
  )
end

function M.next_diff()
  if #M.__changed_files == 0 then
    M.review()
    return
  end
  display(((M.__current_file_index or 0) % #M.__changed_files) + 1)
end

function M.prev_diff()
  if #M.__changed_files == 0 then
    M.review()
    return
  end
  local index = (M.__current_file_index or 1) - 1
  display(index < 1 and #M.__changed_files or index)
end

function M.close_diff()
  diff_tab.close_diff_tab()
  cleanup_temporary_files()
  M.__changed_files = {}
  M.__current_file_index = nil
end

function M.reset_git_status()
  M.close_diff()
end

return M
