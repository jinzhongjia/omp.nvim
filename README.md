# omp.nvim

在 Neovim 内使用 [oh-my-pi](https://github.com/can1357/oh-my-pi) 的聊天界面。

本项目继承 sudo-tee/opencode.nvim 的 UI 与上下文能力，后端已完整切换为 `omp --mode rpc`：Neovim 启动长期运行的 omp 子进程，通过 stdin/stdout NDJSON 收发命令与流式事件，不再启动 opencode HTTP 服务，也不依赖 curl 或 SSE。

## 功能

- Neovim 内聊天面板与 Markdown 流式渲染
- 当前文件、选区、诊断、光标和 Git diff 上下文
- omp 工具调用、思考内容和错误状态展示
- omp 持久化会话的新建、选择、恢复和重命名
- 模型选择与思考级别切换
- `extension_ui_request` 权限确认
- 请求取消、会话压缩、图片输入和斜杠命令
- 每个会话独立的 `omp --mode rpc` 进程；控制面使用 `--no-session`
- RPC v2 协商及大帧 `rpc_chunk` 重组

## 要求

- Neovim 0.10+
- omp 18.0.11+
- 已完成 omp provider 登录或 API Key 配置

确认安装：

```sh
omp --version
```

插件健康检查：

```vim
:checkhealth omp
```

## 安装

lazy.nvim：

```lua
{
  'jinzhongjia/omp.nvim',
  config = function()
    require('omp').setup()
  end,
}
```

## 配置

```lua
require('omp').setup({
  omp_executable = 'omp',
  rpc = {
    timeout = 10000,
    extra_args = {},
  },
  keymap_prefix = '<leader>o',
  default_system_prompt = nil,
  ui = {
    position = 'right',
    window_width = 0.40,
    output = {
      tools = {
        show_output = true,
        show_reasoning_output = true,
      },
    },
  },
})
```

配置使用深合并；只需覆盖需要修改的字段。

## 使用

```vim
:Omp toggle
:Omp open_input
:Omp open_input_new_session
:Omp select_session
:Omp rename_session 新名称
:Omp diff open
:Omp cancel
```

默认按键前缀为 `<leader>o`。主要按键：

| 按键 | 功能 |
|---|---|
| `<leader>og` | 切换聊天窗口 |
| `<leader>oi` | 打开输入窗口 |
| `<leader>oI` | 新会话中打开输入窗口 |
| `<leader>os` | 选择会话 |
| `<leader>op` | 选择模型 |
| `<leader>oV` | 选择 OMP thinking level |
| `<leader>ov` | 粘贴图片 |
| `<leader>od` | 查看当前 Git diff |
| `<leader>o/` | Quick Chat（独立 `--no-session` 进程） |
| `<C-c>` | 取消当前请求 |

Lua API：

```lua
local omp = require('omp.api')
omp.toggle()
omp.run('解释当前文件')
omp.run_new_session('审查当前改动')
```

## 会话

omp 会话由 omp 自身保存到：

```text
~/.omp/agent/sessions/<工作目录编码>/*.jsonl
```

插件只扫描会话元数据。打开历史会话时，会为该会话启动独立 RPC 进程并使用 `--resume <session-file>` 恢复上下文。

### 进程与复用模型

- 插件维护一个 `omp --mode rpc --no-session` 控制进程，用于查询模型、命令和配置。
- 每个实际打开的会话拥有一个独立的长期运行 RPC 进程；仅在 picker 中列出会话不会启动进程。
- 新会话启动 `omp --mode rpc`；历史会话启动 `omp --mode rpc --resume <session-file>`。
- 再次切回仍在运行的同一会话时会复用原进程，不会重复启动。
- 打开 $N$ 个会话时通常有 $N+1$ 个 omp 进程；额外的一个是无持久化控制进程。
- Neovim 退出时，插件会关闭控制进程及全部会话进程。

omp RPC 虽提供 `switch_session`，但跨会话共享一个进程会失去并行能力，并增加流式事件、权限请求和取消操作串线的风险，因此当前选择一会话一进程。外部已经运行的 omp TUI 不能复用：RPC 传输依赖该子进程专属的 stdin/stdout。

## 当前边界

以下 opencode.nvim 专属 UI 没有等价的 OMP RPC 数据模型，已从命令、按键和渲染状态中移除：

- snapshot/timeline undo/redo 与恢复点
- MCP 连接管理面板；OMP 原生 `/mcp` 命令仍可用
- 子会话树、child-session 跳转和基于 opencode message ID 的 fork
- 会话删除
- agent mode、`DEFAULT/BUILD/PLAN` 标签和 variant 概念

OMP 原生 slash commands（包括 `/share`、`/mcp`、`/review`）直接由 RPC 命令列表提供。Diff 面板仅展示当前 Git 工作区改动。

## 开发

定向测试：

```sh
./run_tests.sh -t tests/unit/api_client_spec.lua
./run_tests.sh -t tests/unit/rpc_process_spec.lua
./run_tests.sh -t tests/unit/rpc_adapter_spec.lua
```

完整测试：

```sh
./run_tests.sh
```

架构依赖检查：

```sh
uv run --with json5 python scripts/dependency-topology/scan_topology.py scan --snapshot worktree
```

## 许可证与来源

Apache-2.0。本项目基于 sudo-tee/opencode.nvim 改造，保留原项目版权与许可证声明；后端集成面来自 oh-my-pi 官方 RPC 协议。
