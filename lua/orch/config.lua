-- lua/orch/config.lua
local M = {}

local defaults = {
  models = {},
  ui = {
    split = "vsplit", -- future: choose how results are displayed
  },
  backend = {
    -- "lua"   => use Neovim-side curl providers
    -- "orchd" => call the Go binary via stdin/stdout
    mode = "lua",

    -- Command to start orchd (can be string or list)
    -- e.g. { "orchd" } or { "/usr/local/bin/orchd" }
    orchd_cmd = { "orchd" },

    -- Included in the JSON request to orchd
    timeout_seconds = 30,

    -- Hint flag sent to orchd; when true, we use the streaming path
    streaming = false,

    -- Optional: command to restart orchd if you run it as a daemon/service.
    -- e.g. { "brew", "services", "restart", "orchd" }
    restart_cmd = nil,
  },
  keymaps = {
    enabled = true,
    prefix  = "<leader>o",

    -- visual/normal-mode suffixes under the prefix
    ask      = "a",
    explain  = "e",
    refactor = "r",
    test     = "t",
    merge    = "m", -- interactive merge
    apply    = "o", -- apply first model
    preview  = "p", -- re-open last hunk preview
    stream_toggle = "s", -- toggle streaming
  },
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.apply_keymaps()
  local km = M.values.keymaps
  if not km or km.enabled == false then
    return
  end

  local prefix = km.prefix
  local map = vim.keymap.set

  --------------------------------------------------------------------
  -- Visual mode mappings (operate on selection)
  --------------------------------------------------------------------
  map("v", prefix .. km.ask, ":<C-U>OrchAsk ", {
    desc = "Orch: ask all LLMs with custom prompt (selection)",
  })

  map("v", prefix .. km.explain, ":<C-U>OrchExplain<CR>", {
    desc = "Orch: explain selection",
  })

  map("v", prefix .. km.refactor, ":<C-U>OrchRefactor<CR>", {
    desc = "Orch: refactor selection (diff mode)",
  })

  map("v", prefix .. km.test, ":<C-U>OrchTestGen<CR>", {
    desc = "Orch: generate tests for selection",
  })

  --------------------------------------------------------------------
  -- Normal mode buffer-wide equivalents
  --------------------------------------------------------------------
  map("n", prefix .. km.explain, ":OrchExplain<CR>", {
    desc = "Orch: explain current buffer",
  })

  map("n", prefix .. km.refactor, ":OrchRefactor<CR>", {
    desc = "Orch: refactor current buffer (diff mode)",
  })

  map("n", prefix .. km.test, ":OrchTestGen<CR>", {
    desc = "Orch: generate tests for current buffer",
  })

  --------------------------------------------------------------------
  -- Apply / merge / preview
  --------------------------------------------------------------------
  -- Quick apply: first model result (full range)
  map("n", prefix .. km.apply, function()
    require("orch").apply()
  end, {
    desc = "Orch: apply first model result to original range/buffer",
  })

  -- Interactive merge (hunk-by-hunk) using first model by default
  map("n", prefix .. km.merge, function()
    require("orch").merge()
  end, {
    desc = "Orch: interactive hunk-by-hunk merge from first model",
  })

  -- Re-open last hunk preview
  map("n", prefix .. km.preview, ":OrchHunkPreview<CR>", {
    desc = "Orch: re-open last hunk preview (read-only)",
  })

  --------------------------------------------------------------------
  -- Streaming toggle
  --------------------------------------------------------------------
  map("n", prefix .. km.stream_toggle, ":OrchToggleStreaming<CR>", {
    desc = "Orch: toggle orchd streaming mode",
  })
end

return M

