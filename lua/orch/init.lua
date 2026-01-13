-- lua/orch/init.lua
local config = require("orch.config")
local core   = require("orch.core")

local M = {}

function M.setup(opts)
  config.setup(opts or {})
  config.apply_keymaps()
end

--- Run an Orch ask with options.
--- @param opts table? { prompt?: string, range?: {start_line, end_line}, mode?: "plain"|"diff", models?: string[] }
function M.ask(opts)
  core.run_ask(opts or {})
end

--- Apply a model result from the last Orch run (full range).
--- @param model_name string|nil
function M.apply(model_name)
  core.apply_model(model_name)
end

--- Interactively merge hunks from a model result.
--- @param model_name string|nil
function M.merge(model_name)
  core.merge_model(model_name)
end

--- Re-open the last hunk preview (read-only).
function M.preview_last_hunk()
  core.preview_last_hunk()
end

--- Side-by-side comparison of last results.
function M.compare()
  core.compare_models()
end

return M

