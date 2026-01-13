-- plugin/orch.lua
-- Entry point: registers user commands and wires them to the core API.

if vim.g.loaded_orch then
  return
end
vim.g.loaded_orch = true

local orch     = require("orch")
local commands = require("orch.commands")

vim.api.nvim_create_user_command("OrchSetup", function(_)
  print("Orch is configured in your Lua config via require('orch').setup()")
end, {
  nargs = "?",
  desc = "Configure Orch multi-LLM orchestrator",
})

-- Generic ask with a user-provided prompt
vim.api.nvim_create_user_command("OrchAsk", function(opts)
  orch.ask({
    prompt = opts.args ~= "" and opts.args or nil,
    range  = opts.range > 0 and { start_line = opts.line1, end_line = opts.line2 } or nil,
  })
end, {
  nargs = "?",
  range = true,
  desc = "Send code + custom prompt to all configured LLMs via Orch",
})

-- Preset: Explain
vim.api.nvim_create_user_command("OrchExplain", function(opts)
  orch.ask({
    prompt = "Explain the following code in detail, including what it does, potential pitfalls, and any improvements you would suggest.",
    range  = opts.range > 0 and { start_line = opts.line1, end_line = opts.line2 } or nil,
  })
end, {
  nargs = 0,
  range = true,
  desc = "Explain the selected code using all configured LLMs",
})

-- Preset: Refactor (diff mode)
vim.api.nvim_create_user_command("OrchRefactor", function(opts)
  orch.ask({
    prompt = "Refactor the following code for clarity, maintainability, and idiomatic style. Keep the behavior the same. Return only the refactored code.",
    range  = opts.range > 0 and { start_line = opts.line1, end_line = opts.line2 } or nil,
    mode   = "diff",
  })
end, {
  nargs = 0,
  range = true,
  desc = "Refactor the selected code using all configured LLMs (diff mode)",
})

-- Preset: Test generation
vim.api.nvim_create_user_command("OrchTestGen", function(opts)
  orch.ask({
    prompt = "Write unit tests for the following code. Use clear test case names and focus on edge cases as well as the happy path.",
    range  = opts.range > 0 and { start_line = opts.line1, end_line = opts.line2 } or nil,
  })
end, {
  nargs = 0,
  range = true,
  desc = "Generate tests for the selected code using all configured LLMs",
})

-- Apply a model’s output back to the original buffer (whole selection/buffer)
vim.api.nvim_create_user_command("OrchApply", function(opts)
  orch.apply(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",  -- optional model name
  desc = "Apply Orch result by model name (default: first model, full range)",
})

-- Hunk-by-hunk interactive merge from a given model
vim.api.nvim_create_user_command("OrchMerge", function(opts)
  orch.merge(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc = "Interactively merge hunks from a model result (default: first model)",
})

-- Re-open the last hunk preview (read-only, no apply)
vim.api.nvim_create_user_command("OrchHunkPreview", function(_)
  orch.preview_last_hunk()
end, {
  nargs = 0,
  desc = "Re-open the last hunk preview (original/new/diff) without applying",
})

-- Print full Orch config in a floating window
vim.api.nvim_create_user_command("OrchPrintConfig", function()
  commands.print_config()
end, {
  nargs = 0,
  desc = "Show the resolved Orch configuration in a floating window",
})

-- Run backend.restart_cmd to restart orchd daemon (user-defined)
vim.api.nvim_create_user_command("OrchRestartDaemon", function()
  commands.restart_daemon()
end, {
  nargs = 0,
  desc = "Run backend.restart_cmd to restart the orchd daemon",
})

-- Toggle backend.streaming flag (for orchd)
vim.api.nvim_create_user_command("OrchToggleStreaming", function()
  commands.toggle_streaming()
end, {
  nargs = 0,
  desc = "Toggle Orch backend.streaming (for orchd streaming mode)",
})

-- Side-by-side floating comparison of last results
vim.api.nvim_create_user_command("OrchCompareModels", function()
  orch.compare()
end, {
  nargs = 0,
  desc = "Show last Orch results side-by-side in a floating window",
})

-- Telescope: pick model and ask with prompt
vim.api.nvim_create_user_command("OrchAskPick", function()
  local prompt = vim.fn.input("Orch prompt: ")
  if not prompt or prompt == "" then
    return
  end

  local ok, picker = pcall(require, "orch.telescope")
  if not ok then
    vim.notify("[orch] telescope.nvim not available.", vim.log.levels.ERROR)
    return
  end

  picker.ask_with_model_picker(prompt)
end, {
  nargs = 0,
  desc = "Use Telescope to pick a model, then run OrchAsk with a prompt",
})

