-- lua/orch/render.lua
local M = {}

local function create_scratch_buf(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  if ft then
    vim.api.nvim_buf_set_option(buf, "filetype", ft)
  end
  return buf
end

function M.show_results(context, results)
  local buf = create_scratch_buf("orch")
  local lines = {}

  table.insert(lines, "Orch — multi-LLM results")
  table.insert(lines, string.rep("=", 40))
  table.insert(lines, "")

  if context.prompt then
    table.insert(lines, "Prompt: " .. context.prompt)
    table.insert(lines, "")
  end

  if context.mode == "diff" then
    table.insert(lines, "Mode: diff")
    table.insert(lines, "Use :OrchApply <model> to apply whole result")
    table.insert(lines, "Use :OrchMerge <model> for hunk-by-hunk merge")
  else
    table.insert(lines, "Mode: plain")
  end

  -- Status line about last hunk, if any
  if vim.g.orch_last_hunk_status and vim.g.orch_last_hunk_status ~= "" then
    table.insert(lines, "Status: " .. vim.g.orch_last_hunk_status)
  end

  table.insert(lines, "")

  if context.snippet then
    table.insert(lines, "Original snippet:")
    table.insert(lines, "```")
    for _, l in ipairs(vim.split(context.snippet, "\n", { plain = true })) do
      table.insert(lines, l)
    end
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  local has_diff = vim.diff ~= nil

  for _, r in ipairs(results) do
    table.insert(lines, "===== " .. r.model_name .. " (" .. r.provider .. ") =====")
    table.insert(lines, "Apply full result with: :OrchApply " .. r.model_name)
    table.insert(lines, "Interactive merge with: :OrchMerge " .. r.model_name)
    table.insert(lines, "")

    if r.error then
      table.insert(lines, "[ERROR]")
      table.insert(lines, r.error)
    else
      if context.mode == "diff" and has_diff then
        local diff = vim.diff(context.snippet or "", r.text or "", {
          result_type = "unified",
          algorithm   = "patience",
        })
        if diff == "" then
          table.insert(lines, "[no changes]")
        else
          vim.list_extend(lines, vim.split(diff, "\n", { plain = true }))
        end
      else
        table.insert(lines, r.text or "")
      end
    end

    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

-- Floating side-by-side comparison of last results.
function M.show_side_by_side(context, results)
  if not results or #results == 0 then
    vim.notify("[orch] No results available for comparison.", vim.log.levels.WARN)
    return
  end

  local n = #results
  local max_total_width = vim.o.columns - 4
  local col_width = math.floor((max_total_width - (n - 1) * 3) / n)
  if col_width < 20 then
    col_width = 20
  end

  local model_blocks = {}
  local max_lines = 0

  for _, r in ipairs(results) do
    local header = string.format("%s (%s)", r.model_name, r.provider)
    local block_lines = { header, string.rep("─", #header) }

    local text = r.text or r.error or "[no output]"
    local lines = vim.split(text, "\n", { plain = true })

    -- Limit each model to a reasonable number of lines for side-by-side
    local limit = 60
    for i, l in ipairs(lines) do
      if i > limit then
        table.insert(block_lines, "... (truncated)")
        break
      end
      table.insert(block_lines, l)
    end

    model_blocks[#model_blocks + 1] = block_lines
    if #block_lines > max_lines then
      max_lines = #block_lines
    end
  end

  local rows = {}

  table.insert(rows, "Orch — side-by-side comparison")
  if context and context.prompt then
    table.insert(rows, "Prompt: " .. context.prompt)
  end
  table.insert(rows, string.rep("=", max_total_width))
  table.insert(rows, "")

  for line_idx = 1, max_lines do
    local row = {}

    for j, block in ipairs(model_blocks) do
      local cell = block[line_idx] or ""
      -- hard truncate; no wrapping
      if #cell > col_width then
        cell = cell:sub(1, col_width - 1) .. "…"
      end
      -- pad
      if #cell < col_width then
        cell = cell .. string.rep(" ", col_width - #cell)
      end
      table.insert(row, cell)
      if j < n then
        table.insert(row, " │ ")
      end
    end

    table.insert(rows, table.concat(row, ""))
  end

  local buf = create_scratch_buf("orchcompare")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)

  local width  = math.min(max_total_width, col_width * n + (n - 1) * 3)
  local height = math.min(vim.o.lines - 4, #rows + 2)
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
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

return M

