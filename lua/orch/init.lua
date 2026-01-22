-- lua/orch/init.lua
--
-- Public Neovim-facing API for Orch.
-- This wraps the internal core + commands modules and exposes a stable surface:
--
--   require("orch").setup(opts)
--   require("orch").ask({ prompt = "..." })
--   require("orch").apply(model_name)
--   require("orch").merge(model_name)
--   require("orch").preview_last_hunk()
--   require("orch").compare()
--   require("orch").toggle_streaming()
--   require("orch").print_config()
--
-- For backward compatibility we also export:
--   require("orch").run_ask = require("orch").ask

local core     = require("orch.core")
local commands = require("orch.commands")

local M = {}

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------

--- Initialize Orch configuration from user opts.
-- This just forwards into core.setup (which uses orch.config under the hood).
-- @param opts table|nil
function M.setup(opts)
  core.setup(opts or {})
end

----------------------------------------------------------------------
-- High-level actions
----------------------------------------------------------------------

--- Ask all configured models with a prompt + optional range/snippet.
-- Usage:
--   :OrchAsk "Explain this"
--   require("orch").ask({ prompt = "Explain this", range = { ... } })
--
-- @param opts table|nil  { prompt = string, range = {start_line, end_line}? }
function M.ask(opts)
  core.ask(opts or {})
end

-- Backward-compatible alias for older code that called run_ask.
-- This fixes "attempt to call field 'run_ask' (a nil value)" if plugin code
-- or user mappings were still calling require("orch").run_ask(...)
M.run_ask = M.ask

--- Apply a full model result over the original selection/buffer.
-- @param model_name string|nil
function M.apply(model_name)
  core.apply(model_name)
end

--- Interactive hunk-by-hunk merge from a model result.
-- @param model_name string|nil
function M.merge(model_name)
  core.merge(model_name)
end

--- Re-open the last hunk preview window in read-only mode.
function M.preview_last_hunk()
  core.preview_last_hunk()
end

--- Compare last run's model outputs in a unified window.
function M.compare()
  core.compare()
end

----------------------------------------------------------------------
-- Convenience wrappers for commands
----------------------------------------------------------------------

--- Toggle streaming mode for the orchd backend.
function M.toggle_streaming()
  commands.toggle_streaming()
end

--- Print the effective Orch config (as seen by Neovim).
function M.print_config()
  commands.print_config()
end

return M
