-- lua/orch/core.lua
--
-- Core logic for Orch:
-- - collects context (buffer/selection + prompt)
-- - sends requests to either:
--     * Lua backend (fake provider)   => backend.mode = "lua"
--     * orchd daemon (Go)            => backend.mode = "orchd"
-- - stores last results for apply/merge/compare
--

local config    = require("orch.config")
local providers = require("orch.providers")

local M = {}

-- In-memory state for last run
local state = {
  last_context    = nil,  -- { bufnr, range, snippet, prompt }
  last_results    = nil,  -- { { name, provider, text, error }, ... }
  last_model_name = nil,  -- last model used in merge/apply
  last_hunks      = nil,  -- last diff hunks (for merge)
  last_hunk_index = nil,  -- last merge index
  result_bufnr    = nil,  -- floating results buffer
  result_winid    = nil,  -- floating results window
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function get_backend()
  local values  = config.values or {}
  local backend = values.backend or {}
  backend.mode  = backend.mode or "lua"
  return backend
end

local function get_models()
  local values = config.values or {}
  return values.models or {}
end

local function get_visual_range()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\022" then
    return nil
  end

  local _, ls, cs, _ = unpack(vim.fn.getpos("v"))
  local _, le, ce, _ = unpack(vim.fn.getpos("."))

  if ls > le or (ls == le and cs > ce) then
    ls, le = le, ls
    cs, ce = ce, cs
  end

  return {
    start_line = ls,
    end_line   = le,
  }
end

local function collect_snippet(range)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line

  if range then
    start_line = range.start_line
    end_line   = range.end_line
  else
    start_line = 1
    end_line   = vim.api.nvim_buf_line_count(bufnr)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return bufnr, {
    start_line = start_line,
    end_line   = end_line,
  }, table.concat(lines, "\n")
end

local function ensure_float()
  if state.result_bufnr and vim.api.nvim_buf_is_valid(state.result_bufnr)
     and state.result_winid and vim.api.nvim_win_is_valid(state.result_winid) then
    return state.result_bufnr, state.result_winid
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "orch")

  local width  = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.7)
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })

  state.result_bufnr = buf
  state.result_winid = win
  return buf, win
end

local function render_results(context, results)
  state.last_context = context
  state.last_results = results

  local buf = ensure_float()

  local lines = {}

  -- simple status header with last model + hunk index
  local status = string.format(
    "Orch: last_model=%s, last_hunk=%s",
    state.last_model_name or "-",
    state.last_hunk_index and tostring(state.last_hunk_index) or "-"
  )
  table.insert(lines, status)
  table.insert(lines, string.rep("=", #status))
  table.insert(lines, "")

  for _, r in ipairs(results) do
    local name = r.name or r.model_name or "?"
    local prov = r.provider or "?"
    table.insert(lines, string.format("===== %s (%s) =====", name, prov))

    if r.error and r.error ~= "" then
      table.insert(lines, "ERROR: " .. r.error)
    else
      local text = r.text or ""
      if text == "" then
        text = "<empty response>"
      end
      vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
    end

    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function find_result_by_name(model_name)
  if not state.last_results then
    return nil
  end

  if not model_name or model_name == "" then
    return state.last_results[1]
  end

  for _, r in ipairs(state.last_results) do
    local name = r.name or r.model_name
    if name == model_name then
      return r
    end
  end
  return nil
end

----------------------------------------------------------------------
-- Lua backend (fake provider)
----------------------------------------------------------------------

local function run_lua_backend(context, opts)
  local models = get_models()
  if #models == 0 then
    vim.notify("[orch] No models configured in Orch Lua backend.", vim.log.levels.ERROR)
    return
  end

  local payload = {
    prompt = opts.prompt or "",
    code   = context.snippet or "",
  }

  local results = {}

  for _, spec in ipairs(models) do
    local impl = providers.get(spec.provider)
    if not impl or type(impl.run) ~= "function" then
      table.insert(results, {
        name     = spec.name or "?",
        provider = spec.provider or "?",
        text     = "",
        error    = string.format("no Lua provider for %q", tostring(spec.provider)),
      })
    else
      local ok, text, err = pcall(impl.run, spec, payload)
      if not ok then
        table.insert(results, {
          name     = spec.name or "?",
          provider = spec.provider or "?",
          text     = "",
          error    = "panic in provider: " .. tostring(text),
        })
      else
        table.insert(results, {
          name     = spec.name or "?",
          provider = spec.provider or "?",
          text     = text or "",
          error    = err and tostring(err) or "",
        })
      end
    end
  end

  render_results(context, results)
end

----------------------------------------------------------------------
-- orchd backend helpers
----------------------------------------------------------------------

local function build_orchd_cmd()
  local backend = get_backend()
  local cmd     = backend.orchd_cmd or { "orchd" }
  if type(cmd) == "string" then
    cmd = { cmd }
  end
  return cmd
end

local function build_orchd_request(context, opts)
  return {
    prompt          = opts.prompt or "",
    code            = context.snippet or "",
    models          = get_models(),
    timeout_seconds = get_backend().timeout_seconds or 30,
    stream          = get_backend().streaming or false,
  }
end

local function run_orchd_nonstream(context, opts)
  local req_json = vim.json.encode(build_orchd_request(context, opts))
  local cmd      = build_orchd_cmd()

  local stdout_chunks = {}
  local stderr_chunks = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdin          = "pipe",
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout_chunks, line)
        end
      end
    end,
    on_stderr = function(_, data, _)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_chunks, line)
        end
      end
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify(
            "[orch] orchd exited with code "
              .. tostring(code)
              .. ": "
              .. table.concat(stderr_chunks, "\n"),
            vim.log.levels.ERROR
          )
        end)
        return
      end

      local raw = table.concat(stdout_chunks, "\n")
      local ok, decoded = pcall(vim.json.decode, raw)
      if not ok or type(decoded) ~= "table" then
        vim.schedule(function()
          vim.notify("[orch] Failed to decode orchd response JSON", vim.log.levels.ERROR)
        end)
        return
      end

      local resp_results = decoded.results or decoded.Results
      if type(resp_results) ~= "table" then
        vim.schedule(function()
          vim.notify("[orch] orchd response missing results array", vim.log.levels.ERROR)
        end)
        return
      end

      local results = {}
      for _, r in ipairs(resp_results) do
        table.insert(results, {
          name     = r.name or r.model_name or "?",
          provider = r.provider or "?",
          text     = r.text or "",
          error    = r.error or "",
        })
      end

      vim.schedule(function()
        render_results(context, results)
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("[orch] Failed to start orchd (jobstart error).", vim.log.levels.ERROR)
    return
  end

  vim.fn.chansend(job_id, req_json .. "\n")
  vim.fn.chanclose(job_id, "stdin")
end

local function handle_stream_line(line, results, by_name)
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then
    return
  end

  if obj.event == "result" then
    local name  = obj.name or obj.model_name or "?"
    local entry = {
      name     = name,
      provider = obj.provider or "?",
      text     = obj.text or "",
      error    = obj.error or "",
    }

    if by_name[name] then
      results[by_name[name]] = entry
    else
      table.insert(results, entry)
      by_name[name] = #results
    end
  end
end

local function run_orchd_stream(context, opts)
  local req_json = vim.json.encode(build_orchd_request(context, opts))
  local cmd      = build_orchd_cmd()

  local results = {}
  local by_name = {}
  local stderr_chunks = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdin           = "pipe",
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          handle_stream_line(line, results, by_name)
        end
      end
    end,
    on_stderr = function(_, data, _)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_chunks, line)
        end
      end
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify(
            "[orch] orchd (stream) exited with code "
              .. tostring(code)
              .. ": "
              .. table.concat(stderr_chunks, "\n"),
            vim.log.levels.ERROR
          )
        end)
        return
      end

      vim.schedule(function()
        render_results(context, results)
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("[orch] Failed to start orchd (streaming jobstart error).", vim.log.levels.ERROR)
    return
  end

  vim.fn.chansend(job_id, req_json .. "\n")
  vim.fn.chanclose(job_id, "stdin")
end

local function run_backend(context, opts)
  local backend = get_backend()
  if backend.mode == "orchd" then
    if backend.streaming then
      run_orchd_stream(context, opts)
    else
      run_orchd_nonstream(context, opts)
    end
  else
    run_lua_backend(context, opts)
  end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function M.setup(opts)
  config.setup(opts or {})
end

function M.ask(opts)
  opts = opts or {}
  local range = opts.range or get_visual_range()
  local bufnr, sel_range, snippet = collect_snippet(range)

  local context = {
    bufnr   = bufnr,
    range   = sel_range,
    snippet = snippet,
    prompt  = opts.prompt or "",
  }

  state.last_context    = context
  state.last_results    = nil
  state.last_model_name = nil
  state.last_hunks      = nil
  state.last_hunk_index = nil

  run_backend(context, opts)
end

-- Apply entire model result over the original range/buffer
function M.apply(model_name)
  local ctx = state.last_context
  local results = state.last_results

  if not ctx or not results then
    vim.notify("[orch] No previous results to apply.", vim.log.levels.WARN)
    return
  end

  local chosen = find_result_by_name(model_name)
  if not chosen then
    vim.notify("[orch] Model not found in last results.", vim.log.levels.ERROR)
    return
  end

  state.last_model_name = chosen.name

  local bufnr = ctx.bufnr
  local r     = ctx.range

  -- simple full replacement for now
  local new_lines = vim.split(chosen.text or "", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, r.start_line - 1, r.end_line, false, new_lines)
end

-- Hunk-by-hunk merge: compute diff on demand from last context + model result
function M.merge(model_name)
  local ctx     = state.last_context
  local results = state.last_results

  if not ctx or not results then
    vim.notify("[orch] No previous results to merge.", vim.log.levels.WARN)
    return
  end

  local chosen = find_result_by_name(model_name)
  if not chosen then
    vim.notify("[orch] Model not found in last results.", vim.log.levels.ERROR)
    return
  end

  state.last_model_name = chosen.name

  -- Check if buffer changed since last run
  local current_lines = vim.api.nvim_buf_get_lines(ctx.bufnr, ctx.range.start_line - 1, ctx.range.end_line, false)
  local current = table.concat(current_lines, "\n")
  if current ~= ctx.snippet then
    vim.notify("[orch] Warning: buffer changed since last Orch run; merge may be inaccurate.", vim.log.levels.WARN)
  end

  local orig = ctx.snippet or ""
  local new  = chosen.text or ""
  local hunks = vim.diff(orig, new, {
    result_type = "indices",
    algorithm   = "histogram",
  }) or {}

  if #hunks == 0 then
    vim.notify("[orch] No differences to merge.", vim.log.levels.INFO)
    return
  end

  state.last_hunks      = hunks
  state.last_hunk_index = 1

  local bufnr = ctx.bufnr
  local base_line = ctx.range.start_line
  local offset = 0

  local function apply_hunk(idx)
    local h = hunks[idx]
    if not h then
      vim.notify("[orch] Merge complete.", vim.log.levels.INFO)
      state.last_hunk_index = nil
      return
    end

    state.last_hunk_index = idx

    local a_start, a_count, b_start, b_count = unpack(h)
    local orig_lines = vim.split(orig, "\n", { plain = true })
    local new_lines  = vim.split(new, "\n", { plain = true })

    local a_end = a_start + math.max(a_count - 1, 0)
    local b_end = b_start + math.max(b_count - 1, 0)

    local orig_chunk = {}
    for i = a_start, a_end do
      table.insert(orig_chunk, orig_lines[i] or "")
    end

    local new_chunk = {}
    for i = b_start, b_end do
      table.insert(new_chunk, new_lines[i] or "")
    end

    -- Show preview in a float: original / new / simple diff
    local preview = {}
    table.insert(preview, string.format("Hunk %d / %d", idx, #hunks))
    table.insert(preview, string.rep("=", 40))
    table.insert(preview, "--- ORIGINAL ---")
    vim.list_extend(preview, orig_chunk)
    table.insert(preview, "")
    table.insert(preview, "+++ NEW +++")
    vim.list_extend(preview, new_chunk)
    table.insert(preview, "")
    table.insert(preview, "(y) apply  (n) skip  (q) quit")

    local pbuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(pbuf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, preview)

    local width  = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local pwin = vim.api.nvim_open_win(pbuf, true, {
      relative = "editor",
      width    = width,
      height   = height,
      row      = row,
      col      = col,
      style    = "minimal",
      border   = "rounded",
    })

    local function close_preview()
      if vim.api.nvim_win_is_valid(pwin) then
        pcall(vim.api.nvim_win_close, pwin, true)
      end
    end

    vim.keymap.set("n", "q", function()
      close_preview()
      vim.notify("[orch] Merge cancelled.", vim.log.levels.INFO)
      state.last_hunk_index = nil
    end, { buffer = pbuf, nowait = true, silent = true })

    vim.keymap.set("n", "n", function()
      close_preview()
      apply_hunk(idx + 1)
    end, { buffer = pbuf, nowait = true, silent = true })

    vim.keymap.set("n", "y", function()
      close_preview()

      -- Apply to buffer
      local buf_start = base_line + (a_start - 1) + offset
      local buf_end   = buf_start + a_count

      vim.api.nvim_buf_set_lines(
        bufnr,
        buf_start - 1,
        buf_end - 1,
        false,
        new_chunk
      )

      offset = offset + (b_count - a_count)
      apply_hunk(idx + 1)
    end, { buffer = pbuf, nowait = true, silent = true })
  end

  apply_hunk(1)
end

-- Re-open last hunk preview as a read-only snapshot
function M.preview_last_hunk()
  local hunks     = state.last_hunks
  local idx       = state.last_hunk_index or 1
  local ctx       = state.last_context
  local results   = state.last_results

  if not ctx or not results or not hunks or #hunks == 0 then
    vim.notify("[orch] No last hunk to preview.", vim.log.levels.WARN)
    return
  end

  local chosen = state.last_model_name and find_result_by_name(state.last_model_name) or results[1]
  if not chosen then
    vim.notify("[orch] No model found for last hunk preview.", vim.log.levels.ERROR)
    return
  end

  local orig = ctx.snippet or ""
  local new  = chosen.text or ""
  local h    = hunks[idx]
  if not h then
    vim.notify("[orch] Invalid hunk index.", vim.log.levels.ERROR)
    return
  end

  local a_start, a_count, b_start, b_count = unpack(h)
  local orig_lines = vim.split(orig, "\n", { plain = true })
  local new_lines  = vim.split(new, "\n", { plain = true })

  local a_end = a_start + math.max(a_count - 1, 0)
  local b_end = b_start + math.max(b_count - 1, 0)

  local orig_chunk = {}
  for i = a_start, a_end do
    table.insert(orig_chunk, orig_lines[i] or "")
  end

  local new_chunk = {}
  for i = b_start, b_end do
    table.insert(new_chunk, new_lines[i] or "")
  end

  local preview = {}
  table.insert(preview, string.format("Last hunk %d / %d (model=%s)", idx, #hunks, chosen.name or "?"))
  table.insert(preview, string.rep("=", 40))
  table.insert(preview, "--- ORIGINAL ---")
  vim.list_extend(preview, orig_chunk)
  table.insert(preview, "")
  table.insert(preview, "+++ NEW +++")
  vim.list_extend(preview, new_chunk)

  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(pbuf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, preview)

  local width  = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local pwin = vim.api.nvim_open_win(pbuf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(pwin) then
      pcall(vim.api.nvim_win_close, pwin, true)
    end
  end, { buffer = pbuf, nowait = true, silent = true })
end

-- Compare last results side-by-side in a float
function M.compare()
  local ctx     = state.last_context
  local results = state.last_results

  if not ctx or not results then
    vim.notify("[orch] No previous results to compare.", vim.log.levels.WARN)
    return
  end

  local buf = ensure_float()
  local lines = {}

  local status = string.format(
    "Orch Compare: last_model=%s",
    state.last_model_name or "-"
  )
  table.insert(lines, status)
  table.insert(lines, string.rep("=", #status))
  table.insert(lines, "")

  for _, r in ipairs(results) do
    local name = r.name or r.model_name or "?"
    local prov = r.provider or "?"
    table.insert(lines, string.format("===== %s (%s) =====", name, prov))
    local text = r.text or ""
    if text == "" then
      text = "<empty response>"
    end
    vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

return M
