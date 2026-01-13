-- lua/orch/providers.lua
--
-- Provider registry for the Lua backend.
-- Mirrors the Go orchd ModelConfig:
-- {
--   name, provider, model,
--   api_key, endpoint,
--   temperature, max_tokens,
-- }
--
-- Each HTTP-based provider exposes:
--   build_job(spec, payload) -> cmd, parse_fn
-- where:
--   spec    = model config table (from user config)
--   payload = { prompt = string, code = string }
--   cmd     = { "curl", ... } list for jobstart()
--   parse_fn(raw) -> text, err_string_or_nil
--
-- Additionally, we expose a small registry + a "fake" provider that uses:
--   run(spec, payload) -> text, err
-- for non-HTTP testing with backend.mode="lua" if desired.

local config = require("orch.config")

local M = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function build_content(prompt, code)
  local p = prompt or ""
  local c = code or ""
  if c ~= "" then
    if p == "" then
      p = "Please analyze the following code:\n"
    end
    p = p .. "\n\n```code\n" .. c .. "\n```"
  end
  return p
end

local function json_encode(tbl)
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    return nil, "Failed to encode JSON: " .. tostring(encoded)
  end
  return encoded, nil
end

local function json_decode(raw)
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    return nil, "Failed to decode JSON: " .. tostring(decoded)
  end
  if type(decoded) ~= "table" then
    return nil, "JSON response is not an object"
  end
  return decoded, nil
end

----------------------------------------------------------------------
-- OpenAI provider
----------------------------------------------------------------------

local openai_impl = {}

function openai_impl.build_job(spec, payload)
  local api_key = spec.api_key or os.getenv("OPENAI_API_KEY")
  if not api_key or api_key == "" then
    return nil, "Missing OpenAI API key"
  end

  local model = spec.model or "gpt-4.1-mini"
  local content = build_content(payload.prompt, payload.code)

  local body = {
    model = model,
    messages = {
      { role = "user", content = content },
    },
  }

  if spec.temperature and spec.temperature > 0 then
    body.temperature = spec.temperature
  end
  if spec.max_tokens and spec.max_tokens > 0 then
    body.max_tokens = spec.max_tokens
  end

  local json_body, err = json_encode(body)
  if not json_body then
    return nil, err
  end

  local endpoint = spec.endpoint or "https://api.openai.com/v1/chat/completions"

  local cmd = {
    "curl",
    "-sS",
    endpoint,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. api_key,
    "-d", json_body,
  }

  local function parse(raw)
    local decoded, perr = json_decode(raw)
    if not decoded then
      return nil, perr
    end

    if decoded.error and decoded.error.message then
      return nil, "openai error: " .. decoded.error.message
    end

    local choices = decoded.choices
    if not choices or #choices == 0 or not choices[1].message then
      return nil, "openai: no choices in response"
    end

    return choices[1].message.content or "", nil
  end

  return cmd, parse
end

----------------------------------------------------------------------
-- Anthropic provider
----------------------------------------------------------------------

local anthropic_impl = {}

function anthropic_impl.build_job(spec, payload)
  local api_key = spec.api_key or os.getenv("ANTHROPIC_API_KEY")
  if not api_key or api_key == "" then
    return nil, "Missing Anthropic API key"
  end

  local model = spec.model or "claude-3.5-sonnet"
  local content = build_content(payload.prompt, payload.code)

  local max_tokens = spec.max_tokens or 2048

  local body = {
    model      = model,
    max_tokens = max_tokens,
    messages   = {
      { role = "user", content = content },
    },
  }

  if spec.temperature and spec.temperature > 0 then
    body.temperature = spec.temperature
  end

  local json_body, err = json_encode(body)
  if not json_body then
    return nil, err
  end

  local endpoint = spec.endpoint or "https://api.anthropic.com/v1/messages"

  local cmd = {
    "curl",
    "-sS",
    endpoint,
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. api_key,
    "-H", "anthropic-version: 2023-06-01",
    "-d", json_body,
  }

  local function parse(raw)
    local decoded, perr = json_decode(raw)
    if not decoded then
      return nil, perr
    end

    if decoded.error and decoded.error.message then
      return nil, "anthropic error: " .. decoded.error.message
    end

    local content_arr = decoded.content
    if not content_arr or #content_arr == 0 then
      return nil, "anthropic: no content in response"
    end

    -- First block's text, matching the Go struct simplification.
    local first = content_arr[1]
    if first.text then
      return first.text, nil
    end

    if first.type == "text" and first.text then
      return first.text, nil
    end

    return nil, "anthropic: could not find text content"
  end

  return cmd, parse
end

----------------------------------------------------------------------
-- Ollama provider
----------------------------------------------------------------------

local ollama_impl = {}

function ollama_impl.build_job(spec, payload)
  local model   = spec.model or "llama3"
  local content = build_content(payload.prompt, payload.code)

  local body = {
    model    = model,
    messages = {
      { role = "user", content = content },
    },
    stream = false,
  }

  local json_body, err = json_encode(body)
  if not json_body then
    return nil, err
  end

  local endpoint = spec.endpoint or "http://127.0.0.1:11434/api/chat"

  local cmd = {
    "curl",
    "-sS",
    endpoint,
    "-H", "Content-Type: application/json",
    "-d", json_body,
  }

  local function parse(raw)
    local decoded, perr = json_decode(raw)
    if not decoded then
      return nil, perr
    end

    if decoded.error then
      return nil, "ollama error: " .. decoded.error
    end

    if decoded.message and decoded.message.content then
      return decoded.message.content, nil
    end

    return nil, "ollama: no message content in response"
  end

  return cmd, parse
end

----------------------------------------------------------------------
-- Provider registry (HTTP-oriented)
----------------------------------------------------------------------

local impls = {
  openai    = openai_impl,
  anthropic = anthropic_impl,
  ollama    = ollama_impl,
}

--- Return the list of configured models with attached impls:
--- {
---   {
---     name     = "sonnet",
---     provider = "anthropic",
---     spec     = <raw model config>,
---     impl     = <provider impl>,
---   },
---   ...
--- }
function M.get_models()
  local cfg    = config.values or {}
  local models = cfg.models or {}

  local out = {}

  for _, m in ipairs(models) do
    local provider_name = m.provider
    local impl          = provider_name and impls[provider_name] or nil

    if not impl then
      vim.notify(
        string.format("[orch] Unknown provider '%s' for model '%s'",
          tostring(provider_name),
          tostring(m.name or m.model)),
        vim.log.levels.WARN
      )
    else
      table.insert(out, {
        name     = m.name or m.model or (provider_name .. "_model"),
        provider = provider_name,
        spec     = m,
        impl     = impl,
      })
    end
  end

  return out
end

----------------------------------------------------------------------
-- Generic registry + fake provider (for backend.mode = "lua")
----------------------------------------------------------------------

-- Generic registry: providers can be looked up by name.
-- This is intended for backends that want to call `impl.run(spec, payload)`
-- instead of building `curl` jobs. We *also* keep the HTTP-based build_job
-- contract above for existing code.
local runtime_registry = {}

--- Register a provider implementation under a name.
--- impl is expected to have at least: run(spec, payload) -> text, err
function M.register(name, impl)
  runtime_registry[name] = impl
end

--- Get a provider implementation by name (first checking the runtime registry,
--- then falling back to the HTTP impls table if needed).
function M.get(name)
  if runtime_registry[name] then
    return runtime_registry[name]
  end
  return impls[name]
end

-- Small fake provider that doesn't call any external API.
-- Useful for testing a pure-Lua backend (backend.mode = "lua", provider = "fake").
local fake_impl = {}

--- Run the fake provider:
--- It simply echoes the prompt and code back in a structured format.
function fake_impl.run(spec, payload)
  local name   = spec.name  or "fake"
  local model  = spec.model or "fake-model"
  local prompt = payload.prompt or ""
  local code   = payload.code   or ""

  local out = {}

  table.insert(out, string.format("[FAKE PROVIDER] %s (%s)", name, model))
  table.insert(out, "")
  table.insert(out, "Prompt:")
  table.insert(out, prompt ~= "" and prompt or "<none>")
  table.insert(out, "")
  table.insert(out, "Code:")
  table.insert(out, code ~= "" and code or "<none>")
  table.insert(out, "")
  table.insert(out, "(This is a fake provider. Use orchd backend for real LLM calls.)")

  return table.concat(out, "\n"), nil
end

-- Register under name "fake" for any Lua backend that uses M.get("fake").run(...)
M.register("fake", fake_impl)

return M
