local history = {}
local cursors = {}
local buf, win, prev_win, files, cwd, query
local ns = vim.api.nvim_create_namespace("explorer_icons")

local function cmd(command, stdin)
  local result = vim.system(command, { text = true, stdin = stdin }):wait()

  if result.code ~= 0 and result.code ~= 1 then
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

local function clamp(value, min, max)
  return math.min(max, math.max(min, value))
end

local function get_parent_dir(path)
  return vim.fn.fnamemodify(path, ":h")
end

local function get_absolute_path(path)
  if vim.startswith(path, cwd) then
    return path
  end
  return ("%s/%s"):format(cwd, path)
end

local function load_files()
  local fd = cmd({ "fd", "--base-directory", cwd, "--hidden", "--no-ignore", "--exclude", ".git", "--exclude", "node_modules" })
  local fd_lines = split_lines(fd)
  sort_lines(fd_lines)

  if query and query ~= "" then
    local fzf = cmd({ "fzf", "--scheme", "path", "--tiebreak", "pathname", "--filter", query }, fd_lines)
    local fzf_lines = split_lines(fzf)
    files = fzf_lines
  else
    files = fd_lines
  end
end

local function create_buf()
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
end

local function update_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, files)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for i, file in ipairs(files) do
    local is_dir = vim.endswith(file, "/")
    local icon = is_dir and "󰉋" or "󰈤"
    local hl = is_dir and "Directory" or "Normal"

    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
      virt_text = { { (" %s "):format(icon), hl } },
      virt_text_pos = "inline",
    })
  end
end

local function save_cursor()
  if win and vim.api.nvim_win_is_valid(win) then
    cursors[cwd] = vim.api.nvim_win_get_cursor(win)
  end
end

local function restore_cursor()
  if #files == 0 then
    return
  end

  local cursor = cursors[cwd] or { 1, 0 }
  local row = clamp(cursor[1], 1, #files)
  local col = cursor[2]

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { row, col })
  end
end

local function reset_cursor()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

local function get_win_config()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local title = (query and query ~= "") and (" %s [%s] "):format(cwd, query) or (" %s "):format(cwd)
  return {
    width = width,
    height = height,
    row = row,
    col = col,
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = {
      { " <cr>", "Special" },
      { " open  ", "Comment" },
      { "<bs>", "Special" },
      { " back  ", "Comment" },
      { "a", "Special" },
      { " add  ", "Comment" },
      { "m", "Special" },
      { " move  ", "Comment" },
      { "c", "Special" },
      { " copy  ", "Comment" },
      { "d", "Special" },
      { " delete  ", "Comment" },
      { "f", "Special" },
      { " filter  ", "Comment" },
      { "R", "Special" },
      { " refresh  ", "Comment" },
      { "q", "Special" },
      { " close ", "Comment" },
    },
    footer_pos = "center",
  }
end

local function create_win()
  win = vim.api.nvim_open_win(buf, true, get_win_config())
  vim.wo[win].cursorline = true
  vim.fn.matchadd("Directory", ".*/", -1, -1, { window = win })
end

local function update_win()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, get_win_config())
  end
end

local function close_win()
  save_cursor()

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
  end

  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

local function navigate(dir)
  save_cursor()
  cwd = dir:gsub("/$", "")
  query = nil
  load_files()
  update_buf()
  update_win()
  restore_cursor()
end

local function enter()
  local line = vim.api.nvim_get_current_line()
  if line == "" then
    return
  end

  local path = get_absolute_path(line)

  if vim.endswith(path, "/") then
    table.insert(history, cwd)
    navigate(path)
  else
    close_win()
    vim.cmd.edit(path)
  end
end

local function back()
  if #history > 0 then
    navigate(table.remove(history))
  end
end

local function filter()
  local input = vim.fn.input("Filter: ", query or "")
  query = (input ~= "") and input or nil
  load_files()
  update_buf()
  update_win()
  reset_cursor()
end

local function refresh()
  query = nil
  load_files()
  update_buf()
  update_win()
end

local function jump_to(path)
  for i, file in ipairs(files) do
    local file_path = get_absolute_path(file)

    if file_path == path then
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
      end
      return
    end
  end
end

local function add()
  local line = vim.api.nvim_get_current_line()
  local path = get_absolute_path(line)

  local dir
  if vim.endswith(path, "/") then
    dir = path
  else
    dir = ("%s/"):format(get_parent_dir(path))
  end

  local input = vim.fn.input({ prompt = "New: ", default = dir, completion = "file" })
  if input == "" then
    return
  end

  if vim.endswith(input, "/") then
    cmd({ "mkdir", "-p", input })
  else
    cmd({ "mkdir", "-p", get_parent_dir(input) })
    cmd({ "touch", input })
  end

  query = nil
  load_files()
  update_buf()
  update_win()
  jump_to(input)
end

local function move()
  local line = vim.api.nvim_get_current_line()
  local src = get_absolute_path(line)

  local dst = vim.fn.input({ prompt = "Move to: ", default = src, completion = "file" })
  if dst == "" or dst == src then
    return
  end

  cmd({ "mkdir", "-p", get_parent_dir(dst) })
  cmd({ "mv", src, dst })

  load_files()
  update_buf()
  jump_to(dst)
end

local function copy()
  local line = vim.api.nvim_get_current_line()
  local src = get_absolute_path(line)

  local dst = vim.fn.input({ prompt = "Copy to: ", default = src, completion = "file" })
  if dst == "" or dst == src then
    return
  end

  cmd({ "mkdir", "-p", get_parent_dir(dst) })
  cmd({ "cp", "-r", src, dst })

  load_files()
  update_buf()
  jump_to(dst)
end

local function delete()
  local line = vim.api.nvim_get_current_line()
  local path = get_absolute_path(line)

  local result = vim.fn.confirm(("Delete %s ?"):format(path), "&Yes\n&No", 2)
  if result ~= 1 then
    return
  end

  cmd({ "rm", "-rf", path })

  load_files()
  update_buf()
end

local function set_buf_keymaps()
  local keymap_opts = { buffer = buf, nowait = true }
  vim.keymap.set("n", "<cr>", enter, keymap_opts)
  vim.keymap.set("n", "<bs>", back, keymap_opts)
  vim.keymap.set("n", "a", add, keymap_opts)
  vim.keymap.set("n", "m", move, keymap_opts)
  vim.keymap.set("n", "c", copy, keymap_opts)
  vim.keymap.set("n", "d", delete, keymap_opts)
  vim.keymap.set("n", "f", filter, keymap_opts)
  vim.keymap.set("n", "R", refresh, keymap_opts)
  vim.keymap.set("n", "q", close_win, keymap_opts)
  vim.keymap.set("n", "<esc>", close_win, keymap_opts)
end

local function toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    close_win()
    return
  end

  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    cwd = vim.fn.getcwd()
    load_files()
    create_buf()
    update_buf()
    set_buf_keymaps()
  end

  prev_win = vim.api.nvim_get_current_win()
  create_win()
  restore_cursor()
end

local function open_on_enter()
  local arg = vim.fn.argv(0) --[[@as string]]

  if arg ~= "" and vim.fn.isdirectory(arg) == 1 then
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
