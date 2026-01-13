-- lua/orch/commands.lua
local config = require("orch.config")

local M = {}

local function open_float_with_text(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "json")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width  = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_win_close, 0, true)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.print_config()
  local ok, encoded = pcall(vim.json.encode, config.values, { indent = true })
  if not ok then
    vim.notify("[orch] Failed to encode config as JSON: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end

  local lines = vim.split(encoded, "\n", { plain = true })
  open_float_with_text(lines)
end

function M.restart_daemon()
  local backend = config.values.backend or {}
  local restart_cmd = backend.restart_cmd

  if not restart_cmd then
    vim.notify(
      "[orch] backend.restart_cmd not configured; restart orchd manually (e.g. via systemd/brew/services).",
      vim.log.levels.WARN
    )
    return
  end

  local cmd = restart_cmd
  if type(cmd) == "string" then
    cmd = { cmd }
  end

  local job_id = vim.fn.jobstart(cmd, {
    on_exit = function(_, code, _)
      if code == 0 then
        vim.notify("[orch] orchd daemon restart command completed successfully.", vim.log.levels.INFO)
      else
        vim.notify("[orch] orchd daemon restart command failed (exit code " .. code .. ")", vim.log.levels.ERROR)
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("[orch] Failed to start restart_cmd job.", vim.log.levels.ERROR)
  end
end

function M.toggle_streaming()
  local backend = config.values.backend or {}
  local current = backend.streaming or false
  local new_val = not current

  backend.streaming = new_val
  config.values.backend = backend

  local mode = (config.values.backend.mode or "lua")
  if mode ~= "orchd" then
    vim.notify(string.format(
      "[orch] Streaming=%s (note: backend.mode is '%s'; streaming only applies when mode='orchd').",
      tostring(new_val), mode
    ), vim.log.levels.WARN)
  else
    vim.notify("[orch] Streaming is now " .. (new_val and "ENABLED" or "DISABLED"), vim.log.levels.INFO)
  end
end

return M

