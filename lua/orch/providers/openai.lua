-- lua/orch/providers/openai.lua
-- Uses curl + jobstart to call OpenAI Chat Completions.

local M = {}

--- Build curl command for OpenAI chat
--- @param spec table model spec from config
--- @param payload table { prompt, code }
function M.build_job(spec, payload)
  local api_key = spec.api_key or vim.env.OPENAI_API_KEY
  if not api_key or api_key == "" then
    return nil, "Missing OpenAI API key for model " .. (spec.name or spec.model)
  end

  local endpoint = spec.endpoint or "https://api.openai.com/v1/chat/completions"

  local user_content = payload.prompt or "Act on the following code:"
  if payload.code and payload.code ~= "" then
    user_content = user_content .. "\n\n```code\n" .. payload.code .. "\n```"
  end

  local body = vim.json.encode({
    model = spec.model or "gpt-4.1",
    messages = {
      { role = "user", content = user_content },
    },
    temperature = spec.temperature or 0.2,
  })

  local cmd = {
    "curl",
    "-sS",
    "-X", "POST",
    endpoint,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. api_key,
    "-d", body,
  }

  local parser = function(raw)
    if not raw or raw == "" then
      return nil, "Empty response from OpenAI"
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or not decoded then
      return nil, "Failed to parse OpenAI JSON"
    end

    local choice = decoded.choices and decoded.choices[1]
    if not choice or not choice.message or not choice.message.content then
      return nil, "No choices in OpenAI response"
    end
    return choice.message.content, nil
  end

  return cmd, parser
end

return M
