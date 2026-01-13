package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/oorrwullie/orchd/internal/orch"
)

func printUsage() {
	fmt.Fprintf(os.Stderr, `orchd - multi-LLM orchestrator daemon

Usage:
  echo '{...}' | orchd
  orchd < request.json

Reads a JSON request on stdin and writes a JSON response to stdout.

Flags:
  -h, --help          Show this help message
  -v, --version       Print version and exit
  --config            Print the JSON request / model config schema and exit
  --doctor            Run environment / provider checks and exit
  --check-request     Validate a JSON request from stdin and exit (no API calls)

JSON request shape (simplified):
  {
    "prompt": "string",
    "code": "string",
    "models": [
      {
        "name": "sonnet",
        "provider": "anthropic",
        "model": "claude-3.5-sonnet",
        "api_key": "...",
        "endpoint": "...",
        "temperature": 0.2,
        "max_tokens": 2048
      }
    ],
    "timeout_seconds": 30,
    "stream": false
  }
`)
}

func printConfigSchema() {
	fmt.Print(`orchd configuration schema

The orchd daemon expects a JSON document on stdin.

ModelConfig (per model):
{
  "name":        "short name used in Neovim (e.g. 'sonnet')",
  "provider":    "provider ID (e.g. 'anthropic', 'openai', 'ollama')",
  "model":       "provider-specific model ID (e.g. 'claude-3.5-sonnet', 'gpt-4.1')",

  "api_key":     "optional; API key override. If omitted, reads from provider-specific env var",
  "endpoint":    "optional; API endpoint override. Provider default is used if omitted",

  "temperature": 0.0,
  "max_tokens":  0
}

Request:
{
  "prompt":          "string prompt (high-level instruction)",
  "code":            "string containing the code snippet / buffer contents",
  "models":          [ ModelConfig, ... ],
  "timeout_seconds": 30,
  "stream":          false
}

Notes about providers:

- provider = "openai"
  - Default endpoint: https://api.openai.com/v1/chat/completions
  - API key:   env OPENAI_API_KEY (or ModelConfig.api_key)

- provider = "anthropic"
  - Endpoint:  https://api.anthropic.com/v1/messages
  - API key:   env ANTHROPIC_API_KEY (or ModelConfig.api_key)

- provider = "ollama"
  - Endpoint:  default http://127.0.0.1:11434/api/chat (override with ModelConfig.endpoint)
  - No API key used; assumes local Ollama daemon.

The Neovim plugin sends exactly this JSON into orchd with:
- "models" taken from its Lua configuration,
- "prompt" and "code" from the editor selection,
- "stream" controlled by backend.streaming.
`)
}

func runDoctor() {
	fmt.Printf("orchd doctor\n")
	fmt.Printf("Version: %s\n\n", orch.Version)

	type check struct {
		Name   string
		EnvVar string
		Note   string
	}

	checks := []check{
		{
			Name:   "OpenAI",
			EnvVar: "OPENAI_API_KEY",
			Note:   "required for provider=\"openai\" unless api_key is set per-model",
		},
		{
			Name:   "Anthropic",
			EnvVar: "ANTHROPIC_API_KEY",
			Note:   "required for provider=\"anthropic\" unless api_key is set per-model",
		},
	}

	fmt.Println("Environment / provider checks:")
	for _, c := range checks {
		if v, ok := os.LookupEnv(c.EnvVar); ok && v != "" {
			fmt.Printf("  [OK]   %s: %s is set\n", c.Name, c.EnvVar)
		} else {
			fmt.Printf("  [WARN] %s: %s is NOT set (%s)\n", c.Name, c.EnvVar, c.Note)
		}
	}

	fmt.Println()
	fmt.Println("Ollama:")
	fmt.Println("  [INFO] provider=\"ollama\" assumes a local daemon at http://127.0.0.1:11434")
	fmt.Println("         No environment variables are required; configure \"endpoint\" if needed.")
	fmt.Println()
	fmt.Println("Neovim plugin:")
	fmt.Println("  - Ensure orchd is on your $PATH (e.g. /usr/local/bin/orchd).")
	fmt.Println("  - Ensure the Neovim plugin's `backend.mode` is set to \"orchd\" to use this daemon.")
	fmt.Println()
	fmt.Println("If you are still seeing errors, run Neovim's :OrchPrintConfig and compare")
	fmt.Println("your model definitions with the schema shown by `orchd --config`.")
}

// runCheckRequest reads JSON from stdin, attempts to unmarshal into orch.Request,
// performs basic validation, and prints a summary. It does NOT call any providers.
func runCheckRequest() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[check-request] failed to read stdin: %v\n", err)
		os.Exit(1)
	}

	if len(data) == 0 {
		fmt.Fprintf(os.Stderr, "[check-request] no input provided on stdin\n")
		os.Exit(1)
	}

	var req orch.Request
	if err := json.Unmarshal(data, &req); err != nil {
		fmt.Fprintf(os.Stderr, "[check-request] invalid JSON input: %v\n", err)
		os.Exit(1)
	}

	var issues []string

	if len(req.Models) == 0 {
		issues = append(issues, "no models configured (models array is empty)")
	}

	for i, m := range req.Models {
		prefix := fmt.Sprintf("models[%d]", i)

		if m.Name == "" {
			issues = append(issues, fmt.Sprintf("%s.name is empty", prefix))
		}
		if m.Provider == "" {
			issues = append(issues, fmt.Sprintf("%s.provider is empty", prefix))
		}
		if m.Model == "" {
			issues = append(issues, fmt.Sprintf("%s.model is empty", prefix))
		}
	}

	if req.TimeoutSeconds < 0 {
		issues = append(issues, "timeout_seconds is negative")
	}

	if len(issues) > 0 {
		fmt.Println("Request is NOT valid:")
		for _, iss := range issues {
			fmt.Printf("  - %s\n", iss)
		}
		os.Exit(1)
	}

	fmt.Println("Request looks valid.")
	fmt.Printf("  prompt length: %d\n", len(req.Prompt))
	fmt.Printf("  code length:   %d\n", len(req.Code))
	fmt.Printf("  models:        %d\n", len(req.Models))
	for i, m := range req.Models {
		fmt.Printf("    [%d] name=%q provider=%q model=%q\n", i, m.Name, m.Provider, m.Model)
	}
	if req.TimeoutSeconds > 0 {
		fmt.Printf("  timeout_seconds: %d\n", req.TimeoutSeconds)
	} else {
		fmt.Println("  timeout_seconds: (not set, default will be 30)")
	}
	fmt.Printf("  stream:         %v\n", req.Stream)
}

func main() {
	args := os.Args[1:]

	for _, a := range args {
		switch a {
		case "-h", "--help":
			printUsage()
			return
		case "-v", "--version", "-version":
			fmt.Printf("orchd %s\n", orch.Version)
			return
		case "--config", "-config":
			printConfigSchema()
			return
		case "--doctor":
			runDoctor()
			return
		case "--check-request":
			runCheckRequest()
			return
		}
	}

	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read stdin: %v\n", err)
		os.Exit(1)
	}

	if len(data) == 0 {
		fmt.Fprintf(os.Stderr, "no input provided on stdin (see --help for usage)\n")
		os.Exit(1)
	}

	var req orch.Request
	if err := json.Unmarshal(data, &req); err != nil {
		fmt.Fprintf(os.Stderr, "invalid JSON input: %v\n", err)
		os.Exit(1)
	}

	if req.TimeoutSeconds <= 0 {
		req.TimeoutSeconds = 30
	}

	ctx, cancel := orch.WithTimeout(time.Duration(req.TimeoutSeconds) * time.Second)
	defer cancel()

	if req.Stream {
		// Streaming mode: newline-delimited JSON events
		if err := orch.RunStream(ctx, req, os.Stdout); err != nil {
			fmt.Fprintf(os.Stderr, "streaming error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Non-streaming: single JSON response
	resp := orch.Run(ctx, req)

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(resp); err != nil {
		fmt.Fprintf(os.Stderr, "failed to marshal response: %v\n", err)
		os.Exit(1)
	}
}
