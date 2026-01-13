-- lua/orch/providers/anthropic.lua
-- Anthropic Messages API via curl.

local M = {}

function M.build_job(spec, payload)
  local api_key = spec.api_key or vim.env.ANTHROPIC_API_KEY
  if not api_key or api_key == "" then
    return nil, "Missing Anthropic API key for model " .. (spec.name or spec.model)
  end

  local endpoint = spec.endpoint or "https://api.anthropic.com/v1/messages"

  local user_content = payload.prompt or "Act on the following code:"
  if payload.code and payload.code ~= "" then
    user_content = user_content .. "\n\n```code\n" .. payload.code .. "\n```"
  end

  local body = vim.json.encode({
    model = spec.model or "claude-3.5-sonnet",
    max_tokens = spec.max_tokens or 2048,
    temperature = spec.temperature or 0.2,
    messages = {
      { role = "user", content = user_content },
    },
  })

  local cmd = {
    "curl",
    "-sS",
    "-X", "POST",
    endpoint,
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. api_key,
    "-H", "anthropic-version: 2023-06-01",
    "-d", body,
  }

  local parser = function(raw)
    if not raw or raw == "" then
      return nil, "Empty response from Anthropic"
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or not decoded then
      return nil, "Failed to parse Anthropic JSON"
    end
    if not decoded.content or not decoded.content[1] or not decoded.content[1].text then
      return nil, "No content in Anthropic response"
    end
    return decoded.content[1].text, nil
  end

  return cmd, parser
end

return M
