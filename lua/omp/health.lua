local M = {}

local health = vim.health or require('health')
local config = require('omp.config')
local util = require('omp.util')

local function get_version()
  if vim.fn.executable(config.omp_executable) ~= 1 then
    return nil, 'omp command not found'
  end
  local result = vim.system({ config.omp_executable, '--version' }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr or 'unknown error'
  end
  return (result.stdout or ''):match('(%d+%.%d+%.%d+)')
end

local function check_cli()
  health.start('OMP CLI')
  local version, err = get_version()
  if not version then
    health.error('无法执行 omp: ' .. tostring(err), {
      '安装 oh-my-pi 并确保 omp 位于 PATH 中',
      '参考 https://github.com/can1357/oh-my-pi',
    })
    return
  end
  local required = require('omp.state').required_version
  if not util.is_version_greater_or_equal(version, required) then
    health.error(string.format('omp %s 过旧，需要 >= %s', version, required))
    return
  end
  health.ok(string.format('omp CLI %s', version))
end

local function check_rpc()
  health.start('OMP RPC')
  local Process = require('omp.rpc.process')
  local process = Process.new({ cwd = vim.fn.getcwd(), no_session = true })
  local ok, result = pcall(function()
    process:start():wait(config.rpc.timeout)
    return process:request({ type = 'get_state' }):wait(config.rpc.timeout)
  end)
  process:shutdown():wait(config.rpc.timeout)
  if not ok then
    health.error('OMP RPC 握手失败: ' .. tostring(result))
    return
  end
  if type(result) ~= 'table' or not result.sessionId then
    health.error('OMP RPC get_state 返回无效数据')
    return
  end
  health.ok(string.format('协议 v%d，session=%s', process.protocol_version, result.sessionId))
end

local function check_configuration()
  health.start('omp.nvim 配置')
  local valid_positions = { 'left', 'right', 'top', 'bottom', 'current' }
  if not vim.tbl_contains(valid_positions, config.ui.position) then
    health.warn('无效 ui.position: ' .. tostring(config.ui.position))
  else
    health.ok('ui.position=' .. config.ui.position)
  end
  if type(config.rpc.timeout) ~= 'number' or config.rpc.timeout <= 0 then
    health.error('rpc.timeout 必须是正数')
  else
    health.ok('rpc.timeout=' .. config.rpc.timeout .. 'ms')
  end
end

function M.check()
  check_cli()
  check_rpc()
  check_configuration()
end

return M
