-- lua/orch/providers/ollama.lua
-- Local models via Ollama /api/chat.

local M = {}

function M.build_job(spec, payload)
  local endpoint = (spec.endpoint or "http://127.0.0.1:11434") .. "/api/chat"

  local user_content = payload.prompt or "Act on the following code:"
  if payload.code and payload.code ~= "" then
    user_content = user_content .. "\n\n```code\n" .. payload.code .. "\n```"
  end

  local body = vim.json.encode({
    model = spec.model or "llama3.1:8b",
    messages = {
      { role = "user", content = user_content },
    },
    stream = false,
  })

  local cmd = {
    "curl",
    "-sS",
    "-X", "POST",
    endpoint,
    "-H", "Content-Type: application/json",
    "-d", body,
  }

  local parser = function(raw)
    if not raw or raw == "" then
      return nil, "Empty response from Ollama"
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or not decoded then
      return nil, "Failed to parse Ollama JSON"
    end
    local msg = decoded.message
    if not msg or not msg.content then
      return nil, "No message content in Ollama response"
    end
    return msg.content, nil
  end

  return cmd, parser
end

return M
