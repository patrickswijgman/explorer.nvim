local buf, win, prev_win, cursor
local entries = {}
local ns = vim.api.nvim_create_namespace("explorer")

local function cmd(command, stdin)
  local result = vim.system(command, { text = true, stdin = stdin }):wait()

  if result.code ~= 0 then
    vim.notify(("Command failed with error:\n%s"):format(result.stderr), vim.log.levels.ERROR)
    return ""
  end

  return result.stdout
end

local function split_lines(output)
  return vim.split(output, "\n", { trimempty = true })
end

local function sort_lines(lines)
  table.sort(lines, function(_a, _b)
    local a = _a:lower()
    local b = _b:lower()
    local a_dir = a:match("^(.*)/") or ""
    local b_dir = b:match("^(.*)/") or ""
    if a_dir ~= b_dir then
      return a_dir < b_dir
    end
    return a < b
  end)
end

local function parse_line(line)
  local id, path = line:match("^%[(%d+)%](.*)$")

  if id then
    return tonumber(id), vim.trim(path)
  else
    return nil, vim.trim(line)
  end
end

local function get_path_start(line)
  local prefix = line:match("^%[%d+%]")
  return prefix and #prefix or 0
end

local function get_parent_dir(path)
  return vim.fn.fnamemodify(path, ":h")
end

local function is_directory(path, is_on_disk)
  if is_on_disk then
    return vim.fn.isdirectory(path) == 1
  else
    return vim.endswith(path, "/")
  end
end

local function load_files()
  local output = cmd({ "fd", "--hidden", "--no-ignore", "--exclude", ".git", "--exclude", "node_modules" })
  local files = split_lines(output)
  sort_lines(files)
  return files
end

local function decorate()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for i, line in ipairs(lines) do
    if line ~= "" then
      local id, path = parse_line(line)
      local is_dir = is_directory(path)
      local icon = is_dir and " 󰉋 " or " 󰈤 "
      local hl = is_dir and "Directory" or "NormalFloat"
      local col = get_path_start(line)

      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, {
        virt_text = { { icon, hl } },
        virt_text_pos = "inline",
      })

      if id then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
          end_col = col,
          conceal = "",
          hl_group = "Comment",
        })
      end
    end
  end
end

local function render()
  local files = load_files()
  local lines = {}

  entries = {}

  for i, file in ipairs(files) do
    entries[i] = file
    lines[i] = ("[%d]%s"):format(i, file)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  decorate()
end

local function get_operations()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local operations = { create = {}, copy = {}, move = {}, delete = {} }
  local paths_per_id = {}

  for _, line in ipairs(lines) do
    local id, path = parse_line(line)

    if path ~= "" then
      if id == nil then
        table.insert(operations.create, { dst = path })
      else
        paths_per_id[id] = paths_per_id[id] or {}
        table.insert(paths_per_id[id], path)
      end
    end
  end

  for id, paths in pairs(paths_per_id) do
    local src = entries[id]
    local is_kept = vim.tbl_contains(paths, src)
    local is_moved = false

    for _, dst in ipairs(paths) do
      if dst ~= src then
        if is_kept or is_moved then
          table.insert(operations.copy, { src = src, dst = dst })
        else
          table.insert(operations.move, { src = src, dst = dst })
          is_moved = true
        end
      end
    end
  end

  for id, src in pairs(entries) do
    if not paths_per_id[id] then
      table.insert(operations.delete, { src = src })
    end
  end

  return operations
end

local function has_operations(operations)
  return #operations.create > 0 or #operations.copy > 0 or #operations.move > 0 or #operations.delete > 0
end

local function update_modified()
  vim.bo[buf].modified = has_operations(get_operations())
end

local function on_edit()
  decorate()
  update_modified()
end

local function apply_operations(operations)
  for _, o in ipairs(operations.delete) do
    cmd({ "rm", "-rf", o.src })
  end

  for _, o in ipairs(operations.copy) do
    cmd({ "mkdir", "-p", get_parent_dir(o.dst) })
    cmd({ "cp", "-rn", o.src, o.dst })
  end

  for _, o in ipairs(operations.move) do
    cmd({ "mkdir", "-p", get_parent_dir(o.dst) })
    cmd({ "mv", "-n", o.src, o.dst })
  end

  for _, o in ipairs(operations.create) do
    if is_directory(o.dst) then
      cmd({ "mkdir", "-p", o.dst })
    else
      cmd({ "mkdir", "-p", get_parent_dir(o.dst) })
      cmd({ "touch", o.dst })
    end
  end
end

local function get_summary(operations)
  local summary = {}

  for _, o in ipairs(operations.create) do
    table.insert(summary, ("%-7s %s"):format("Create", o.dst))
  end

  for _, o in ipairs(operations.move) do
    table.insert(summary, ("%-7s %s → %s"):format("Move", o.src, o.dst))
  end

  for _, o in ipairs(operations.copy) do
    table.insert(summary, ("%-7s %s → %s"):format("Copy", o.src, o.dst))
  end

  for _, o in ipairs(operations.delete) do
    table.insert(summary, ("%-7s %s"):format("Delete", o.src))
  end

  return summary
end

local function apply()
  local operations = get_operations()

  if not has_operations(operations) then
    return
  end

  local summary = get_summary(operations)
  local message = ("Apply the following %d change(s)?\n\n%s\n"):format(#summary, table.concat(summary, "\n"))

  if vim.fn.confirm(message, "&Yes\n&No", 2) == 1 then
    apply_operations(operations)
    render()
  end
end

local function save_cursor()
  if win and vim.api.nvim_win_is_valid(win) then
    cursor = vim.api.nvim_win_get_cursor(win)
  end
end

local function restore_cursor()
  if win and vim.api.nvim_win_is_valid(win) then
    if cursor then
      vim.api.nvim_win_set_cursor(win, cursor)
    else
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      local row = 1
      local col = get_path_start(line)
      vim.api.nvim_win_set_cursor(win, { row, col })
    end
  end
end

local function clamp_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row = pos[1]
  local col = pos[2]
  local min_col = get_path_start(vim.api.nvim_get_current_line())

  if col < min_col then
    vim.api.nvim_win_set_cursor(0, { row, min_col })
  end
end

local function get_win_config()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local title = (" %s "):format(vim.fn.getcwd())

  return {
    title = title,
    title_pos = "center",
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = row,
    col = col,
    footer = {
      { " <cr>", "Special" },
      { " open  ", "Comment" },
      { ":w", "Special" },
      { " apply  ", "Comment" },
      { "q", "Special" },
      { " close ", "Comment" },
    },
    footer_pos = "center",
  }
end

local function create_win()
  win = vim.api.nvim_open_win(buf, true, get_win_config())
  vim.wo[win].cursorline = true
  vim.wo[win].conceallevel = 3
  vim.wo[win].concealcursor = "nc"
  vim.fn.matchadd("Directory", [[^\(\[\d\+\]\)\?\zs.*/]], -1, -1, { window = win })
end

local function update_win()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, get_win_config())
  end
end

local function close_win()
  if buf and vim.api.nvim_buf_is_valid(buf) and has_operations(get_operations()) then
    local result = vim.fn.confirm("Discard unsaved changes?", "&Yes\n&No", 2)

    if result ~= 1 then
      return
    end
  end

  save_cursor()

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
  end

  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

local function create_buf()
  buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, ("explorer://%s"):format(vim.fn.getcwd()))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = apply,
    desc = "Apply explorer edits to the filesystem",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    buffer = buf,
    callback = on_edit,
    desc = "Refresh explorer decorations and modified state after an edit",
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = clamp_cursor,
    desc = "Keep the cursor out of the id prefix",
  })
end

local function open()
  local _, path = parse_line(vim.api.nvim_get_current_line())

  if path == "" or is_directory(path) then
    return
  end

  if has_operations(get_operations()) then
    vim.notify("Save (:w) or undo your edits first", vim.log.levels.WARN)
    return
  end

  close_win()
  vim.cmd.edit(path)
end

local function set_buf_keymaps()
  local keymap_opts = { buffer = buf, nowait = true }
  vim.keymap.set("n", "<cr>", open, keymap_opts)
  vim.keymap.set("n", "q", close_win, keymap_opts)
end

local function toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    close_win()
    return
  end

  create_buf()
  set_buf_keymaps()

  prev_win = vim.api.nvim_get_current_win()
  create_win()
  render()
  restore_cursor()
end

local function open_on_enter()
  local arg = vim.fn.argv(0)

  if arg ~= "" and is_directory(arg, true) then
    vim.cmd.cd(arg)
    toggle()
  end
end

vim.api.nvim_create_user_command("Explorer", toggle, { desc = "Toggle file explorer" })

local group = vim.api.nvim_create_augroup("Explorer", { clear = true })

vim.api.nvim_create_autocmd("VimResized", {
  callback = update_win,
  desc = "Resize explorer window on terminal resize",
  group = group,
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = open_on_enter,
  desc = "Open explorer when Neovim is opened with a directory",
  group = group,
})
