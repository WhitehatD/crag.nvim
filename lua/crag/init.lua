--- crag.nvim - governance for AI coding agents
--- Wraps the crag CLI with Neovim-native UI: status line, diagnostics, commands.

local M = {}

--- @class CragConfig
--- @field auto_compile boolean Auto-recompile on governance.md save
--- @field status_line boolean Show drift status in statusline
--- @field diagnostics boolean Show audit results as diagnostics
--- @field cli_path string|nil Custom path to crag binary
local defaults = {
  auto_compile = true,
  status_line = true,
  diagnostics = true,
  cli_path = nil,
}

local config = {}
local ns = vim.api.nvim_create_namespace('crag')
local last_audit = nil --- @type table|nil
local status_text = ''

local function is_windows()
  return vim.loop.os_uname().sysname:match('Windows') ~= nil
end

local function file_exists(path)
  return path and vim.loop.fs_stat(path) ~= nil
end

local function executable(path)
  return vim.fn.executable(path) == 1 or file_exists(path)
end

--- Resolve crag argv prefix.
--- @return string[]
local function crag_argv_prefix()
  if config.cli_path and config.cli_path ~= '' then
    return { config.cli_path }
  end

  local ext = is_windows() and '.cmd' or ''
  local local_bin = vim.fn.getcwd() .. '/node_modules/.bin/crag' .. ext
  if executable(local_bin) then
    return { local_bin }
  end

  local global_bin = 'crag' .. ext
  if vim.fn.executable(global_bin) == 1 then
    return { global_bin }
  end

  return is_windows()
    and { 'npx.cmd', '--yes', '@whitehatd/crag' }
    or { 'npx', '--yes', '@whitehatd/crag' }
end

--- Build a full argv list for crag.
--- @param args string[]
--- @return string[]
local function build_argv(args)
  return vim.list_extend(vim.deepcopy(crag_argv_prefix()), args)
end

--- Run crag command asynchronously with JSON output.
--- @param args string[] CLI arguments
--- @param callback fun(ok: boolean, data: table|nil, raw: string)
local function run_json(args, callback)
  local raw_out = ''
  local raw_err = ''

  vim.fn.jobstart(build_argv(args), {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    env = { CRAG_NO_UPDATE_CHECK = '1', NO_COLOR = '1' },
    on_stdout = function(_, data)
      raw_out = table.concat(data or {}, '\n')
    end,
    on_stderr = function(_, data)
      raw_err = table.concat(data or {}, '\n')
    end,
    on_exit = function(_, code)
      local raw = raw_out
      if raw_err ~= '' then
        raw = raw == '' and raw_err or (raw .. '\n\n' .. raw_err)
      end

      if code ~= 0 then
        if raw_err ~= '' then
          vim.schedule(function()
            vim.notify('[crag] ' .. raw_err, vim.log.levels.WARN)
          end)
        end
        callback(false, nil, raw)
        return
      end

      local ok, parsed = pcall(vim.json.decode, raw_out)
      callback(ok, ok and parsed or nil, raw)
    end,
  })
end

--- Run crag command and show output in a split.
--- @param args string[]
local function run_display(args)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.api.nvim_buf_set_name(buf, '[crag ' .. args[1] .. ']')
  vim.cmd('botright split')
  vim.api.nvim_win_set_buf(0, buf)

  local output = {}

  vim.fn.jobstart(build_argv(args), {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    env = { CRAG_NO_UPDATE_CHECK = '1', NO_COLOR = '1' },
    on_stdout = function(_, data)
      if data then
        vim.list_extend(output, data)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        if #output > 0 then
          table.insert(output, '')
        end
        vim.list_extend(output, data)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if #output == 0 then
          output = { code == 0 and '(no output)' or ('Command failed with exit code ' .. code) }
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
      end)
    end,
  })
end

local update_status
local update_diagnostics
local find_command_line

local function refresh_audit()
  run_json({ 'audit', '--json' }, function(ok, data)
    if not ok or not data then
      return
    end
    last_audit = data
    vim.schedule(function()
      update_status()
      if config.diagnostics then
        update_diagnostics(data)
      end
    end)
  end)
end

update_status = function()
  if not config.status_line then
    status_text = ''
    return
  end

  if not last_audit or not last_audit.summary then
    status_text = 'crag'
    return
  end

  local s = last_audit.summary
  local issues = (s.stale or 0) + (s.drift or 0) + (s.missing or 0)
  if issues == 0 then
    local total = (s.current or 0) + (s.stale or 0) + (s.missing or 0)
    status_text = string.format('crag: %d/%d synced', s.current or 0, total)
  else
    local parts = {}
    if (s.stale or 0) > 0 then
      table.insert(parts, s.stale .. ' stale')
    end
    if (s.drift or 0) > 0 then
      table.insert(parts, s.drift .. ' drift')
    end
    if (s.missing or 0) > 0 then
      table.insert(parts, s.missing .. ' missing')
    end
    status_text = 'crag: ' .. table.concat(parts, ' | ')
  end
end

update_diagnostics = function(data)
  vim.diagnostic.reset(ns)

  local cwd = vim.fn.getcwd()
  local gov_path = cwd .. '/.claude/governance.md'
  -- Normalize path separators for buffer matching on Windows
  local gov_normalized = gov_path:gsub('\\', '/')
  local bufnr = -1
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local bname = vim.api.nvim_buf_get_name(b):gsub('\\', '/')
    if bname == gov_normalized then
      bufnr = b
      break
    end
  end
  if bufnr == -1 then
    return
  end

  local diagnostics = {}

  for _, entry in ipairs(data.drift or {}) do
    table.insert(diagnostics, {
      lnum = find_command_line(bufnr, entry.command),
      col = 0,
      message = 'Drift: ' .. entry.command .. ' - ' .. (entry.detail or ''),
      severity = vim.diagnostic.severity.ERROR,
      source = 'crag',
    })
  end

  for _, entry in ipairs(data.stale or {}) do
    table.insert(diagnostics, {
      lnum = 0,
      col = 0,
      message = 'Stale: ' .. entry.path .. ' - governance.md is newer',
      severity = vim.diagnostic.severity.WARN,
      source = 'crag',
    })
  end

  for _, entry in ipairs(data.missing or {}) do
    table.insert(diagnostics, {
      lnum = 0,
      col = 0,
      message = 'Missing: ' .. entry.target .. (entry.indicator and (' - ' .. entry.indicator) or ''),
      severity = vim.diagnostic.severity.WARN,
      source = 'crag',
    })
  end

  for _, entry in ipairs(data.extra or {}) do
    table.insert(diagnostics, {
      lnum = 0,
      col = 0,
      message = 'Extra: ' .. entry.command .. ' - in CI but not governance',
      severity = vim.diagnostic.severity.HINT,
      source = 'crag',
    })
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Find line number of a gate command in governance.md buffer.
find_command_line = function(bufnr, command)
  if not command or command == '' then
    return 0
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local needle = command:lower():match('^%s*(.-)%s*$')
  for i, line in ipairs(lines) do
    if line:match('^%- ') then
      local cmd = line:sub(3):lower():match('^%s*(.-)%s*$')
      if cmd == needle or cmd:find(needle, 1, true) then
        return i - 1
      end
    end
  end
  return 0
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup('crag', { clear = true })

  if config.auto_compile then
    -- Use both forward and backslash patterns for Windows compatibility
    local patterns = is_windows()
      and { '*/.claude/governance.md', '*\\.claude\\governance.md' }
      or { '*/.claude/governance.md' }
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = group,
      pattern = patterns,
      callback = function()
        vim.notify('[crag] governance.md saved - recompiling...', vim.log.levels.INFO)
        vim.fn.jobstart(build_argv({ 'compile', '--target', 'all' }), {
          cwd = vim.fn.getcwd(),
          stdout_buffered = true,
          stderr_buffered = true,
          env = { CRAG_NO_UPDATE_CHECK = '1', NO_COLOR = '1' },
          on_exit = function(_, code)
            vim.schedule(function()
              if code == 0 then
                vim.notify('[crag] recompiled', vim.log.levels.INFO)
                refresh_audit()
              else
                vim.notify('[crag] compile failed', vim.log.levels.ERROR)
              end
            end)
          end,
        })
      end,
    })
  end
end

local function register_commands()
  vim.api.nvim_create_user_command('CragAnalyze', function()
    run_display({ 'analyze' })
  end, { desc = 'Generate governance.md from project' })

  vim.api.nvim_create_user_command('CragCompile', function(opts)
    local target = opts.args ~= '' and opts.args or 'all'
    run_display({ 'compile', '--target', target })
  end, { desc = 'Compile governance to targets', nargs = '?' })

  vim.api.nvim_create_user_command('CragScaffold', function()
    run_display({ 'compile', '--target', 'scaffold' })
  end, { desc = 'Generate hooks, settings, agents, CI playbook' })

  vim.api.nvim_create_user_command('CragAudit', function()
    run_display({ 'audit' })
    refresh_audit()
  end, { desc = 'Audit governance drift' })

  vim.api.nvim_create_user_command('CragDiff', function()
    run_display({ 'diff' })
  end, { desc = 'Diff governance vs codebase reality' })

  vim.api.nvim_create_user_command('CragDoctor', function()
    run_display({ 'doctor' })
  end, { desc = 'Full diagnostic' })

  vim.api.nvim_create_user_command('CragHookInstall', function()
    run_display({ 'hook', 'install' })
  end, { desc = 'Install pre-commit hook' })

  vim.api.nvim_create_user_command('CragRefresh', function()
    refresh_audit()
  end, { desc = 'Refresh crag audit state' })
end

--- Returns the crag status string for use in statusline.
--- Usage in lualine: require('crag').status()
--- Usage raw: vim.o.statusline = '%{v:lua.require("crag").status()}'
function M.status()
  return config.status_line == false and '' or status_text
end

function M.refresh()
  refresh_audit()
end

--- @param opts CragConfig|nil
function M.setup(opts)
  config = vim.tbl_deep_extend('force', defaults, opts or {})

  register_commands()
  setup_autocmds()

  local gov_path = vim.fn.getcwd() .. '/.claude/governance.md'
  if vim.fn.filereadable(gov_path) == 1 then
    vim.defer_fn(refresh_audit, 1000)
  else
    status_text = config.status_line == false and '' or 'crag: no governance'
  end
end

return M
