local M = {}

local function report_ok(msg)
  vim.health.ok(msg)
end

local function report_warn(msg)
  vim.health.warn(msg)
end

function M.check()
  vim.health.start('crag.nvim')

  if vim.fn.has('nvim-0.9') == 1 then
    report_ok('Neovim 0.9+ detected')
  else
    report_warn('Neovim 0.9+ is recommended')
  end

  if vim.fn.executable('crag') == 1 then
    report_ok('crag CLI found on PATH')
  elseif vim.fn.executable('npx') == 1 or vim.fn.executable('npx.cmd') == 1 then
    report_ok('npx fallback available for @whitehatd/crag')
  else
    report_warn('Neither crag nor npx was found on PATH')
  end

  local gov = vim.fn.getcwd() .. '/.claude/governance.md'
  if vim.fn.filereadable(gov) == 1 then
    report_ok('Found .claude/governance.md in the current working directory')
  else
    report_warn('No .claude/governance.md found in the current working directory')
  end
end

return M
