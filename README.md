<p align="center">

  <!-- Version (uses GitHub releases) -->
  <a href="https://github.com/oorrwullie/orch/releases">
    <img src="https://img.shields.io/github/v/release/oorrwullie/orch?label=version&color=blue" alt="Version">
  </a>

  <!-- License -->
  <a href="https://github.com/oorrwullie/orch/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT">
  </a>

  <!-- Go build -->
  <a href="https://github.com/oorrwullie/orch/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/oorrwullie/orch/go.yml?label=orchd%20build&logo=go" alt="Go Build">
  </a>

  <!-- Neovim version -->
  <img src="https://img.shields.io/badge/Neovim-0.9%2B-57A143.svg?logo=neovim&logoColor=white" alt="Neovim 0.9+">

  <!-- Lua badge -->
  <img src="https://img.shields.io/badge/Lua-5.1%2B-blue.svg?logo=lua&logoColor=white" alt="Lua">

  <!-- Stars -->
  <a href="https://github.com/oorrwullie/orch/stargazers">
    <img src="https://img.shields.io/github/stars/oorrwullie/orch?style=social" alt="GitHub Stars">
  </a>

  <!-- PRs Welcome -->
  <a href="https://github.com/oorrwullie/orch/pulls">
    <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome">
  </a>

  <!-- Made for Neovim -->
  <img src="https://img.shields.io/badge/Made%20for-Neovim-57A143.svg?logo=neovim&logoColor=white" alt="Made for Neovim">

  <!-- Powered by orchd -->
  <img src="https://img.shields.io/badge/powered%20by-orchd-black.svg?logo=go&logoColor=white" alt="Powered by orchd">

</p>
# Orch — Multi‑Model LLM Orchestrator for Neovim

**Orch** is a Neovim plugin + optional Go daemon (`orchd`) that lets you run **multiple LLMs in parallel**, compare outputs side‑by‑side, diff and merge patches hunk‑by‑hunk, stream results as they arrive, and apply patches directly to your buffer — all without leaving Neovim.

Think of it as:

**Cursor / Windsurf / Claude Desktop — but entirely inside Neovim, fully model‑agnostic, and fully under your control.**

---

# ✨ Features

### 🔀 Multi‑Model Orchestration
- Configure *any number* of models.
- Run them in **parallel** with a single command.
- Compare outputs across OpenAI, Anthropic, Ollama, and more.

### 🪟 Rich UI
- Unified results buffer
- Per‑model scratch sections
- Side‑by‑side **floating comparison windows**
- **Hunk‑by‑hunk merge mode** with:
  - Original view
  - Patched view
  - Unified diff
- Reopen last hunk preview with:
  ```
  :OrchHunkPreview
  ```

### ⚡ Streaming
`orchd` supports true streaming output:

```
{"event":"result","name":"gpt4","text":"..."}
{"event":"result","name":"sonnet","text":"..."}
{"event":"done"}
```

The Neovim streaming backend updates live as tokens arrive.

Toggle at any time:

```
:OrchToggleStreaming
```

### 🧠 Built‑in Smart Commands
- `:OrchAsk` — freeform prompt
- `:OrchExplain` — explain code
- `:OrchRefactor` — refactor with diff/merge mode
- `:OrchTestGen` — generate tests
- `:OrchApply` — apply full model output
- `:OrchMerge` — interactive merge
- `:OrchCompareModels` — side‑by‑side all‑model view
- `:OrchAskPick` — Telescope‑powered model picker

### 🛠️ Config + Debug Tools
- `:OrchPrintConfig` — view effective config
- `orchd --doctor` — check env vars, providers, PATH
- `orchd --config` — print full JSON request schema
- `orchd --check-request` — validate JSON against schema

---

# 🚧 Roadmap Highlights

Already implemented:
- Streaming responses
- Per‑model floating windows
- Diff mode with hunk merging
- Apply‑patch UI
- Model picker via Telescope
- Go backend with concurrency + streaming

Coming soon:
- Judge model (best‑of‑N selection)
- Merge model (response synthesizer)
- Conflict detection
- Workspace‑wide transformations
- Project presets

---

# ⚙️ Installation

## Lazy.nvim Example

```lua
{
  "oorrwullie/orch",
  config = function()
    local orch = require("orch")

    orch.setup({
      models = {
        {
          name     = "sonnet",
          provider = "anthropic",
          model    = "claude-3.5-sonnet",
          api_key  = os.getenv("ANTHROPIC_API_KEY"),
        },
        {
          name     = "gpt4",
          provider = "openai",
          model    = "gpt-4.1",
          api_key  = os.getenv("OPENAI_API_KEY"),
        },
        {
          name     = "local_llama",
          provider = "ollama",
          model    = "llama3",
        },
      },

      backend = {
        mode            = "orchd",        -- or "lua"
        orchd_cmd       = { "orchd" },
        timeout_seconds = 30,
        streaming       = false,
      },

      keymaps = {
        enabled = true,
        prefix  = "<leader>o",
      }
    })

    require("orch.config").apply_keymaps()
  end
}
```

---

# 🧠 Usage

### Ask all models

```
:OrchAsk "Explain this"
```

### Visual‑mode selection:

```
v
:OrchAsk "Refactor this"
```

### Diff & Merge

```
:OrchRefactor
:OrchMerge
```

### Reopen last hunk preview

```
:OrchHunkPreview
```

### Toggle streaming

```
:OrchToggleStreaming
```

### Side‑by‑Side Model Comparison

```
:OrchCompareModels
```

---

# 🎹 Default Keymaps

With `prefix = "<leader>o"`:

| Mapping | Action |
|--------|--------|
| `<leader>oa` | OrchAsk |
| `<leader>oe` | OrchExplain |
| `<leader>or` | OrchRefactor |
| `<leader>ot` | OrchTestGen |
| `<leader>oo` | Apply first model |
| `<leader>om` | Interactive merge |
| `<leader>op` | Reopen last preview |
| `<leader>os` | Toggle streaming |

---

# 🛠️ The `orchd` Daemon

Orchd is a small Go binary responsible for:

- Concurrent multi‑model fan‑out
- Streaming
- Provider abstraction
- Timeouts
- Versioning & structured CLI tools

## Build

```
make
```

## Install

```
sudo make install
```

## Release Build (version‑embedded)

```
make release VERSION=v0.1.0 MODULE_PATH=github.com/oorrwullie/orchd
```

### CLI Flags

| Flag | Description |
|------|-------------|
| `--version` | Print version |
| `--help` | Show help |
| `--config` | Print config schema |
| `--doctor` | Env + provider diagnostic |
| `--check-request` | Validate JSON without calling APIs |

Full CLI docs are in `docs/cli.md`
Schema docs are in `docs/config.md`

---

# 🧭 Troubleshooting

### In Neovim
```
:OrchPrintConfig
:messages
```

### From Shell
```
orchd --doctor
orchd --check-request < config.example.json
which orchd
```

### Common issues
- Missing API keys
- `orchd` not on PATH
- Wrong `backend.mode`

---

# 📄 License
MIT License.

---

# 🤝 Contributing

Contributions welcome! Especially:
- Provider adapters
- New UI modes
- Merge/judge models
- Documentation

---

# 🚀 Vision

**Give Neovim the multi‑model, streaming, diff‑driven coding intelligence of modern AI IDEs — without any vendor lock‑in or closed ecosystem.**

