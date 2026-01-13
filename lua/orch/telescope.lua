-- lua/orch/telescope.lua
local config = require("orch.config")

local M = {}

--- Use Telescope to pick a model, then run Orch.ask with that single model.
--- @param prompt string
function M.ask_with_model_picker(prompt)
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    vim.notify("[orch] telescope.nvim not available.", vim.log.levels.ERROR)
    return
  end

  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local cfg     = config.values
  local models  = cfg.models or {}
  if vim.tbl_isempty(models) then
    vim.notify("[orch] No models configured.", vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = "Orch: choose model",
    finder = finders.new_table({
      results = models,
      entry_maker = function(m)
        local name     = m.name or m.model or "unnamed"
        local provider = m.provider or "?"
        local model_id = m.model or "?"
        return {
          value   = name,
          display = string.format("%s (%s:%s)", name, provider, model_id),
          ordinal = name .. " " .. provider .. " " .. model_id,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr, map)
      local function on_select()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        if not entry or not entry.value then
          return
        end
        local model_name = entry.value
        local orch = require("orch")
        orch.ask({
          prompt = prompt,
          models = { model_name },
        })
      end

      map("i", "<CR>", on_select)
      map("n", "<CR>", on_select)
      return true
    end,
  }):find()
end

return M
