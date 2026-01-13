-- init.lua (or your plugin config file)

require("orch").setup({
  models = {
    {
      name        = "sonnet",
      provider    = "anthropic",
      model       = "claude-3.5-sonnet",
      api_key     = os.getenv("ANTHROPIC_API_KEY"),
      temperature = 0.2,
      max_tokens  = 2048,
    },
    {
      name        = "gpt4",
      provider    = "openai",
      model       = "gpt-4.1",
      api_key     = os.getenv("OPENAI_API_KEY"),
      temperature = 0.2,
      max_tokens  = 2048,
    },
    {
      name        = "local_llama",
      provider    = "ollama",
      model       = "llama3",
      endpoint    = "http://127.0.0.1:11434/api/chat",
      temperature = 0.5,
    },
  },

  backend = {
    mode            = "orchd",                 -- "lua" or "orchd"
    orchd_cmd       = { "/usr/local/bin/orchd" },
    timeout_seconds = 30,
    streaming       = false,                   -- wired through to orchd JSON, but currently still returns a single JSON
    restart_cmd     = nil,                     -- e.g. { "brew", "services", "restart", "orchd" }
  },

  ui = {
    split = "vsplit",
  },

  keymaps = {
    enabled = true,
    prefix  = "<leader>o",
  },
})

