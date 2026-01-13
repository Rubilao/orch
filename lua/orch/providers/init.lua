-- lua/orch/providers/init.lua
local config = require("orch.config")

local providers = {
  openai    = require("orch.providers.openai"),
  anthropic = require("orch.providers.anthropic"),
  ollama    = require("orch.providers.ollama"),
}

local M = {}

--- Returns list of models with their provider module.
function M.get_models()
  local out = {}
  for _, m in ipairs(config.values.models or {}) do
    local mod = providers[m.provider]
    if mod then
      table.insert(out, {
        name     = m.name or (m.provider .. ":" .. (m.model or "")),
        provider = m.provider,
        spec     = m,
        impl     = mod,
      })
    else
      vim.notify(
        string.format("[orch] Unknown provider '%s' for model '%s'", m.provider, m.name or "?"),
        vim.log.levels.WARN
      )
    end
  end
  return out
end

return M
