# omp.nvim

A Neovim chat interface for [oh-my-pi](https://github.com/can1357/oh-my-pi).

This project retains the UI and editor-context capabilities of sudo-tee/opencode.nvim while replacing its backend with `omp --mode rpc`. Neovim communicates with long-running omp subprocesses over stdin/stdout NDJSON. It does not start an opencode HTTP server and does not depend on curl or SSE.

## Features

- In-editor chat panel with streaming Markdown rendering
- Current file, visual selection, diagnostics, cursor, and Git diff context
- omp tool-call, thinking, and error-state rendering
- Create, select, resume, and rename persistent omp sessions
- Model selection and OMP thinking-level controls
- Permission handling through `extension_ui_request`
- Request cancellation, compaction, image input, and slash commands
- One isolated `omp --mode rpc` process per opened session
- A separate ephemeral control process for model, command, and configuration queries
- RPC v2 negotiation and lossless `rpc_chunk` reassembly
- Ephemeral Quick Chat through `omp --mode rpc --no-session`

## Requirements

- Neovim 0.10+
- omp 18.0.11+
- An authenticated omp provider or configured API key

Verify the CLI installation:

```sh
omp --version
```

Run the plugin health check:

```vim
:checkhealth omp
```

## Installation

With lazy.nvim:

```lua
{
  'jinzhongjia/omp.nvim',
  config = function()
    require('omp').setup()
  end,
}
```

## Configuration

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

Configuration is deep-merged. Only override the fields you need.

## Usage

```vim
:Omp toggle
:Omp open_input
:Omp open_input_new_session
:Omp select_session
:Omp session rename New name
:Omp thinking_level
:Omp diff open
:Omp cancel
```

The default keymap prefix is `<leader>o`.

| Key | Action |
|---|---|
| `<leader>og` | Toggle the chat panel |
| `<leader>oi` | Open the input window |
| `<leader>oI` | Open the input window in a new session |
| `<leader>os` | Select a session |
| `<leader>op` | Select a model |
| `<leader>oV` | Select an OMP thinking level |
| `<leader>ov` | Paste an image |
| `<leader>od` | Open the current Git diff |
| `<leader>o/` | Start an ephemeral Quick Chat |
| `<C-c>` | Cancel the active request |

Lua API:

```lua
local omp = require('omp.api')
omp.toggle()
omp.run('Explain the current file')
omp.run_new_session('Review the current changes')
```

## Sessions

omp stores persistent sessions under:

```text
~/.omp/agent/sessions/<encoded-working-directory>/*.jsonl
```

The plugin only scans session metadata. Opening a historical session starts a dedicated RPC process with `--resume <session-file>`.

### Process and reuse model

- One `omp --mode rpc --no-session` control process handles model, command, and configuration queries.
- Every opened chat session owns one long-running RPC process. Listing a session in the picker does not start it.
- A new session starts `omp --mode rpc`.
- A historical session starts `omp --mode rpc --resume <session-file>`.
- Switching back to an already running session reuses its process instead of starting a duplicate.
- Opening $N$ sessions normally results in $N+1$ omp processes; the extra process is the ephemeral control process.
- Neovim shuts down the control process and every session process on exit.

OMP RPC provides `switch_session`, but sharing one process across multiple sessions would prevent concurrent runs and make streaming events, permission requests, and cancellation state easier to mix up. The plugin therefore uses one process per independently controlled session. It also cannot attach to an already running external omp TUI because RPC transport requires ownership of that process's stdin/stdout.

## Backend-specific boundaries

The following opencode.nvim UI concepts do not have an equivalent OMP RPC data model and have been removed from commands, keymaps, and renderer state:

- Snapshot/timeline undo and redo, restore points, and message revert UI
- The MCP connection-management panel; OMP's native `/mcp` command remains available
- Child-session trees, child-session navigation, and message-ID-based forks
- Session deletion
- Agent modes, `DEFAULT/BUILD/PLAN` labels, and model variants

OMP-native slash commands, including `/share`, `/mcp`, and `/review`, are provided directly from the RPC command list. The diff panel shows current Git working-tree changes only.

## Development

Run focused RPC tests:

```sh
./run_tests.sh -t tests/unit/api_client_spec.lua
./run_tests.sh -t tests/unit/rpc_process_spec.lua
./run_tests.sh -t tests/unit/rpc_adapter_spec.lua
./run_tests.sh -t tests/unit/thinking_level_picker_spec.lua
```

Run the complete test suite:

```sh
./run_tests.sh
```

Inspect the current dependency topology:

```sh
uv run --with json5 python scripts/dependency-topology/scan_topology.py scan --snapshot worktree
```

## License and attribution

Apache-2.0. This project is derived from sudo-tee/opencode.nvim and retains the original copyright and license notices. The backend integration targets the official oh-my-pi RPC protocol.
