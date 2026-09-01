
---@class OmpDiagnostic
---@field message string
---@field severity number
---@field lnum number
---@field col number
---@field end_lnum? number
---@field end_col? number
---@field source? string
---@field code? string|number
---@field user_data? any

---@class OmpConfigFile
---@field theme string
---@field autoupdate boolean
---@field model string
---@field command table<string, table>
---@field plugin table[]
---@field username string

---@class OmpProject
---@field id string
---@field worktree string
---@field vcs string
---@field time { created: number }

---@class OmpPath
---@field state string
---@field config string
---@field worktree string
---@field directory string

---@class OmpSkill
---@field name string
---@field description string|nil
---@field location string
---@field content string

---@class OmpCommand
---@field description string
---@field agent string
---@field model string
---@field template string

---@class OmpUICommand
---@field desc string
---@field execute fun(args: string[], range: OmpSelectionRange|nil): any
---@field completions? string[]
---@field nested_subcommand? OmpNestedSubcommandValidation
---@field completion_provider_id? string
---@field sub_completions? string[]
---@field nargs? string|integer
---@field range? boolean
---@field complete? boolean

---@class OmpNestedSubcommandValidation
---@field allow_empty boolean

---@class OmpCommandSubcommandSpec
---@field completions? string[]
---@field nested_subcommand? OmpNestedSubcommandValidation
---@field sub_completions? string[]
---@field completion_provider_id? string

---@class OmpCommandApi
---@field [string] any

---@alias OmpCommandHandler fun(api: OmpCommandApi, args: string[], range?: OmpSelectionRange): any
---@alias OmpCommandHandlerMap table<string, OmpCommandHandler>

---@class OmpParsedIntentSource
---@field raw_args string
---@field argv string[]

---@class OmpParsedIntent
---@field name string
---@field hook_key? string
---@field args string[]
---@field range OmpSelectionRange|nil
---@field source OmpParsedIntentSource

---@class OmpCommandParseError
---@field code 'unknown_subcommand'|'invalid_subcommand'
---@field message string
---@field subcommand string

---@class OmpCommandParseResult
---@field ok boolean
---@field intent? OmpParsedIntent
---@field error? OmpCommandParseError

---@class OmpCommandRouteOpts
---@field args? string
---@field range? integer
---@field line1? integer
---@field line2? integer

---@class OmpCommandDispatchError
---@field code 'unknown_subcommand'|'missing_handler'|'missing_execute'|'invalid_subcommand'|'invalid_arguments'|'execute_error'
---@field message string
---@field subcommand? string

---@class OmpCommandDispatchResult
---@field ok boolean
---@field intent? OmpParsedIntent
---@field result? any
---@field error? OmpCommandDispatchError

---@class OmpCommandActionContext
---@field parsed OmpCommandParseResult
---@field intent? OmpParsedIntent
---@field args? string[]
---@field range? OmpSelectionRange|nil
---@field execute? fun(args: string[], range: OmpSelectionRange|nil): any

---@class Session
---@field workspace string
---@field title string
---@field time { created: number, updated: number }
---@field id string
---@field model { id: string, providerID: string }|nil
---@field directory? string

---@class SessionProjectInfo
---@field id string
---@field name? string
---@field worktree string

---@class GlobalSession : Session
---@field project SessionProjectInfo|nil

---@class OmpKeymapEntry
---@field [1] string # Function name
---@field mode? string|string[] # Mode(s) for the keymap
---@field desc? string # Keymap description
---@field defer_to_completion? boolean # Whether to defer the keymap when completion menu is open

---@class OmpKeymapEditor : table<string, OmpKeymapEntry>
---@class OmpKeymapInputWindow : table<string, OmpKeymapEntry>
---@class OmpKeymapOutputWindow : table<string, OmpKeymapEntry>

---@class OmpKeymap
---@field editor OmpKeymapEditor
---@field input_window OmpKeymapInputWindow
---@field output_window OmpKeymapOutputWindow
---@field session_picker OmpSessionPickerKeymap
---@field history_picker OmpHistoryPickerKeymap
---@field quick_chat OmpQuickChatKeymap

---@class OmpSessionPickerKeymap
---@field delete_session OmpKeymapEntry
---@field new_session OmpKeymapEntry
---@field rename_session OmpKeymapEntry
---@field toggle_scope OmpKeymapEntry

---@class OmpHistoryPickerKeymap
---@field delete_entry OmpKeymapEntry
---@field clear_all OmpKeymapEntry

---@class OmpQuickChatKeymap
---@field cancel OmpKeymapEntry

---@class OmpCompletionFileSourcesConfig
---@field enabled boolean
---@field preferred_cli_tool 'server'|'fd'|'fdfind'|'rg'|'git'
---@field ignore_patterns string[]
---@field max_files number
---@field max_display_length number

---@class OmpCompletionConfig
---@field file_sources OmpCompletionFileSourcesConfig

---@class OmpLoadingAnimationConfig
---@field frames string[]

---@class OmpRpcConfig
---@field timeout number RPC request/health-check timeout in milliseconds
---@field extra_args string[] Additional arguments appended to `omp --mode rpc`

---@class OmpUIFloatConfig
---@field width number # Width in columns, or ratio when <= 1 (default: 0.95)
---@field height number # Height in rows, or ratio when <= 1 (default: 0.9)
---@field row number|nil # Top row, centered when nil
---@field col number|nil # Left column, centered when nil
---@field border string|string[]|nil # Float border passed to nvim_open_win
---@field gap integer # Rows between output and input floats
---@field zindex integer # Output float zindex; input uses zindex + 1
---@field opts table<string, any> # Window-local options applied to float windows

---@class OmpUIConfig
---@field enable_treesitter_markdown boolean
---@field position 'right'|'left'|'current'|'float' # Position of the UI (default: 'right')
---@field input_position 'bottom'|'top' # Position of the input window (default: 'bottom')
---@field window_width number
---@field persist_state boolean
---@field zoom_width number
---@field float OmpUIFloatConfig
---@field picker_width number|false|nil # Width for pickers. 0<w<=1 = fraction of screen; >1 = absolute columns; false = use picker backend defaults.
---@field display_model boolean
---@field display_context_size boolean
---@field display_cost boolean
---@field window_highlight string
---@field icons { preset: 'text'|'nerdfonts', overrides: table<string,string> }
---@field loading_animation OmpLoadingAnimationConfig
---@field output OmpUIOutputConfig
---@field input OmpUIInputConfig
---@field completion OmpCompletionConfig
---@field highlights? OmpHighlightConfig
---@field picker OmpUIPickerConfig

---Window-local options applied to the input window.
---Any valid Neovim window-local option (`:h window-variable`) can be set here.
---Common examples:
---  signcolumn = 'no'
---  cursorline = true
---  number = true
---  relativenumber = true
---  foldcolumn = '0'
---  statuscolumn = ''
---  conceallevel = 2
---@class OmpUIInputWinOptions : table<string, any>
---@field signcolumn? string # Value for 'signcolumn' (e.g. 'yes', 'no', 'auto')
---@field cursorline? boolean
---@field number? boolean
---@field relativenumber? boolean

---@class OmpUIInputConfig
---@field text { wrap: boolean }
---@field min_height number
---@field max_height number
---@field auto_hide boolean
---@field win_options? OmpUIInputWinOptions # Window-local options applied to the input window. Any valid Neovim window option is accepted.

---@class OmpHighlightConfig
---@field vertical_borders? { tool?: { fg?: string, bg?: string }, user?: { fg?: string, bg?: string }, assistant?: { fg?: string, bg?: string } }

---@class OmpUIOutputRenderingConfig
---@field markdown_debounce_ms number
---@field on_data_rendered (fun(buf: integer, win: integer)|boolean)|nil
---@field markdown_on_idle boolean
---@field event_throttle_ms number
---@field event_collapsing boolean

---@class OmpUIOutputToolsConfig
---@field show_output boolean
---@field show_reasoning_output boolean
---@field use_folds boolean
---@field fold_exclude (string|{server: string, tool: string})[]|nil
---@field folding_threshold number

---@class OmpUIOutputConfig
---@field time_format string|nil # Custom os.date format for timestamps, e.g. '%m/%d %H:%M'. Uses fixed default when nil.
---@field tools OmpUIOutputToolsConfig
---@field rendering OmpUIOutputRenderingConfig
---@field max_messages integer|nil
---@field always_scroll_to_bottom boolean
---@field filetype string
---@field compact_assistant_headers boolean | 'minimal' | 'hidden' | 'full'

---@class OmpUIPickerConfig
---@field snacks_layout? snacks.picker.layout.Config
--- TODO: add more picker-specific presets

---@class OmpContextConfig
---@field enabled boolean
---@field cursor_data { enabled: boolean, context_lines?: number }
---@field diagnostics { enabled:boolean, info: boolean, warning: boolean, error: boolean, only_closest: boolean}
---@field current_file { enabled: boolean }
---@field selection { enabled: boolean }
---@field agents { enabled: boolean }
---@field buffer { enabled: boolean }
---@field git_diff { enabled: boolean }

---@alias OmpToggleableContextKey
---| 'current_file'
---| 'selection'
---| 'diagnostics'
---| 'cursor_data'
---| 'buffer'
---| 'git_diff'

---@class OmpDebugConfig
---@field enabled boolean
---@field capture_streamed_events boolean
---@field show_ids boolean
---@field highlight_changed_lines boolean
---@field highlight_changed_lines_timeout_ms integer
---@field quick_chat {keep_session: boolean, set_active_session: boolean}

---@alias OmpCommandLifecycleStage 'before'|'after'|'error'|'finally'
---@alias OmpCommandDispatchHook fun(ctx: OmpCommandDispatchContext): OmpCommandDispatchContext|nil
---@alias OmpCommandHookScope string|string[]|'*'

---@class OmpCommandHookRegisterOptions
---@field command? OmpCommandHookScope

---@class OmpHooks
---@field on_file_edited? fun(file: string): nil
---@field on_session_loaded? fun(session: Session): nil
---@field on_done_thinking? fun(session: Session): nil
---@field on_permission_requested? fun(session: Session): nil
---@field on_command_before? OmpCommandDispatchHook
---@field on_command_after? OmpCommandDispatchHook
---@field on_command_error? OmpCommandDispatchHook
---@field on_command_finally? OmpCommandDispatchHook

---@class OmpCommandDispatchContext
---@field parsed OmpCommandParseResult
---@field intent OmpParsedIntent|nil
---@field args string[]|nil
---@field range OmpSelectionRange|nil
---@field result? any
---@field error OmpCommandDispatchError|nil

---@class OmpCommandLifecycleHookSpec
---@field before? OmpCommandDispatchHook
---@field after? OmpCommandDispatchHook
---@field error? OmpCommandDispatchHook
---@field finally? OmpCommandDispatchHook
---@field on_command_before? OmpCommandDispatchHook
---@field on_command_after? OmpCommandDispatchHook
---@field on_command_error? OmpCommandDispatchHook
---@field on_command_finally? OmpCommandDispatchHook

---@class OmpProviders
---@field [string] string[]

---@class OmpConfigModule
---@field defaults OmpConfig
---@field values OmpConfig
---@field setup fun(opts?: OmpConfig): nil
---@field get_key_for_function fun(scope: 'editor'|'input_window'|'output_window', function_name: string): string|nil

---@class OmpQuickChatConfig
---@field default_model? string -- Use current model if nil
---@field instructions? string[] -- Custom instructions for quick chat

---@class OmpLoggingConfig
---@field enabled boolean
---@field level 'debug' | 'info' | 'warn' | 'error'
---@field outfile string|nil

---@class OmpSlashCommandSpec
---@field desc? string
---@field args? boolean
---@field cmd_str? string
---@field command_name? string
---@field preset_args? string[]
---@field fn? fun(args:string[]|nil):nil|Promise<any>|any

---@class OmpConfig
---@field preferred_picker 'telescope' | 'telescope.nvim' | 'fzf' | 'fzf-lua' | 'mini.pick' | 'snacks' | 'snacks.nvim' | 'select' | nil
---@field default_global_keymaps boolean
---@field default_system_prompt string | nil
---@field keymap_prefix string
---@field omp_executable 'omp' | string -- Command run for calling omp
---@field lock_session_to_directory boolean -- If true, active session is preserved across DirChanged events
---@field rpc OmpRpcConfig
---@field keymap OmpKeymap
---@field ui OmpUIConfig
---@field context OmpContextConfig
---@field logging OmpLoggingConfig
---@field debug OmpDebugConfig
---@field prompt_guard? fun(mentioned_files: string[]): boolean
---@field hooks OmpHooks
---@field quick_chat OmpQuickChatConfig

---@class MessagePartState
---@field input TaskToolInput|BashToolInput|FileToolInput|TodoToolInput|GlobToolInput|GrepToolInput|WebFetchToolInput|ListToolInput|QuestionToolInput|ApplyPatchToolInput Input data for the tool
---@field metadata TaskToolMetadata|ToolMetadataBase|WebFetchToolMetadata|BashToolMetadata|FileToolMetadata|GlobToolMetadata|GrepToolMetadata|ListToolMetadata|QuestionToolMetadata Metadata about the tool execution
---@field time { start: number, end: number } Timestamps for tool use
---@field status string Status of the tool use (e.g., 'running', 'completed', 'failed')
---@field title string Title of the tool use
---@field output string Output of the tool use, if applicable
---@field error? string Error message if the part failed

---@class ApplyPatchToolInput
---@field patchText string The patch content in unified diff format

---@class ApplyPatchFileResult
---@field filePath string Absolute path to the file
---@field relativePath string Relative path to the file
---@field before string File contents before the patch
---@field after string File contents after the patch
---@field additions number Number of lines added
---@field deletions number Number of lines deleted
---@field type 'add'|'edit'|'delete' Type of file operation
---@field diff string Unified diff for this file

---@class ApplyPatchToolMetadata: ToolMetadataBase
---@field truncated boolean Whether the output was truncated
---@field diagnostics table<string, any> Diagnostic information keyed by file path
---@field files ApplyPatchFileResult[] Per-file results
---@field diff string Combined unified diff for all files

---@class ToolMetadataBase
---@field error boolean|nil Whether the tool execution resulted in an error
---@field message string|nil Optional status or error message

---@class TaskToolMetadata: ToolMetadataBase
---@field summary TaskToolSummaryItem[]

---@class WebFetchToolMetadata: ToolMetadataBase
---@field http_status number|nil HTTP response status code
---@field content_type string|nil Content type of the response

---@class BashToolMetadata: ToolMetadataBase
---@field output string|nil

---@class FileToolMetadata: ToolMetadataBase
---@field diff string|nil The diff of changes made to the file
---@field file_type string|nil Detected file type/extension
---@field line_count number|nil Number of lines in the file

---@class GlobToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field count number|nil

---@class GrepToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field matches number|nil

---@class BashToolInput
---@field command string The command to execute
---@field description string Description of what the command does

---@class FileToolInput
---@field filePath string The path to the file
---@field content? string Content to write (for write tool)

---@class TodoToolInput
---@field todos { id: string, content: string, status: 'pending'|'in_progress'|'completed'|'cancelled', priority: 'high'|'medium'|'low' }[]

---@class ListToolInput
---@field path string The directory path to list

---@class ListToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field count number|nil

---@class GlobToolInput
---@field pattern string The glob pattern to match files against
---@field path? string Optional directory to search in

---@class ListToolOutput
---@field output string The raw output string from the list tool

---@class GrepToolInput
---@field pattern? string The glob pattern to match
---@field path? string Optional directory to search in
---@field include? string Optional file type to include (e.g., '*.lua')

---@class WebFetchToolInput
---@field url string The URL to fetch content from
---@field format 'text'|'markdown'|'html'
---@field timeout? number Optional timeout in seconds (max 120)

---@class TaskToolInput
---@field prompt string The subtask prompt
---@field description string Description of the subtask
---@field subagent_type string The type of specialized agent to use

---@class TaskToolSummaryItem
---@field id string Tool call ID
---@field tool string Tool name
---@field state { status: string, title?: string }

-- Question types

---@class OmpQuestionOption
---@field label string Display text
---@field description string Explanation of choice

---@class OmpQuestionInfo
---@field question string Complete question
---@field header string Very short label (max 12 chars)
---@field options OmpQuestionOption[] Available choices
---@field multiple? boolean Allow selecting multiple choices
---@field custom? boolean Allow a custom response

---@class OmpQuestionRequest
---@field id string Question request ID
---@field sessionID string Session ID
---@field questions OmpQuestionInfo[] Questions to ask
---@field tool? { messageID: string, callID: string }

---@class QuestionToolInput
---@field questions OmpQuestionInfo[] Questions that were asked

---@class QuestionToolMetadata: ToolMetadataBase
---@field answers string[][] Array of answer arrays (one per question)
---@field truncated boolean Whether the results were truncated

---@class MessageTokenCount
---@field reasoning number
---@field input number
---@field output number
---@field cache { write: number, read: number }

---@class OutputMetadata
---@field msg_idx number|nil Message index in session
---@field part_idx number|nil Part index in message
---@field role 'user'|'assistant'|'system'|nil Message role
---@field type 'text'|'tool'|'header'|nil Message part type

---@class OutputAction
---@field text string Action text
---@field type string
---@field args? string[] Optional arguments for the command
---@field key string keybinding for the action
---@field display_line number Line number to display the action
---@field range? { from: number, to: number } Optional range for the action

---@class CodeReferenceTextRange
---@field start_offset integer Raw part text offset, 1-based inclusive
---@field end_offset integer Raw part text offset, 1-based inclusive

---@class CodeReference
---@field session_id string
---@field message_id string
---@field part_id string
---@field path string
---@field line? integer
---@field col? integer
---@field source_kind 'assistant_text'|'tool_file_path'
---@field raw_range? CodeReferenceTextRange Required for assistant_text references
---@field order integer Smaller values appear earlier in the session message/part/text order.

---@class SymbolSnapshotCycle

---@class FormatterContext
---@field interactive boolean
---@field get_child_parts? fun(session_id: string): OmpMessagePart[]?
---@field current_refs? CodeReference[]
---@field current_files? string[]
---@field symbol_cycle? SymbolSnapshotCycle

---@class OutputTargetRange
---@field line integer Output-local line, 1-based
---@field start_col integer Output-local column, 0-based inclusive
---@field end_col integer Output-local column, 0-based exclusive

---@class OutputTarget
---@field kind 'file'|'diff'|'symbol'
---@field range OutputTargetRange
---@field path? string
---@field line? integer
---@field col? integer
---@field token? string
---@field candidate_files? string[]

---@class RenderedTarget: OutputTarget
---@field part_id string
---@field message_id string

---@alias OutputExtmarkType vim.api.keyset.set_extmark & {start_col:0}
---@alias OutputExtmark OutputExtmarkType|fun():OutputExtmarkType

---@class OmpMessage
---@field info MessageInfo Metadata about the message
---@field parts OmpMessagePart[] Parts that make up the message
---@field references CodeReference[]|nil Parsed file references from text parts (cached)
---@field system string|nil System message content

---@class MessageInfo
---@field id string Unique message identifier
---@field sessionID string Unique session identifier
---@field tokens MessageTokenCount Token usage statistics
---@field system string[] System messages
---@field time { created: number, completed: number } Timestamps
---@field cost number Cost of the message
---@field path { cwd: string, root: string } Working directory paths
---@field modelID string Model identifier
---@field providerID string Provider identifier
---@field role 'user'|'assistant'|'system' Role of the message sender
---@field system_role string|nil Role defined in system messages
---@field error table

---@class OpenOpts
---@field focus? 'input' | 'output'
---@field start_insert? boolean
---@field new_session? boolean
---@field open_action? 'reuse_visible'|'restore_hidden'|'create_fresh'

---@class SendMessageOpts
---@field new_session? boolean
---@field context? OmpContextConfig
---@field model? string
---@field thinking_level? 'off'|'minimal'|'low'|'medium'|'high'|'xhigh'|'max'
---@field system? string

---@class CompletionContext
---@field trigger_char string The character that triggered completion
---@field input string The current input text
---@field cursor_pos number Current cursor position
---@field line string The full current line text

---@class CompletionItem
---@field label string Display text for the completion item
---@field kind string Type of completion item (e.g., 'file', 'subagent')
---@field kind_icon string Icon representing the kind
---@field kind_hl? string Highlight group for the kind
---@field detail string Additional detail text
---@field documentation string Documentation text
---@field insert_text string Text to insert when selected
---@field source_name string Name of the completion source
---@field priority? number Optional priority for individual item sorting (lower numbers have higher priority)
---@field data table Additional data associated with the item

---@class CompletionSource
---@field name string Name of the completion source
---@field priority number Priority for ordering sources
---@field complete fun(context: CompletionContext): Promise<CompletionItem[]> Function to generate completion items
---@field on_complete fun(item: CompletionItem): nil Optional callback when item is selected
---@field is_incomplete? boolean Whether the completion results are incomplete (for sources that support pagination)
---@field get_trigger_character? fun(): string|nil Optional function returning the trigger character for this source
---@field custom_kind? integer Custom LSP CompletionItemKind registered for this source

---Extended LSP completion item with omp-specific rendering fields
---@class OmpLspItem : lsp.CompletionItem
---@field kind lsp.CompletionItemKind
---@field kind_hl? string Highlight group for the kind icon
---@field kind_icon string Icon string for the kind

---@class OmpContext
---@field current_file OmpContextFile|nil
---@field cursor_data OmpContextCursorData|nil
---@field mentioned_files string[]|nil
---@field mentioned_subagents string[]|nil
---@field selections OmpContextSelection[]|nil
---@field linter_errors OmpDiagnostic[]|nil

---@class OmpContextSelection
---@field file OmpContextFile
---@field content string|nil
---@field lines string|nil

---@class OmpContextCursorData
---@field line number
---@field column number
---@field line_content string
---@field lines_before string[]
---@field lines_after string[]

---@class OmpContextFile
---@field path string
---@field name string
---@field extension string
---@field sent_at? number

---@class OmpMessagePartSourceText
---@field start number
---@field value string
---@field ['end'] number

---@class OmpMessagePartSource
---@field path string|nil
---@field type string|nil
---@field text OmpMessagePartSourceText|nil
---@field value string|nil

---@class OmpMessagePart
---@field type 'text'|'file'|'agent'|'tool'|'reasoning'|string
---@field id string|nil Unique identifier for tool use parts
---@field text string|nil
---@field tool string|nil Name of the tool being used
---@field state MessagePartState|nil State information for tool use parts
---@field filename string|nil
---@field mime string|nil
---@field url string|nil
---@field source OmpMessagePartSource|nil
---@field name string|nil
---@field synthetic boolean|nil
---@field sessionID string|nil Session identifier
---@field messageID string|nil Message identifier
---@field callID string|nil Call identifier (used for tools)
---@field time { start: number, end?: number }|nil Timestamps for the part

---@class OmpModelModalities
---@field input ('text'|'image'|'audio'|'video')[] Supported input modalities
---@field output ('text')[] Supported output modalities

---@class OmpModelCost
---@field input number Cost per input token
---@field output number Cost per output token
---@field cache_read number|nil Cost per cache read token
---@field cache_write number|nil Cost per cache write token

---@class OmpModelLimits
---@field context number Maximum context length in tokens
---@field output number Maximum output length in tokens

---@class OmpModel
---@field id string Unique identifier for the model
---@field name string Human-readable name of the model
---@field attachment boolean Whether the model supports file attachments
---@field reasoning boolean Whether the model supports reasoning/thinking
---@field temperature boolean Whether the model supports temperature parameter
---@field tool_call boolean Whether the model supports tool calling
---@field knowledge string|nil Knowledge cutoff date (e.g., "2024-04")
---@field release_date string Release date in YYYY-MM-DD format
---@field last_updated string Last updated date in YYYY-MM-DD format
---@field modalities OmpModelModalities Supported input/output modalities
---@field open_weights boolean Whether the model has open weights
---@field limit OmpModelLimits Token limits for the model
---@field cost OmpModelCost Pricing information for the model

---@class OmpProvider
---@field id string Unique identifier for the provider
---@field env string[] Required environment variables for authentication
---@field npm string NPM package name for the provider SDK
---@field api string|nil Base API URL for the provider
---@field name string Human-readable name of the provider
---@field doc string|nil Documentation URL for the provider
---@field models table<string, OmpModel> Map of model ID to model configuration

---@class OmpProvidersResponse
---@field providers OmpProvider[] List of available providers
---@field default table<string, string> Map of provider ID to default model ID

---@class OmpToolListItem
---@field id string Tool identifier
---@field description string Tool description
---@field parameters any JSON schema parameters for the tool

---@alias OmpToolList OmpToolListItem[]

---@class OmpAgentPermissionBash
---@field [string] string Permission level ('allow', 'deny', etc.)

---@class OmpAgentPermission
---@field edit string Permission level for edit operations
---@field webfetch string Permission level for web fetch operations
---@field bash OmpAgentPermissionBash Bash command permissions

---@class OmpAgentModel
---@field providerID string Provider identifier
---@field modelID string Model identifier

---@class OmpAgent
---@field name string Unique identifier for the agent
---@field description string Human-readable description of the agent
---@field tools table<string, boolean> Map of tool names to availability
---@field options table Additional configuration options
---@field permission OmpAgentPermission Permissions for various operations
---@field mode 'primary'|'subagent'|'all' Agent execution mode
---@field builtIn boolean Whether this is a built-in agent
---@field model OmpAgentModel|nil Optional model configuration
---@field prompt string|nil Optional custom prompt for the agent
---@field temperature number|nil Optional temperature setting

---@class OmpSlashCommand
---@field slash_cmd string The command trigger (e.g., "/help")
---@field desc string|nil Description of the command
---@field fn fun(args:string[]|nil):nil|Promise<any>|any Function to execute the command
---@field args boolean Whether the command accepts arguments

---@class OmpSelectionRange
---@field start number Starting line number (inclusive)
---@field stop number Ending line number (inclusive)

---@class OmpSessionStatusInfo
---@field type 'idle'|'busy'|'retry' Current status of the session
---@field message? string Human-readable detail (populated for `retry`)
---@field attempt? number Retry attempt counter (populated for `retry`)
---@field next? number Server-side timestamp of the next retry (populated for `retry`)
---@field action? table Optional retry action metadata (populated for `retry`)
