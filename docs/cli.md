# orchd CLI

## Basic Usage

Pipe JSON into stdin:

```bash
echo '{...}' | orchd
orchd < file.json
```

## Flags

### --help
Show help.

### --version
Show version.

### --config
Print request/config schema.

### --doctor
Check environment, API keys, Ollama status.

### --check-request
Validate request JSON without calling APIs.

## Streaming Mode

If `"stream": true`, output is newline-delimited JSON events:

```json
{"event":"result", "name":"gpt4", "text":"..."}
{"event":"done"}
```
