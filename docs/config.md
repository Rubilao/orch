# Orch / orchd Configuration

This document describes the JSON schema used by **orchd**, the Go daemon behind the Orch Neovim plugin.

## Overview

`orchd` takes a single JSON document on stdin and writes either:
- a single JSON response, or
- newline-delimited streaming events.

## Request Schema

```jsonc
{
  "prompt": "string",
  "code": "string",
  "models": [ ModelConfig ],
  "timeout_seconds": 30,
  "stream": false
}
```

## ModelConfig

```jsonc
{
  "name": "friendly-name",
  "provider": "openai | anthropic | ollama",
  "model": "provider-specific model ID",
  "api_key": "optional",
  "endpoint": "optional",
  "temperature": 0.2,
  "max_tokens": 2048
}
```

## Providers

### OpenAI
- Endpoint: https://api.openai.com/v1/chat/completions
- Env var: OPENAI_API_KEY

### Anthropic
- Endpoint: https://api.anthropic.com/v1/messages
- Env var: ANTHROPIC_API_KEY

### Ollama
- Endpoint: http://127.0.0.1:11434/api/chat
- No API key required.

## Example Request

```json
{
  "prompt": "Explain this code.",
  "code": "print(\"Hello\")",
  "models": [
    { "name": "gpt4", "provider": "openai", "model": "gpt-4.1" }
  ],
  "timeout_seconds": 30,
  "stream": false
}
```
